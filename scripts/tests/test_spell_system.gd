# 文件名：test_spell_system.gd
# 作用：测试法术系统核心逻辑——火球数据校验、塔减伤、击退机制。
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
#  火球卡牌数据校验
# ============================================================

func test_fireball_card_exists() -> void:
	var card := DataRegistry.get_card_data("card_fireball")
	assert_eq(card.get("id", ""), "card_fireball", "火球卡牌应存在")


func test_fireball_card_type() -> void:
	var card := DataRegistry.get_card_data("card_fireball")
	assert_eq(card.get("card_type", ""), "spell", "火球应为 spell 类型")


func test_fireball_cost() -> void:
	var card := DataRegistry.get_card_data("card_fireball")
	assert_eq(int(card.get("cost", 0)), 4, "火球消耗应为4")


func test_fireball_damage_values() -> void:
	var card := DataRegistry.get_card_data("card_fireball")
	assert_eq(int(card.get("spell_damage", 0)), 688, "火球单位伤害应为688")
	assert_eq(int(card.get("tower_damage", 0)), 172, "火球塔伤害应为172")


func test_fireball_radius() -> void:
	var card := DataRegistry.get_card_data("card_fireball")
	assert_eq(float(card.get("spell_radius", 0)), 2.5, "火球半径应为2.5格")


func test_fireball_knockback() -> void:
	var card := DataRegistry.get_card_data("card_fireball")
	assert_true(bool(card.get("knockback", false)), "火球应有击退")
	assert_eq(float(card.get("knockback_distance", 0)), 1.0, "击退距离应为1格")


func test_fireball_speed() -> void:
	var card := DataRegistry.get_card_data("card_fireball")
	assert_eq(float(card.get("projectile_speed", 0)), 10.0, "飞行速度应为10格/秒")


func test_fireball_in_player_deck() -> void:
	var deck := DataRegistry.get_default_player_deck()
	assert_true(deck.has("card_fireball"), "玩家卡组应包含火球")


func test_fireball_in_enemy_deck() -> void:
	var deck := DataRegistry.get_default_enemy_deck()
	assert_true(deck.has("card_fireball"), "敌方卡组应包含火球")


# ============================================================
#  塔减伤（DamageSystem.deal_area_damage with tower_damage）
# ============================================================

func test_area_damage_tower_reduction() -> void:
	var unit := _make_target(1000)
	var tower := _make_target(1000, true)
	unit.global_position = Vector2(10, 0)
	tower.global_position = Vector2(20, 0)

	EntityRegistry.clear()
	EntityRegistry.register(unit)
	EntityRegistry.register(tower)

	# 688 单位伤害，172 塔伤害
	DamageSystem.deal_area_damage(Vector2.ZERO, 60.0, 688, "player", 172)

	assert_eq(unit.current_hp, 312, "单位应受688伤害")
	assert_eq(tower.current_hp, 828, "塔应受172伤害")

	EntityRegistry.clear()
	unit.free()
	tower.free()


func test_area_damage_no_tower_reduction_by_default() -> void:
	var tower := _make_target(1000, true)
	tower.global_position = Vector2(10, 0)

	EntityRegistry.clear()
	EntityRegistry.register(tower)

	# 不传 tower_damage → 塔受全额
	DamageSystem.deal_area_damage(Vector2.ZERO, 60.0, 100, "player")

	assert_eq(tower.current_hp, 900, "默认塔受全额伤害")

	EntityRegistry.clear()
	tower.free()


func test_area_damage_unit_and_tower_mixed() -> void:
	var u1 := _make_target(500)
	var u2 := _make_target(500)
	var t1 := _make_target(2000, true)
	u1.global_position = Vector2(5, 0)
	u2.global_position = Vector2(15, 0)
	t1.global_position = Vector2(25, 0)

	EntityRegistry.clear()
	EntityRegistry.register(u1)
	EntityRegistry.register(u2)
	EntityRegistry.register(t1)

	DamageSystem.deal_area_damage(Vector2.ZERO, 60.0, 300, "player", 100)

	assert_eq(u1.current_hp, 200, "单位1受300")
	assert_eq(u2.current_hp, 200, "单位2受300")
	assert_eq(t1.current_hp, 1900, "塔受100")

	EntityRegistry.clear()
	u1.free()
	u2.free()
	t1.free()


# ============================================================
#  击退（CombatantBase.knockback）
# ============================================================

func test_knockback_moves_unit() -> void:
	var unit := _make_target(100)
	unit.position = Vector2(100, 100)
	unit.knockback(Vector2(1, 0), 20.0)
	assert_eq(unit.position, Vector2(120, 100), "单位应沿X正方向移动20px")


func test_knockback_diagonal() -> void:
	var unit := _make_target(100)
	unit.position = Vector2(100, 100)
	# 45度方向，距离 20px
	var dir := Vector2(1, 1).normalized()
	unit.knockback(dir, 20.0)
	assert_approx(unit.position.x, 100 + dir.x * 20.0, 0.1, "X方向偏移正确")
	assert_approx(unit.position.y, 100 + dir.y * 20.0, 0.1, "Y方向偏移正确")


func test_knockback_tower_immune() -> void:
	var tower := _make_target(100, true)  # mass = 0
	tower.position = Vector2(100, 100)
	tower.knockback(Vector2(1, 0), 20.0)
	assert_eq(tower.position, Vector2(100, 100), "塔(mass=0)应免疫击退")


func test_knockback_dead_immune() -> void:
	var unit := _make_target(100)
	unit.is_dead = true
	unit.position = Vector2(100, 100)
	unit.knockback(Vector2(1, 0), 20.0)
	assert_eq(unit.position, Vector2(100, 100), "死亡单位应免疫击退")


func test_knockback_clamped_to_arena() -> void:
	var unit := _make_target(100)
	# 放在右边缘附近
	unit.position = Vector2(BattleConstants.ARENA_WIDTH - 5, 100)
	unit.knockback(Vector2(1, 0), 20.0)
	# 应被钳制到 ARENA_WIDTH - 0.5*CELL_SIZE
	var max_x := BattleConstants.ARENA_WIDTH - BattleConstants.CELL_SIZE * 0.5
	assert_eq(unit.position.x, max_x, "击退应被钳制到竞技场边界")


func test_knockback_zero_distance_noop() -> void:
	var unit := _make_target(100)
	unit.position = Vector2(100, 100)
	unit.knockback(Vector2(1, 0), 0.0)
	assert_eq(unit.position, Vector2(100, 100), "零距离击退不应移动")
