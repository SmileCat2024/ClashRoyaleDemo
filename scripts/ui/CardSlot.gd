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

@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel

# 选中时的暖色高亮
const SELECTED_TINT := Color(1.35, 1.15, 0.4)
# 能量不足时的暗化
const DIM_COLOR := Color(0.35, 0.35, 0.35)


func _ready() -> void:
	# 卡牌不需要键盘焦点（快捷键 1-4 由 BattleManager 全局处理）
	focus_mode = Control.FOCUS_NONE
	_apply_theme()
	pressed.connect(_on_pressed)


## 配置卡牌显示内容。由 CardBar 在 hand_updated 时调用。
func setup(p_card_id: String, p_hand_index: int) -> void:
	card_id = p_card_id
	hand_index = p_hand_index
	var card := DataRegistry.get_card_data(p_card_id)
	_card_cost = int(card.get("cost", 0))
	if name_label:
		name_label.text = card.get("display_name", p_card_id)
	if cost_label:
		cost_label.text = str(_card_cost)


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


## 三态外观：不可负担（暗+禁用）> 选中（高亮）> 正常
func _update_appearance() -> void:
	disabled = not _affordable
	if not _affordable:
		modulate = DIM_COLOR
	elif _selected:
		modulate = SELECTED_TINT
	else:
		modulate = Color.WHITE


## 扁平像素风按钮样式（运行时生成 StyleBoxFlat，无需 .tres 文件）
func _apply_theme() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.2, 0.3)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.4, 0.45, 0.58)
	sb.set_content_margin_all(2)
	add_theme_stylebox_override("normal", sb)

	var sb_hover := sb.duplicate()
	sb_hover.bg_color = Color(0.26, 0.3, 0.42)
	add_theme_stylebox_override("hover", sb_hover)

	var sb_pressed := sb.duplicate()
	sb_pressed.bg_color = Color(0.12, 0.15, 0.22)
	add_theme_stylebox_override("pressed", sb_pressed)

	var sb_disabled := sb.duplicate()
	sb_disabled.bg_color = Color(0.1, 0.1, 0.14)
	sb_disabled.border_color = Color(0.18, 0.18, 0.22)
	add_theme_stylebox_override("disabled", sb_disabled)
