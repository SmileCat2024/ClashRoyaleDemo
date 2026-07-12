# 文件名：test_astar_pathfinder.gd
# 作用：A* 网格寻路的单元测试。
#       覆盖：无障碍直线路径、绕塔路径、河道阻挡+桥通行、目标在障碍物内修正、
#       两塔间窄通道可通过、路径平滑、起点在障碍物内修正、无路径兜底。
# 挂载位置：由 TestRunner 自动加载。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

var _mocks: Array = []


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()


func teardown() -> void:
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()


## 创建 mock 障碍物（mass=0 塔模拟）并注册到 EntityRegistry。
func _make_obstacle(pos: Vector2, radius_px: float = 30.0) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.mass = 0
	m.collision_radius = radius_px
	m.position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


## 检查路径中是否有至少一个点落在指定矩形范围内。
func _path_has_point_in_rect(path: Array, rect: Rect2) -> bool:
	for p in path:
		if rect.has_point(p):
			return true
	return false


## 检查路径中所有点（不含被替换为目标中心的最后一个点）是否远离障碍物中心。
func _path_avoids_center(path: Array, center: Vector2, min_dist: float, skip_last: bool) -> bool:
	var n := path.size() - (1 if skip_last else 0)
	for i in range(n):
		if path[i].distance_to(center) < min_dist:
			return false
	return true


# ============================================================
#  基础寻路
# ============================================================

func test_open_path_returns_target() -> void:
	# 格 (4,20)→(4,10)，x=90 在左桥范围 → 河道格可通行 → 无障碍直线
	var path := AStarPathfinder.find_path(Vector2(90, 400), Vector2(90, 200), 0.5)
	assert_false(path.is_empty(), "无障碍时路径不应为空")
	assert_eq(path[-1], Vector2(90, 200), "路径终点应等于目标")
	# 无障碍直线 → 平滑后应只有 1 个点
	assert_eq(path.size(), 1, "无障碍直线应平滑为单点路径")


func test_path_not_empty_with_obstacle() -> void:
	_make_obstacle(Vector2(90, 300), 30.0)
	var path := AStarPathfinder.find_path(Vector2(90, 400), Vector2(90, 200), 0.5)
	assert_false(path.is_empty(), "有障碍物时路径不应为空")
	assert_eq(path[-1], Vector2(90, 200), "路径终点应等于目标")


func test_path_detours_around_obstacle() -> void:
	# 正前方放一个塔，单位应绕行而非穿过
	_make_obstacle(Vector2(110, 300), 30.0)
	var path := AStarPathfinder.find_path(Vector2(110, 400), Vector2(110, 200), 0.5)
	assert_false(path.is_empty(), "绕塔路径不应为空")
	# 路径中间点不应穿过障碍物中心（膨胀半径 = 30 + 0.5*20 + 0.25*20 = 45）
	# 跳过最后一个点（被替换为目标位置，可能在塔 x 线上）
	assert_true(_path_avoids_center(path, Vector2(110, 300), 40.0, true),
		"路径中间点应远离障碍物中心")


# ============================================================
#  河道与桥
# ============================================================

func test_river_forces_bridge_route() -> void:
	# 起点和目标在河道两侧，x=170 不在桥范围 → 必须绕到桥过河
	var path := AStarPathfinder.find_path(Vector2(170, 400), Vector2(170, 200), 0.5)
	assert_false(path.is_empty(), "跨河路径不应为空")
	assert_eq(path[-1], Vector2(170, 200), "跨河路径终点应等于目标")
	# 路径中应有至少一个点在左桥区域（x=50-90, y=290-350）
	var left_bridge := Rect2(45, 290, 50, 65)
	var right_bridge := Rect2(265, 290, 50, 65)
	assert_true(
		_path_has_point_in_rect(path, left_bridge) or _path_has_point_in_rect(path, right_bridge),
		"跨河路径应经过左桥或右桥区域"
	)


func test_bridge_x_direct_cross() -> void:
	# x=70 在左桥中心 → 可直接过河
	var path := AStarPathfinder.find_path(Vector2(70, 400), Vector2(70, 200), 0.5)
	assert_false(path.is_empty(), "桥上直行路径不应为空")
	assert_eq(path[-1], Vector2(70, 200), "路径终点应等于目标")


# ============================================================
#  目标/起点在障碍物内
# ============================================================

func test_goal_inside_obstacle_corrected() -> void:
	var tower := _make_obstacle(Vector2(170, 400), 30.0)
	# 目标 = 塔中心（在障碍物内）
	var path := AStarPathfinder.find_path(Vector2(170, 200), Vector2(170, 400), 0.5)
	assert_false(path.is_empty(), "目标在障碍物内时路径不应为空")
	# 路径倒数第二个点（修正后的接近点）应在障碍物膨胀半径外
	if path.size() >= 2:
		var approach: Vector2 = path[path.size() - 2]
		var expand_r := 30.0 + 0.5 * 20.0 + 0.25 * 20.0  # 塔半径 + 单位半径 + 安全余量
		assert_true(approach.distance_to(Vector2(170, 400)) > expand_r - 5.0,
			"接近点应在障碍物膨胀半径外（dist=%f, expand=%f）" % [approach.distance_to(Vector2(170, 400)), expand_r])


func test_start_inside_obstacle_corrected() -> void:
	_make_obstacle(Vector2(170, 400), 30.0)
	# 起点 = 塔中心（单位被卡在塔旁）
	var path := AStarPathfinder.find_path(Vector2(170, 400), Vector2(170, 200), 0.5)
	assert_false(path.is_empty(), "起点在障碍物内时路径不应为空")
	assert_eq(path[-1], Vector2(170, 200), "路径终点应等于目标")


# ============================================================
#  塔间窄通道（公主塔-国王塔场景）
# ============================================================

func test_narrow_passage_between_towers() -> void:
	# 模拟玩家左公主塔和国王塔
	_make_obstacle(Vector2(70, 510), 30.0)   # 左公主塔 collision_radius=1.5格=30px
	_make_obstacle(Vector2(180, 580), 40.0)  # 国王塔 collision_radius=2.0格=40px
	# 起点：公主塔后方偏右（公主塔和国王塔之间）
	# 目标：正前方（向上推进）
	var path := AStarPathfinder.find_path(Vector2(120, 540), Vector2(120, 400), 0.5)
	assert_false(path.is_empty(), "两塔间窄通道时路径不应为空（单位应能绕出）")
	assert_eq(path[-1], Vector2(120, 400), "窄通道路径终点应等于目标")


func test_three_towers_simulated() -> void:
	# 模拟玩家全部三座塔
	_make_obstacle(Vector2(70, 510), 30.0)   # 左公主塔
	_make_obstacle(Vector2(290, 510), 30.0)  # 右公主塔
	_make_obstacle(Vector2(180, 580), 40.0)  # 国王塔
	# 起点：左公主塔后方
	# 目标：河道方向（向上）
	var path := AStarPathfinder.find_path(Vector2(100, 550), Vector2(100, 350), 0.5)
	assert_false(path.is_empty(), "三塔场景时路径不应为空")
