# 文件名：SpawnManager.gd
# 作用：根据卡牌数据实例化单位场景，把单位加入战场。
#       它是唯一负责"创建单位"的地方，其他脚本不直接 instantiate。
#       场景固定 preload UnitBase.tscn，不从 unit_data 读 scene_path。
# 挂载位置：BattleScene/Managers/SpawnManager（或 DebugBattle/Managers/SpawnManager）
# 依赖节点：UnitsRoot（单位的父容器）
# 初学者阅读建议：先看 spawn_unit()，了解单位怎么从卡牌变成战场上的实体。

extends Node

## 所有单位共用同一个场景文件。差异完全由 setup(data) 数据驱动。
const UNIT_SCENE := preload("res://scenes/entities/units/UnitBase.tscn")

## 单位的父容器（所有生成的单位都挂在这里下面）
@onready var units_root: Node2D = $"../../World/UnitsRoot"


## 根据卡牌 id 生成单位到指定位置。
## card_id: 卡牌 id（如 "card_knight"）
## team_name: "player" 或 "enemy"
## pos: 单位在世界中的生成位置
## 返回: 最后一个生成的单位节点，失败返回 null
func spawn_unit(card_id: String, team_name: String, pos: Vector2) -> Node:
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

	# 4. 读取召唤数量和散开半径（卡牌属性，不是单位属性）
	var count: int = int(card.get("spawn_count", 1))
	var spread: float = BattleConstants.px(float(card.get("spawn_spread", 0.0)))

	# 5. 循环生成
	var last_unit: Node = null
	for i in range(count):
		var unit = UNIT_SCENE.instantiate()

		# 计算散开偏移
		var offset = _calc_spawn_offset(i, count, spread)
		unit.position = pos + offset

		# 先 add_child（触发 _ready，@onready 解析）
		units_root.add_child(unit)

		# 再 setup（配置属性，创建 AttackComponent 等）
		unit.setup(u_data, team_name)

		# 注册到 EntityRegistry
		EntityRegistry.register(unit)

		# 发出信号
		SignalBus.unit_spawned.emit(unit, team_name)
		last_unit = unit

	print("[SpawnManager] spawn: %s x%d %s @ %s" % [unit_id, count, team_name, pos])
	return last_unit


## 计算多体召唤的散开偏移
func _calc_spawn_offset(index: int, total: int, spread: float) -> Vector2:
	if total <= 1 or spread <= 0.0:
		return Vector2.ZERO
	var angle = TAU * float(index) / float(total)
	return Vector2(cos(angle), sin(angle)) * spread * randf_range(0.5, 1.0)
