# 文件名：test_attack_targeting.gd
# 作用：验证 AttackComponent 的索敌锁定/切换逻辑——这是本次 Bug 修复的核心测试。
#
#   期望行为（修复后）：
#     1. 无目标时 → 搜索视野内最近敌人
#     2. 目标在 attack_range 内 → 保持锁定，原地攻击，不切换（即使有更近的敌人出现）
#     3. 目标离开 attack_range → 每帧重新搜索最近敌人，追击中可自由切换
#     4. 视野内无敌人 → target = null
#
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 setup 了解测试环境怎么搭建，再看 test_locks_when_in_attack_range。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

# 近战攻击配置：attack_range = 1.5格 = 30px
const ATTACK_DATA := {
	"name": "test_melee",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": false,
	"attack_range": 1.5,
	"attack_interval": 1.0,
	"first_attack_delay": 0.0,
	"delivery": "instant",
	"damage": 10,
}

var _mocks: Array = []
var _attacker: CombatantBase
var _comp: AttackComponent


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()

	# 创建攻击者（位于原点，视野 120px = 6格）
	_attacker = MockScript.new()
	_attacker.team = "player"
	_attacker.sight_range = 120.0
	_attacker.global_position = Vector2.ZERO
	_attacker.initialized = true

	# 创建 AttackComponent（不加入场景树，直接调方法测试）
	_comp = AttackComponent.new()
	_comp.combatant = _attacker
	_comp.setup(ATTACK_DATA)
	# setup 后：_comp.attack_range = BattleConstants.px(1.5) = 30px


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


## 创建敌方 mock 并注册到 EntityRegistry
func _make_enemy(pos: Vector2) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.global_position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# ============================================================
#  基础索敌
# ============================================================

func test_finds_nearest_in_sight() -> void:
	_make_enemy(Vector2(50, 0))
	_make_enemy(Vector2(100, 0))
	_comp._update_targeting()
	assert_not_null(_comp.current_target, "应找到敌人")
	assert_eq(_comp.current_target.global_position, Vector2(50, 0),
		"应选最近的（50px < 100px）")


func test_no_target_when_empty() -> void:
	_comp._update_targeting()
	assert_null(_comp.current_target, "无敌人时 target 应为 null")


func test_no_target_when_beyond_sight() -> void:
	_make_enemy(Vector2(200, 0))  # 超出视野(120px)
	_comp._update_targeting()
	assert_null(_comp.current_target, "超出视野时 target 应为 null")


# ============================================================
#  锁定逻辑（Bug 修复核心）
# ============================================================

func test_locks_when_in_attack_range() -> void:
	# near 在攻击范围内(25px < 30px)，closer 更近(20px) 也在范围内
	var near := _make_enemy(Vector2(25, 0))
	_make_enemy(Vector2(20, 0))  # closer，但不应抢占锁定

	# 手动锁定 near
	_comp.current_target = near
	_comp._update_targeting()

	# near 在 attack_range 内 → 保持锁定，不切换到 closer
	assert_eq(_comp.current_target, near,
		"在攻击范围内应保持锁定，不切换到更近的目标")


func test_drops_locked_target_when_it_becomes_air() -> void:
	var near := _make_enemy(Vector2(25, 0))
	_comp.current_target = near

	near.movement_type = "air"
	_comp._update_targeting()

	assert_null(_comp.current_target,
		"目标临时变为空中后，不能对空的攻击组件应取消锁定")


func test_re_evaluates_when_target_leaves_range() -> void:
	# enemy_a 初始在攻击范围内(25px)
	var enemy_a := _make_enemy(Vector2(25, 0))
	var enemy_b := _make_enemy(Vector2(28, 0))  # 也在范围内

	# 锁定 A
	_comp.current_target = enemy_a
	_comp._update_targeting()
	assert_eq(_comp.current_target, enemy_a, "初始锁定 A")

	# A 移出攻击范围
	enemy_a.global_position = Vector2(80, 0)
	_comp._update_targeting()

	# A 离开 attack_range → 重新搜索 → B(28px) 最近
	assert_eq(_comp.current_target, enemy_b,
		"A 离开攻击范围后应切换到最近的 B")


func test_pursuit_switches_to_closer_enemy() -> void:
	# A 在视野内但攻击范围外
	var enemy_a := _make_enemy(Vector2(80, 0))
	_comp._update_targeting()
	assert_eq(_comp.current_target, enemy_a, "初始锁定 A（唯一敌人）")

	# A 移远，新敌人 B 出现在更近处
	enemy_a.global_position = Vector2(100, 0)
	var enemy_b := _make_enemy(Vector2(50, 0))
	_comp._update_targeting()

	# 两者都在 attack_range 外 → 每帧重新搜索 → B 更近
	assert_eq(_comp.current_target, enemy_b,
		"追击中（攻击范围外）应切换到更近的 B")


func test_keeps_nearest_during_pursuit() -> void:
	# 三个敌人，都在攻击范围外
	var a := _make_enemy(Vector2(60, 0))
	var b := _make_enemy(Vector2(50, 0))
	var c := _make_enemy(Vector2(70, 0))

	_comp._update_targeting()
	# 应选 B（50px 最近）
	assert_eq(_comp.current_target, b, "应锁定最近的 B")

	# B 移远，A 变成最近
	b.global_position = Vector2(90, 0)
	_comp._update_targeting()
	assert_eq(_comp.current_target, a, "B 移远后应切换到 A（新的最近）")
