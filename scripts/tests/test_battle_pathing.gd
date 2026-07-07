# 文件名：test_battle_pathing.gd
# 作用：测试地面单位按桥寻路、可达距离和空中单位直线移动。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看跨河距离测试，再看 advance_position 的移动测试。

extends TestBase


func test_ground_path_distance_uses_bridge_when_crossing_river() -> void:
	var from_pos := Vector2(180, 380)
	var to_pos := Vector2(180, 260)
	var direct := from_pos.distance_to(to_pos)
	var path := BattlePathing.path_distance(from_pos, to_pos, "ground")

	assert_true(path > direct, "地面单位跨河距离应按桥路径计算，不能用直线距离")


func test_air_path_distance_is_direct_when_crossing_river() -> void:
	var from_pos := Vector2(180, 380)
	var to_pos := Vector2(180, 260)
	var direct := from_pos.distance_to(to_pos)
	var path := BattlePathing.path_distance(from_pos, to_pos, "air")

	assert_approx(path, direct, 0.001, "空中单位跨河仍应使用直线距离")


func test_jump_river_path_distance_is_shorter_than_bridge_route() -> void:
	var from_pos := Vector2(180, 380)
	var to_pos := Vector2(180, 260)
	var bridge_path := BattlePathing.path_distance(from_pos, to_pos, "ground", false)
	var jump_path := BattlePathing.path_distance(from_pos, to_pos, "ground", true)

	assert_true(jump_path < bridge_path, "可跳河单位跨河可达距离应短于普通走桥路线")


func test_jump_river_path_prefers_bridge_when_on_bridge_lane() -> void:
	var from_pos := Vector2(BattleConstants.LEFT_LANE_X, 380)
	var to_pos := Vector2(BattleConstants.LEFT_LANE_X, 260)

	assert_false(BattlePathing.should_jump_river(from_pos, to_pos),
		"可跳河单位在桥线上跨河时应正常走桥，不做多余跳跃")


func test_ground_next_waypoint_goes_to_nearest_bridge() -> void:
	var from_pos := Vector2(220, 380)
	var to_pos := Vector2(220, 260)
	var waypoint := BattlePathing.get_next_waypoint(from_pos, to_pos, "ground")

	assert_eq(waypoint, Vector2(BattleConstants.RIGHT_LANE_X, BattleConstants.RIVER_Y_MAX),
		"地面单位跨河时应先走向更近的右桥入口")


func test_ground_advance_does_not_enter_non_bridge_river() -> void:
	var from_pos := Vector2(180, 360)
	var to_pos := Vector2(180, 260)
	var next_pos := BattlePathing.advance_position(from_pos, to_pos, 80.0, "ground")

	assert_false(BattlePathing.is_in_river(next_pos) and not BattlePathing.is_on_bridge(next_pos),
		"地面单位不应进入非桥面的河道区域")


func test_ground_on_bridge_crosses_river_along_bridge() -> void:
	var from_pos := Vector2(BattleConstants.LEFT_LANE_X, BattleConstants.RIVER_Y_MAX)
	var to_pos := Vector2(180, 260)
	var next_pos := BattlePathing.advance_position(from_pos, to_pos, 25.0, "ground")

	assert_eq(next_pos.x, BattleConstants.LEFT_LANE_X, "在桥上过河时 x 应保持在桥中心")
	assert_true(next_pos.y < BattleConstants.RIVER_Y_MAX, "应沿桥向河对岸移动")
