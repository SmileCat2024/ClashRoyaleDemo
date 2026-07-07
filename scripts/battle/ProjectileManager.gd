# 文件名：ProjectileManager.gd
# 作用：统一的飞行物生成入口。所有飞行物都通过这里创建，不直接 instantiate。
#       参考 SpawnManager 的模式，保持一致的架构风格。
# 挂载位置：BattleScene/Managers/ProjectileManager
# 依赖节点：ProjectilesRoot（飞行物的父容器）
# 初学者阅读建议：看 spawn_projectile()，了解飞行物从参数到战场实体的完整流程。

extends Node

## 飞行物场景（预加载，避免每次发射都重新读取文件）
const PROJECTILE_SCENE := preload("res://scenes/entities/Projectile.tscn")

## 飞行物的父容器（所有生成的飞行物都挂在这里下面）
@onready var projectiles_root: Node2D = $"../../World/ProjectilesRoot"


## 发射一个飞行物。
## spawn_pos: 发射位置（World 本地游戏空间坐标）
## target_node: 目标节点（单位或塔）
## damage: 伤害值
## speed: 飞行速度（像素/秒）
## team_name: "player" 或 "enemy"
## is_homing: true = 锁定型（追踪目标），false = 范围型（固定方向 + 溅射）
## splash: 溅射半径（可选，默认 0 = 单体伤害）
## 返回: 生成的飞行物节点
func spawn_projectile(spawn_pos: Vector2, target_node, damage: int, speed: float, team_name: String, is_homing: bool = true, splash: float = 0.0) -> Node2D:
	var projectile = PROJECTILE_SCENE.instantiate()
	projectiles_root.add_child(projectile)
	projectile.setup(spawn_pos, target_node, damage, speed, team_name, is_homing, splash)
	SignalBus.projectile_spawned.emit(projectile, team_name)
	return projectile
