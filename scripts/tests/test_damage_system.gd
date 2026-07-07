# 文件名：test_damage_system.gd
# 作用：测试 DamageSystem 的单体伤害结算和范围伤害。
#       同时验证 CombatantBase.take_damage 的护盾吸收逻辑。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 _make_target 了解 mock 怎么创建，再看各 test_ 方法。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")


## 创建一个 mock 目标（100hp，可选护盾）
func _make_target(hp: int = 100, shield: int = 0) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.max_hp = hp
	m.current_hp = hp
	m.shield = shield
	m.current_shield = shield
	m.initialized = true
	return m


# ============================================================
#  resolve_impact — 单体伤害
# ============================================================

func test_resolve_impact_deals_damage() -> void:
	var target := _make_target(100)
	DamageSystem.resolve_impact(target, 30)
	assert_eq(target.current_hp, 70, "应扣除30血")
	assert_eq(target.damage_taken_total, 30)


func test_resolve_impact_skips_null() -> void:
	# 不应崩溃
	DamageSystem.resolve_impact(null, 30)
	assert_true(true, "null 目标不崩溃即通过")


func test_resolve_impact_skips_dead() -> void:
	var target := _make_target(100)
	target.is_dead = true
	DamageSystem.resolve_impact(target, 30)
	assert_eq(target.current_hp, 100, "死亡目标不应受伤")
	assert_eq(target.damage_taken_total, 0)


func test_resolve_impact_kills_target() -> void:
	var target := _make_target(50)
	DamageSystem.resolve_impact(target, 60)
	assert_eq(target.current_hp, 0, "血量不低于0")
	assert_true(target.is_dead, "应标记为死亡")


# ============================================================
#  护盾吸收
# ============================================================

func test_shield_absorbs_full_damage() -> void:
	var target := _make_target(100, 50)
	DamageSystem.resolve_impact(target, 30)
	assert_eq(target.current_shield, 20, "护盾吸收30，剩20")
	assert_eq(target.current_hp, 100, "有盾时不掉血")


func test_shield_break_no_overflow() -> void:
	var target := _make_target(100, 20)
	DamageSystem.resolve_impact(target, 50)
	# 护盾20吸收20，剩余30应扣血 → 但设计是：有盾时不溢出
	assert_eq(target.current_shield, 0, "护盾被打穿")
	assert_eq(target.current_hp, 100, "盾存在时不溢出到血量（本次伤害全部被盾吃掉或部分）")


func test_shield_then_hp() -> void:
	var target := _make_target(100, 20)
	# 第一击：打20，护盾归零
	DamageSystem.resolve_impact(target, 20)
	assert_eq(target.current_shield, 0)
	assert_eq(target.current_hp, 100)
	# 第二击：护盾已破，直接扣血
	DamageSystem.resolve_impact(target, 30)
	assert_eq(target.current_hp, 70, "护盾破后正常扣血")


# ============================================================
#  deal_area_damage — 范围伤害
# ============================================================

func test_deal_area_damage_hits_in_radius() -> void:
	var a := _make_target(100)
	var b := _make_target(100)
	var c := _make_target(100)
	a.global_position = Vector2(10, 0)   # 在范围内
	b.global_position = Vector2(50, 0)   # 在范围内
	c.global_position = Vector2(200, 0)  # 在范围外

	# 需要注册到 EntityRegistry 才能被 deal_area_damage 查到
	a.team = "enemy"
	b.team = "enemy"
	c.team = "enemy"
	EntityRegistry.clear()
	EntityRegistry.register(a)
	EntityRegistry.register(b)
	EntityRegistry.register(c)

	DamageSystem.deal_area_damage(Vector2.ZERO, 60.0, 40, "player")

	assert_eq(a.current_hp, 60, "范围内单位应受伤")
	assert_eq(b.current_hp, 60, "范围内单位应受伤")
	assert_eq(c.current_hp, 100, "范围外单位不应受伤")

	EntityRegistry.clear()
	a.free()
	b.free()
	c.free()
