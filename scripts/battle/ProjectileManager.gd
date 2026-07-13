# 文件名：ProjectileManager.gd
# 作用：统一的飞行物生成入口。所有飞行物都通过这里创建，不直接 instantiate。
#       参考 SpawnManager 的模式，保持一致的架构风格。
# 挂载位置：BattleScene/Managers/ProjectileManager
# 依赖节点：ProjectilesRoot（飞行物的父容器）
# 初学者阅读建议：看 spawn_projectile()，了解飞行物从参数到战场实体的完整流程。

extends Node

## 飞行物场景（预加载，避免每次发射都重新读取文件）
const PROJECTILE_SCENE := preload("res://scenes/entities/Projectile.tscn")
const MORTAR_SHELL_SCENE := preload("res://scenes/entities/MortarShell.tscn")

## 飞行物的父容器（所有生成的飞行物都挂在这里下面）
@onready var projectiles_root: Node2D = $"../../World/ProjectilesRoot"

## 联机投射物 ID 计数器（host 分配唯一名字 "P1", "P2", ...）
var _next_net_id: int = 1


## 发射一个飞行物。
## spawn_pos: 发射位置（World 本地游戏空间坐标）
## target_node: 目标节点（单位或塔）
## damage: 伤害值
## speed: 飞行速度（像素/秒）
## team_name: "player" 或 "enemy"
## is_homing: true = 锁定型（追踪目标），false = 范围型（固定方向 + 溅射）
## splash: 溅射半径（可选，默认 0 = 单体伤害）
## arc_height_grids: 弹道弧高峰值（格，可选）。>0 时施加抛物线视觉偏移，不影响逻辑命中
## 返回: 生成的飞行物节点
func spawn_projectile(spawn_pos: Vector2, target_node, damage: int, speed: float, team_name: String, is_homing: bool = true, splash: float = 0.0, arc_height_grids: float = 0.0) -> Node2D:
	var projectile = PROJECTILE_SCENE.instantiate()
	projectiles_root.add_child(projectile)
	projectile.setup(spawn_pos, target_node, damage, speed, team_name, is_homing, splash)
	if arc_height_grids > 0.0:
		projectile.arc_height = arc_height_grids
	SignalBus.projectile_spawned.emit(projectile, team_name)
	# 联机 host 端：通知 client 也创建投射物（两端独立运行确定性飞行，client 端 _on_hit 跳过伤害）
	if NetworkManager.is_server():
		var target_pos := BattlePathing.game_position_of(target_node) if target_node else spawn_pos
		var net_name := "P%d" % _next_net_id
		_next_net_id += 1
		projectile.name = net_name
		_rpc_spawn_projectile.rpc(net_name, spawn_pos, target_pos, damage, speed, team_name, is_homing, splash, arc_height_grids)
	return projectile


## 发射迫击炮炮弹（高抛溅射）。由 AttackComponent 在 trajectory=ballistic 时调用。
## spawn_pos: 发射位置 | target_node: 目标节点（取其当前位置为落点）
## damage: 范围伤害 | splash_px: 溅射半径（像素）| speed_px: 飞行速度（像素/秒）
## team_name: 阵营 | arc_grids: 弧高峰值（格）
## 返回: 生成的炮弹节点
func spawn_mortar_shell(spawn_pos: Vector2, target_node, damage: int, splash_px: float, speed_px: float, team_name: String, arc_grids: float, attack_ground: bool = true, attack_air: bool = true) -> Node2D:
	var shell = MORTAR_SHELL_SCENE.instantiate()
	projectiles_root.add_child(shell)
	shell.setup_shell(spawn_pos, target_node, damage, splash_px, speed_px, team_name, arc_grids, attack_ground, attack_air)
	SignalBus.projectile_spawned.emit(shell, team_name)
	# 联机 host 端：通知 client 也创建炮弹（两端独立运行确定性飞行）
	if NetworkManager.is_server():
		var target_pos := BattlePathing.game_position_of(target_node) if target_node else spawn_pos
		var net_name := "M%d" % _next_net_id
		_next_net_id += 1
		shell.name = net_name
		_rpc_spawn_mortar_shell.rpc(net_name, spawn_pos, target_pos, damage, splash_px, speed_px, team_name, arc_grids)
	return shell


# =============================================================================
# 联机 RPC
# =============================================================================

## Host → Client：通知 Client 创建投射物。两端独立运行确定性飞行，client 端 _on_hit 跳过伤害。
@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_projectile(proj_name: String, spawn_pos: Vector2, target_pos: Vector2, dmg: int, spd: float, team_name: String, is_homing: bool, splash: float, arc_height_grids: float) -> void:
	if NetworkManager.is_server():
		return
	# Client 端 180 度镜像：发射点和落点都镜像
	var m_spawn := BattleConstants.mirror(spawn_pos)
	var m_target := BattleConstants.mirror(target_pos)
	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.name = proj_name
	projectiles_root.add_child(projectile)
	# Client 端 team 翻转 + 飞向固定位置（非追踪），飞行轨迹与 host 端镜像对称
	var local_team := "enemy" if team_name == "player" else "player"
	projectile.setup(m_spawn, null, dmg, spd, local_team, false, splash)
	projectile._last_target_pos = m_target
	projectile._start_pos = m_spawn
	projectile._total_dist = m_spawn.distance_to(m_target)
	if arc_height_grids > 0.0:
		projectile.arc_height = arc_height_grids
	# 按阵营设色（用翻转后的 local_team）
	if projectile.body_rect:
		projectile.body_rect.color = Color(0.9, 0.85, 0.2) if local_team == "player" else Color(0.9, 0.5, 0.1)


## Host → Client：通知 Client 创建迫击炮炮弹。
@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_mortar_shell(shell_name: String, spawn_pos: Vector2, target_pos: Vector2, dmg: int, splash_px: float, speed_px: float, team_name: String, arc_grids: float) -> void:
	if NetworkManager.is_server():
		return
	# Client 端 180 度镜像 + team 翻转
	var m_spawn := BattleConstants.mirror(spawn_pos)
	var m_target := BattleConstants.mirror(target_pos)
	var shell = MORTAR_SHELL_SCENE.instantiate()
	shell.name = shell_name
	projectiles_root.add_child(shell)
	# Client 端：飞向固定位置（迫击炮本来就是非追踪的），team 翻转
	var local_team := "enemy" if team_name == "player" else "player"
	shell.setup_shell(m_spawn, null, dmg, splash_px, speed_px, local_team, arc_grids)
	shell._last_target_pos = m_target
	shell._start_pos = m_spawn
	shell._total_dist = m_spawn.distance_to(m_target)
