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


# 回归：单位被碰撞推到桥面边缘外（≤ 碰撞半径）时，x 应被吸附到桥面边缘，
# 而非弹回岸。这是桥入口卡兵死锁的根因——A* 路径经过桥格 4（中心 x=90=桥面边界），
# 单位沿 x=90 过桥时碰撞分离推到 x=91 就触发河道回弹，反复震荡。
func test_river_bounce_bridge_edge_snap() -> void:
	var a := MockScript.new()
	var dummy := MockScript.new()
	a.collision_radius = 10.0  # 标准 0.5 格
	a.movement_type = "ground"
	# 单位在河道内，x=92 略超左桥右边界 x=90（2px = 0.1 格，在碰撞半径 10px 内）
	a.position = Vector2(92, 330)
	a.mass = 5
	# dummy 远离 A，不产生碰撞交互，仅让 resolve_overlaps 进入后处理
	dummy.collision_radius = 10.0
	dummy.movement_type = "ground"
	dummy.position = Vector2(180, 580)
	dummy.mass = 5

	CollisionSystem.resolve_overlaps([a, dummy])

	# 应被吸附到桥面边缘 x=90（而非弹回岸 y=341）
	assert_approx(a.position.x, 90.0, 0.01, "桥面边缘外的单位应被吸附到 x=90")
	assert_true(BattlePathing.is_in_river(a.position),
		"吸附后单位仍应在河道 y 区间内（未被弹回岸）")
	assert_true(BattlePathing.is_on_bridge(a.position),
		"吸附后单位应在桥面上")
	a.free()
	dummy.free()


# 对照：单位离桥面太远（超出碰撞半径）时仍正常弹回岸
func test_river_bounce_far_from_bridge() -> void:
	var a := MockScript.new()
	var dummy := MockScript.new()
	a.collision_radius = 10.0
	a.movement_type = "ground"
	# x=120 离左桥右边界 x=90 有 30px，远超碰撞半径 10px
	a.position = Vector2(120, 330)
	a.mass = 5
	dummy.collision_radius = 10.0
	dummy.movement_type = "ground"
	dummy.position = Vector2(180, 580)
	dummy.mass = 5

	CollisionSystem.resolve_overlaps([a, dummy])

	# 应被弹回岸（y 回到河道外）
	assert_false(BattlePathing.is_in_river(a.position),
		"远离桥面的河道单位应被弹回岸")
	a.free()
	dummy.free()


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


# 回归：两个同向同速前进的友军重叠时，只做径向分离，不施加切向推力。
# 旧逻辑会沿连线切向把两单位一前一后错开，导致下一帧连线方向翻号、形成左右震荡。
func test_same_direction_no_tangential_slide() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 10.0
	b.collision_radius = 10.0
	a.position = Vector2(100, 200)
	b.position = Vector2(110, 200)  # dist=10, radius_sum=20, overlap=10
	# 双方都向上前进（同向）
	a.set_move_direction(Vector2(0, -1))
	b.set_move_direction(Vector2(0, -1))

	CollisionSystem.resolve_overlaps([a, b])

	# 切向 = 此处的 y 方向。同向时不应有切向位移，两单位 y 应保持 200
	assert_approx(a.position.y, 200.0, 0.01, "同向前进时 A 不应产生切向（y）位移")
	assert_approx(b.position.y, 200.0, 0.01, "同向前进时 B 不应产生切向（y）位移")
	# 径向分离仍应生效：最终间距 ≈ radius_sum
	var dist := a.position.distance_to(b.position)
	assert_approx(dist, 20.0, 0.5, "同向前进时径向分离仍应将两单位推开到 radius_sum")
	a.free()
	b.free()


# 对照：一方移动、一方静止时，切向滑动仍生效（移动方沿前进方向轻推，静止方反向轻推）。
# 确认同向跳过修复没有破坏原有的"侧滑绕过静止单位"功能。
func test_one_moving_tangential_slide_applies() -> void:
	var a := MockScript.new()
	var b := MockScript.new()
	a.collision_radius = 10.0
	b.collision_radius = 10.0
	a.position = Vector2(100, 200)
	b.position = Vector2(110, 200)  # dist=10, radius_sum=20, overlap=10
	# A 向上移动，B 静止
	a.set_move_direction(Vector2(0, -1))
	# direction(A→B)=(1,0)，tangent 翻成 (0,-1)：A 沿前进方向轻推，B 反向

	CollisionSystem.resolve_overlaps([a, b])

	# 切向滑动生效：A 的 y 应减小（向上），B 的 y 应增大（向下）
	assert_true(a.position.y < 200.0, "移动方 A 应被沿前进方向（切向）轻推，y 减小")
	assert_true(b.position.y > 200.0, "静止方 B 应被反向（切向）轻推，y 增大")
	a.free()
	b.free()
