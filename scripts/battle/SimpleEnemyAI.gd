# 文件名：SimpleEnemyAI.gd
# 作用：让敌方自动出牌。AI 像玩家一样持有 4 张手牌（独立 DeckManager 轮转），
#       从手牌里随机"相中"一张作为目标，耐心等圣水够费时立即出牌，出完再相中下一张。
#       出牌节奏由圣水驱动，不再用固定时间间隔。
# 挂载位置：BattleScene/Managers/SimpleEnemyAI
# 依赖节点：BattleManager（调用 try_play_card / can_afford_card）、Arena（获取部署位置）
# 初学者阅读建议：先看 _process() 了解"相中→等费→出牌"循环，再看 _pick_target() / _try_play()。

extends Node

## 敌方专属卡组管理器（4 手牌 + 1 预告 + 队列轮转，与玩家 DeckManager 同机制）
var _deck: DeckManager = null

## 当前相中的手牌索引（-1 = 尚未相中）。AI 会耐心等这张牌够费才出。
var _target_index: int = -1

## BattleManager 引用
@onready var battle_manager: Node = $"../BattleManager"

## Arena 引用
@onready var arena: Node2D = $"../../World/Arena"


## 初始化敌方 AI（由 BattleManager.start_battle() 调用）
func setup() -> void:
	_deck = DeckManager.new()
	_deck.name = "EnemyDeckManager"
	add_child(_deck)
	_deck.setup(DataRegistry.get_default_enemy_deck())
	_target_index = -1
	print("[SimpleEnemyAI] setup, hand:", _deck.get_hand(), " next:", _deck.get_next())


func _process(_delta: float) -> void:
	# 战斗未开始或已结束时不行动
	if battle_manager == null or not battle_manager.battle_running:
		return
	if _deck == null:
		return

	# 尚未相中目标：从手牌随机相中一张
	if _target_index < 0:
		_pick_target()
		if _target_index < 0:
			return  # 手牌为空（理论上不会）

	# 检查相中的目标牌圣水是否够：够则立即出牌并轮转手牌
	var hand = _deck.get_hand()
	if _target_index >= hand.size():
		_target_index = -1
		return
	var card_id = hand[_target_index]
	if battle_manager.can_afford_card("enemy", card_id):
		_try_play(card_id)


## 从当前手牌中随机相中一张作为出牌目标
func _pick_target() -> void:
	var hand = _deck.get_hand()
	if hand.is_empty():
		_target_index = -1
		return
	_target_index = randi() % hand.size()


## 出掉相中的目标牌：部署 + 扣费 + 手牌轮转 + 清空目标
func _try_play(card_id: String) -> void:
	var pos = _choose_spawn_position(card_id)
	var success = battle_manager.try_play_card(card_id, "enemy", pos)
	if success:
		# 手牌轮转：打出的牌回队尾，下一张填补空位
		_deck.play_card(_target_index)
		print("[SimpleEnemyAI] played:", card_id, " hand:", _deck.get_hand(), " next:", _deck.get_next())
	# 无论成功失败都清空目标，下一帧重新相中（避免卡在同一张牌上）
	_target_index = -1


## 选择部署位置。法术卡瞄准玩家半场，单位卡在敌方半场随机。
func _choose_spawn_position(card_id: String) -> Vector2:
	var card := DataRegistry.get_card_data(card_id)
	if card.get("card_type") == "spell":
		# 法术：瞄准玩家半场（敌方想伤害玩家单位/塔）
		var x = randf_range(BattleConstants.px(1.5), BattleConstants.ARENA_WIDTH - BattleConstants.px(1.5))
		var y = randf_range(
			BattleConstants.PLAYER_DEPLOY_Y_MIN + BattleConstants.CELL_SIZE,
			BattleConstants.PLAYER_DEPLOY_Y_MAX - BattleConstants.CELL_SIZE
		)
		return Vector2(x, y)
	return arena.get_random_enemy_deploy_position()
