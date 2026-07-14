# 文件名：DeckManager.gd
# 作用：管理玩家卡组轮转。卡牌循环：4张手牌 + 1张预告 + 剩余在队列中等待。
#       打出一张手牌后：预告牌填补空位，队列头成为新预告，打出的牌回到队尾。
#       这是皇室战争的核心卡牌循环机制。支持任意数量的卡牌。
# 挂载位置：BattleManager 动态创建并 add_child（不放在 tscn 里）。
# 初学者阅读建议：先看 setup() 理解初始分配，再看 play_card() 理解轮转逻辑。

class_name DeckManager
extends Node

const HAND_SIZE := 4  ## 手牌数量

var _queue: Array[String] = []  ## 等待区（3张）
var _hand: Array[String] = []   ## 手牌（4张，索引 0-3 对应屏幕从左到右）
var _next: String = ""          ## 下一张预告


## 初始化卡组。传入卡牌 id 列表（≥5张），打乱后分配到 hand/next/queue。
func setup(deck_card_ids: Array) -> void:
	_queue.clear()
	_hand.clear()
	_next = ""

	var shuffled = deck_card_ids.duplicate()
	shuffled.shuffle()

	# 标记了 exclude_from_initial_hand 的卡不能进入最初 4 张手牌（如圣水收集器）。
	for card_id in shuffled:
		var card_data: Dictionary = DataRegistry.card_data.get(card_id, {})
		if _hand.size() < HAND_SIZE and not bool(card_data.get("exclude_from_initial_hand", false)):
			_hand.append(card_id)
	for card_id in shuffled:
		if not _hand.has(card_id):
			_queue.append(card_id)
	if not _queue.is_empty():
		_next = _queue.pop_front()

	print("[DeckManager] hand:", _hand, " next:", _next, " queue:", _queue)


## 获取当前手牌（4张牌 id）
func get_hand() -> Array:
	return _hand.duplicate()


## 获取下一张预告牌 id
func get_next() -> String:
	return _next


## 被动设置手牌状态（联机模式 client 端使用，由 host 通过 RPC 同步）。
func set_hand(hand: Array, next_card: String) -> void:
	_hand = hand.duplicate()
	_next = next_card


## 打出手牌中指定索引的牌。
## hand_index: 0-3
## 返回打出的牌 id；索引无效返回空字符串。
func play_card(hand_index: int) -> String:
	if hand_index < 0 or hand_index >= _hand.size():
		return ""

	var played = _hand[hand_index]

	# 预告牌填补打出牌的位置
	_hand[hand_index] = _next

	# 队列头成为新预告
	_next = _queue.pop_front()

	# 打出的牌回到队尾
	_queue.append(played)

	print("[DeckManager] played:", played, " hand:", _hand, " next:", _next)
	return played
