# 文件名：CardSlot.gd
# 作用：单个卡牌槽位的显示与交互。展示卡牌名称和费用，
#       点击时通过 SignalBus.card_selected 通知 BattleManager。
#       能量不足时自动变暗（disabled）且不可点击，选中时高亮。
# 挂载位置：CardBar/HBox/CardSlotN（场景 CardSlot.tscn 的根节点）
# 初学者阅读建议：先看 setup() 了解初始化，再看 _update_appearance() 了解三种状态切换。

extends Button

var card_id: String = ""
var hand_index: int = -1

var _card_cost: int = 0
var _selected: bool = false
var _affordable: bool = true
var _awakening_ready: bool = false  ## 觉醒就绪（下次打出为觉醒版）

@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostBadge/CostLabel
@onready var icon_rect: TextureRect = $CardIcon

# 缓存已加载的卡面纹理，避免重复 load
var _icon_cache: Dictionary = {}

# 选中时的暖色高亮
const SELECTED_TINT := Color(1.35, 1.15, 0.4)
# 能量不足时的暗化
const DIM_COLOR := Color(0.35, 0.35, 0.35)
# 觉醒就绪时的金色高亮（下一次打出为觉醒版）
const AWAKENING_TINT := Color(1.0, 0.85, 0.3)


func _ready() -> void:
	# 卡牌不需要键盘焦点（快捷键 1-4 由 BattleManager 全局处理）
	focus_mode = Control.FOCUS_NONE
	_apply_theme()
	pressed.connect(_on_pressed)
	# 监听觉醒进度变化（start_battle 会延迟广播初始进度）
	SignalBus.awakening_progress_changed.connect(_on_awakening_progress)


## 配置卡牌显示内容。由 CardBar 在 hand_updated 时调用。
func setup(p_card_id: String, p_hand_index: int) -> void:
	card_id = p_card_id
	hand_index = p_hand_index
	_awakening_ready = false  # 重置觉醒状态（卡牌轮转后由信号更新）
	var card := DataRegistry.get_card_data(p_card_id)
	_card_cost = int(card.get("cost", 0))
	if name_label:
		# 有卡面的卡牌不显示名称（图片即标识）
		var icon_path: String = card.get("icon", "")
		name_label.visible = (icon_path == "")
		name_label.text = card.get("display_name", p_card_id)
	if cost_label:
		cost_label.text = str(_card_cost)
	_load_icon(card.get("icon", ""))


## 加载卡面图片。无 icon 字段时清空图片。
func _load_icon(icon_path: String) -> void:
	if icon_path == "":
		icon_rect.texture = null
		return
	if _icon_cache.has(icon_path):
		icon_rect.texture = _icon_cache[icon_path]
		return
	var tex := load(icon_path) as Texture2D
	if tex:
		_icon_cache[icon_path] = tex
		icon_rect.texture = tex


## 设置选中高亮
func set_selected(p_selected: bool) -> void:
	_selected = p_selected
	_update_appearance()


## 设置是否可负担（能量是否足够）。不可负担时禁用并暗化。
func set_affordable(p_affordable: bool) -> void:
	_affordable = p_affordable
	_update_appearance()


## 点击卡牌 → 通知 BattleManager
func _on_pressed() -> void:
	if card_id != "":
		SignalBus.card_selected.emit(card_id, hand_index)


## 觉醒进度变化回调。只关心本地玩家方且卡牌 id 匹配时更新高亮。
func _on_awakening_progress(team: String, p_card_id: String, _count: int, _trigger_count: int, next_awakened: bool) -> void:
	if team != "player" or p_card_id != card_id:
		return
	_awakening_ready = next_awakened
	_update_appearance()


## 四态外观：不可负担（暗+禁用）> 觉醒就绪（金色）> 选中（暖色）> 正常
func _update_appearance() -> void:
	disabled = not _affordable
	if not _affordable:
		modulate = DIM_COLOR
	elif _awakening_ready:
		modulate = AWAKENING_TINT
	elif _selected:
		modulate = SELECTED_TINT
	else:
		modulate = Color.WHITE


## 透明背景——底板图由 CardBar/BgTexture 提供，卡槽只做交互层。
## 选中/变暗通过 modulate 实现，不画任何 StyleBox。
func _apply_theme() -> void:
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("disabled", empty)
