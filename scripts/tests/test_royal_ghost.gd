# 文件名：test_royal_ghost.gd
# 作用：测试皇室幽灵核心机制——偏移全圆溅射（数据校验）、隐身索敌过滤
#       （find_best_target 跳过隐身单位）、隐身可受伤但不退出隐身；
#       附 deal_arc_damage 扇形通用机制的回归测试（皇室幽灵当前不用扇形）。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 _make_target 了解 mock 创建，再看各 test_ 方法。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")


## 创建一个 mock 目标（1000hp 地面单位，可指定坐标/是否隐身/是否空中）
func _make_target(pos: Vector2 = Vector2.ZERO, stealthed: bool = false, air: bool = false) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.max_hp = 1000
	m.current_hp = 1000
	m.shield = 0
	m.current_shield = 0
	m.initialized = true
	m.mass = 5
	m.hurt_radius = 10.0
	m.is_stealthed = stealthed
	m.movement_type = "air" if air else "ground"
	m.global_position = pos
	return m


# ============================================================
#  数据校验
# ============================================================

func test_royal_ghost_unit_exists() -> void:
	var u := DataRegistry.get_unit_data("royal_ghost")
	assert_eq(u.get("id", ""), "royal_ghost", "皇室幽灵单位应存在")


func test_royal_ghost_hp() -> void:
	var u := DataRegistry.get_unit_data("royal_ghost")
	assert_eq(int(u.get("max_hp", 0)), 1210, "HP 应为 1210")


func test_royal_ghost_move_speed() -> void:
	var u := DataRegistry.get_unit_data("royal_ghost")
	assert_eq(float(u.get("move_speed", 0)), 1.5, "移速应为 1.5（快速）")


func test_royal_ghost_stealth_enabled() -> void:
	var u := DataRegistry.get_unit_data("royal_ghost")
	var s: Dictionary = u.get("stealth", {})
	assert_true(bool(s.get("enabled", false)), "隐身应启用")


func test_royal_ghost_attack_values() -> void:
	var u := DataRegistry.get_unit_data("royal_ghost")
	var a: Dictionary = u.get("attacks", [])[0]
	assert_eq(int(a.get("damage", 0)), 261, "伤害应为 261")
	assert_eq(float(a.get("attack_interval", 0)), 1.8, "攻击间隔应为 1.8s")
	assert_eq(float(a.get("attack_range", 0)), 1.2, "攻击距离应为 1.2 格")
	assert_eq(float(a.get("impact_radius", 0)), 1.0, "溅射半径应为 1.0 格")
	assert_eq(float(a.get("impact_offset", 0)), 1.2, "溅射圆心偏移应为 1.2 格")
	assert_false(bool(a.get("attack_air", true)), "仅攻击地面（attack_air=false）")
	assert_eq(a.get("delivery", ""), "instant", "应为 instant 近战")


func test_royal_ghost_card_cost() -> void:
	var c := DataRegistry.get_card_data("card_royal_ghost")
	assert_eq(int(c.get("cost", 0)), 3, "卡牌费用应为 3")
	assert_eq(c.get("unit_id", ""), "royal_ghost", "卡牌应关联 royal_ghost")


func test_royal_ghost_in_decks() -> void:
	assert_true(DataRegistry.get_default_player_deck().has("card_royal_ghost"), "玩家卡组应包含皇室幽灵")
	assert_true(DataRegistry.get_default_enemy_deck().has("card_royal_ghost"), "敌方卡组应包含皇室幽灵")


# ============================================================
#  扇形溅射机制（DamageSystem.deal_arc_damage 角度过滤）—— 通用机制回归测试
#  注：皇室幽灵已改为 impact_offset 偏移全圆溅射（不再用扇形）；
#  此处保留 deal_arc_damage 机制的回归测试（center=原点，facing 朝右 +X，半径 30px，180°）
# ============================================================

func _setup_arc_targets() -> Array:
	# 前方(20,0) / 侧前(15,15) / 侧后(-15,15) / 后方(-20,0)，均在半径内
	var front := _make_target(Vector2(20, 0))
	var side_front := _make_target(Vector2(15, 15))
	var side_back := _make_target(Vector2(-15, 15))
	var back := _make_target(Vector2(-20, 0))
	EntityRegistry.clear()
	for t in [front, side_front, side_back, back]:
		EntityRegistry.register(t)
	return [front, side_front, side_back, back]


func test_arc_hits_front() -> void:
	var ts := _setup_arc_targets()
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 180.0, Vector2(1, 0), 100, "player")
	assert_eq(ts[0].current_hp, 900, "前方目标应在扇形内（命中）")
	_cleanup(ts)


func test_arc_misses_back() -> void:
	var ts := _setup_arc_targets()
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 180.0, Vector2(1, 0), 100, "player")
	assert_eq(ts[3].current_hp, 1000, "后方目标应在扇形外（不命中）")
	_cleanup(ts)


