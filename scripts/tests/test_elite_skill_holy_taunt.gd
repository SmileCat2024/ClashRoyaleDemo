# 文件名：test_elite_skill_holy_taunt.gd
# 作用：验证精英骑士「圣光嘲讽」的范围筛选、强制锁敌和解除后的自然索敌行为。

extends TestBase

const UnitScene := preload("res://scenes/entities/units/UnitBase.tscn")
const MockScript := preload("res://scripts/tests/MockCombatant.gd")
const ELITE_CARD_ID := "card_knight_elite"

const ATTACK_DATA := {
	"name": "test_taunt_attack",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": false,
	"attack_range": 1.5,
	"attack_interval": 1.0,
	"first_attack_delay": 0.0,
	"delivery": "instant",
	"damage": 10,
}

var _knight: UnitBase
var _mocks: Array = []


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()


func teardown() -> void:
	EntityRegistry.clear()
	if _knight and is_instance_valid(_knight):
		_knight.free()
	_knight = null
	for mock in _mocks:
		if is_instance_valid(mock):
			mock.free()
	_mocks.clear()


func _make_elite_knight(pos: Vector2) -> UnitBase:
	_knight = UnitScene.instantiate() as UnitBase
	add_child(_knight)
	_knight.position = pos
	var card := DataRegistry.get_card_data(ELITE_CARD_ID)
	var data := DataRegistry.get_unit_data(card["unit_id"])
	_knight.setup(data, "player", {}, card.get("elite_skill", {}), card.get("visual_overrides", {}))
	# 测试直接验证技能，不等待部署动画。
	_knight.is_deployed = true
	_knight._deploy_timer = 0.0
	_knight._finish_deploy_anim()
	return _knight


## 返回含 unit / attack 的字典，便于同时断言单位和其攻击组件。
func _make_enemy(pos: Vector2, targeting: String = "any") -> Dictionary:
	var unit: MockCombatant = MockScript.new()
	unit.team = "enemy"
	unit.position = pos
	unit.initialized = true
	EntityRegistry.register(unit)
	var data := ATTACK_DATA.duplicate()
	data["targeting"] = targeting
	var attack := AttackComponent.new()
	unit.add_child(attack)
	attack.combatant = unit
	attack.setup(data)
	unit.attack_components.append(attack)
	_mocks.append(unit)
	return {"unit": unit, "attack": attack}


func _make_player_target(pos: Vector2) -> MockCombatant:
	var target: MockCombatant = MockScript.new()
	target.team = "player"
	target.position = pos
	target.initialized = true
	EntityRegistry.register(target)
	_mocks.append(target)
	return target


func test_skill_config_is_official_taunt_values() -> void:
	var effect: Dictionary = DataRegistry.get_card_data(ELITE_CARD_ID)["elite_skill"]["effect"]
	assert_eq(effect.get("type"), "holy_taunt", "精英骑士应使用圣光嘲讽效果")
	assert_approx(float(effect.get("radius", 0.0)), 8.5, 0.001, "圣光法阵半径应为 8.5 格")
	assert_approx(float(effect.get("duration", 0.0)), 4.0, 0.001, "嘲讽持续时间应为 4 秒")
	assert_true(float(effect.get("formation_duration", 0.0)) > 0.0, "法阵应有短暂建立时间")


func test_taunt_applies_only_after_formation_and_in_range() -> void:
	var knight := _make_elite_knight(Vector2.ZERO)
	var in_range := _make_enemy(Vector2(160, 0))  # 半径 170px 内
	var out_of_range := _make_enemy(Vector2(181, 0))  # 扣除 10px 受击半径后仍在 170px 外

	knight.trigger_skill(Vector2.ZERO)
	knight._process_holy_taunt(0.2)
	assert_false(in_range["attack"].has_active_taunt(), "法阵未完成前不应提前嘲讽")

	knight._process_holy_taunt(0.2)
	assert_true(in_range["attack"].has_active_taunt(), "法阵完成时范围内目标应被嘲讽")
	assert_eq(in_range["attack"].get_taunt_target(), knight, "强制目标应为精英骑士")
	assert_not_null(in_range["unit"].get_node_or_null("TauntAuraEffect"), "被嘲讽单位应出现淡金色状态标识")
	assert_false(out_of_range["attack"].has_active_taunt(), "范围外目标不应被嘲讽")


func test_taunt_overrides_normal_targeting_and_building_only_is_immune() -> void:
	var knight := _make_elite_knight(Vector2.ZERO)
	var affected := _make_enemy(Vector2(100, 0))
	var building_only := _make_enemy(Vector2(100, 20), "building_only")
	var closer_player := _make_player_target(Vector2(99, 0))

	affected["attack"]._update_targeting()
	assert_eq(affected["attack"].current_target, closer_player, "普通索敌应先选更近的目标")
	knight.trigger_skill(Vector2.ZERO)
	knight._process_holy_taunt(0.5)
	affected["attack"]._update_targeting()
	assert_eq(affected["attack"].current_target, knight, "嘲讽期间应无视更近目标并锁定骑士")
	assert_false(building_only["attack"].has_active_taunt(), "只攻击建筑的单位不受嘲讽影响")


func test_taunt_expiry_keeps_in_range_lock_but_retargets_while_pursuing() -> void:
	var knight := _make_elite_knight(Vector2(25, 0))
	var enemy := _make_enemy(Vector2.ZERO)
	var closer_player := _make_player_target(Vector2(15, 0))
	var attack: AttackComponent = enemy["attack"]

	assert_true(attack.apply_taunt(knight, 4.0), "可攻击部队的单位应能被施加嘲讽")
	attack._process_taunt(4.1)
	attack._update_targeting()
	assert_eq(attack.current_target, knight, "嘲讽结束时已在攻击距离内，应继续攻击骑士")

	knight.position = Vector2(100, 0)
	attack._update_targeting()
	assert_eq(attack.current_target, closer_player, "嘲讽结束且仍在追击时，应恢复常规索敌")
