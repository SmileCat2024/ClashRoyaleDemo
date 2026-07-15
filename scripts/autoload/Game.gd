# 文件名：Game.gd
# 作用：保存全局游戏状态，提供场景切换的统一入口。
#       不处理具体战斗细节，只管"现在在哪个界面"。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：先看 start_battle()，理解点击"开始战斗"后场景怎么跳转。

extends Node

## 游戏状态枚举
enum GameState {
	MENU,     ## 在主菜单
	BATTLE,   ## 在战斗中
	PAUSED,   ## 暂停
	RESULT    ## 战斗结束，显示结果
}

## 当前游戏状态
var current_state: GameState = GameState.MENU

## 是否处于联机模式（true = 联机对战 / false = 单机 vs AI）
var network_mode: bool = false

## 对局规则：极速模式维持原有 7 倍圣水；经典模式采用官方 1v1 时间与倍率节奏。
enum MatchMode { FAST_7X, CLASSIC_1V1 }
var match_mode: int = MatchMode.FAST_7X

## 大厅中选择的预设卡组。卡组由设计方固定，不开放编辑。
var selected_deck_index: int = 0
var remote_deck_cards: Array = []

const PRESET_DECKS: Array[Dictionary] = [
	{"name": "皇家冲锋", "cards": ["card_hog_rider", "card_musketeer", "card_knight_elite", "card_fireball", "card_archers", "card_goblins", "card_inferno_tower", "card_arrows"]},
	{"name": "空中奇袭", "cards": ["card_balloon", "card_flyer", "card_mega_minion_elite", "card_musketeer", "card_fireball", "card_arrows", "card_goblins", "card_inferno_tower"]},
	{"name": "重甲推进", "cards": ["card_giant", "card_pekka", "card_mini_pekka", "card_musketeer", "card_poison", "card_arrows", "card_goblins", "card_elixir_collector"]},
	{"name": "迫击炮阵地", "cards": ["card_mortar", "card_princess", "card_knight_elite", "card_archers", "card_fireball", "card_poison", "card_ranger", "card_inferno_tower"]},
	{"name": "王子突击", "cards": ["card_prince", "card_valkyrie", "card_hog_rider", "card_musketeer", "card_fireball", "card_arrows", "card_mega_minion_elite", "card_elixir_collector"]},
]


## 设置联机模式（由 MainMenu 在进入战斗前调用）
func set_network_mode(enabled: bool) -> void:
	network_mode = enabled
	print("[Game] network_mode =", enabled)


func set_match_mode(mode: int) -> void:
	match_mode = mode
	print("[Game] match_mode =", mode)


func set_selected_deck(index: int) -> void:
	selected_deck_index = clampi(index, 0, PRESET_DECKS.size() - 1)
	print("[Game] selected deck =", selected_deck_index)


func get_selected_deck() -> Array:
	return PRESET_DECKS[selected_deck_index].get("cards", []).duplicate()


func set_remote_deck(cards: Array) -> void:
	remote_deck_cards = cards.duplicate()


func get_remote_deck() -> Array:
	return remote_deck_cards.duplicate()


## 进入战斗场景
func start_battle() -> void:
	current_state = GameState.BATTLE
	SceneLoader.load_battle()


## 返回主菜单
func return_to_menu() -> void:
	current_state = GameState.MENU
	SceneLoader.load_main_menu()


## 重新开始战斗（重新加载战斗场景）
func restart_battle() -> void:
	current_state = GameState.BATTLE
	SceneLoader.load_battle()
