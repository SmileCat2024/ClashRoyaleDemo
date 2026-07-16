# 文件名：test_charge_movement.gd
# 作用：验证王子冲锋距离的移动累计逻辑，重点是走跳河路线期间的累计。
#       修复前 _move_towards_position 在跳河分支直接 return 不调用 _accumulate_charge，
#       导致可跳河单位（王子/野猪骑士）在己方半场走跳河路线时冲锋进度永远为 0。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 test_charge_accumulates_during_river_jump_route 了解修复的核心场景。

extends TestBase

const UnitScene := preload("res://scenes/entities/units/UnitBase.tscn")

var _units: Array = []


func teardown() -> void:
	for u in _units:
		if u and is_instance_valid(u):
			u.free()
	_units.clear()


func _make_unit(unit_id: String, pos: Vector2) -> UnitBase:
	var unit := UnitScene.instantiate() as UnitBase
	add_child(unit)
	unit.global_position = pos
	unit.setup(DataRegistry.get_unit_data(unit_id), "player")
	_units.append(unit)
	return unit


## 王子在远离桥的位置（x=9格）走跳河路线期间，冲锋距离应正确累计。
## 修复前：跳河分支直接 return，_charge_distance_accum 始终为 0。
func test_charge_accumulates_during_river_jump_route() -> void:
	var prince := _make_unit("prince", Vector2(180, 360))
	# 前置条件：该位置跳河比走桥更短（x=180=9格，离左桥70px/右桥290px都远）
	assert_true(BattlePathing.should_jump_river(Vector2(180, 360), Vector2(180, 260)),
		"测试前置条件：x=9格处跳河应比走桥更短")
	assert_eq(prince._charge_distance_accum, 0.0, "初始累计应为 0")

	prince._move_towards_position(Vector2(180, 260), 0.5)

	assert_true(prince._charge_distance_accum > 0.0,
		"王子走跳河路线期间应累计冲锋距离（修复前此值始终为 0）")


## 持续走跳河路线（模拟多帧走向河岸）后，累计达到阈值应触发冲锋状态。
func test_charge_triggers_after_sustained_jump_route_movement() -> void:
	var prince := _make_unit("prince", Vector2(180, 360))
	assert_true(prince._charge_enabled, "测试前置条件：王子应启用冲锋机制")

	var delta := 0.1
	for i in range(60):
		if prince.is_charging:
			break
		prince._move_towards_position(Vector2(180, 260), delta)

	assert_true(prince.is_charging,
		"王子沿跳河路线持续移动后应进入冲锋状态")


## 桥线上走桥（不走跳河路线）时，冲锋距离也应正确累计。
func test_charge_accumulates_on_bridge_lane() -> void:
	var prince := _make_unit("prince", Vector2(BattleConstants.LEFT_LANE_X, 360))

	prince._move_towards_position(Vector2(BattleConstants.LEFT_LANE_X, 260), 0.5)

	assert_true(prince._charge_distance_accum > 0.0,
		"王子走桥路线也应累计冲锋距离")


## 野猪骑士（非冲锋单位）走跳河路线不应触发冲锋。
func test_hog_rider_no_charge_on_jump_route() -> void:
	var hog := _make_unit("hog_rider", Vector2(180, 360))
	assert_false(hog._charge_enabled, "野猪骑士不应启用冲锋机制")

	hog._move_towards_position(Vector2(180, 260), 0.5)

	assert_false(hog.is_charging, "野猪骑士不应进入冲锋状态")
