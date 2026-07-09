# 文件名：test_projectile_base.gd
# 作用：测试 ProjectileBase 共享飞行基础设施（_fly_toward / _fly_progress / _apply_arc_offset）。
#       验证基类方法可被直接调用（无需场景树），以及 body_rect 为 null 时的安全行为。
extends TestBase


func test_fly_toward_moves_toward_target() -> void:
	var p := ProjectileBase.new()
	p.position = Vector2.ZERO
	p.speed = 100.0  # 像素/秒
	p._start_pos = Vector2.ZERO
	p._total_dist = 200.0
	var arrived := p._fly_toward(Vector2(200, 0), 0.5)
	assert_false(arrived, "距离 200px，速度 100px/s，0.5s 移动 50px → 未到达")
	assert_approx(p.position.x, 50.0, 0.5, "移动了 50 像素")
	p.free()


func test_fly_toward_arrives_in_one_frame() -> void:
	var p := ProjectileBase.new()
	p.position = Vector2.ZERO
	p.speed = 200.0
	p._start_pos = Vector2.ZERO
	p._total_dist = 50.0
	# 0.5 秒可移动 100px > 50px 距离 → 本帧到达
	var arrived := p._fly_toward(Vector2(50, 0), 0.5)
	assert_true(arrived, "速度 200px/s × 0.5s = 100px > 50px → 到达")
	assert_eq(p.position.x, 50.0, "到达后位置精确")
	p.free()


func test_fly_toward_diagonal() -> void:
	var p := ProjectileBase.new()
	p.position = Vector2.ZERO
	p.speed = 100.0
	p._start_pos = Vector2.ZERO
	p._total_dist = 100.0 * sqrt(2.0)
	var dest := Vector2(100, 100)
	var arrived := p._fly_toward(dest, 0.5)
	assert_false(arrived, "斜向飞行未到达")
	# 应在 45° 方向移动 50px
	assert_approx(p.position.x, 50.0 / sqrt(2.0), 0.5, "斜向 X 分量")
	assert_approx(p.position.y, 50.0 / sqrt(2.0), 0.5, "斜向 Y 分量")
	p.free()


func test_fly_progress_at_start() -> void:
	var p := ProjectileBase.new()
	p._start_pos = Vector2.ZERO
	p._total_dist = 100.0
	p.position = Vector2.ZERO
	assert_approx(p._fly_progress(), 0.0, 0.01, "起点进度为 0")
	p.free()


func test_fly_progress_midway() -> void:
	var p := ProjectileBase.new()
	p._start_pos = Vector2.ZERO
	p._total_dist = 100.0
	p.position = Vector2(50, 0)
	assert_approx(p._fly_progress(), 0.5, 0.01, "中点进度为 0.5")
	p.free()


func test_fly_progress_zero_distance() -> void:
	var p := ProjectileBase.new()
	p._start_pos = Vector2.ZERO
	p._total_dist = 0.0
	assert_eq(p._fly_progress(), 1.0, "零距离时进度为 1.0")
	p.free()


func test_apply_arc_offset_null_body_rect_safe() -> void:
	# ProjectileBase 用 .new() 创建时无场景树，body_rect 为 null（@onready 未触发）
	var p := ProjectileBase.new()
	assert_eq(p.body_rect, null, ".new() 创建时 body_rect 为 null")
	# 设置弧高参数后调用 _apply_arc_offset 不应崩溃
	p.arc_height = 2.0
	p._total_dist = 100.0
	p._start_pos = Vector2.ZERO
	p._body_base_y = 0.0
	p.position = Vector2(50, 0)
	p._apply_arc_offset()  # 应安全跳过（body_rect == null）
	# 如果没有崩溃即为通过
	assert_true(true, "null body_rect 时 _apply_arc_offset 安全跳过")
	p.free()


func test_fly_toward_with_null_body_rect_no_crash() -> void:
	# 模拟 ArrowProjectile 场景：无 Body 子节点，body_rect 为 null
	var p := ProjectileBase.new()
	p.position = Vector2.ZERO
	p.speed = 100.0
	p._start_pos = Vector2.ZERO
	p._total_dist = 200.0
	p.arc_height = 3.0  # 有弧高但无 body_rect
	var arrived := p._fly_toward(Vector2(200, 0), 0.3)
	assert_false(arrived, "正常飞行")
	# 无崩溃即为通过
	p.free()
