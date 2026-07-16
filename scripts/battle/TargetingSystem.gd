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
		# 隐身过滤：隐身单位（皇室幽灵移动中）不可被索敌锁定
		if u.get("is_stealthed") == true:
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
## targeting_mode: "any" = 单位+塔都找 | "building_only" = 只找建筑（塔 + 建筑卡牌，如迫击炮）。
## attack_ground/attack_air: 能否攻击地面/空中目标。
## 塔没有 movement_type，默认视为 ground 目标。
## p_self_collision_radius: 攻击者碰撞半径（像素）。视野按两个实体的边缘距离判定，
## 必须与 AttackComponent.compute_reach() 使用同一套几何口径，避免单位在攻击触及范围内
## 停步、却因尚未索敌而永久发呆。
static func find_best_target(
	from_position: Vector2,
	self_team: String,
	max_range: float,
	targeting_mode: String,
	p_attack_ground: bool,
	p_attack_air: bool,
	mover_movement_type: String = "ground",
	mover_can_jump_river: bool = false,
	p_min_range: float = 0.0,
	p_self_collision_radius: float = 0.0
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
		# 隐身过滤：隐身单位（皇室幽灵移动/待机中）不可被索敌锁定
		if e.get("is_stealthed") == true:
			continue

		# targeting 规则过滤
		# building_only 只攻击建筑：塔（tower_type）或建筑单位（mass=0，如迫击炮）
		if targeting_mode == "building_only":
			var is_tower := e.get("tower_type") != null
			var e_mass = e.get("mass")
			var is_building := is_tower or (e_mass != null and int(e_mass) <= 0)
			if not is_building:
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
		# 盲区过滤（如迫击炮最小射程）：目标中心在盲区内直接跳过
		if p_min_range > 0.0 and d < p_min_range:
			continue
		# 视野按实体边缘的可触及距离判定，与攻击 reach 公式一致：
		# sight_range + 自身 collision_radius + 目标 hurt_radius。
		# 目标受击体积是攻击命中的几何边界，不能误用碰撞体积（两者允许独立配置）。
		var target_hurt_radius := 0.0
		var hr = e.get("hurt_radius")
		if hr != null:
			target_hurt_radius = float(hr)
		var effective_distance := d - p_self_collision_radius - target_hurt_radius
		if effective_distance <= nearest_dist:
			nearest_dist = effective_distance
			nearest = e

	return nearest
