# 文件名：SkillBar.gd
# 作用：精英技能按钮容器。监听 elite_skill_added / removed 动态创建/移除技能按钮。
#       位于卡槽上方右侧，按钮从上到下垂直排列。
#       每个精英单位对应一个按钮，单位死亡时按钮自动销毁。
# 挂载位置：BattleHUD 下动态创建（由 BattleHUD._ready 实例化）。
# 初学者阅读建议：先看 _ready() 了解信号连接，再看 _on_skill_added/_on_skill_removed 了解按钮生命周期。

class_name SkillBar
extends Control

## 技能按钮尺寸和间距
const BUTTON_W := 56
const BUTTON_H := 56
const BUTTON_GAP := 8

## 当前活跃的技能按钮。key: unit.get_instance_id(), value: SkillButton 节点。
var _buttons: Dictionary = {}


func _ready() -> void:
	SignalBus.elite_skill_added.connect(_on_skill_added)
	SignalBus.elite_skill_removed.connect(_on_skill_removed)
	SignalBus.elite_skill_cooldown_changed.connect(_on_cooldown_changed)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 精英单位生成：创建技能按钮并加入容器。
func _on_skill_added(unit: Node, skill_data: Dictionary) -> void:
	# 防御性检查：只为我方（player）精英单位创建按钮（EliteSkillManager 也已过滤）
	if unit.get("team") != null and unit.team != "player":
		return
	var key := unit.get_instance_id()
	if _buttons.has(key):
		return  # 已存在（防重复注册）
	var btn := SkillButton.new()
	add_child(btn)
	btn.setup(unit, skill_data)
	_buttons[key] = btn
	_relayout()


## 精英单位死亡：移除对应技能按钮。
func _on_skill_removed(unit: Node) -> void:
	var key := unit.get_instance_id()
	if not _buttons.has(key):
		return
	var btn = _buttons[key]
	if is_instance_valid(btn):
		btn.queue_free()
	_buttons.erase(key)
	_relayout()


## 冷却变化：转发给对应按钮。
func _on_cooldown_changed(unit: Node, remaining: float, total: float) -> void:
	var key := unit.get_instance_id()
	if _buttons.has(key):
		var btn = _buttons[key]
		if is_instance_valid(btn):
			btn.update_cooldown(remaining, total)


## 重新排列所有按钮（从上到下垂直排列）。
func _relayout() -> void:
	var y := 0
	for key in _buttons:
		var btn = _buttons[key]
		if is_instance_valid(btn):
			btn.position = Vector2(0, y)
			btn.size = Vector2(BUTTON_W, BUTTON_H)
			y += BUTTON_H + BUTTON_GAP
