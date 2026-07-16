# 文件名：test_match_settlement.gd
# 作用：验证常规时间、加时赛与最终最低塔血量结算规则。

extends TestBase

const BATTLE_MANAGER_SCRIPT := preload("res://scripts/battle/BattleManager.gd")


class TowerStub extends RefCounted:
	var team: String
	var tower_type: String
	var current_hp: int
	var is_dead: bool

	func _init(p_team: String, p_tower_type: String, p_current_hp: int, p_is_dead: bool = false) -> void:
		team = p_team
		tower_type = p_tower_type
		current_hp = p_current_hp
		is_dead = p_is_dead

	func activate_king() -> void:
		pass


var _manager


func setup() -> void:
	_manager = BATTLE_MANAGER_SCRIPT.new()


func teardown() -> void:
	_manager.free()


func _set_towers(player_hps: Array[int], enemy_hps: Array[int], player_dead: Array[bool] = [], enemy_dead: Array[bool] = []) -> void:
	_manager._towers.clear()
	for index in player_hps.size():
		var hp := player_hps[index]
		var dead := player_dead[index] if player_dead.size() > index else false
		_manager._towers.append(TowerStub.new("player", "guard", hp, dead))
	for index in enemy_hps.size():
		var dead := enemy_dead[index] if enemy_dead.size() > index else false
		_manager._towers.append(TowerStub.new("enemy", "guard", enemy_hps[index], dead))


func test_regular_time_tie_requires_equal_remaining_towers() -> void:
	_set_towers([300, 200, 100], [999, 1, 1])
	assert_true(_manager._are_sides_tied(), "常规时间同样数量的皇冠塔存活时应进入加时")
	_manager._towers[2].is_dead = true
	assert_false(_manager._are_sides_tied(), "任一方多损失一座塔就不应进入加时")


func test_regular_time_tie_enters_overtime() -> void:
	_set_towers([300, 200, 100], [999, 1, 1])
	_manager.battle_running = true
	_manager.battle_time = _manager.max_battle_time
	_manager._check_time_limit()
	assert_true(_manager.battle_running, "双方平局时不应在常规时间结束战斗")
	assert_eq(_manager.battle_phase, "overtime", "双方平局时应进入加时赛")


func test_king_tower_destruction_ends_regular_time_immediately() -> void:
	_manager.battle_running = true
	_manager.battle_phase = "regular"
	_manager._on_tower_destroyed("EnemyKing", "enemy", "king")
	assert_false(_manager.battle_running, "国王塔被毁后必须立即停止战斗")
	assert_eq(_manager.match_result, "victory", "敌方国王塔被毁应判本地玩家胜利")


func test_any_tower_destruction_ends_overtime_immediately() -> void:
	_manager.battle_running = true
	_manager.battle_phase = "overtime"
	_manager._on_tower_destroyed("PlayerGuard", "player", "guard")
	assert_false(_manager.battle_running, "加时赛任意皇冠塔被毁后必须立即停止战斗")
	assert_eq(_manager.match_result, "defeat", "本方公主塔在加时被毁应判本地玩家失败")


func test_overtime_uses_lowest_current_tower_hp_not_total_hp() -> void:
	# 敌方总血量更高（1,197 vs 600），但最低塔血量更低（99 vs 100）。
	_set_towers([300, 200, 100], [999, 99, 99])
	assert_eq(_manager._determine_result_by_stats(), "victory", "加时结束应只比较双方最低塔血量")


func test_destroyed_tower_counts_as_zero_for_tiebreak() -> void:
	_set_towers([300, 200, 100], [999, 300, 200], [], [false, false, true])
	assert_eq(_manager._get_lowest_tower_hp("enemy"), 0, "已毁塔在最低血量比较中必须按 0 计")
	assert_eq(_manager._determine_result_by_stats(), "victory", "对方存在被毁塔时，本方应以非零最低血量获胜")


func test_equal_lowest_tower_hp_is_draw() -> void:
	_set_towers([900, 200, 100], [999, 100, 100])
	assert_eq(_manager._determine_result_by_stats(), "draw", "最低塔血量相同应判平局")
