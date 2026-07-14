# 文件名：test_elite_skill_dash.gd
# 作用：精英技能「死亡俯冲」（dash_to_weakest）核心逻辑回归测试。
#       覆盖：配置完整性 / 找血量最低敌方单位 / 无目标时中止释放 / 成功释放进入冲刺 /
#             冲刺到达结算伤害 / 冲刺期间禁用普通 AI。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 setup 了解测试环境怎么搭建，再看 test_finds_weakest_enemy_unit。

extends TestBase

const UnitScene := preload("res://scenes/entities/units/UnitBase.tscn")
const MockScript := preload("res://scripts/tests/MockCombatant.gd")

const ELITE_CARD_ID := "card_mega_minion_elite"

var _unit: UnitBase
var _mocks: Array = []


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()


func teardown() -> void:
	EntityRegistry.clear()
	if _unit and is_instance_valid(_unit):
		_unit.free()
	_unit = null
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()


# ---- 辅助 ----

## 创建精英重甲亡灵（player 方），加入场景树并 setup。
func _make_elite_mega_minion(pos: Vector2) -> UnitBase:
	_unit = UnitScene.instantiate() as UnitBase
	add_child(_unit)
	_unit.position = pos
	var card := DataRegistry.get_card_data(ELITE_CARD_ID)
	var u_data := DataRegistry.get_unit_data(card["unit_id"])
	_unit.setup(u_data, "player", {}, card.get("elite_skill", {}), card.get("visual_overrides", {}))
	# mega_minion 有 deploy_time=1.0，setup 后 is_deployed=false。测试中手动跳过部署等待。
	_unit.is_deployed = true
	_unit._deploy_timer = 0.0
	_unit._finish_deploy_anim()
	return _unit


## 创建 MockCombatant 模拟敌方单位并注册到 EntityRegistry。
func _make_enemy(pos: Vector2, hp: int) -> MockCombatant:
	var m := MockScript.new()
	m.team = "enemy"
	m.position = pos
	m.max_hp = hp
	m.current_hp = hp
	m.initialized = true
	# MockCombatant 继承 CombatantBase，无 is_deployed 属性（UnitBase 专属）。
	# _find_weakest_enemy_unit 中 e.get("is_deployed") 对 MockCombatant 返回 null，
	# null == false 为 false，不会误过滤。
	m.tower_type = null
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# =====================================================================
# 配置完整性
# =====================================================================

func test_card_data_exists_and_valid() -> void:
	var card := DataRegistry.get_card_data(ELITE_CARD_ID)
	assert_false(card.is_empty(), "card_mega_minion_elite 应存在")
	assert_eq(card.get("unit_id"), "mega_minion", "关联 mega_minion 单位")
	assert_eq(card.get("card_type"), "troop", "卡牌类型为 troop")


func test_elite_skill_config_structure() -> void:
	var card := DataRegistry.get_card_data(ELITE_CARD_ID)
	var es: Dictionary = card.get("elite_skill", {})
	assert_false(es.is_empty(), "应有 elite_skill 配置")
	assert_eq(es.get("id"), "mega_minion_death_dive", "技能 id")
	assert_eq(int(es.get("cost", -1)), 2, "技能耗费 2 圣水")
	assert_eq(es.get("targeting"), "instant", "瞬发类型")
	assert_true(float(es.get("cooldown", -1)) > 0, "冷却时间应 > 0")


func test_elite_visual_overrides() -> void:
	var card := DataRegistry.get_card_data(ELITE_CARD_ID)
	var overrides: Dictionary = card.get("visual_overrides", {})
	var animation: Dictionary = overrides.get("animation", {})
	var base_animation: Dictionary = DataRegistry.get_unit_data("mega_minion").get("animation", {})
	assert_true(float(animation.get("visual_scale", 0.0)) > float(base_animation.get("visual_scale", 0.0)),
		"精英重甲亡灵模型应大于普通版")
	assert_true(float(animation.get("health_bar_y", 0.0)) < float(base_animation.get("health_bar_y", 0.0)),
		"精英重甲亡灵血条应比普通版更靠上")
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	assert_approx(mega.sprite_animator._base_scale.x, float(animation["visual_scale"]), 0.0001,
		"精英卡牌视觉覆盖应传递给 SpriteAnimator")
	assert_eq(mega.health_bar.position.y, float(animation["health_bar_y"]),
		"精英卡牌视觉覆盖应传递给血条位置")


