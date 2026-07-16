# 文件名：test_unit_animation_facing.gd
# 作用：验证行走动画跟随实际路径方向，而不是最终攻击/移动目标方向。
# 挂载位置：由 TestRunner 实例化。

extends TestBase


func _make_moving_unit(move_dir: Vector2, target_pos: Vector2) -> Array:
	var unit := UnitBase.new()
	unit.team = "player"
	unit.is_deployed = true
	unit.position = Vector2(100, 100)
	unit._is_moving = true
	unit._last_move_dir = move_dir.normalized()

	var target := Node2D.new()
	target.position = target_pos
	add_child(target)
	unit._move_target = target
	return [unit, target]


func test_walk_front_follows_downward_waypoint_when_final_target_is_above() -> void:
	var pair := _make_moving_unit(Vector2.DOWN, Vector2(100, 0))
	var unit: UnitBase = pair[0]
	var target: Node2D = pair[1]

	assert_eq(unit.get_facing(), "front",
		"最终目标在上方但 A* 下一路径点向下时，应播放 walk_front")
	unit.free()
	target.free()


func test_walk_back_follows_upward_waypoint_when_final_target_is_below() -> void:
	var pair := _make_moving_unit(Vector2.UP, Vector2(100, 200))
	var unit: UnitBase = pair[0]
	var target: Node2D = pair[1]

	assert_eq(unit.get_facing(), "back",
		"最终目标在下方但 A* 下一路径点向上时，应播放 walk_back")
	unit.free()
	target.free()


func test_walk_flip_follows_horizontal_detour_instead_of_final_target() -> void:
	var pair := _make_moving_unit(Vector2.RIGHT, Vector2(0, 100))
	var unit: UnitBase = pair[0]
	var target: Node2D = pair[1]

	assert_true(unit.get_flip_h(),
		"最终目标在左侧但实际绕路向右时，贴图应朝右翻转")
	unit.free()
	target.free()


func test_idle_facing_still_uses_target_direction() -> void:
	var pair := _make_moving_unit(Vector2.DOWN, Vector2(200, 0))
	var unit: UnitBase = pair[0]
	var target: Node2D = pair[1]
	unit._is_moving = false

	assert_eq(unit.get_facing(), "back", "静止时仍应面向上方目标")
	assert_true(unit.get_flip_h(), "静止时仍应按右侧目标设置水平翻转")
	unit.free()
	target.free()
