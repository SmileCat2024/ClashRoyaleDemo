# 文件名：test_data_registry.gd
# 作用：验证 DataRegistry 中的所有配置数据完整且一致。
#       单位/卡牌/塔/攻击配置的字段完整性 + 卡牌引用的 unit_id 存在性。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：看各 test_ 方法了解 DataRegistry 数据结构的约束。

extends TestBase


# ============================================================
#  单位数据
# ============================================================

func test_all_units_have_id() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		assert_eq(u.get("id", ""), uid, "单位 id 应与字典 key 一致: " + uid)


func test_all_units_have_positive_hp() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		assert_true(int(u.get("max_hp", 0)) > 0, "max_hp 应 > 0: " + uid)


func test_all_units_have_attacks() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		var attacks: Array = u.get("attacks", [])
		if bool(u.get("is_passive", false)):
			assert_true(attacks.is_empty(), "被动单位不应配置攻击: " + uid)
			continue
		assert_false(attacks.is_empty(), "attacks 不应为空: " + uid)


func test_all_unit_attacks_have_required_fields() -> void:
	var required := ["damage", "attack_range", "attack_interval", "targeting", "delivery"]
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		var attacks: Array = u.get("attacks", [])
		for i in range(attacks.size()):
			var a: Dictionary = attacks[i]
			for field in required:
				assert_true(a.has(field),
					"单位 %s attacks[%d] 缺少 %s" % [uid, i, field])


func test_all_unit_attack_ranges_positive() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		var attacks: Array = u.get("attacks", [])
		for i in range(attacks.size()):
			var a: Dictionary = attacks[i]
			assert_true(float(a.get("attack_range", 0)) > 0,
				"单位 %s attacks[%d] attack_range 应 > 0" % [uid, i])


func test_only_hog_rider_can_jump_river_for_now() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		var can_jump := bool(u.get("can_jump_river", false))
		assert_eq(can_jump, uid in ["hog_rider", "prince"],
			"当前版本只有野猪骑士和王子允许跳河: " + uid)


func test_all_units_have_collision_radius() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		assert_true(float(u.get("collision_radius", 0)) > 0,
			"单位 %s collision_radius 应 > 0" % uid)


func test_all_units_have_hurt_radius() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		assert_true(float(u.get("hurt_radius", 0)) > 0,
			"单位 %s hurt_radius 应 > 0" % uid)


func test_all_units_have_valid_mass() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		assert_true(int(u.get("mass", -1)) >= 0,
			"单位 %s mass 应 >= 0" % uid)


func test_flyer_has_elevated_altitude() -> void:
	var flyer: Dictionary = DataRegistry.unit_data["flyer"]
	assert_true(float(flyer.get("altitude", 0.0)) > 2.5,
		"飞行器应高于默认空中单位的 2.5 格离地高度")


func test_princess_high_arc_arrow_tuning() -> void:
	var attack: Dictionary = DataRegistry.unit_data["princess"]["attacks"][0]
	assert_eq(float(attack.get("projectile_speed", 0.0)), 10.0,
		"公主箭矢弹速应为 10 格/秒")
	assert_eq(float(attack.get("arc_height", 0.0)), 7.0,
		"公主箭矢弧高应为 7 格")


func test_ranger_visual_uses_final_sprite_only() -> void:
	var animation: Dictionary = DataRegistry.unit_data["ranger"].get("animation", {})
	assert_true(bool(animation.get("hide_placeholder", false)),
		"神箭游侠应隐藏底部调试占位")
	assert_eq(float(animation.get("visual_scale", 0.0)), 0.025,
		"神箭游侠模型应使用校准后的缩放")


