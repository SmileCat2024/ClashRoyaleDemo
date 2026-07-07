# 文件名：CollisionSystem.gd
# 作用：碰撞分离系统。在每帧所有单位移动完毕后统一执行，
#       解析同层（ground/air）实体间的圆形碰撞体重叠，按质量反比分配分离位移。
#       不可移动实体（mass=0，如塔）承担零修正。
# 挂载位置：不需要挂载。通过 class_name 注册为全局类型。
# 初学者阅读建议：先看 resolve_overlaps()，再看 _resolve_pair()。

class_name CollisionSystem

const MAX_ITERATIONS := 3        ## 每帧碰撞分离迭代次数
const ZERO_DIST_THRESHOLD := 1.0 ## 距离小于此值视为同位置，使用回退方向
const RIVER_BOUNCE_MARGIN := 1.0 ## 河道回弹时离岸边的留白（px）


## 对所有活跃实体执行碰撞分离。在 BattleManager._process() 末尾调用（所有单位已移动完毕）。
static func resolve_overlaps(entities: Array) -> void:
	if entities.size() < 2:
		return

	for _i in range(MAX_ITERATIONS):
		_resolve_one_pass(entities)

	_post_process(entities)


## 单次遍历：对所有实体两两检查并分离重叠。
static func _resolve_one_pass(entities: Array) -> void:
	var n := entities.size()
	for i in range(n):
		for j in range(i + 1, n):
			_resolve_pair(entities[i], entities[j])


## 分离一对重叠的实体。
static func _resolve_pair(a: Node2D, b: Node2D) -> void:
	# 分层检查：地面碰地面，空中碰空中
	if _get_layer(a) != _get_layer(b):
		return

	var diff := b.position - a.position
	var dist := diff.length()

	var r_a := _get_collision_radius(a)
	var r_b := _get_collision_radius(b)
	var radius_sum := r_a + r_b

	if dist >= radius_sum:
		return  # 无重叠

	# 计算分离方向（direction 始终从 A 指向 B）
	var direction: Vector2
	if dist < ZERO_DIST_THRESHOLD:
		# 同位置回退：x 小的在左、x 大的在右。A 在 B 左时方向 = (+1,0)，A 在 B 右时 = (-1,0)
		if a.position.x <= b.position.x:
			direction = Vector2(1, 0)
		else:
			direction = Vector2(-1, 0)
	else:
		direction = diff / dist

	var overlap := radius_sum - dist

	var mass_a := _get_mass(a)
	var mass_b := _get_mass(b)

	# 不可移动实体（mass=0）特判
	if mass_a <= 0 and mass_b <= 0:
		return
	if mass_a <= 0:
		b.position += direction * overlap
		return
	if mass_b <= 0:
		a.position -= direction * overlap
		return

	# 质量反比分配：轻的被推得更远
	var inv_a := 1.0 / float(mass_a)
	var inv_b := 1.0 / float(mass_b)
	var total_inv := inv_a + inv_b
	a.position -= direction * (overlap * inv_a / total_inv)
	b.position += direction * (overlap * inv_b / total_inv)


## 后处理：河道回弹 + 边界钳制。对所有实体执行，保证不会出现卡河道或飞出地图的情况。
static func _post_process(entities: Array) -> void:
	for e in entities:
		# 河道回弹：地面单位被推入河道（非桥面）时拉回最近岸
		if _get_layer(e) == "ground":
			if BattlePathing.is_in_river(e.position) and not BattlePathing.is_on_bridge(e.position):
				var river_mid := (BattleConstants.RIVER_Y_MIN + BattleConstants.RIVER_Y_MAX) * 0.5
				if e.position.y < river_mid:
					e.position.y = BattleConstants.RIVER_Y_MIN - RIVER_BOUNCE_MARGIN
				else:
					e.position.y = BattleConstants.RIVER_Y_MAX + RIVER_BOUNCE_MARGIN

		# 边界钳制
		var r := _get_collision_radius(e)
		e.position.x = clampf(e.position.x, r, BattleConstants.ARENA_WIDTH - r)
		e.position.y = clampf(e.position.y, r, BattleConstants.ARENA_HEIGHT - r)


# ============================================================
#  工具方法
# ============================================================

static func _get_layer(entity: Node2D) -> String:
	var mt = entity.get("movement_type")
	if mt == null:
		return "ground"
	return str(mt)


static func _get_collision_radius(entity: Node2D) -> float:
	var r = entity.get("collision_radius")
	if r == null:
		return 10.0
	return float(r)


static func _get_mass(entity: Node2D) -> int:
	var m = entity.get("mass")
	if m == null:
		return 5
	return int(m)
