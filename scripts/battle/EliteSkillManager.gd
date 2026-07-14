# 文件名：EliteSkillManager.gd
# 作用：管理精英单位的注册/注销和技能释放协调。
#       监听 SignalBus.unit_spawned / unit_died 自动注册/注销带 elite_skill 的单位。
#       SkillBar 通过 elite_skill_added / removed 信号动态创建/移除技能按钮。
#       技能释放的能量检查和瞄准由 BattleManager 处理（本 Manager 不直接扣能量）。
# 挂载位置：BattleManager 动态创建并 add_child（与 DeckManager / AwakeningTracker 平级）。
# 初学者阅读建议：先看 _on_unit_spawned / _on_unit_died 了解自动注册注销，再看 get_active_units 了解查询。
#
# 技能释放完整链路（跨 Manager 协作）：
#   SkillButton 点击 → SignalBus.elite_skill_requested(unit, skill_data)
#   → BattleManager._on_elite_skill_requested：能量检查 + instant 直接释放 / targeted 进入瞄准
#   → BattleManager._cast_elite_skill：扣能量 → unit.trigger_skill(target_pos)
#   → UnitBase.trigger_skill：按 effect.type 执行效果 + 启动冷却 + emit elite_skill_cast

class_name EliteSkillManager
extends Node

## 当前活跃的精英单位列表（仅本地 player 方）。单位死亡/释放时自动移除。
## BattleManager 通过 get_active_units() 查询，用于技能瞄准状态判定。
var _active_units: Array = []


func _ready() -> void:
	SignalBus.unit_spawned.connect(_on_unit_spawned)
	SignalBus.unit_died.connect(_on_unit_died)


## 单位生成回调：检查是否有精英技能配置，有则注册并通知 UI 创建按钮。
## 只关心本地玩家方（team == "player"），敌方精英单位技能由 AI 控制，不创建 UI 按钮。
func _on_unit_spawned(unit: Node, team: String) -> void:
	if team != "player":
		return
	if not (unit is UnitBase):
		return
	if unit.elite_skill_data.is_empty():
		return
	_active_units.append(unit)
	SignalBus.elite_skill_added.emit(unit, unit.elite_skill_data)
	print("[EliteSkillManager] 精英单位注册:", unit.unit_id, unit.elite_skill_data.get("id", ""))


## 单位死亡回调：从活跃列表移除并通知 UI 销毁按钮。
func _on_unit_died(unit: Node, _team: String) -> void:
	var idx := _active_units.find(unit)
	if idx >= 0:
		_active_units.remove_at(idx)
		SignalBus.elite_skill_removed.emit(unit)


## 获取当前活跃的精英单位列表（副本）。BattleManager 查询用。
func get_active_units() -> Array:
	return _active_units.duplicate()


## 清空所有注册（重开战斗时调用）。通知 UI 移除所有按钮。
func clear() -> void:
	for unit in _active_units:
		if is_instance_valid(unit):
			SignalBus.elite_skill_removed.emit(unit)
	_active_units.clear()
