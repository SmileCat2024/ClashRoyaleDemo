# 文件名：test_charge_attack.gd
# 作用：验证王子冲锋首击零延迟机制。
#
#   期望行为（修复后）：
#     1. 冲锋状态（is_charging=true）下进入射程，无视 first_attack_delay 立即触发冲锋爆发伤害
#     2. 冲锋首击伤害使用 charge_damage（783）而非普通 damage（391）
#     3. 冲锋首击后立即退出冲锋状态（is_charging=false）
#     4. 冲锋首击后 cooldown 重置为 attack_interval（进入正常攻击节奏）
#     5. 非冲锋状态仍受 first_attack_delay 约束（首击有起手延迟）
#     6. 冲锋首击退出后，后续攻击恢复使用普通 damage
#
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 setup 了解冲锋单位/攻击组件怎么搭建，再看 test_charge_first_hit_ignores_first_attack_delay。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

# 模拟王子的攻击配置：长近战 + 0.5s 首击前摇 + 1.4s 攻击间隔
const CHARGE_ATTACK_DATA := {
	"name": "spear_thrust",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": false,
	"attack_range": 1.6,        # 王子长近战（32px）
	"attack_interval": 1.4,
	"first_attack_delay": 0.5,  # 首次出手前摇（仅非冲锋态生效）
	"delivery": "instant",
	"damage": 391,              # 普通命中伤害
}

const NORMAL_DAMAGE := 391
const CHARGE_DAMAGE := 783

var _mocks: Array = []
# _attacker 不加类型注解：MockCombatant 无 class_name，且需访问其专属属性
# is_charging/charge_damage（CombatantBase 上不存在），Variant 引用才能通过编译。
var _attacker
var _comp: AttackComponent


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()

	# 创建冲锋单位（位于原点）。collision_radius=10px 模拟中等体型
	_attacker = MockScript.new()
	_attacker.team = "player"
	_attacker.sight_range = 120.0
	_attacker.global_position = Vector2.ZERO
	_attacker.collision_radius = 10.0
	_attacker.initialized = true
	EntityRegistry.register(_attacker)

	# 创建 AttackComponent（不加入场景树，直接调方法测试）
	_comp = AttackComponent.new()
	_comp.combatant = _attacker
	_comp.setup(CHARGE_ATTACK_DATA)
	# setup 后：attack_range = px(1.6) = 32px，cooldown = first_attack_delay = 0.5


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


## 创建敌方 mock（模拟受击目标）并注册。hurt_radius=10px 使 reach=32+10+10=52px。
## 血量设大值避免单次冲锋伤害（783）致死触发 die()，确保 damage_taken_total 精确记录。
## 返回值不加类型注解：调用方需访问 damage_taken_total（MockCombatant 专属）。
func _make_target(pos: Vector2):
	var m = MockScript.new()
	m.team = "enemy"
	m.global_position = pos
	m.hurt_radius = 10.0
	m.max_hp = 99999
	m.current_hp = 99999
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# ============================================================
#  冲锋首击：零延迟 + charge_damage + 退出冲锋
# ============================================================

## 冲锋状态下进入射程，无视 first_attack_delay（0.5s），第一帧立即触发伤害。
func test_charge_first_hit_ignores_first_attack_delay() -> void:
	_attacker.is_charging = true
	_attacker.charge_damage = CHARGE_DAMAGE
	var target = _make_target(Vector2(30, 0))  # 30px < reach(52px)，在射程内
	_comp.current_target = target  # 手动锁定

	# setup 后 cooldown=0.5，仅推进一帧（0.016s 远小于 0.5）
	_comp._process(0.016)

	# 冲锋首击零延迟：目标立即受到伤害
	assert_eq(target.damage_taken_total, CHARGE_DAMAGE,
		"冲锋首击应无视 first_attack_delay 立即造成 charge_damage")


## 冲锋首击伤害应为 charge_damage（783），而非普通 damage（391）。
func test_charge_first_hit_uses_charge_damage() -> void:
	_attacker.is_charging = true
	_attacker.charge_damage = CHARGE_DAMAGE
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	_comp._process(0.016)

	assert_eq(target.damage_taken_total, CHARGE_DAMAGE,
		"冲锋首击伤害应为 charge_damage(783) 而非普通 damage(391)")
	assert_ne(target.damage_taken_total, NORMAL_DAMAGE,
		"冲锋首击不应使用普通 damage")


