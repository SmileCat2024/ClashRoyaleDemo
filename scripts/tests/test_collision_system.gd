# 文件名：test_collision_system.gd
# 作用：碰撞分离系统的单元测试。覆盖两体分离、质量分配、不可移动实体、
#       跨层不碰、同位置回退、河道回弹、无重叠不变。
# 挂载位置：不挂载。由 TestRunner 自动加载。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")


func test_two_units_separate() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 10.0
	b.collision_radius = 10.0
	a.position = Vector2(100, 200)
	b.position = Vector2(115, 200)  # dist=15, radius_sum=20, overlap=5

	CollisionSystem.resolve_overlaps([a, b])

	var dist := a.position.distance_to(b.position)
	assert_approx(dist, 20.0, 0.5, "两体重叠单位应被分离到恰好 radius_sum")
	a.free()
	b.free()


func test_no_overlap_no_change() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 10.0
	b.collision_radius = 10.0
	a.position = Vector2(100, 200)
	b.position = Vector2(150, 200)  # dist=50 > radius_sum=20, 无重叠

	CollisionSystem.resolve_overlaps([a, b])

	assert_eq(a.position, Vector2(100, 200), "无重叠时单位 A 不应移动")
	assert_eq(b.position, Vector2(150, 200), "无重叠时单位 B 不应移动")
	a.free()
	b.free()


func test_mass_weighted() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 10.0
	a.mass = 10  # 重
	b.collision_radius = 10.0
	b.mass = 2   # 轻
	a.position = Vector2(100, 200)
	b.position = Vector2(110, 200)  # dist=10, overlap=10

	CollisionSystem.resolve_overlaps([a, b])

	# inv_a=0.1, inv_b=0.5, total=0.6
	# move_a = 10 * 0.1/0.6 ≈ 1.667
	# move_b = 10 * 0.5/0.6 ≈ 8.333
	var move_a := 100.0 - a.position.x
	var move_b := b.position.x - 110.0
	assert_approx(move_a, 1.667, 0.1, "高质量单位应被推得更少")
	assert_approx(move_b, 8.333, 0.1, "低质量单位应被推得更多")
	a.free()
	b.free()


func test_immovable_tower() -> void:
	var tower := MockScript.new()
	var unit := MockScript.new()
	tower.collision_radius = 30.0
	tower.mass = 0  # 不可移动
	unit.collision_radius = 10.0
	unit.mass = 5
	tower.position = Vector2(100, 200)
	unit.position = Vector2(100, 170)  # dist=30, radius_sum=40, overlap=10

	CollisionSystem.resolve_overlaps([tower, unit])

	# 塔不动，单位承担全部修正
	assert_eq(tower.position, Vector2(100, 200), "不可移动的塔不应被推动")
	var dist := tower.position.distance_to(unit.position)
	assert_approx(dist, 40.0, 0.5, "单位应被推到恰好 radius_sum 处")
	tower.free()
	unit.free()


func test_different_layers_no_collision() -> void:
	var ground := MockScript.new()
	var air := MockScript.new()
	ground.collision_radius = 10.0
	air.collision_radius = 10.0
	ground.movement_type = "ground"
	air.movement_type = "air"
	ground.position = Vector2(100, 200)
	air.position = Vector2(100, 200)  # 完全重叠但不同层

	CollisionSystem.resolve_overlaps([ground, air])

	assert_eq(ground.position, Vector2(100, 200), "地面单位不应被空中单位推开")
	assert_eq(air.position, Vector2(100, 200), "空中单位不应被地面单位推开")
	ground.free()
	air.free()


func test_same_position_fallback() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 10.0
	b.collision_radius = 10.0
	a.position = Vector2(100, 200)
	b.position = Vector2(100, 200)  # 完全同位置

	CollisionSystem.resolve_overlaps([a, b])

	# 回退方向：a.x == b.x → direction=(1,0)，A 向左、B 向右
	var dist := a.position.distance_to(b.position)
	assert_approx(dist, 20.0, 0.5, "同位置单位应沿 x 轴确定性分离")
	assert_true(a.position.x < 100.0, "A 应被推向左侧")
	assert_true(b.position.x > 100.0, "B 应被推向右侧")
	a.free()
	b.free()


func test_river_bounce() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 15.0
	b.collision_radius = 15.0
	a.position = Vector2(100, 310)  # 河道内（y=300-340），x=100 非桥面
	b.position = Vector2(100, 330)  # 同样在河道内

	CollisionSystem.resolve_overlaps([a, b])

	# 后处理应将两个地面单位从河道弹回岸上
	var a_in_river := BattlePathing.is_in_river(a.position) and not BattlePathing.is_on_bridge(a.position)
	var b_in_river := BattlePathing.is_in_river(b.position) and not BattlePathing.is_on_bridge(b.position)
	assert_false(a_in_river, "单位 A 不应留在河道中")
	assert_false(b_in_river, "单位 B 不应留在河道中")
	a.free()
	b.free()


func test_boundary_clamp() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 15.0
	b.collision_radius = 15.0
	a.position = Vector2(2, 200)  # 接近左边界
	b.position = Vector2(5, 200)  # 与 A 重叠，碰撞会把 A 推向左边界外

	CollisionSystem.resolve_overlaps([a, b])

	# 边界钳制：位置不应小于 collision_radius
	assert_true(a.position.x >= 15.0 - 0.01, "单位 A 应被钳制在左边界内（x >= collision_radius）")
	assert_true(b.position.x >= 15.0 - 0.01, "单位 B 应被钳制在左边界内（x >= collision_radius）")
	a.free()
	b.free()
