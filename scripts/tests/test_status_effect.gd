# 文件名：test_status_effect.gd
# 作用：测试 StatusEffect 数据对象的所有效果类型和叠加规则。
#       覆盖 slow / stun / freeze / rage / poison 的 merge()、is_expired()、get_remaining()。
extends TestBase


func test_slow_merge_takes_strongest() -> void:
	var e1 := StatusEffect.new("slow", 3.0)
	e1.move_speed_mult = 0.85
	var e2 := StatusEffect.new("slow", 2.0)
	e2.move_speed_mult = 0.7  # 更强减速
	e1.merge(e2)
	assert_eq(e1.move_speed_mult, 0.7, "slow merge 取最强减速")
	# 取更长剩余时间：e1 剩余 3.0，e2 剩余 2.0 → 3.0
	assert_eq(e1.duration, 3.0, "slow merge 取更长持续时间")


func test_slow_merge_keeps_strongest_on_refresh() -> void:
	var e1 := StatusEffect.new("slow", 5.0)
	e1.move_speed_mult = 0.5  # 很强
	e1.elapsed = 3.0  # 已经过 3 秒，剩余 2 秒
	var e2 := StatusEffect.new("slow", 1.0)
	e2.move_speed_mult = 0.85  # 较弱
	e1.merge(e2)
	# 减速取最强
	assert_eq(e1.move_speed_mult, 0.5, "slow merge 保持最强减速")
	# 持续时间取最长剩余：max(2.0, 1.0) = 2.0，加上已过 elapsed
	assert_eq(e1.duration, 3.0 + 2.0, "slow merge 保持最长剩余时间")


func test_stun_merge_refreshes_duration() -> void:
	var e1 := StatusEffect.new("stun", 1.0)
	e1.elapsed = 0.5  # 剩余 0.5 秒
	var e2 := StatusEffect.new("stun", 2.0)
	e1.merge(e2)
	# 取更长剩余：max(0.5, 2.0) = 2.0
	assert_eq(e1.duration, 0.5 + 2.0, "stun merge 取更长剩余时间")


func test_freeze_merge_refreshes_duration() -> void:
	var e1 := StatusEffect.new("freeze", 1.0)
	e1.elapsed = 0.8  # 剩余 0.2 秒
	var e2 := StatusEffect.new("freeze", 3.0)
	e1.merge(e2)
	assert_eq(e1.duration, 0.8 + 3.0, "freeze merge 取更长剩余时间")


func test_freeze_is_separate_type_from_stun() -> void:
	var e := StatusEffect.new("freeze", 2.0)
	assert_eq(e.type, "freeze", "freeze 类型正确")
	var s := StatusEffect.new("stun", 2.0)
	assert_ne(s.type, e.type, "freeze 和 stun 是不同类型")


func test_rage_merge_takes_strongest_buffs() -> void:
	var e1 := StatusEffect.new("rage", 5.0)
	e1.move_speed_mult = 1.3
	e1.attack_speed_mult = 1.2
	var e2 := StatusEffect.new("rage", 3.0)
	e2.move_speed_mult = 1.35  # 更强移动 buff
	e2.attack_speed_mult = 1.1  # 更弱攻击 buff
	e1.merge(e2)
	assert_eq(e1.move_speed_mult, 1.35, "rage merge 取最强移动速度 buff")
	assert_eq(e1.attack_speed_mult, 1.2, "rage merge 取最强攻击速度 buff")
	assert_eq(e1.duration, 5.0, "rage merge 取更长持续时间")


func test_rage_has_attack_speed_mult() -> void:
	var e := StatusEffect.new("rage", 6.0)
	e.attack_speed_mult = 1.5
	assert_eq(e.attack_speed_mult, 1.5, "rage attack_speed_mult 可设")


func test_poison_merge_takes_higher_damage() -> void:
	var e1 := StatusEffect.new("poison", 8.0)
	e1.tick_damage = 50
	e1.tick_interval = 1.0
	var e2 := StatusEffect.new("poison", 5.0)
	e2.tick_damage = 92  # 更高伤害
	e1.merge(e2)
	assert_eq(e1.tick_damage, 92, "poison merge 取更高 tick_damage")


func test_is_expired() -> void:
	var e := StatusEffect.new("slow", 2.0)
	assert_false(e.is_expired(), "新效果未过期")
	e.elapsed = 2.0
	assert_true(e.is_expired(), "elapsed >= duration 过期")
	e.elapsed = 3.0
	assert_true(e.is_expired(), "elapsed > duration 过期")


func test_get_remaining() -> void:
	var e := StatusEffect.new("slow", 5.0)
	assert_eq(e.get_remaining(), 5.0, "初始剩余 = duration")
	e.elapsed = 2.0
	assert_eq(e.get_remaining(), 3.0, "经过 2 秒后剩余 3 秒")
	e.elapsed = 6.0
	assert_eq(e.get_remaining(), 0.0, "过期后剩余 0（不返回负数）")
