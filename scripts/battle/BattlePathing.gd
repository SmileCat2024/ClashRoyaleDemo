# 文件名：BattlePathing.gd
# 作用：提供战场路径工具，统一处理河道、桥和地面/空中单位的可达距离。
# 挂载位置：不需要挂载。通过 class_name 注册为全局类型。
# 初学者阅读建议：先看 path_distance()，再看 get_next_waypoint()。

class_name BattlePathing

const ARRIVAL_EPSILON := 1.0


## 节点位置转为 World 本地的游戏空间坐标。BattleConstants 中的桥/河/塔坐标都在这个空间。
static func game_position_of(node: Node2D) -> Vector2:
	if node == null:
		return Vector2.ZERO
	var tree := node.get_tree()
	if tree and tree.current_scene:
		var world := tree.current_scene.get_node_or_null("World") as Node2D
		if world:
			return world.to_local(node.global_position)
	return node.global_position


## 点是否处在河道 y 区间。
static func is_in_river(pos: Vector2) -> bool:
	return pos.y >= BattleConstants.RIVER_Y_MIN and pos.y <= BattleConstants.RIVER_Y_MAX


## 点是否处在任意桥的 x 区间。
static func is_bridge_x(x: float) -> bool:
	var on_left := x >= BattleConstants.LEFT_BRIDGE_X_MIN and x <= BattleConstants.LEFT_BRIDGE_X_MAX
	var on_right := x >= BattleConstants.RIGHT_BRIDGE_X_MIN and x <= BattleConstants.RIGHT_BRIDGE_X_MAX
	return on_left or on_right


## 点是否在桥面区域内。
static func is_on_bridge(pos: Vector2) -> bool:
	return is_in_river(pos) and is_bridge_x(pos.x)


## -1=上半场，1=下半场，0=河道区间。
static func river_side(pos: Vector2) -> int:
	if pos.y < BattleConstants.RIVER_Y_MIN:
		return -1
	if pos.y > BattleConstants.RIVER_Y_MAX:
		return 1
	return 0


## 按可达路径计算距离。空中单位直线飞；普通地面单位跨河走桥；
## 可跳河单位比较走桥和跳河两条路线，取更短的可达距离。
static func path_distance(from_pos: Vector2, to_pos: Vector2, movement_type: String = "ground", can_jump_river: bool = false) -> float:
	if movement_type == "air" or not _needs_bridge_route(from_pos, to_pos):
		return from_pos.distance_to(to_pos)
	if can_jump_river:
		return min(_distance_via_best_bridge(from_pos, to_pos), _distance_via_river_jump(from_pos, to_pos))

	return _distance_via_best_bridge(from_pos, to_pos)


## 可跳河单位是否应该选择跳河。平局优先走桥，避免在桥面上多余起跳。
static func should_jump_river(from_pos: Vector2, to_pos: Vector2) -> bool:
	if not _needs_bridge_route(from_pos, to_pos):
		return false
	var jump_dist := _distance_via_river_jump(from_pos, to_pos)
	var bridge_dist := _distance_via_best_bridge(from_pos, to_pos)
	return jump_dist < bridge_dist - ARRIVAL_EPSILON


## 返回下一段要走向的路径点。地面单位跨河时会先对齐最近桥，再过桥，再走向目标。
static func get_next_waypoint(from_pos: Vector2, to_pos: Vector2, movement_type: String = "ground") -> Vector2:
	if movement_type == "air" or not _needs_bridge_route(from_pos, to_pos):
		return to_pos

	var from_side := river_side(from_pos)
	var to_side := river_side(to_pos)
	var bridge_x := _best_bridge_x(from_pos, to_pos)

	if from_side == 0:
		if is_on_bridge(from_pos):
			bridge_x = _current_bridge_x(from_pos)
			if to_side < 0:
				return Vector2(bridge_x, BattleConstants.RIVER_Y_MIN)
			if to_side > 0:
				return Vector2(bridge_x, BattleConstants.RIVER_Y_MAX)
			return to_pos
		return Vector2(bridge_x, from_pos.y)

	var entry_y := BattleConstants.RIVER_Y_MAX if from_side > 0 else BattleConstants.RIVER_Y_MIN
	var entry := Vector2(bridge_x, entry_y)
	if from_pos.distance_to(entry) > ARRIVAL_EPSILON:
		return entry

	var exit_y := BattleConstants.RIVER_Y_MIN if from_side > 0 else BattleConstants.RIVER_Y_MAX
	return Vector2(bridge_x, exit_y)


