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
const TANGENTIAL_SLIDE := 0.3   ## 切向滑动系数：碰撞推挤时叠加的切向分量比例（0=纯径向，1=切向=径向）
const SAME_DIRECTION_DOT := 0.5 ## 同向判定阈值（点积）：双方移动方向夹角余弦大于此值（约60°内）视为同向


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

	# 部署虚影期间的普通单位（is_deployed=false 且 mass>0）不参与碰撞推挤。
	# 这样新单位可在已有单位所在格部署，不被推开也不推开别人；
	# 部署完成（is_deployed=true）后碰撞系统自动分离重叠。
	# 建筑（mass=0）部署期间仍作为障碍物参与碰撞。
	if _is_deploying_non_building(a) or _is_deploying_non_building(b):
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
	var push_a := overlap * inv_a / total_inv
	var push_b := overlap * inv_b / total_inv
	a.position -= direction * push_a
	b.position += direction * push_b

	# 切向滑动：沿碰撞法线的垂直方向叠加推力，帮助单位侧滑绕过彼此。
	# 仅当至少一方在移动时生效，静止实体碰撞保持纯径向推挤。
	# 特例：双方同向同速前进时跳过——它们只需径向分离保持间距；
	#       若施加反向切向推力，会让两单位在前进方向上一前一后错开，
	#       下一帧连线方向翻号、切向选择反转，形成左右位置震荡。
	var move_a := _get_move_direction(a)
	var move_b := _get_move_direction(b)
	var combined := move_a + move_b
	var same_direction := move_a.length() > 0.01 and move_b.length() > 0.01 \
			and move_a.dot(move_b) > SAME_DIRECTION_DOT
	if combined.length() > 0.01 and not same_direction:
		var tangent := Vector2(-direction.y, direction.x)
		if tangent.dot(combined) < 0.0:
			tangent = -tangent
		a.position += tangent * push_a * TANGENTIAL_SLIDE
		b.position -= tangent * push_b * TANGENTIAL_SLIDE


## 后处理：河道回弹 + 边界钳制。对所有实体执行，保证不会出现卡河道或飞出地图的情况。
static func _post_process(entities: Array) -> void:
	for e in entities:
		# 河道回弹：地面单位被推入河道（非桥面）时处理
		if _get_layer(e) == "ground":
			if BattlePathing.is_in_river(e.position) and not BattlePathing.is_on_bridge(e.position):
				# 桥面边缘吸附：单位被碰撞分离推到桥面外缘（≤ 碰撞半径距离）时，
				# 把 x 拉回桥面边缘，而非弹回岸。避免在桥面边界处反复"入水→弹回→再入水"震荡。
				# A* 路径经过桥格 4（中心 x=90 = 桥面右边界），单位沿 x=90 过桥时
				# 任何微小推力都会让中心点越界触发回弹，形成死锁。
				var snap_x := _try_bridge_snap_x(e.position.x, _get_collision_radius(e))
				if snap_x >= 0.0:
					e.position.x = snap_x
				else:
					# 离桥面太远：正常弹回最近岸
					var river_mid := (BattleConstants.RIVER_Y_MIN + BattleConstants.RIVER_Y_MAX) * 0.5
					if e.position.y < river_mid:
						e.position.y = BattleConstants.RIVER_Y_MIN - RIVER_BOUNCE_MARGIN
					else:
						e.position.y = BattleConstants.RIVER_Y_MAX + RIVER_BOUNCE_MARGIN

		# 边界钳制
		var r := _get_collision_radius(e)
		e.position.x = clampf(e.position.x, r, BattleConstants.ARENA_WIDTH - r)
		e.position.y = clampf(e.position.y, r, BattleConstants.ARENA_HEIGHT - r)


## 检查 x 是否在某个桥面边缘的容差范围内。是则返回钳制到桥面边缘的 x，否则返回 -1。
## tolerance 通常为单位碰撞半径——单位中心可以越出桥面边缘最多一个半径距离（身体仍接触桥面）。
static func _try_bridge_snap_x(x: float, tolerance: float) -> float:
	# 左桥 [LEFT_BRIDGE_X_MIN, LEFT_BRIDGE_X_MAX]
	if x >= BattleConstants.LEFT_BRIDGE_X_MIN - tolerance and x <= BattleConstants.LEFT_BRIDGE_X_MAX + tolerance:
		return clampf(x, BattleConstants.LEFT_BRIDGE_X_MIN, BattleConstants.LEFT_BRIDGE_X_MAX)
	# 右桥 [RIGHT_BRIDGE_X_MIN, RIGHT_BRIDGE_X_MAX]
	if x >= BattleConstants.RIGHT_BRIDGE_X_MIN - tolerance and x <= BattleConstants.RIGHT_BRIDGE_X_MAX + tolerance:
		return clampf(x, BattleConstants.RIGHT_BRIDGE_X_MIN, BattleConstants.RIGHT_BRIDGE_X_MAX)
	return -1.0


# ============================================================
#  工具方法
# ============================================================

static func _get_layer(entity: Node2D) -> String:
	var mt = entity.get("movement_type")
	if mt == null:
		return "ground"
	return str(mt)


## 是否处于部署虚影期且为普通单位（非建筑）。
## is_deployed=false 且 mass>0 → 部署虚影中，跳过碰撞推挤（允许叠加部署）。
static func _is_deploying_non_building(entity: Node2D) -> bool:
	return entity.get("is_deployed") == false and _get_mass(entity) > 0


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


static func _get_move_direction(entity: Node2D) -> Vector2:
	if entity.has_method("get_move_direction"):
		return entity.get_move_direction()
	return Vector2.ZERO
