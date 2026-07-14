# 文件名：CardBar.gd
# 作用：底部卡牌栏控制器。管理背景底板图、4 张手牌槽位、预告牌、圣水条。
#       监听 SignalBus 的 hand_updated / energy_changed / selection_changed。
#       所有布局常量集中在本文件顶部，供视觉模型微调对齐。
# 挂载位置：BattleHUD/CardBar（场景 CardBar.tscn 的根节点）
# 初学者阅读建议：先看顶部布局常量区，再看 _ready() 了解信号连接和定位。
#
# ============================================================
#  视觉模型交接区：以下常量控制底板图中所有元素的位置和尺寸。
#  坐标系：CardBar 本地坐标（左上角为原点），单位 = 逻辑像素。
#  CardBar 覆盖区域由 BattleHUD.tscn 中 CardBar 节点的 offset 决定。
#  改这里面的数字即可调整对应元素位置，无需改 .tscn 文件。
# ============================================================

extends Control

## ── CardBar 自身覆盖区域 ──
## CanvasLayer offset=(40,0)，HUD x=0 → viewport x=40。
## 要占满 viewport 440px 宽，CardBar 需从 HUD x=-40 到 x=400。
const BAR_LEFT   := -40   ## 延伸到 viewport 左边缘（-40 + CanvasLayer偏移40 = viewport 0）
const BAR_TOP    := 590   ## 国王塔在 y≈586，卡槽从其下方开始
const BAR_RIGHT  := 400   ## viewport 右边缘
const BAR_BOTTOM := 780   ## 视口底部（新视口高度 780）

## ── 卡牌槽位（4 张手牌）──
## 底板图的 4 个卡框不是数学等距，逐个定位能更贴合边框。
const SLOT_W   := 75      ## 单个卡槽宽度
const SLOT_H   := 104     ## 单个卡槽高度
const SLOT_ROW_Y := 29    ## 卡槽行顶部 y（CardBar 本地坐标）
const SLOT_XS := [103, 187, 270, 354]  ## 4 张手牌的左上角 x

## ── 预告牌（下一张）区域 ──
## 对齐底板预告牌框；"下一张"标题已印在底板图上，无需再显示文字。
const NEXT_W := 37        ## 底板金色预告牌内框宽度
const NEXT_H := 50        ## 底板金色预告牌内框高度
const NEXT_X  := 28       ## 按卡槽底板原图定位（横向）
const NEXT_Y  := 115      ## 按卡槽底板原图定位（纵向）

## ── 圣水条（底板桥是 11 格，实际圣水只占右侧 10 格） ──
## 以桥的右侧为锚点，宽度只覆盖右侧 10 格，跳过最左边的空格。
const ELIXIR_RIGHT := 426
const ELIXIR_W := 300
const ELIXIR_X := ELIXIR_RIGHT - ELIXIR_W
const ELIXIR_Y := 146     ## 圣水条 y
const ELIXIR_H := 20      ## 圣水条高度
const ELIXIR_ICON_X := 88
const ELIXIR_ICON_Y := 133
const ELIXIR_ICON_SIZE := 45
const ELIXIR_VALUE_X := 117
const ELIXIR_VALUE_Y := 136
const ELIXIR_VALUE_W := 38
const ELIXIR_VALUE_H := 28
const ELIXIR_MAX_X := 124
const ELIXIR_MAX_Y := 153
const ELIXIR_MAX_W := 66
const ELIXIR_MAX_H := 18

var _player_energy: int = 5
var _player_energy_max: int = 10
## 记录本地玩家每张觉醒牌的就绪状态，避免卡牌轮转离手后丢失状态。
var _awakening_ready_by_card: Dictionary = {}
var _next_card_id: String = ""

@onready var slots: Array[Button] = [
	$CardSlot0, $CardSlot1, $CardSlot2, $CardSlot3,
]
@onready var next_name_label: Label = $NextCardPanel/NextNameLabel
@onready var next_card_panel: Panel = $NextCardPanel
@onready var next_icon_rect: TextureRect = $NextCardPanel/NextCardIcon
@onready var elixir_bar: Control = $ElixirBar
@onready var elixir_fill: ColorRect = $ElixirBar/ElixirFill
@onready var elixir_pending: ColorRect = $ElixirBar/ElixirPending
@onready var elixir_icon: TextureRect = $ElixirIcon
@onready var elixir_value_label: Label = $ElixirValueLabel
@onready var elixir_max_label: Label = $ElixirMaxLabel


