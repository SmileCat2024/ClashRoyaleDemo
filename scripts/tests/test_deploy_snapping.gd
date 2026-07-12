# 文件名：test_deploy_snapping.gd
# 作用：部署位置吸附系统的单元测试。覆盖建筑冲突检测、区域合法性综合判定、
#       非法位置自动吸附到最近合法格、法术全图含河道可施放。
# 挂载位置：不挂载。由 TestRunner 自动加载。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")
const ArenaScript := preload("res://scripts/battle/Arena.gd")

# Arena 脚本无 class_name，不加类型注解以免阻断 := 返回类型推断
var _arena
var _obstacles: Array = []


func setup() -> void:
	EntityRegistry.clear()
	_arena = ArenaScript.new()
	_obstacles = []


func teardown() -> void:
	EntityRegistry.clear()
	for obs in _obstacles:
		if is_instance_valid(obs):
			obs.free()
	if is_instance_valid(_arena):
		_arena.free()
	_obstacles = []


## 创建一个模拟障碍（塔/建筑），mass=0 注册到 EntityRegistry
func _make_obstacle(pos: Vector2, radius_cells: float, team: String) -> Node:
	var obs := MockScript.new()
	obs.team = team
	obs.mass = 0
	obs.collision_radius = BattleConstants.px(radius_cells)
	obs.position = pos
	EntityRegistry.register(obs)
	_obstacles.append(obs)
	return obs


# ============================================================
#  overlaps_static_obstacle
# ============================================================

func test_obstacle_at_center_detected() -> void:
	_make_obstacle(Vector2(70, 510), 1.5, "player")  # 公主塔位置，半径 30px
	assert_true(_arena.overlaps_static_obstacle(Vector2(70, 510)), "塔中心应检测到障碍重叠")


func test_obstacle_within_margin_detected() -> void:
	_make_obstacle(Vector2(70, 510), 1.5, "player")
	# 距塔 35px < 30+10(margin)=40
	assert_true(_arena.overlaps_static_obstacle(Vector2(105, 510)), "距塔35px在margin内应检测到障碍")


func test_obstacle_outside_radius_no_overlap() -> void:
	_make_obstacle(Vector2(70, 510), 1.5, "player")
	# 距塔 50px > 40
	assert_false(_arena.overlaps_static_obstacle(Vector2(120, 510)), "距塔50px超出margin不应检测到障碍")


func test_no_obstacle_no_overlap() -> void:
	assert_false(_arena.overlaps_static_obstacle(Vector2(100, 400)), "无障碍时不应检测到重叠")


# ============================================================
#  is_cell_deployable
# ============================================================

func test_unit_deployable_in_open_area() -> void:
	assert_true(_arena.is_cell_deployable(Vector2(180, 400), false, "player"), "玩家半场空旷处应可部署")


func test_unit_not_deployable_on_obstacle() -> void:
	_make_obstacle(Vector2(70, 510), 1.5, "player")
	assert_false(_arena.is_cell_deployable(Vector2(70, 510), false, "player"), "塔上不可部署单位")


func test_unit_not_deployable_outside_half() -> void:
	# 敌方半场 y < 340
	assert_false(_arena.is_cell_deployable(Vector2(180, 100), false, "player"), "玩家单位不可部署在敌方半场")


func test_unit_not_deployable_in_river() -> void:
	assert_false(_arena.is_cell_deployable(Vector2(180, 320), false, "player"), "玩家单位不可部署在河道")


func test_spell_deployable_everywhere() -> void:
	assert_true(_arena.is_cell_deployable(Vector2(180, 320), true, "player"), "法术可在河道施放")
	assert_true(_arena.is_cell_deployable(Vector2(180, 100), true, "player"), "法术可在敌方半场施放")
	assert_true(_arena.is_cell_deployable(Vector2(180, 500), true, "player"), "法术可在己方半场施放")


func test_spell_deployable_on_obstacle() -> void:
	_make_obstacle(Vector2(70, 510), 1.5, "player")
	assert_true(_arena.is_cell_deployable(Vector2(70, 510), true, "player"), "法术可在建筑上施放")


# ============================================================
#  find_nearest_valid_deploy
# ============================================================

func test_find_nearest_open_area_snaps_to_cell_center() -> void:
	# 合法区域内的位置应直接吸附到最近格中心，不偏移
	var result: Vector2 = _arena.find_nearest_valid_deploy(Vector2(105, 405), false, "player")
	assert_eq(result, Vector2(110, 410), "合法区域内应直接吸附到最近格中心")


func test_find_nearest_snaps_off_obstacle() -> void:
	_make_obstacle(Vector2(70, 510), 1.5, "player")
	var result: Vector2 = _arena.find_nearest_valid_deploy(Vector2(70, 510), false, "player")
	# 返回位置应合法且不在障碍上
	assert_false(_arena.overlaps_static_obstacle(result), "吸附后位置不应在障碍上")
	assert_true(_arena.is_cell_deployable(result, false, "player"), "吸附后位置应可部署")


func test_find_nearest_snaps_from_outside_boundary() -> void:
	# 从竞技场左边界外吸附回来
	var result: Vector2 = _arena.find_nearest_valid_deploy(Vector2(-50, 400), false, "player")
	assert_true(_arena.is_cell_deployable(result, false, "player"), "出界位置吸附后应合法")
	assert_true(result.x >= BattleConstants.px(0.5), "吸附后 x 应在可部署区域内")


func test_find_nearest_snaps_from_enemy_half() -> void:
	# 从敌方半场吸附回己方半场
	var result: Vector2 = _arena.find_nearest_valid_deploy(Vector2(180, 100), false, "player")
	assert_true(result.y >= BattleConstants.PLAYER_DEPLOY_Y_MIN, "从敌方半场吸附后 y 应在玩家部署区域内")


func test_find_nearest_spell_in_river_stays() -> void:
	# 法术在河道应直接吸附到格中心，不被偏移
	var result: Vector2 = _arena.find_nearest_valid_deploy(Vector2(180, 320), true, "player")
	var expected := BattleConstants.snap_to_cell_center(Vector2(180, 320))
	assert_eq(result, expected, "法术在河道应直接吸附到格中心，不偏移到陆地")
	assert_true(_arena.is_cell_deployable(result, true, "player"), "法术河道格中心应合法")