func test_knockback_immunity_config() -> void:
	var pekka: Dictionary = DataRegistry.unit_data["pekka"]
	var valkyrie: Dictionary = DataRegistry.unit_data["valkyrie"]
	var prince: Dictionary = DataRegistry.unit_data["prince"]
	assert_eq(int(pekka.get("mass", -1)), 18, "大皮卡质量应为 18")
	assert_true(bool(pekka.get("knockback_immune", false)), "大皮卡应免疫击退")
	assert_eq(int(valkyrie.get("mass", -1)), 5, "瓦基丽武神质量应为 5")
	assert_false(bool(valkyrie.get("knockback_immune", false)), "瓦基丽武神应可被击退")
	assert_eq(int(prince.get("mass", -1)), 6, "王子质量应为 6")
	assert_true(bool(prince.get("knockback_immune", false)), "王子应免疫击退")


func test_all_static_combatants_are_knockback_immune() -> void:
	for uid in DataRegistry.unit_data:
		var u: Dictionary = DataRegistry.unit_data[uid]
		if int(u.get("mass", -1)) == 0:
			assert_true(bool(u.get("knockback_immune", false)),
				"静态单位 %s 应显式免疫击退" % uid)
	for tid in DataRegistry.tower_data:
		var t: Dictionary = DataRegistry.tower_data[tid]
		assert_true(bool(t.get("knockback_immune", false)),
			"塔 %s 应显式免疫击退" % tid)


# ============================================================
#  卡牌数据
# ============================================================

func test_all_cards_have_cost() -> void:
	for cid in DataRegistry.card_data:
		var c: Dictionary = DataRegistry.card_data[cid]
		assert_true(c.has("cost"), "卡牌缺少 cost: " + cid)


func test_troop_cards_reference_valid_units() -> void:
	for cid in DataRegistry.card_data:
		var c: Dictionary = DataRegistry.card_data[cid]
		if c.get("card_type") != "troop":
			continue
		var uid: String = c.get("unit_id", "")
		assert_false(uid == "", "troop 卡牌缺少 unit_id: " + cid)
		assert_true(DataRegistry.unit_data.has(uid),
			"卡牌 %s 引用了不存在的 unit_id: %s" % [cid, uid])


func test_troop_cards_have_spawn_count() -> void:
	for cid in DataRegistry.card_data:
		var c: Dictionary = DataRegistry.card_data[cid]
		if c.get("card_type") != "troop":
			continue
		assert_true(int(c.get("spawn_count", 0)) >= 1,
			"卡牌 %s spawn_count 应 >= 1" % cid)


# ============================================================
#  塔数据
# ============================================================

func test_all_towers_have_valid_type() -> void:
	for tid in DataRegistry.tower_data:
		var t: Dictionary = DataRegistry.tower_data[tid]
		var tt: String = t.get("tower_type", "")
		assert_true(tt == "king" or tt == "guard",
			"塔 %s tower_type 不合法: %s" % [tid, tt])


func test_all_towers_have_positive_hp() -> void:
	for tid in DataRegistry.tower_data:
		var t: Dictionary = DataRegistry.tower_data[tid]
		assert_true(int(t.get("max_hp", 0)) > 0,
			"塔 %s max_hp 应 > 0" % tid)


func test_all_towers_have_attacks() -> void:
	for tid in DataRegistry.tower_data:
		var t: Dictionary = DataRegistry.tower_data[tid]
		var attacks: Array = t.get("attacks", [])
		assert_false(attacks.is_empty(),
			"塔 %s attacks 不应为空" % tid)


func test_all_towers_have_collision_radius() -> void:
	for tid in DataRegistry.tower_data:
		var t: Dictionary = DataRegistry.tower_data[tid]
		assert_true(float(t.get("collision_radius", 0)) > 0,
			"塔 %s collision_radius 应 > 0" % tid)


func test_all_towers_have_zero_mass() -> void:
	for tid in DataRegistry.tower_data:
		var t: Dictionary = DataRegistry.tower_data[tid]
		assert_eq(int(t.get("mass", -1)), 0,
			"塔 %s mass 必须为 0（不可移动）" % tid)


# ============================================================
#  默认卡组
# ============================================================

