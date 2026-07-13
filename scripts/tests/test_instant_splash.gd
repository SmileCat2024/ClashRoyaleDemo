# 文件名：test_instant_splash.gd
# 作用：验证 AttackComponent 的 instant + splash（近战范围溅射）机制。
#       瓦基里武神为首例 instant+splash 单位，此前 splash 仅 projectile（迫击炮）。
#       覆盖：① splash 命中范围内所有敌方、范围外不受伤
#             ② 溅射中心是攻击者自身位置（非 current_target）
#             ③ 回归：instant + single 仍只打单体（不影响现有近战单位）
# 挂载位置：由 TestRunner 实例化。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

# 近战溅射配置：impact_radius=1格 → setup 后 20px，damage=50
const SPLASH_ATTACK_DATA := {
	"name": "axe_spin",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": false,
	"attack_range": 0.5,
	"attack_interval": 1.8,
	"first_attack_delay": 0.6,
	"delivery": "instant",
	"impact_type": "splash",
	"impact_radius": 1.0,
	"damage": 50,
}

# 近战单体配置（回归测试）
const SINGLE_ATTACK_DATA := {
	"name": "sword",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": false,
	"attack_range": 0.5,
	"attack_interval": 1.0,
	"first_attack_delay": 0.0,
	"delivery": "instant",
	"impact_type": "single",
	"damage": 50,
}

var _mocks: Array = []
var _attacker: CombatantBase
var _comp: AttackComponent


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()
	_attacker = MockScript.new()
	_attacker.team = "player"
	_attacker.global_position = Vector2.ZERO
	_attacker.initialized = true


func teardown() -> void:
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()
	if _comp and is_instance_valid(_comp):
		_comp.free()
	if _attacker and is_instance_valid(_attacker):
		_attacker.free()


func _make_enemy(pos: Vector2) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.global_position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


func _make_comp(data: Dictionary) -> AttackComponent:
	var c := AttackComponent.new()
	c.combatant = _attacker
	c.setup(data)
	return c


# ============================================================
#  instant + splash（瓦基里转斧）
# ============================================================

func test_splash_hits_all_in_radius() -> void:
	_comp = _make_comp(SPLASH_ATTACK_DATA)  # impact_radius = 20px
	var in_a := _make_enemy(Vector2(10, 0))   # 距离 10 <= 20，命中
	var in_b := _make_enemy(Vector2(0, 15))   # 距离 15 <= 20，命中
	var out_c := _make_enemy(Vector2(100, 0)) # 距离 100 > 20，不命中

	_comp.current_target = in_a
	_comp._execute_attack()

	assert_eq(in_a.damage_taken_total, 50, "范围内敌人 A 应受 50 溅射伤害")
	assert_eq(in_b.damage_taken_total, 50, "范围内敌人 B 应受 50 溅射伤害")
	assert_eq(out_c.damage_taken_total, 0, "范围外敌人不应受伤")


func test_splash_centered_on_attacker_not_target() -> void:
	# 验证溅射中心是攻击者自身位置，而非 current_target
	_comp = _make_comp(SPLASH_ATTACK_DATA)
	_attacker.global_position = Vector2(0, 0)
	var target := _make_enemy(Vector2(8, 0))
	# 侧敌：距攻击者 15px（<= 20 命中），距 target 23px（若以 target 为中心则不命中）
	var side := _make_enemy(Vector2(-15, 0))

	_comp.current_target = target
	_comp._execute_attack()

	assert_eq(side.damage_taken_total, 50,
		"溅射以攻击者自身为中心：侧敌距攻击者 15<=20 应命中（证明中心非 target）")


func test_splash_skips_air_when_attack_air_false() -> void:
	# SPLASH_ATTACK_DATA 的 attack_air=false，范围内空中单位不应被溅射
	_comp = _make_comp(SPLASH_ATTACK_DATA)
	var ground_e := _make_enemy(Vector2(10, 0))
	var air_e := _make_enemy(Vector2(10, 0))
	air_e.movement_type = "air"

	_comp.current_target = ground_e
	_comp._execute_attack()

	assert_eq(ground_e.damage_taken_total, 50, "地面敌人在范围内应被溅射命中")
	assert_eq(air_e.damage_taken_total, 0, "空中敌人不应被 attack_air=false 的溅射命中")


# ============================================================
#  回归：instant + single 不受影响
# ============================================================

func test_single_only_hits_current_target() -> void:
	_comp = _make_comp(SINGLE_ATTACK_DATA)
	var target := _make_enemy(Vector2(10, 0))
	var bystander := _make_enemy(Vector2(10, 0))  # 同位置但非 target

	_comp.current_target = target
	_comp._execute_attack()

	assert_eq(target.damage_taken_total, 50, "single 攻击应命中 current_target")
	assert_eq(bystander.damage_taken_total, 0, "single 攻击不应溅射到其他单位")