func _ready() -> void:
	SignalBus.hand_updated.connect(_on_hand_updated)
	SignalBus.energy_changed.connect(_on_energy_changed)
	SignalBus.selection_changed.connect(_on_selection_changed)
	SignalBus.awakening_progress_changed.connect(_on_awakening_progress)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 定位 CardBar 自身
	position = Vector2(BAR_LEFT, BAR_TOP)
	size = Vector2(BAR_RIGHT - BAR_LEFT, BAR_BOTTOM - BAR_TOP)

	# 定位 4 张卡牌槽位
	for i in range(slots.size()):
		var x := int(SLOT_XS[i])
		slots[i].position = Vector2(x, SLOT_ROW_Y)
		slots[i].size = Vector2(SLOT_W, SLOT_H)

	# 定位预告牌
	next_card_panel.position = Vector2(NEXT_X, NEXT_Y)
	next_card_panel.size = Vector2(NEXT_W, NEXT_H)
	var panel_sb := StyleBoxEmpty.new()
	next_card_panel.add_theme_stylebox_override("panel", panel_sb)
	# 预告牌卡面仅覆盖底板左下角的金色内框，不覆盖“下一张”文字区域。
	next_icon_rect.offset_left = 0.0
	next_icon_rect.offset_top = 0.0
	next_icon_rect.offset_right = 0.0
	next_icon_rect.offset_bottom = 0.0

	# 定位圣水条
	elixir_bar.position = Vector2(ELIXIR_X, ELIXIR_Y)
	elixir_bar.size = Vector2(ELIXIR_W, ELIXIR_H)
	# 原版式圣水显示：水滴在左，当前值使用大号数字，最大值置于下方。
	elixir_icon.position = Vector2(ELIXIR_ICON_X, ELIXIR_ICON_Y)
	elixir_icon.size = Vector2(ELIXIR_ICON_SIZE, ELIXIR_ICON_SIZE)
	elixir_value_label.position = Vector2(ELIXIR_VALUE_X, ELIXIR_VALUE_Y)
	elixir_value_label.size = Vector2(ELIXIR_VALUE_W, ELIXIR_VALUE_H)
	elixir_max_label.position = Vector2(ELIXIR_MAX_X, ELIXIR_MAX_Y)
	elixir_max_label.size = Vector2(ELIXIR_MAX_W, ELIXIR_MAX_H)

	# 初始化圣水条显示（start_battle 的 energy_changed 信号可能在 _ready 之前已发出）
	_update_elixir_bar()


func _process(_delta: float) -> void:
	_update_elixir_pending()


## 手牌更新：刷新 4 张卡牌 + 预告牌 + 可负担状态
func _on_hand_updated(hand: Array, next_card: String) -> void:
	for i in range(slots.size()):
		var card_id: String = hand[i] if i < hand.size() else ""
		var awakening_ready := bool(_awakening_ready_by_card.get(card_id, false))
		slots[i].setup(card_id, i, awakening_ready)
	_next_card_id = next_card
	if next_card == "":
		next_name_label.text = "—"
		next_name_label.visible = true
		next_icon_rect.texture = null
	else:
		var card := DataRegistry.get_card_data(next_card)
		var icon_path: String = card.get("icon", "")
		next_name_label.visible = (icon_path == "")
		next_name_label.text = card.get("display_name", next_card)
		var display_icon_path := _get_card_icon_path(next_card)
		if display_icon_path != "":
			next_icon_rect.texture = load(display_icon_path) as Texture2D
		else:
			next_icon_rect.texture = null
	_refresh_affordability()


## 觉醒进度变化：缓存状态，并同步更新预告牌卡面。
## CardSlot 自己也监听该信号，用于更新当前手牌中的觉醒卡面。
func _on_awakening_progress(team: String, card_id: String, _count: int,
		_trigger_count: int, next_awakened: bool) -> void:
	if team != "player":
		return
	_awakening_ready_by_card[card_id] = next_awakened
	if _next_card_id == card_id:
		var icon_path := _get_card_icon_path(card_id)
		if icon_path != "":
			next_icon_rect.texture = load(icon_path) as Texture2D
		else:
			next_icon_rect.texture = null


## 返回卡牌当前应该展示的卡面。
func _get_card_icon_path(card_id: String) -> String:
	var card := DataRegistry.get_card_data(card_id)
	if bool(_awakening_ready_by_card.get(card_id, false)):
		var awakening_icon: String = card.get("awakening_icon", "")
		if awakening_icon != "":
			return awakening_icon
	return card.get("icon", "")


## 能量变化：更新圣水条 + 重新评估各卡牌是否可负担
func _on_energy_changed(team: String, current: int, max_val: int) -> void:
	if team == "player":
		_player_energy = current
		_player_energy_max = max_val
		_update_elixir_bar()
		_refresh_affordability()


## 选中状态变化：更新高亮
func _on_selection_changed(hand_index: int) -> void:
	for i in range(slots.size()):
		slots[i].set_selected(i == hand_index)


## 遍历所有槽位，根据当前能量设置可负担状态
func _refresh_affordability() -> void:
	for slot in slots:
		var card := DataRegistry.get_card_data(slot.card_id)
		var cost := int(card.get("cost", 0))
		slot.set_affordable(_player_energy >= cost)


## 更新圣水条显示
func _update_elixir_bar() -> void:
	var ratio := float(_player_energy) / float(max(_player_energy_max, 1))
	elixir_fill.size = Vector2(ELIXIR_W * ratio, ELIXIR_H)
	elixir_value_label.text = str(_player_energy)
	elixir_max_label.text = "最多：%d" % _player_energy_max
	_update_elixir_pending()

## 更新正在积累的那一滴圣水的半透明填充
func _update_elixir_pending() -> void:
	var solid_w := ELIXIR_W * float(_player_energy) / float(max(_player_energy_max, 1))
	var seg_w := ELIXIR_W / float(_player_energy_max)
	var pending_w := seg_w * SignalBus.player_energy_progress
	elixir_pending.position.x = solid_w
	elixir_pending.size = Vector2(pending_w, ELIXIR_H)
