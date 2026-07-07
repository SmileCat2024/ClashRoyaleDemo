# 文件名：test_tower_attack.gd
# 作用：验证 TowerBase 的 AttackComponent 接入是否正确——
#       塔能否正确索敌（地面/空中）、攻击范围是否准确、instant 攻击能否造成伤害。
#       使用公主塔（guard_tower）数据配置测试。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 setup 了解测试环境怎么搭建（mock 塔和 AttackComponent），再看各 test_ 方法。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

# 公主塔攻击配置（取自 DataRegistry.tower_data.guard_tower.attacks[0]）
# 原始数据：attack_range=7.5格 → px 后 150px，delivery=projectile
const GUARD_TOWER_ATTACK := {
	"name": "arrow_shot",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": true,
	"attack_range": 7.5,
	"attack_interval": 0.8,
	"first_attack_delay": 0.8,
	"delivery": "projectile",
	"trajectory": "homing",
	"impact_type": "single",
	"impact_radius": 0.0,
	"damage": 109,
	"projectile_speed": 12.5,
}

# 用于伤害测试的 instant 变体（避免 projectile 需要 Projectile.tscn 场景）
const GUARD_TOWER_INSTANT := {
	"name": "arrow_shot",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": true,
	"attack_range": 7.5,
	"attack_interval": 0.8,
	"first_attack_delay": 0.0,
	"delivery": "instant",
	"damage": 109,
}

var _mocks: Array = []
var _tower: CombatantBase
var _comp: AttackComponent


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()

	# 创建塔 mock（位于原点，模拟公主塔）
	_tower = MockScript.new()
	_tower.team = "player"
	_tower.tower_type = "guard"
	# 塔没有 sight_range 属性，AttackComponent 会用 attack_range + 20px 兜底
	_tower.global_position = Vector2.ZERO
	_tower.initialized = true


func teardown() -> void:
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()
	if _comp and is_instance_valid(_comp):
		_comp.free()
	if _tower and is_instance_valid(_tower):
		_tower.free()


## 创建敌方 mock 并注册到 EntityRegistry
func _make_enemy(pos: Vector2, movement: String = "ground") -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.movement_type = movement
	m.global_position = pos
	m.max_hp = 1000
	m.current_hp = 1000
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


## 创建一个配置好公主塔攻击数据的 AttackComponent
func _make_tower_attack(attack_data: Dictionary) -> AttackComponent:
	var comp := AttackComponent.new()
	comp.combatant = _tower
	comp.setup(attack_data)
	return comp


# ============================================================
#  攻击范围配置正确性
# ============================================================

func test_attack_range_converted_to_pixels() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	# 7.5 格 × CELL_SIZE(20) = 150px
	assert_eq(_comp.attack_range, 150.0, "公主塔攻击范围应从 7.5 格转换为 150px")


func test_tower_uses_projectile_delivery() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	assert_eq(_comp.delivery, "projectile", "公主塔应使用 projectile 投递方式")


func test_tower_sight_range_fallback() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	# MockCombatant 有 sight_range=120，应直接使用该值
	assert_eq(_comp._get_sight_range(), 120.0, "有 sight_range 时应直接使用 mock 的 120px")


# ============================================================
#  索敌：地面目标
# ============================================================

func test_targets_ground_enemy_in_range() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	_make_enemy(Vector2(100, 0))  # 100px < 150px attack_range
	_comp._update_targeting()
	assert_not_null(_comp.current_target, "应在攻击范围内找到地面敌人")


func test_no_target_beyond_sight_range() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	_make_enemy(Vector2(200, 0))  # 200px > 170px sight_range
	_comp._update_targeting()
	assert_null(_comp.current_target, "超出视野范围不应索敌")


func test_targets_nearest_ground_enemy() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	var near := _make_enemy(Vector2(80, 0))
	_make_enemy(Vector2(140, 0))
	_comp._update_targeting()
	assert_eq(_comp.current_target, near, "应锁定最近的地面敌人")


# ============================================================
#  索敌：空中目标（公主塔可对空）
# ============================================================

func test_targets_air_enemy() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	_make_enemy(Vector2(100, 0), "air")
	_comp._update_targeting()
	assert_not_null(_comp.current_target, "公主塔 attack_air=true 应能锁定空中敌人")


func test_prefers_nearest_regardless_of_ground_or_air() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_ATTACK)
	var ground := _make_enemy(Vector2(120, 0), "ground")
	var air := _make_enemy(Vector2(90, 0), "air")
	_comp._update_targeting()
	# 空中单位(90px)更近，应被优先锁定
	assert_eq(_comp.current_target, air, "应锁定最近的敌人（不分地面/空中）")


# ============================================================
#  攻击执行（instant 变体验证伤害结算）
# ============================================================

func test_tower_deals_damage_on_attack() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_INSTANT)
	var enemy := _make_enemy(Vector2(100, 0))
	# 锁定目标
	_comp.current_target = enemy
	# 直接执行攻击（绕过冷却）
	_comp._execute_attack()
	assert_eq(enemy.current_hp, 1000 - 109, "塔应造成 109 点伤害")


func test_tower_attack_respects_cooldown() -> void:
	_comp = _make_tower_attack(GUARD_TOWER_INSTANT)
	# first_attack_delay=0.0，cooldown 初始为 0
	var enemy := _make_enemy(Vector2(100, 0))
	_comp.current_target = enemy
	# 第一次攻击应成功（cooldown=0）
	_comp._process(0.016)
	assert_eq(enemy.current_hp, 1000 - 109, "首次攻击应造成伤害")
	# 攻击后 cooldown = attack_interval = 0.8
	_comp._process(0.016)  # 仅过 0.016s，cooldown 未恢复
	assert_eq(enemy.current_hp, 1000 - 109, "冷却期间不应再次攻击")