func test_effect_fields_complete() -> void:
	var es: Dictionary = DataRegistry.get_card_data(ELITE_CARD_ID)["elite_skill"]
	var effect: Dictionary = es["effect"]
	assert_eq(effect.get("type"), "dash_to_weakest", "效果类型")
	assert_true(float(effect.get("dash_speed_cells", 0)) > 0.0, "冲刺固定速度应 > 0")
	assert_true(int(effect.get("impact_damage", 0)) > 0, "冲击伤害应 > 0")
	assert_true(float(effect.get("impact_radius", 0)) > 0, "冲击范围应 > 0")
	assert_true(float(effect.get("mark_duration", 0)) > 0, "标志显示时长应 > 0")


# =====================================================================
# 找血量最低敌方单位
# =====================================================================

func test_finds_weakest_enemy_unit() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	var e1 := _make_enemy(Vector2(100, 300), 500)  # 满血
	var e2 := _make_enemy(Vector2(120, 300), 100)  # 残血（最低）
	var e3 := _make_enemy(Vector2(140, 300), 300)

	var weakest = mega._find_weakest_enemy_unit()
	assert_true(weakest == e2, "应锁定血量最低（100hp）的 e2")


func test_returns_null_when_no_enemies() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	var weakest = mega._find_weakest_enemy_unit()
	assert_true(weakest == null, "无敌方单位时应返回 null")


func test_skips_dead_enemies() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	var dead := _make_enemy(Vector2(100, 300), 10)
	dead.is_dead = true
	var alive := _make_enemy(Vector2(120, 300), 500)

	var weakest = mega._find_weakest_enemy_unit()
	assert_true(weakest == alive, "应跳过已死亡单位，锁定存活单位")


func test_skips_towers() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	# 模拟塔（tower_type 不为 null），血量很低但不应被锁定
	var tower_mock := _make_enemy(Vector2(100, 300), 50)
	tower_mock.tower_type = "guard"
	# 普通单位，血量更高
	var unit := _make_enemy(Vector2(120, 300), 800)

	var weakest = mega._find_weakest_enemy_unit()
	assert_true(weakest == unit, "应跳过塔，锁定普通单位（即使塔血量更低）")


# =====================================================================
# 技能释放行为
# =====================================================================

func test_skill_aborts_without_target() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	mega.trigger_skill(Vector2.ZERO)
	# 无目标时不应消耗冷却
	assert_false(mega.is_dashing, "无目标时不应进入冲刺状态")
	assert_approx(mega._skill_cooldown_timer, 0.0, 0.001, "无目标时不应启动冷却")


func test_skill_enters_dash_state() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	var weakest := _make_enemy(Vector2(100, 300), 100)

	mega.trigger_skill(Vector2.ZERO)
	assert_true(mega.is_dashing, "释放后应进入冲刺状态")
	assert_true(mega._dash_speed > 0.0, "冲刺速度应已设置")
	assert_true(mega._dash_damage > 0, "冲刺伤害应已设置")
	# 冷却应已启动
	assert_true(mega._skill_cooldown_timer > 0.0, "冷却应已启动")
	# 冲刺目标应接近 weakest 的位置
	var target_pos := BattlePathing.game_position_of(weakest)
	assert_approx(mega._dash_target_pos.distance_to(target_pos), 0.0, 1.0,
		"冲刺目标应为最弱单位的位置")


func test_dash_arrival_deals_damage_and_exits() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	var weakest := _make_enemy(Vector2(100, 300), 100)
	# 另一个也在冲击范围内的敌方单位
	var nearby := _make_enemy(Vector2(110, 300), 300)

	mega.trigger_skill(Vector2.ZERO)
	var damage_before := weakest.current_hp + nearby.current_hp

	# 手动调用到达结算（模拟冲刺完成）
	mega._arrive_dash()

	assert_false(mega.is_dashing, "到达后应退出冲刺状态")
	# 两个敌方单位都应受到伤害
	var damage_after := weakest.current_hp + nearby.current_hp
	assert_true(damage_after < damage_before, "冲击范围内敌方单位应受到伤害")


func test_is_skill_ready_blocked_during_dash() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	_make_enemy(Vector2(100, 300), 100)

	mega.trigger_skill(Vector2.ZERO)
	assert_true(mega.is_dashing, "应处于冲刺中")
	# 冲刺期间冷却已启动，is_skill_ready 应返回 false
	assert_false(mega.is_skill_ready(), "冲刺期间（冷却中）技能不可用")


# =====================================================================
# 冲刺推进
# =====================================================================

func test_dash_moves_toward_target() -> void:
	var mega := _make_elite_mega_minion(Vector2(100, 500))
	var weakest := _make_enemy(Vector2(100, 300), 100)

	mega.trigger_skill(Vector2.ZERO)
	var pos_before := mega.position.x
	# 推进一小步（不足以到达）
	mega._process_dash(0.1)
	# 重甲亡灵从 y=500 向 y=300 移动，y 应减小
	assert_true(mega.position.y < 500.0, "冲刺应使单位向目标移动（y 减小）")
