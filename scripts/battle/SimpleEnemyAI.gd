# 文件名：SimpleEnemyAI.gd
# 作用：让敌方自动出牌。每隔 2~4 秒随机选一张卡牌，在敌方半场随机位置部署。
#       AI 不需要聪明，只需要让战斗能自动进行。
# 挂载位置：BattleScene/Managers/SimpleEnemyAI
# 依赖节点：BattleManager（调用 try_play_card）、Arena（获取部署位置）
# 初学者阅读建议：先看 _process() 了解计时逻辑，再看 try_enemy_action() 了解出牌流程。

extends Node

## 计时器，累积时间
var ai_timer: float = 0.0

## 下次行动的时间间隔（秒）
var next_action_time: float = 3.0

## 敌方卡组（卡牌 id 列表）
var enemy_deck: Array = []

## BattleManager 引用
@onready var battle_manager: Node = $"../BattleManager"

## Arena 引用
@onready var arena: Node2D = $"../../World/Arena"


## 初始化敌方 AI（由 BattleManager.start_battle() 调用）
func setup() -> void:
	enemy_deck = DataRegistry.get_default_enemy_deck()
	ai_timer = 0.0
	next_action_time = randf_range(2.0, 4.0)
	print("[SimpleEnemyAI] setup, deck size:", enemy_deck.size())


func _process(delta: float) -> void:
	# 战斗未开始或已结束时不行动
	if battle_manager == null or not battle_manager.battle_running:
		return

	ai_timer += delta
	if ai_timer >= next_action_time:
		ai_timer = 0.0
		next_action_time = randf_range(2.0, 4.0)
		try_enemy_action()


## 尝试一次敌方出牌
func try_enemy_action() -> void:
	var card_id = choose_random_card()
	if card_id == "":
		return
	var pos = choose_spawn_position()
	var success = battle_manager.try_play_card(card_id, "enemy", pos)
	if success:
		print("[SimpleEnemyAI] played:", card_id, "at", pos)


## 从敌方卡组中随机选一张卡牌
func choose_random_card() -> String:
	if enemy_deck.is_empty():
		return ""
	return enemy_deck[randi() % enemy_deck.size()]


## 在敌方部署区域随机选一个位置
func choose_spawn_position() -> Vector2:
	return arena.get_random_enemy_deploy_position()
