# 文件名：SpellManager.gd
# 作用：法术卡牌的统一部署入口。接收卡牌 id + 目标位置，创建法术飞行物。
#       法术不生成单位，而是从施法方的国王塔发射 SpellProjectile，飞到目标位置爆炸。
#       与 SpawnManager（生成单位）平行，BattleManager 根据 card_type 分流到对应 Manager。
# 挂载位置：BattleScene/Managers/SpellManager
# 依赖节点：ProjectilesRoot（法术飞行物的父容器）
# 初学者阅读建议：看 cast_spell()，了解法术从卡牌到飞行物的完整流程。

extends Node

## 法术飞行物场景
const SPELL_PROJECTILE_SCENE := preload("res://scenes/entities/SpellProjectile.tscn")

## 飞行物的父容器
@onready var projectiles_root: Node2D = $"../../World/ProjectilesRoot"


## 施放法术。由 BattleManager.try_play_card() 在 card_type == "spell" 时调用。
## card_id: 卡牌 id（如 "card_fireball"）
## team_name: "player" 或 "enemy"
## target_pos: 目标位置（World 本地游戏空间坐标）
func cast_spell(card_id: String, team_name: String, target_pos: Vector2) -> void:
	var card := DataRegistry.get_card_data(card_id)
	if card.is_empty():
		push_error("[SpellManager] Unknown card id: " + card_id)
		return

	var origin := _get_king_tower_position(team_name)
	var projectile = SPELL_PROJECTILE_SCENE.instantiate()
	projectiles_root.add_child(projectile)
	projectile.setup(origin, target_pos, card, team_name)

	print("[SpellManager] cast %s (%s) → %s" % [card_id, team_name, target_pos])


## 获取指定阵营国王塔的位置（World 本地游戏空间坐标）。
## 使用常量而非查找节点——即使国王塔被摧毁，法术仍从该位置发射。
static func _get_king_tower_position(team_name: String) -> Vector2:
	var key := "PlayerKingTower" if team_name == "player" else "EnemyKingTower"
	return BattleConstants.TOWER_PIXEL_POSITIONS[key]