func test_player_deck_has_all_available_cards() -> void:
	var deck := DataRegistry.get_default_player_deck()
	var expected := DataRegistry.card_data.keys()
	# 精英变种替代同定位的普通卡，避免默认开发卡组出现重复单位。
	expected.erase("card_knight")
	expected.erase("card_mega_minion")
	assert_eq(deck.size(), expected.size(),
		"玩家默认卡组应包含全部可用卡牌（普通版被精英版替代）")
	assert_false(deck.has("card_knight"), "精英骑士应替代默认卡组中的普通骑士")
	assert_false(deck.has("card_mega_minion"), "精英重甲亡灵应替代默认卡组中的普通重甲亡灵")
	assert_true(deck.has("card_knight_elite"), "默认卡组应包含精英骑士")
	assert_true(deck.has("card_mega_minion_elite"), "默认卡组应包含精英重甲亡灵")
	assert_true(deck.has("card_mortar"), "普通迫击炮应保留在默认卡组，觉醒不应替换牌库卡牌")
	assert_true(deck.has("card_musketeer"), "普通火枪手应保留在默认卡组，觉醒不应替换牌库卡牌")


func test_deck_cards_all_exist() -> void:
	var deck := DataRegistry.get_default_player_deck()
	for cid in deck:
		assert_true(DataRegistry.card_data.has(cid),
			"默认卡组引用了不存在的卡牌: " + cid)


func test_mortar_and_musketeer_awakening_cards() -> void:
	for card_id in ["card_mortar", "card_musketeer"]:
		var card: Dictionary = DataRegistry.card_data[card_id]
		var awakening: Dictionary = card.get("awakening", {})
		var icon_path: String = card.get("awakening_icon", "")
		assert_eq(int(awakening.get("trigger_count", 0)), 1,
			"%s 应打出 1 次普通版后进入觉醒版" % card_id)
		assert_false(icon_path == "",
			"%s 应配置觉醒卡面" % card_id)
		assert_true(FileAccess.file_exists(icon_path),
			"%s 的觉醒卡面文件不存在" % card_id)
		var effects: Dictionary = awakening.get("effects", {})
		assert_false(effects.is_empty(),
			"%s 应配置觉醒效果" % card_id)


func test_awakened_mortar_summons_one_goblin_on_impact() -> void:
	var effects: Dictionary = DataRegistry.card_data["card_mortar"].get("awakening", {}).get("effects", {})
	assert_eq(effects.get("projectile_impact_summon_unit_id", ""), "goblins",
		"觉醒迫击炮炮弹落点应召唤哥布林单位")
	assert_true(DataRegistry.unit_data.has(effects.get("projectile_impact_summon_unit_id", "")),
		"觉醒迫击炮落点召唤配置必须引用已存在的单位")


# ============================================================
#  新卡牌专项校验（王子冲锋 / 迫击炮盲区）
# ============================================================

func test_prince_has_charge_config() -> void:
	var prince: Dictionary = DataRegistry.unit_data.get("prince", {})
	assert_false(prince.is_empty(), "王子数据应存在")
	var charge: Dictionary = prince.get("charge", {})
	assert_false(charge.is_empty(), "王子应有 charge 配置")
	assert_true(float(charge.get("min_charge_distance", 0)) > 0,
		"charge min_charge_distance 应 > 0")
	assert_true(float(charge.get("charge_move_speed", 0)) > 0,
		"charge_move_speed 应 > 0")
	assert_true(int(charge.get("charge_damage", 0)) > 0,
		"charge_damage 应 > 0")


func test_mortar_min_range_less_than_max() -> void:
	var mortar: Dictionary = DataRegistry.unit_data.get("mortar", {})
	assert_false(mortar.is_empty(), "迫击炮数据应存在")
	var attacks: Array = mortar.get("attacks", [])
	assert_false(attacks.is_empty(), "迫击炮应有攻击配置")
	var a: Dictionary = attacks[0]
	var min_r := float(a.get("min_attack_range", 0))
	var max_r := float(a.get("attack_range", 0))
	assert_true(min_r > 0, "迫击炮应有 min_attack_range（盲区）")
	assert_true(min_r < max_r, "迫击炮 min_attack_range 应小于 attack_range")
