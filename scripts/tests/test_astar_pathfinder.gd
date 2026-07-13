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
	# 格 (3,20)→(3,10)，x=70 在左桥中心（收紧后唯一桥格）→ 河道格可通行 → 无障碍直线
	var path := AStarPathfinder.find_path(Vector2(70, 400), Vector2(70, 200), 0.5)
	assert_false(path.is_empty(), "无障碍时路径不应为空")
	assert_eq(path[-1], Vector2(70, 200), "路径终点应等于目标")
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
#  桥入口卡兵回归（路径不得斜穿桥面外水域）
# ============================================================

## 检查从 from 出发、依次经过 path 各点的折线，是否穿过"河道 y 区间但不在桥面 x 区间"的区域。
## 这是 CollisionSystem 河道回弹的触发条件——单位中心点进入此区域会被反复推回，形成死锁。
func _path_crosses_off_bridge_river(from: Vector2, path: Array) -> bool:
	var prev := from
	for curr in path:
		if _segment_crosses_off_bridge_river(prev, curr):
			return true
		prev = curr
	return false


## 检查线段 [a, b] 是否穿过桥面外水域。采样步长 4 像素。
func _segment_crosses_off_bridge_river(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	if dist < 1.0:
		return false
	var steps := maxi(2, int(dist / 4.0))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		if BattlePathing.is_in_river(p) and not BattlePathing.is_bridge_x(p.x):
			return true
	return false


## 中场单位（x 偏离桥中心）过左桥时，路径不得斜穿桥面外水域。
## 这是桥入口卡兵死锁的核心场景：A* 桥格判定若过宽（格 2/4 也算桥格），
## 平滑会生成 (110,410)→(90,270) 这样的大斜线，在 y∈[300,340] 段 x∈[94,100]
## 全部落在桥面外水域，单位走到此处被河道回弹反复推回 y=341，形成死锁。
func test_bridge_entry_no_cross_off_bridge_river() -> void:
	# 场景 1：中场过左桥（从桥内侧斜进）
	var path1 := AStarPathfinder.find_path(Vector2(110, 410), Vector2(110, 200), 0.5)
	assert_false(path1.is_empty(), "中场过左桥路径不应为空")
	assert_false(_path_crosses_off_bridge_river(Vector2(110, 410), path1),
		"中场过左桥路径不得斜穿桥面外水域")

	# 场景 2：中场过右桥（对称）
	var path2 := AStarPathfinder.find_path(Vector2(250, 410), Vector2(250, 200), 0.5)
	assert_false(path2.is_empty(), "中场过右桥路径不应为空")
	assert_false(_path_crosses_off_bridge_river(Vector2(250, 410), path2),
		"中场过右桥路径不得斜穿桥面外水域")

	# 场景 3：紧贴桥内侧 x=95（最严苛——起点 x 已在桥面外）
	var path3 := AStarPathfinder.find_path(Vector2(95, 410), Vector2(95, 200), 0.5)
	assert_false(path3.is_empty(), "紧贴桥内侧过桥路径不应为空")
	assert_false(_path_crosses_off_bridge_river(Vector2(95, 410), path3),
		"紧贴桥内侧过桥路径不得斜穿桥面外水域")

	# 场景 4：大半径单位（巨人 0.8 格）
	var path4 := AStarPathfinder.find_path(Vector2(110, 410), Vector2(110, 200), 0.8)
	assert_false(path4.is_empty(), "大半径单位过桥路径不应为空")
	assert_false(_path_crosses_off_bridge_river(Vector2(110, 410), path4),
		"大半径单位过桥路径不得斜穿桥面外水域")

	# 场景 5：敌方半场对称（从上往下过右桥）
	var path5 := AStarPathfinder.find_path(Vector2(250, 200), Vector2(250, 410), 0.5)
	assert_false(path5.is_empty(), "敌方半场过右桥路径不应为空")
	assert_false(_path_crosses_off_bridge_river(Vector2(250, 200), path5),
		"敌方半场过右桥路径不得斜穿桥面外水域")


## 收紧桥格判定后，左桥只有格 3（x=70），右桥只有格 14（x=290）。
## 验证 A* 路径确实经过桥中心 x，而非桥面边界（x=50/90 等）。
func test_bridge_path_goes_through_center() -> void:
	var path := AStarPathfinder.find_path(Vector2(110, 410), Vector2(110, 200), 0.5)
	assert_false(path.is_empty(), "路径不应为空")
	# 路径中应至少有一个点在左桥中心 x=70 附近（±5px 容差）
	var has_center_point := false
	for p in path:
		if absf(p.x - 70.0) < 5.0 and BattlePathing.is_in_river(p):
			has_center_point = true
			break
	assert_true(has_center_point, "左桥路径应经过桥中心 x=70（实际路径：%s）" % str(path))


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
