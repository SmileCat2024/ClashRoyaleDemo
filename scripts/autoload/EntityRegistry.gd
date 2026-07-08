# 文件名：EntityRegistry.gd
# 作用：战场实体注册表。所有战斗实体（单位、塔、建筑）生成时注册，死亡时注销。
#       索敌时从这里按 team 查询，不遍历场景树。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：看 get_enemies_of() 了解索敌时怎么拿到敌方列表。

extends Node

# 按 team 分组的实体列表
var _entities_by_team: Dictionary = {}


## 注册一个实体到注册表
func register(entity: Node) -> void:
	var t: String = entity.team
	if not _entities_by_team.has(t):
		_entities_by_team[t] = []
	if not _entities_by_team[t].has(entity):
		_entities_by_team[t].append(entity)


## 从注册表移除一个实体
func unregister(entity: Node) -> void:
	var t: String = entity.team
	if _entities_by_team.has(t):
		_entities_by_team[t].erase(entity)


## 获取指定 team 的所有活跃敌方实体（已过滤死亡和无效引用）
func get_enemies_of(team: String) -> Array:
	var enemies: Array = []
	for t in _entities_by_team:
		if t == team:
			continue
		for e in _entities_by_team[t]:
			if is_instance_valid(e) and not e.is_dead:
				enemies.append(e)
	return enemies


## 获取指定 team 的所有活跃友方实体
func get_allies_of(team: String) -> Array:
	var allies: Array = []
	if not _entities_by_team.has(team):
		return allies
	for e in _entities_by_team[team]:
		if is_instance_valid(e) and not e.is_dead:
			allies.append(e)
	return allies


## 获取所有已注册实体（不过滤，用于调试）
func get_all() -> Array:
	var all: Array = []
	for t in _entities_by_team:
		all.append_array(_entities_by_team[t])
	return all


## 获取所有静态障碍物（mass=0 的活跃实体：塔、未来建筑）。供寻路避障使用。
func get_static_obstacles() -> Array:
	var obstacles: Array = []
	for t in _entities_by_team:
		for e in _entities_by_team[t]:
			if is_instance_valid(e) and not e.is_dead:
				var m = e.get("mass")
				if m != null and int(m) <= 0:
					obstacles.append(e)
	return obstacles


## 获取所有活跃战斗实体（含友军和塔），供碰撞分离系统使用。
func get_all_combatants() -> Array:
	var all: Array = []
	for t in _entities_by_team:
		for e in _entities_by_team[t]:
			if is_instance_valid(e) and not e.is_dead:
				all.append(e)
	return all


## 清空注册表（场景切换时调用）
func clear() -> void:
	_entities_by_team.clear()


## 打印所有实体状态（调试用，绑 F8）
func dump() -> void:
	print("=== EntityRegistry Dump ===")
	var all = get_all()
	for e in all:
		if not is_instance_valid(e):
			continue
		var eid = e.get("unit_id")
		if eid == null:
			eid = e.get("tower_id")
		var state = "DEAD" if e.is_dead else "ALIVE"
		var tgt = "null"
		if e.has_method("get") and e.get("target") != null:
			tgt = str(e.get("target"))
		print("  [%s] team=%s pos=%s hp=%d/%d state=%s target=%s" % [
			eid, e.team, str(e.global_position), e.current_hp, e.max_hp, state, tgt
		])
	print("  Total: %d entities" % all.size())
	print("===========================")