## 沿路径前进最多 max_distance 像素，避免一帧跨过桥点后又直线穿河。
static func advance_position(from_pos: Vector2, to_pos: Vector2, max_distance: float, movement_type: String = "ground") -> Vector2:
	var remaining := max_distance
	var current := from_pos
	var guard := 0

	while remaining > 0.0 and guard < 4:
		guard += 1
		var waypoint := get_next_waypoint(current, to_pos, movement_type)
		var to_waypoint := waypoint - current
		var dist := to_waypoint.length()
		if dist <= ARRIVAL_EPSILON:
			current = waypoint
			continue
		if dist > remaining:
			return current + to_waypoint.normalized() * remaining
		current = waypoint
		remaining -= dist

	return current


static func _needs_bridge_route(from_pos: Vector2, to_pos: Vector2) -> bool:
	var from_side := river_side(from_pos)
	var to_side := river_side(to_pos)

	if from_side != 0 and to_side != 0:
		return from_side != to_side
	if from_side == 0 and to_side == 0:
		return not is_on_bridge(from_pos) or not is_on_bridge(to_pos)
	if from_side == 0:
		if not is_on_bridge(from_pos):
			return true
		if to_side < 0:
			return from_pos.y > BattleConstants.RIVER_Y_MIN + ARRIVAL_EPSILON
		return from_pos.y < BattleConstants.RIVER_Y_MAX - ARRIVAL_EPSILON
	if to_side == 0:
		return not is_on_bridge(to_pos)
	return false


static func _distance_via_bridge(from_pos: Vector2, to_pos: Vector2, bridge_x: float) -> float:
	var from_side := river_side(from_pos)
	var to_side := river_side(to_pos)
	var from_entry_y := BattleConstants.RIVER_Y_MAX if from_side >= 0 else BattleConstants.RIVER_Y_MIN
	var to_exit_y := BattleConstants.RIVER_Y_MAX if to_side >= 0 else BattleConstants.RIVER_Y_MIN
	var entry := Vector2(bridge_x, from_entry_y)
	var exit := Vector2(bridge_x, to_exit_y)
	return from_pos.distance_to(entry) + entry.distance_to(exit) + exit.distance_to(to_pos)


static func _distance_via_best_bridge(from_pos: Vector2, to_pos: Vector2) -> float:
	var left_dist := _distance_via_bridge(from_pos, to_pos, BattleConstants.LEFT_LANE_X)
	var right_dist := _distance_via_bridge(from_pos, to_pos, BattleConstants.RIGHT_LANE_X)
	return min(left_dist, right_dist)


static func _distance_via_river_jump(from_pos: Vector2, to_pos: Vector2) -> float:
	var from_side := river_side(from_pos)
	if from_side == 0:
		return from_pos.distance_to(to_pos)
	var start_y := BattleConstants.RIVER_Y_MAX if from_side > 0 else BattleConstants.RIVER_Y_MIN
	var end_y := BattleConstants.RIVER_Y_MIN if from_side > 0 else BattleConstants.RIVER_Y_MAX
	var start := Vector2(from_pos.x, start_y)
	var end := Vector2(from_pos.x, end_y)
	return from_pos.distance_to(start) + start.distance_to(end) + end.distance_to(to_pos)


static func _best_bridge_x(from_pos: Vector2, to_pos: Vector2) -> float:
	var left_dist := _distance_via_bridge(from_pos, to_pos, BattleConstants.LEFT_LANE_X)
	var right_dist := _distance_via_bridge(from_pos, to_pos, BattleConstants.RIGHT_LANE_X)
	if left_dist <= right_dist:
		return BattleConstants.LEFT_LANE_X
	return BattleConstants.RIGHT_LANE_X


static func _current_bridge_x(pos: Vector2) -> float:
	var left_center_dist := absf(pos.x - BattleConstants.LEFT_LANE_X)
	var right_center_dist := absf(pos.x - BattleConstants.RIGHT_LANE_X)
	if left_center_dist <= right_center_dist:
		return BattleConstants.LEFT_LANE_X
	return BattleConstants.RIGHT_LANE_X
