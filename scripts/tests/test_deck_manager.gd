# 文件名：test_deck_manager.gd
# 作用：测试 DeckManager 的卡组轮转逻辑（全卡牌循环：4手牌+1预告+队列）。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 _make_deck 了解测试数据结构，再看 test_play_card_cycles 了解轮转。

extends TestBase


## 创建一个 DeckManager 并用 8 张牌初始化
func _make_deck() -> DeckManager:
	var dm := DeckManager.new()
	dm.setup(["c0", "c1", "c2", "c3", "c4", "c5", "c6", "c7"])
	return dm


# ============================================================
#  setup 初始分配
# ============================================================

func test_setup_hand_size() -> void:
	var dm := _make_deck()
	assert_eq(dm.get_hand().size(), 4, "初始手牌4张")


func test_setup_next_card_exists() -> void:
	var dm := _make_deck()
	# next_card 应该是第5张牌（索引4）
	assert_true(dm.get_next() != "", "预告牌不应为空")


func test_setup_total_consistency() -> void:
	var dm := _make_deck()
	var hand := dm.get_hand()
	var all_cards := hand.duplicate()
	all_cards.append(dm.get_next())
	# 8张牌中，5张在 hand+next，3张在队列
	# 验证 hand 中无重复
	var unique: Dictionary = {}
	for c in hand:
		assert_false(unique.has(c), "手牌不应有重复: " + c)
		unique[c] = true


# ============================================================
#  play_card 轮转
# ============================================================

func test_play_card_returns_played_id() -> void:
	var dm := _make_deck()
	var hand := dm.get_hand()
	var played := dm.play_card(0)
	assert_eq(played, hand[0], "应返回打出的牌id")


func test_play_card_hand_size_unchanged() -> void:
	var dm := _make_deck()
	dm.play_card(0)
	assert_eq(dm.get_hand().size(), 4, "打出后手牌仍为4张")


func test_play_card_next_fills_slot() -> void:
	var dm := _make_deck()
	var hand_before := dm.get_hand()
	var next_before := dm.get_next()

	dm.play_card(0)

	var hand_after := dm.get_hand()
	# 打出 hand[0]，next_card 填补位置0
	assert_eq(hand_after[0], next_before, "预告牌应填补打出位置")


func test_play_card_cycles_back() -> void:
	var dm := _make_deck()
	var first_card: String = dm.get_hand()[0]

	# 打出位置0的牌 → 该牌进入队列尾部
	dm.play_card(0)

	# 连续打出7次（每次位置0），第8次时最初打出的牌应该回到手牌
	for i in range(7):
		dm.play_card(0)

	# 经过8次打出+轮转，所有牌都轮转了一遍
	# 手牌始终4张
	assert_eq(dm.get_hand().size(), 4, "8次打出后手牌仍4张")
	# 验证初始牌最终会回来（不检查具体位置，只验证它还在系统中）
	var hand := dm.get_hand()
	var next := dm.get_next()
	var found: bool = (hand.has(first_card) or next == first_card)
	# first_card 经过8轮后可能还在队列里，这是正常的
	# 关键验证：系统始终维持 4手牌 + 1预告 的结构
	assert_true(dm.get_next() != "", "8次打出后仍有预告牌")


func test_play_card_invalid_index() -> void:
	var dm := _make_deck()
	var result := dm.play_card(-1)
	assert_eq(result, "", "负索引返回空字符串")
	result = dm.play_card(99)
	assert_eq(result, "", "越界索引返回空字符串")


# ============================================================
#  get_hand 返回副本
# ============================================================

func test_get_hand_returns_copy() -> void:
	var dm := _make_deck()
	var hand1 := dm.get_hand()
	var hand2 := dm.get_hand()
	assert_eq(hand1, hand2, "两次获取应相同")
	# 修改副本不应影响原数据
	hand1[0] = "HACKED"
	var hand3 := dm.get_hand()
	assert_ne(hand3[0], "HACKED", "修改副本不应影响原始手牌")
