# 文件名：test_river_jump.gd
# 作用：测试可跳河地面单位的状态切换、2.5D 离地视觉和落地恢复。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看野猪骑士用例，再看骑士不会跳河的对照用例。

extends TestBase

const UnitScene := preload("res://scenes/entities/units/UnitBase.tscn")

var _unit: UnitBase


func teardown() -> void:
	if _unit and is_instance_valid(_unit):
		_unit.free()
	_unit = null


func _make_unit(unit_id: String, pos: Vector2) -> UnitBase:
	_unit = UnitScene.instantiate() as UnitBase
	add_child(_unit)
	_unit.global_position = pos
	_unit.setup(DataRegistry.get_unit_data(unit_id), "player")
	return _unit


func test_hog_rider_starts_jump_and_becomes_air() -> void:
	var hog := _make_unit("hog_rider", Vector2(180, 360))

	hog._move_towards_position(Vector2(180, 260), 1.0)

	assert_true(hog.is_jumping_river, "野猪骑士跨河时应进入跳河状态")
	assert_eq(hog.movement_type, "air", "跳河期间应临时视为空中单位")
	assert_true(hog.global_position.y > BattleConstants.RIVER_Y_MAX,
		"跳跃起点应在己方河岸外侧，不落在河道内部")


func test_hog_rider_jump_uses_altitude_arc() -> void:
	var hog := _make_unit("hog_rider", Vector2(180, 360))
	hog._move_towards_position(Vector2(180, 260), 1.0)

	hog._process_river_jump(hog._jump_duration * 0.5)

	assert_true(hog.is_jumping_river, "跳跃中点仍应处于跳河状态")
	assert_true(hog.altitude > 0.0, "跳河中点应有离地高度形成抛物线")
	assert_eq(hog.movement_type, "air", "跳跃中点仍应按空中单位处理")


func test_hog_rider_lands_and_restores_ground_type() -> void:
	var hog := _make_unit("hog_rider", Vector2(180, 360))
	hog._move_towards_position(Vector2(180, 260), 1.0)

	hog._process_river_jump(hog._jump_duration + 0.1)

	assert_false(hog.is_jumping_river, "跳跃结束后应退出跳河状态")
	assert_eq(hog.movement_type, "ground", "落地后应恢复地面单位")
	assert_approx(hog.altitude, 0.0, 0.001, "落地后离地高度应归零")
	assert_true(hog.global_position.y < BattleConstants.RIVER_Y_MIN,
		"落点应在对岸河岸外侧，不留在河道内部")


func test_hog_rider_uses_bridge_without_jumping_when_on_bridge_lane() -> void:
	var hog := _make_unit("hog_rider", Vector2(BattleConstants.LEFT_LANE_X, 360))

	hog._move_towards_position(Vector2(BattleConstants.LEFT_LANE_X, 260), 1.0)

	assert_false(hog.is_jumping_river, "野猪骑士在桥线上跨河时应走桥，不应跳河")
	assert_eq(hog.movement_type, "ground", "走桥时仍应保持地面单位状态")


func test_knight_does_not_jump_river() -> void:
	var knight := _make_unit("knight", Vector2(180, 360))

	knight._move_towards_position(Vector2(180, 260), 1.0)

	assert_false(knight.is_jumping_river, "未配置 can_jump_river 的地面单位不应跳河")
	assert_eq(knight.movement_type, "ground", "普通地面单位应保持地面状态")
