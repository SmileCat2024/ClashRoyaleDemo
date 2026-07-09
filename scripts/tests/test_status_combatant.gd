# 文件名：test_status_combatant.gd
# 作用：测试 CombatantBase 的状态效果查询和生命周期管理。
#       覆盖 get_move_speed_mult()、is_stunned()、get_attack_speed_mult()、
#       apply_stun/freeze/rage 便捷方法、效果过期移除、slow+rage 交互。
#       使用 MockCombatant（不放入场景树），测试完毕 free()。
extends TestBase


func _make_combatant() -> MockCombatant:
	var c := MockCombatant.new()
	c.team = "player"
	c.max_hp = 100
	c.current_hp = 100
	c.initialized = true
	return c


func test_no_effects_normal_speed() -> void:
	var c := _make_combatant()
	assert_eq(c.get_move_speed_mult(), 1.0, "无效果时移动速度正常")
	assert_eq(c.get_attack_speed_mult(), 1.0, "无效果时攻击速度正常")
	assert_false(c.is_stunned(), "无效果时不瘫痪")
	c.free()


func test_slow_reduces_speed() -> void:
	var c := _make_combatant()
	c.apply_slow(0.85, 3.0)
	assert_eq(c.get_move_speed_mult(), 0.85, "slow 减速到 85%")
	c.free()


func test_multiple_slows_take_strongest() -> void:
	var c := _make_combatant()
	c.apply_slow(0.85, 3.0)
	c.apply_slow(0.6, 2.0)
	assert_eq(c.get_move_speed_mult(), 0.6, "多个 slow 取最强减速")
	c.free()


func test_stun_blocks_movement_and_attacking() -> void:
	var c := _make_combatant()
	c.apply_stun(2.0)
	assert_eq(c.get_move_speed_mult(), 0.0, "stun 移动速度为 0")
	assert_true(c.is_stunned(), "stun 时处于瘫痪状态")
	c.free()


func test_freeze_blocks_movement_and_attacking() -> void:
	var c := _make_combatant()
	c.apply_freeze(2.0)
	assert_eq(c.get_move_speed_mult(), 0.0, "freeze 移动速度为 0")
	assert_true(c.is_stunned(), "freeze 时处于瘫痪状态")
	c.free()


func test_freeze_and_stun_both_checked() -> void:
	var c := _make_combatant()
	c.apply_stun(1.0)
	c.apply_freeze(2.0)
	assert_true(c.is_stunned(), "同时有 stun 和 freeze 时瘫痪")
	c.free()


func test_rage_increases_move_and_attack_speed() -> void:
	var c := _make_combatant()
	c.apply_rage(1.35, 1.35, 6.0)
	assert_eq(c.get_move_speed_mult(), 1.35, "rage 移动速度 +35%")
	assert_eq(c.get_attack_speed_mult(), 1.35, "rage 攻击速度 +35%")
	c.free()


func test_rage_and_slow_multiply() -> void:
	var c := _make_combatant()
	c.apply_slow(0.85, 5.0)
	c.apply_rage(1.35, 1.35, 5.0)
	# debuff(0.85) * buff(1.35) = 1.1475
	assert_approx(c.get_move_speed_mult(), 1.1475, 0.001, "slow*rage 乘法交互")
	c.free()


func test_stun_overrides_rage_and_slow() -> void:
	var c := _make_combatant()
	c.apply_rage(1.35, 1.35, 5.0)
	c.apply_slow(0.5, 5.0)
	c.apply_stun(2.0)
	assert_eq(c.get_move_speed_mult(), 0.0, "stun 覆盖一切")
	assert_true(c.is_stunned(), "stun 时瘫痪")
	c.free()


func test_freeze_overrides_rage() -> void:
	var c := _make_combatant()
	c.apply_rage(1.5, 1.5, 5.0)
	c.apply_freeze(1.0)
	assert_eq(c.get_move_speed_mult(), 0.0, "freeze 覆盖 rage 移动速度")
	assert_true(c.is_stunned(), "freeze 时瘫痪")
	# rage 的攻击速度仍然生效（freeze 不影响攻击速度查询）
	assert_eq(c.get_attack_speed_mult(), 1.5, "rage 攻速仍生效")
	c.free()


func test_effect_expires_after_duration() -> void:
	var c := _make_combatant()
	c.apply_slow(0.5, 2.0)
	assert_eq(c.get_move_speed_mult(), 0.5, "slow 激活时减速")
	# 模拟 2 秒流逝
	c._process_status_effects(2.0)
	assert_eq(c.get_move_speed_mult(), 1.0, "slow 过期后恢复正常速度")
	c.free()


func test_stun_expires() -> void:
	var c := _make_combatant()
	c.apply_stun(1.0)
	assert_true(c.is_stunned(), "stun 激活")
	c._process_status_effects(1.0)
	assert_false(c.is_stunned(), "stun 过期后不再瘫痪")
	c.free()


func test_freeze_expires() -> void:
	var c := _make_combatant()
	c.apply_freeze(1.5)
	assert_true(c.is_stunned(), "freeze 激活")
	c._process_status_effects(1.5)
	assert_false(c.is_stunned(), "freeze 过期后不再瘫痪")
	c.free()


func test_rage_expires() -> void:
	var c := _make_combatant()
	c.apply_rage(1.35, 1.35, 3.0)
	assert_eq(c.get_move_speed_mult(), 1.35, "rage 激活")
	assert_eq(c.get_attack_speed_mult(), 1.35, "rage 攻速激活")
	c._process_status_effects(3.0)
	assert_eq(c.get_move_speed_mult(), 1.0, "rage 过期后移动速度恢复")
	assert_eq(c.get_attack_speed_mult(), 1.0, "rage 过期后攻击速度恢复")
	c.free()


func test_has_status_type() -> void:
	var c := _make_combatant()
	assert_false(c.has_status_type("rage"), "无 rage")
	c.apply_rage(1.3, 1.3, 5.0)
	assert_true(c.has_status_type("rage"), "有 rage")
	assert_false(c.has_status_type("freeze"), "无 freeze")
	c.free()


func test_rage_merge_takes_strongest() -> void:
	var c := _make_combatant()
	c.apply_rage(1.2, 1.2, 3.0)
	c.apply_rage(1.35, 1.35, 2.0)
	assert_eq(c.get_move_speed_mult(), 1.35, "rage 合并取最强移动 buff")
	assert_eq(c.get_attack_speed_mult(), 1.35, "rage 合并取最强攻击 buff")
	c.free()


func test_dead_combatant_ignores_status() -> void:
	var c := _make_combatant()
	c.is_dead = true
	c.apply_stun(2.0)
	assert_false(c.is_stunned(), "死亡单位不受状态影响")
	c.free()
