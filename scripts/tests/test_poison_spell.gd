# 文件名：test_poison_spell.gd
# 作用：测试毒药法术——数据校验、DOT 塔减伤、减速乘数逻辑。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 _make_target 了解 mock 创建，再看各 test_ 方法。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")


## 创建一个 mock 目标（100hp，可指定为塔）
func _make_target(hp: int = 100, is_tower: bool = false) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.max_hp = hp
	m.current_hp = hp
	m.shield = 0
	m.current_shield = 0
	m.initialized = true
	m.mass = 5
	m.hurt_radius = 10.0
	if is_tower:
		m.tower_type = "guard"
		m.mass = 0
	return m


# ============================================================
#  毒药卡牌数据校验
# ============================================================

func test_poison_card_exists() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	assert_false(c.is_empty(), "card_poison 应存在于 card_data")

func test_poison_basic_fields() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	assert_eq(str(c.get("id", "")), "card_poison", "id")
	assert_eq(str(c.get("display_name", "")), "毒药", "display_name")
	assert_eq(int(c.get("cost", -1)), 4, "cost 应为 4")
	assert_eq(str(c.get("card_type", "")), "spell", "card_type 应为 spell")
	assert_eq(str(c.get("spell_type", "")), "poison", "spell_type 应为 poison")

func test_poison_radius() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	assert_eq(float(c.get("spell_radius", 0)), 3.5, "spell_radius 应为 3.5 格")

func test_poison_dot_fields() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	assert_eq(float(c.get("duration", 0)), 8.0, "duration 应为 8 秒")
	assert_eq(float(c.get("tick_interval", 0)), 1.0, "tick_interval 应为 1 秒")
	assert_eq(int(c.get("tick_damage", 0)), 92, "tick_damage 应为 92")
	assert_eq(int(c.get("tick_tower_damage", 0)), 21, "tick_tower_damage 应为 21")

func test_poison_total_damage() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	var tick := int(c.get("tick_damage", 0))
	var ticks := int(float(c.get("duration", 0)) / float(c.get("tick_interval", 1)))
	assert_eq(tick * ticks, 736, "总伤害应为 92×8=736")

func test_poison_total_tower_damage() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	var tick := int(c.get("tick_tower_damage", 0))
	var ticks := int(float(c.get("duration", 0)) / float(c.get("tick_interval", 1)))
	assert_eq(tick * ticks, 168, "塔总伤害应为 21×8=168")

func test_poison_slow() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	assert_eq(float(c.get("slow_factor", 1.0)), 0.85, "slow_factor 应为 0.85（减速15%）")

func test_poison_no_knockback() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	assert_false(bool(c.get("knockback", true)), "毒药不应有击退")


# ============================================================
#  DOT 单跳塔减伤
# ============================================================

func test_poison_tick_tower_damage() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	var tick_tower := int(c.get("tick_tower_damage", 0))
	var radius_px := BattleConstants.px(float(c.get("spell_radius", 0)))
	var tower := _make_target(1000, true)
	EntityRegistry.register(tower)
	# 模拟单跳
	DamageSystem.deal_area_damage(Vector2.ZERO, radius_px, tick_tower, "player", tick_tower)
	assert_eq(tower.current_hp, 1000 - 21, "塔单跳应扣 21 血")
	EntityRegistry.unregister(tower)

func test_poison_tick_unit_damage() -> void:
	var c := DataRegistry.get_card_data("card_poison")
	var tick_dmg := int(c.get("tick_damage", 0))
	var radius_px := BattleConstants.px(float(c.get("spell_radius", 0)))
	var unit := _make_target(500, false)
	EntityRegistry.register(unit)
	# 模拟单跳
	DamageSystem.deal_area_damage(Vector2.ZERO, radius_px, tick_dmg, "player")
	assert_eq(unit.current_hp, 500 - 92, "单位单跳应扣 92 血")
	EntityRegistry.unregister(unit)

func test_poison_tick_tower_reduced_vs_unit() -> void:
	# 同一 tick 中，单位受 92，塔受 21
	var c := DataRegistry.get_card_data("card_poison")
	var tick_dmg := int(c.get("tick_damage", 0))
	var tick_tower := int(c.get("tick_tower_damage", 0))
	var radius_px := BattleConstants.px(float(c.get("spell_radius", 0)))
	var unit := _make_target(500, false)
	var tower := _make_target(500, true)
	EntityRegistry.register(unit)
	EntityRegistry.register(tower)
	DamageSystem.deal_area_damage(Vector2.ZERO, radius_px, tick_dmg, "player", tick_tower)
	assert_eq(unit.current_hp, 500 - 92, "单位应受 92")
	assert_eq(tower.current_hp, 500 - 21, "塔应受 21（减伤）")
	EntityRegistry.unregister(unit)
	EntityRegistry.unregister(tower)
