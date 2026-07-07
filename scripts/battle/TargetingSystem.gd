# 文件名：TargetingSystem.gd
# 作用：提供静态工具方法，用于在单位/塔之间寻找攻击目标。
#       所有方法都是 static 的，不需要实例化即可调用。
# 挂载位置：不需要挂载。通过 class_name 注册为全局类型。
# 初学者阅读建议：看 find_best_target() 了解三重过滤索敌逻辑。

class_name TargetingSystem


## 判断两个阵营是否敌对
static func is_enemy(a_team: String, b_team: String) -> bool:
	return a_team != b_team


## 在给定的单位列表中，找到离 from_position 最近的敌方单位
static func find_nearest_enemy_unit(from_position: Vector2, self_team: String, units: Array) -> Node2D:
	var nearest = null
	var nearest_dist = 999999.0
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		var dead_val = u.get("is_dead")
		var u_team = u.get("team")
		if dead_val != null and dead_val:
			continue
		if u_team == null or not is_enemy(self_team, u_team):
			continue
		var d = from_position.distance_to(BattlePathing.game_position_of(u))
		if d < nearest_dist:
			nearest_dist = d
			nearest = u
	return nearest


## 在给定的塔列表中，找到离 from_position 最近的敌方塔
static func find_nearest_enemy_tower(from_position: Vector2, self_team: String, towers: Array) -> Node2D:
	var nearest = null
	var nearest_dist = 999999.0
	for t in towers:
		if t == null or not is_instance_valid(t):
			continue
		var dead_val = t.get("is_dead")
		var t_team = t.get("team")
		if dead_val != null and dead_val:
			continue
		if t_team == null or not is_enemy(self_team, t_team):
			continue
		var d = from_position.distance_to(BattlePathing.game_position_of(t))
		if d < nearest_dist:
			nearest_dist = d
			nearest = t
	return nearest


## 先找最近的敌方单位；没有敌方单位时，再找最近的敌方塔。
## 返回找到的目标节点，没有目标时返回 null。
static func find_nearest_enemy_target(from_position: Vector2, self_team: String, units: Array, towers: Array) -> Node2D:
	var unit = find_nearest_enemy_unit(from_position, self_team, units)
	if unit != null:
		return unit
	return find_nearest_enemy_tower(from_position, self_team, towers)


## 统一索敌入口。三重过滤：阵营 → targeting规则 → ground/air → 可达距离。
## 从 EntityRegistry 查询敌方列表，返回 max_range 内最近的合法目标。
## targeting_mode: "any" = 单位+塔都找 | "building_only" = 只找塔。
## attack_ground/attack_air: 能否攻击地面/空中目标。
## 塔没有 movement_type，默认视为 ground 目标。
static func find_best_target(
	from_position: Vector2,
	self_team: String,
	max_range: float,
	targeting_mode: String,
	p_attack_ground: bool,
	p_attack_air: bool,
	mover_movement_type: String = "ground",
	mover_can_jump_river: bool = false
) -> Node2D:
	var enemies = EntityRegistry.get_enemies_of(self_team)
	var nearest: Node2D = null
	var nearest_dist: float = max_range

	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		# 死亡过滤
		if e.get("is_dead") == true:
			continue

		# targeting 规则过滤
		if targeting_mode == "building_only":
			if e.get("tower_type") == null:
				continue

		# ground/air 过滤
		var movement = e.get("movement_type")
		if movement == null:
			movement = "ground"  # 塔默认视为地面目标
		if movement == "ground" and not p_attack_ground:
			continue
		if movement == "air" and not p_attack_air:
			continue

		# 可达距离过滤：地面单位跨河必须按桥路径计算，空中单位保持直线。
		var e_pos := BattlePathing.game_position_of(e)
		var d := BattlePathing.path_distance(
			from_position,
			e_pos,
			mover_movement_type,
			mover_can_jump_river
		)
		# 碰撞半径偏移：大目标的边缘比中心更早进入索敌范围
		var cr = e.get("collision_radius")
		if cr != null:
			d -= float(cr)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e

	return nearest
