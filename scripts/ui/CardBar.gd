# 文件名：CardBar.gd
# 作用：底部卡牌栏控制器。管理 4 张手牌槽位 + 1 张预告牌的显示。
#       监听 SignalBus 的 hand_updated / energy_changed / selection_changed，
#       驱动各 CardSlot 刷新内容、可负担状态、选中高亮。
#       CardBar 不直接引用任何 Manager——纯信号驱动。
# 挂载位置：BattleHUD/CardBar（场景 CardBar.tscn 的根节点）
# 初学者阅读建议：先看 _ready() 了解信号连接，再看 _on_hand_updated() 了解刷新流程。

extends Control

var _player_energy: int = 5

@onready var slots: Array[Button] = [
	$HBox/CardSlot0, $HBox/CardSlot1, $HBox/CardSlot2, $HBox/CardSlot3,
]
@onready var next_name_label: Label = $HBox/NextCardPanel/NextNameLabel


func _ready() -> void:
	SignalBus.hand_updated.connect(_on_hand_updated)
	SignalBus.energy_changed.connect(_on_energy_changed)
	SignalBus.selection_changed.connect(_on_selection_changed)
	# CardBar 根节点不拦截鼠标（让卡牌间隙的点击穿透到战场），
	# 各 CardSlot（Button）自行以 STOP 拦截自身区域。
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 手牌更新：刷新 4 张卡牌 + 预告牌 + 可负担状态
func _on_hand_updated(hand: Array, next_card: String) -> void:
	for i in range(slots.size()):
		var card_id: String = hand[i] if i < hand.size() else ""
		slots[i].setup(card_id, i)
	# 更新预告牌名称
	if next_card == "":
		next_name_label.text = "—"
	else:
		var card := DataRegistry.get_card_data(next_card)
		next_name_label.text = card.get("display_name", next_card)
	_refresh_affordability()


## 能量变化：重新评估各卡牌是否可负担
func _on_energy_changed(team: String, current: int, _max: int) -> void:
	if team == "player":
		_player_energy = current
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