## 冲锋首击触发后立即退出冲锋状态（_end_charge 被调用）。
func test_charge_first_hit_ends_charge() -> void:
	_attacker.is_charging = true
	_attacker.charge_damage = CHARGE_DAMAGE
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	_comp._process(0.016)

	assert_false(_attacker.is_charging, "冲锋首击后应退出冲锋状态")
	assert_eq(_attacker.end_charge_call_count, 1, "_end_charge 应被调用恰好 1 次")


## 冲锋首击后 cooldown 重置为 attack_interval（1.4s），进入正常攻击节奏。
func test_charge_first_hit_resets_cooldown_to_interval() -> void:
	_attacker.is_charging = true
	_attacker.charge_damage = CHARGE_DAMAGE
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	_comp._process(0.016)

	assert_approx(_comp.cooldown, CHARGE_ATTACK_DATA["attack_interval"], 0.001,
		"冲锋首击后 cooldown 应重置为 attack_interval(1.4)")


## 冲锋首击应触发 _is_firing 标记（驱动攻击动画）。
func test_charge_first_hit_marks_firing() -> void:
	_attacker.is_charging = true
	_attacker.charge_damage = CHARGE_DAMAGE
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	_comp._process(0.016)

	assert_true(_comp.is_firing(), "冲锋首击应触发 _is_firing 标记")


# ============================================================
#  非冲锋状态：first_attack_delay 正常生效
# ============================================================

## 非冲锋状态下，first_attack_delay（0.5s）生效，短帧内不出手。
func test_non_charge_respects_first_attack_delay() -> void:
	_attacker.is_charging = false
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	# setup 后 cooldown=0.5，推进 0.1s（小于 0.5）
	_comp._process(0.1)

	assert_eq(target.damage_taken_total, 0,
		"非冲锋状态 first_attack_delay 期间不应造成伤害")
	# cooldown 应在倒计时（0.5 - 0.1 = 0.4）
	assert_approx(_comp.cooldown, 0.4, 0.001,
		"非冲锋状态 cooldown 应在倒计时")


## 非冲锋状态等够 first_attack_delay 后用普通 damage 出手。
func test_non_charge_first_hit_uses_normal_damage() -> void:
	_attacker.is_charging = false
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	# 推进 0.5s 让 first_attack_delay 倒完，再用一小帧触发出手
	_comp._process(0.5)
	_comp._process(0.016)

	assert_eq(target.damage_taken_total, NORMAL_DAMAGE,
		"非冲锋状态首击应使用普通 damage(391)")


# ============================================================
#  冲锋首击后：恢复正常攻击节奏
# ============================================================

## 冲锋首击退出后，后续攻击恢复使用普通 damage（不再是 charge_damage）。
func test_charge_subsequent_hit_uses_normal_damage() -> void:
	_attacker.is_charging = true
	_attacker.charge_damage = CHARGE_DAMAGE
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	# 第一帧：冲锋首击（783），退出冲锋，cooldown=1.4
	_comp._process(0.016)
	assert_eq(target.damage_taken_total, CHARGE_DAMAGE, "首击应为冲锋伤害")

	# 推进 attack_interval(1.4s) 让冷却倒完，再用一帧触发普通攻击
	_comp._process(1.4)
	_comp._process(0.016)

	# 第二击应叠加普通 damage(391)：783 + 391 = 1174
	assert_eq(target.damage_taken_total, CHARGE_DAMAGE + NORMAL_DAMAGE,
		"冲锋退出后第二击应使用普通 damage(391)")


## 冲锋首击后，在 attack_interval 冷却期间不会重复出手。
func test_charge_first_hit_no_repeat_during_cooldown() -> void:
	_attacker.is_charging = true
	_attacker.charge_damage = CHARGE_DAMAGE
	var target = _make_target(Vector2(30, 0))
	_comp.current_target = target

	# 冲锋首击
	_comp._process(0.016)
	# 推进 0.5s（小于 attack_interval=1.4），不应再次出手
	_comp._process(0.5)

	# is_charging 已 false，不会重复触发冲锋；cooldown 未倒完也不出手
	assert_eq(target.damage_taken_total, CHARGE_DAMAGE,
		"冲锋首击后 cooldown 期间不应重复造成伤害")
