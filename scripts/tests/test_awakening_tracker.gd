# 文件名：test_awakening_tracker.gd
# 作用：AwakeningTracker 循环觉醒计数逻辑回归测试。
#       覆盖：初始状态 / 普通打出 / 阈值触发 / 觉醒消耗 / 循环 / team 隔离 / peek 只读。
extends TestBase

const TEST_CARD := "card_knight"  # DataRegistry 中已有 awakening 配置（trigger_count=2）
const ONE_CYCLE_CARDS := ["card_mortar", "card_musketeer"]


func _new_tracker() -> AwakeningTracker:
	var t := AwakeningTracker.new()
	t.reset()
	return t


func test_non_awakening_card_peek() -> void:
	var t := _new_tracker()
	var effects := t.peek_next_effects("player", "card_hog_rider")
	assert_true(effects.is_empty(), "非觉醒牌 peek 应返回空字典")


func test_non_awakening_card_record() -> void:
	var t := _new_tracker()
	t.record_play("player", "card_hog_rider")
	var p := t.get_progress("player", "card_hog_rider")
	assert_true(p.is_empty(), "非觉醒牌 get_progress 应返回空字典")


func test_initial_state() -> void:
	var t := _new_tracker()
	var p := t.get_progress("player", TEST_CARD)
	assert_eq(p["count"], 0, "初始 count=0")
	assert_eq(p["trigger_count"], 2, "trigger_count=2")
	assert_false(p["next_awakened"], "初始 next_awakened=false")


func test_first_play_normal() -> void:
	var t := _new_tracker()
	var effects := t.peek_next_effects("player", TEST_CARD)
	assert_true(effects.is_empty(), "第一次 peek 应为普通版（空字典）")
	t.record_play("player", TEST_CARD)
	var p := t.get_progress("player", TEST_CARD)
	assert_eq(p["count"], 1, "第一次打出后 count=1")
	assert_false(p["next_awakened"], "第一次打出后 next_awakened=false")


func test_trigger_threshold() -> void:
	var t := _new_tracker()
	t.record_play("player", TEST_CARD)  # count→1
	t.record_play("player", TEST_CARD)  # count→2 达阈值→重置0，next=true
	var p := t.get_progress("player", TEST_CARD)
	assert_true(p["next_awakened"], "打出 trigger_count 次后 next_awakened=true")
	assert_eq(p["count"], 0, "达到阈值后 count 重置为0")


func test_peek_after_threshold() -> void:
	var t := _new_tracker()
	t.record_play("player", TEST_CARD)
	t.record_play("player", TEST_CARD)
	var effects := t.peek_next_effects("player", TEST_CARD)
	assert_false(effects.is_empty(), "达到阈值后 peek 应返回觉醒效果")
	assert_true(effects.has("shield"), "觉醒效果应包含 shield")
	assert_true(effects.has("max_hp_bonus"), "觉醒效果应包含 max_hp_bonus")


func test_awakening_consumption() -> void:
	var t := _new_tracker()
	t.record_play("player", TEST_CARD)  # count→1
	t.record_play("player", TEST_CARD)  # 阈值→next=true
	t.record_play("player", TEST_CARD)  # 觉醒版打出→重置
	var p := t.get_progress("player", TEST_CARD)
	assert_false(p["next_awakened"], "觉醒版打出后 next_awakened 重置为 false")
	assert_eq(p["count"], 0, "觉醒版打出后 count=0")


func test_cycling() -> void:
	var t := _new_tracker()
	# 第一轮：普通→普通→觉醒
	t.record_play("player", TEST_CARD)
	t.record_play("player", TEST_CARD)
	t.record_play("player", TEST_CARD)
	# 第二轮：普通→普通→觉醒就绪
	t.record_play("player", TEST_CARD)
	t.record_play("player", TEST_CARD)
	assert_true(t.is_next_awakened("player", TEST_CARD), "第二轮循环后应觉醒就绪")


func test_team_isolation() -> void:
	var t := _new_tracker()
	t.record_play("player", TEST_CARD)
	t.record_play("player", TEST_CARD)
	assert_true(t.is_next_awakened("player", TEST_CARD), "player 方应觉醒就绪")
	assert_false(t.is_next_awakened("enemy", TEST_CARD), "enemy 方应未觉醒（独立计数）")


func test_peek_no_mutation() -> void:
	var t := _new_tracker()
	t.peek_next_effects("player", TEST_CARD)
	t.peek_next_effects("player", TEST_CARD)
	t.peek_next_effects("player", TEST_CARD)
	var p := t.get_progress("player", TEST_CARD)
	assert_eq(p["count"], 0, "peek 不应改变 count")
	assert_false(p["next_awakened"], "peek 不应改变 next_awakened")


func test_one_cycle_awakening_cards() -> void:
	for card_id in ONE_CYCLE_CARDS:
		var t := _new_tracker()
		assert_true(t.peek_next_effects("player", card_id).is_empty(),
			"%s 第一次打出前应显示普通卡面" % card_id)
		t.record_play("player", card_id)
		assert_true(t.is_next_awakened("player", card_id),
			"%s 打出 1 次后下一次应为觉醒版" % card_id)
		assert_false(t.peek_next_effects("player", card_id).is_empty(),
			"%s 觉醒就绪时应返回觉醒效果" % card_id)
		t.record_play("player", card_id)
		assert_false(t.is_next_awakened("player", card_id),
			"%s 打出觉醒版后应重新回到普通版" % card_id)
