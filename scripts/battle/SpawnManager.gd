# 文件名：SpawnManager.gd
# 作用：根据卡牌数据实例化单位场景，把单位加入战场。
#       它是唯一负责"创建单位"的地方，其他脚本不直接 instantiate。
#       场景固定 preload UnitBase.tscn，不从 unit_data 读 scene_path。
# 挂载位置：BattleScene/Managers/SpawnManager（或 DebugBattle/Managers/SpawnManager）
# 依赖节点：UnitsRoot（单位的父容器）
# 初学者阅读建议：先看 spawn_unit()，了解单位怎么从卡牌变成战场上的实体。

class_name SpawnManager
extends Node

## 所有单位共用同一个场景文件。差异完全由 setup(data) 数据驱动。
const UNIT_SCENE := preload("res://scenes/entities/units/UnitBase.tscn")

## 单位的父容器（所有生成的单位都挂在这里下面）
@onready var units_root: Node2D = $"../../World/UnitsRoot"

## 联机单位 ID 计数器（host 分配唯一名字 "U1", "U2", ...，用于 Synchronizer 配对）
var _next_net_id: int = 1


## 根据卡牌 id 生成单位到指定位置。
## card_id: 卡牌 id（如 "card_knight"）
## team_name: "player" 或 "enemy"
## pos: 单位在世界中的生成位置
## awakening_effects: 觉醒效果配置（来自 AwakeningTracker，空字典=普通版）
## 返回: 最后一个生成的单位节点，失败返回 null
func spawn_unit(card_id: String, team_name: String, pos: Vector2, awakening_effects: Dictionary = {}) -> Node:
	# 1. 从 DataRegistry 获取卡牌数据
	var card = DataRegistry.get_card_data(card_id)
	if card.is_empty():
		push_error("[SpawnManager] Unknown card id: " + card_id)
		return null

	# 2. 从卡牌数据找到对应的单位 id
	var unit_id: String = card.get("unit_id", "")

	# 3. 从 DataRegistry 获取单位数据
	var u_data = DataRegistry.get_unit_data(unit_id)
	if u_data.is_empty():
		push_error("[SpawnManager] Unknown unit id: " + unit_id)
		return null

	# 4. 读取召唤数量和偏移配置（卡牌属性，不是单位属性）
	var count: int = int(card.get("spawn_count", 1))
	var spread: float = BattleConstants.px(float(card.get("spawn_spread", 0.0)))
	var offsets_data = card.get("spawn_offsets", null)

	# 5. 循环生成
	var last_unit: Node = null
	for i in range(count):
		var unit = UNIT_SCENE.instantiate()

		# 计算部署偏移（与 DeployPreview 共用同一套逻辑）
		var offset = _get_spawn_offset(i, count, spread, offsets_data)
		unit.position = pos + offset

		# 先 add_child（触发 _ready，@onready 解析）
		units_root.add_child(unit)

		# 再 setup（配置属性，创建 AttackComponent 等；elite_skill 从卡牌数据透传）
		unit.setup(u_data, team_name, awakening_effects, card.get("elite_skill", {}))

		# 注册到 EntityRegistry
		EntityRegistry.register(unit)

		# 联机模式：Host 分配唯一名字并通知 Client 创建同名单位
		# 同名节点让 BattleManager 手动 RPC 状态同步正确配对
		var final_pos: Vector2 = pos + offset
		if NetworkManager.is_networked() and NetworkManager.is_server():
			var net_name := "U%d" % _next_net_id
			_next_net_id += 1
			unit.name = net_name
			_rpc_spawn_unit.rpc(net_name, unit_id, team_name, final_pos)

		# 发出信号
		SignalBus.unit_spawned.emit(unit, team_name)
		last_unit = unit

	print("[SpawnManager] spawn: %s x%d %s @ %s" % [unit_id, count, team_name, pos])
	return last_unit


## 计算第 index 个单位的部署偏移（像素，World 本地游戏空间）。
## 优先使用卡牌中显式指定的 spawn_offsets（格 → 像素），
## 未指定时回退到确定性圆形分布（无随机因子，与 DeployPreview 完全一致）。
static func get_spawn_offsets(count: int, spread_px: float, offsets_data) -> Array:
	var result: Array = []
	for i in range(count):
		result.append(_calc_one_offset(i, count, spread_px, offsets_data))
	return result


## 计算单个单位的偏移（实例方法包装，方便内部调用）
func _get_spawn_offset(index: int, total: int, spread_px: float, offsets_data) -> Vector2:
	return _calc_one_offset(index, total, spread_px, offsets_data)


static func _calc_one_offset(index: int, total: int, spread_px: float, offsets_data) -> Vector2:
	# 优先使用显式偏移（spawn_offsets 数组，每项为格坐标 Vector2）
	if offsets_data != null and index < offsets_data.size():
		var o: Vector2 = offsets_data[index]
		return Vector2(BattleConstants.px(o.x), BattleConstants.px(o.y))
	# 回退：确定性圆形分布（无随机）
	if total <= 1 or spread_px <= 0.0:
		return Vector2.ZERO
	var angle = TAU * float(index) / float(total)
	return Vector2(cos(angle), sin(angle)) * spread_px


# =============================================================================
# 联机 RPC
# =============================================================================

## Host → Client：通知 Client 创建同名单位。两端节点名一致，Synchronizer 自动配对。
@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_unit(unit_name: String, unit_id: String, team_name: String, world_pos: Vector2) -> void:
	if NetworkManager.is_server():
		return  # Host 自己已创建
	var u_data = DataRegistry.get_unit_data(unit_id)
	if u_data.is_empty():
		push_error("[SpawnManager] Client 收到未知 unit_id: " + unit_id)
		return
	var unit = UNIT_SCENE.instantiate()
	unit.name = unit_name
	units_root.add_child(unit)
	# Client 端 team 翻转：host 的 player → client 的 enemy，反之亦然。
	# 这样 client 自己始终是 player（蓝方），对方始终是 enemy（红方）。
	var local_team := "enemy" if team_name == "player" else "player"
	unit.setup(u_data, local_team)
	# Client 端：镜像初始位置（后续由 BattleManager 手动 RPC 持续同步镜像坐标）
	unit.position = BattleConstants.mirror(world_pos)
	# Client 不注册到 EntityRegistry（不跑索敌/攻击逻辑）
	SignalBus.unit_spawned.emit(unit, local_team)
	print("[SpawnManager] Client spawn:", unit_name, unit_id, team_name)