func test_arc_hits_side_front_within_90() -> void:
	var ts := _setup_arc_targets()
	# 侧前 (15,15)：与 +X 夹角 45° < 90°，在 180° 扇形(±90°)内
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 180.0, Vector2(1, 0), 100, "player")
	assert_eq(ts[1].current_hp, 900, "侧前目标(45°)应在扇形内（命中）")
	_cleanup(ts)


func test_arc_misses_side_back_beyond_90() -> void:
	var ts := _setup_arc_targets()
	# 侧后 (-15,15)：与 +X 夹角 135° > 90°，在扇形外
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 180.0, Vector2(1, 0), 100, "player")
	assert_eq(ts[2].current_hp, 1000, "侧后目标(135°)应在扇形外（不命中）")
	_cleanup(ts)


func test_arc_full_circle_when_360() -> void:
	var ts := _setup_arc_targets()
	# arc=360 退化为全圆，所有方向都命中
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 360.0, Vector2(1, 0), 100, "player")
	for i in ts.size():
		assert_eq(ts[i].current_hp, 900, "全圆(arc=360)应命中所有方向目标")
	_cleanup(ts)


func test_arc_full_circle_when_no_facing() -> void:
	var ts := _setup_arc_targets()
	# facing 为零向量 → 退化为全圆
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 180.0, Vector2.ZERO, 100, "player")
	assert_eq(ts[3].current_hp, 900, "零方向应退化为全圆（后方也命中）")
	_cleanup(ts)


func test_arc_respects_ground_air_filter() -> void:
	# attack_air=false 时空中目标不命中
	var ground_t := _make_target(Vector2(20, 0), false, false)
	var air_t := _make_target(Vector2(20, 0), false, true)
	EntityRegistry.clear()
	EntityRegistry.register(ground_t)
	EntityRegistry.register(air_t)
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 180.0, Vector2(1, 0), 100, "player", -1, true, false)
	assert_eq(ground_t.current_hp, 900, "地面目标应命中")
	assert_eq(air_t.current_hp, 1000, "空中目标不应命中（attack_air=false）")
	_cleanup([ground_t, air_t])


func test_arc_out_of_range_misses() -> void:
	# 超出半径的目标不命中（即使在前方）
	var far := _make_target(Vector2(100, 0))
	EntityRegistry.clear()
	EntityRegistry.register(far)
	DamageSystem.deal_arc_damage(Vector2.ZERO, 30.0, 180.0, Vector2(1, 0), 100, "player")
	assert_eq(far.current_hp, 1000, "超出半径的目标不应命中")
	_cleanup([far])


# ============================================================
#  隐身索敌过滤（TargetingSystem.find_best_target）
# ============================================================

func test_stealth_unit_not_targeted() -> void:
	# 隐身单位更近，但应被索敌跳过，返回较远的显形单位
	var normal := _make_target(Vector2(100, 470))   # 距离 30
	var stealth := _make_target(Vector2(100, 480), true)  # 距离 20，更近但隐身
	EntityRegistry.clear()
	EntityRegistry.register(normal)
	EntityRegistry.register(stealth)
	var target := TargetingSystem.find_best_target(
		Vector2(100, 500), "player", 200.0, "any", true, false, "ground", false, 0.0, 0.0
	)
	assert_eq(target, normal, "索敌应跳过隐身单位，返回显形单位")
	_cleanup([normal, stealth])


func test_only_stealth_returns_null() -> void:
	# 只有隐身单位时，索敌应返回 null
	var stealth := _make_target(Vector2(100, 480), true)
	EntityRegistry.clear()
	EntityRegistry.register(stealth)
	var target := TargetingSystem.find_best_target(
		Vector2(100, 500), "player", 200.0, "any", true, false, "ground", false, 0.0, 0.0
	)
	assert_eq(target, null, "仅有隐身单位时索敌应返回 null")
	_cleanup([stealth])


func test_revealed_unit_targeted() -> void:
	# 显形（is_stealthed=false）单位正常被索敌
	var revealed := _make_target(Vector2(100, 480), false)
	EntityRegistry.clear()
	EntityRegistry.register(revealed)
	var target := TargetingSystem.find_best_target(
		Vector2(100, 500), "player", 200.0, "any", true, false, "ground", false, 0.0, 0.0
	)
	assert_eq(target, revealed, "显形单位应被正常索敌")
	_cleanup([revealed])


# ============================================================
#  隐身可受伤但不退出隐身
# ============================================================

func test_stealth_takes_damage_without_revealing() -> void:
	# 隐身单位受伤后血量减少，但 is_stealthed 不变（不退出隐身）
	var ghost := _make_target(Vector2(100, 480), true)
	ghost.take_damage(200)
	assert_eq(ghost.current_hp, 800, "隐身单位应正常受伤")
	assert_true(ghost.is_stealthed, "隐身单位受伤后应保持隐身（不退出）")
	_cleanup([ghost])


## 释放 mock 并清空注册表（避免污染后续测试）
func _cleanup(targets: Array) -> void:
	EntityRegistry.clear()
	for t in targets:
		if is_instance_valid(t):
			t.free()
