# 文件名：test_piercing.gd
# 作用：验证 ProjectileBase 的 piercing 穿透机制（神箭游侠）。
#       覆盖：① 投射物飞到敌人附近时命中
#             ② 投射物远离敌人时不命中
#             ③ 同一敌人只打一次（不重复伤害）
#             ④ 投射物沿路径依次穿透多个敌人
# 挂载位置：由 TestRunner 实例化。

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


func _make_enemy(pos: Vector2) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.global_position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


## 创建穿透投射物（手动设字段，无需场景树）
func _make_piercing(pierce_r: float, dmg: int) -> ProjectileBase:
	var p := ProjectileBase.new()
	p.position = Vector2.ZERO
	p._start_pos = Vector2.ZERO
	p.team = "player"
	p.piercing = true
	p.pierce_radius = pierce_r
	p.damage = dmg
	return p


# ============================================================
#  穿透命中检测
# ============================================================

func test_pierce_hits_enemy_at_projectile_pos() -> void:
	var p := _make_piercing(10.0, 40)
	var enemy := _make_enemy(Vector2(50, 5))
	# 投射物飞到 (50,0)，距敌人 5px <= 10
	p.position = Vector2(50, 0)
	p._check_pierce_hits()
	assert_eq(enemy.damage_taken_total, 40, "投射物飞到敌人附近（5px<=10）应命中")
	p.free()


func test_pierce_skips_enemy_out_of_radius() -> void:
	var p := _make_piercing(10.0, 40)
	var enemy := _make_enemy(Vector2(50, 5))
	# 投射物在 (50,50)，距敌人 sqrt(0+45²)=45px > 10
	p.position = Vector2(50, 50)
	p._check_pierce_hits()
	assert_eq(enemy.damage_taken_total, 0, "投射物远离敌人（45px>10）不应命中")
	p.free()


func test_pierce_no_duplicate_hit() -> void:
	var p := _make_piercing(10.0, 40)
	var enemy := _make_enemy(Vector2(50, 0))
	p.position = Vector2(50, 0)
	p._check_pierce_hits()
	assert_eq(enemy.damage_taken_total, 40, "第一次检测应命中")
	# 投射物仍停在该位置，再次检测同一敌人不应重复受伤
	p._check_pierce_hits()
	assert_eq(enemy.damage_taken_total, 40, "同一敌人不应被同一箭矢重复伤害")
	p.free()


func test_pierce_only_hits_current_arrow_body_not_full_history() -> void:
	var p := _make_piercing(10.0, 40)
	p._fly_dir = Vector2.RIGHT
	# 箭头已飞到 x=200，极长实体箭身仅覆盖约 x=110~200；x=50 的敌人不应仍处于伤害带内。
	var enemy := _make_enemy(Vector2(50, 0))
	p.position = Vector2(200, 0)
	p._check_pierce_hits()
	assert_eq(enemy.damage_taken_total, 0, "穿透箭经过后不应保留激光式历史伤害带")
	p.free()


func test_pierce_multiple_enemies_along_path() -> void:
	# 模拟穿透箭沿 x 轴飞行，依次经过 3 个敌人
	var p := _make_piercing(10.0, 40)
	var e1 := _make_enemy(Vector2(50, 0))
	var e2 := _make_enemy(Vector2(100, 0))
	var e3 := _make_enemy(Vector2(150, 0))
	# 沿路径依次"飞到"每个敌人位置并检测
	p.position = Vector2(50, 0)
	p._check_pierce_hits()
	p.position = Vector2(100, 0)
	p._check_pierce_hits()
	p.position = Vector2(150, 0)
	p._check_pierce_hits()
	assert_eq(e1.damage_taken_total, 40, "路径上敌人1应被穿透命中")
	assert_eq(e2.damage_taken_total, 40, "路径上敌人2应被穿透命中")
	assert_eq(e3.damage_taken_total, 40, "路径上敌人3应被穿透命中")
	p.free()
