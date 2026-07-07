# 文件名：ProjectileBase.gd
# 作用：飞行物实体——从发射者飞向目标，命中后造成伤害，然后销毁。
#
#       两种飞行模式：
#         锁定型（homing = true）：持续追踪目标，命中后单体伤害。
#         范围型（homing = false）：发射时锁定方向，不追踪，到达后对范围内所有敌方造成溅射伤害。
#
#       如果目标在飞行途中死亡：
#         锁定型仍飞向目标最后位置，到达时因目标已死而不造成伤害，自然消失。
#         范围型不受影响——它本来就是飞向固定位置，到达后照常溅射。
# 挂载位置：Projectile.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解飞行物怎么初始化，再看 _process() 了解每帧的移动和命中判定。

extends Node2D

# ---- 战斗属性 ----
var damage: int = 10
var speed: float = 200.0
var splash_radius: float = 0.0  ## 溅射半径。>0 时命中后对范围内所有敌方造成伤害

# ---- 飞行模式 ----
var homing: bool = true  ## true = 锁定型（追踪目标），false = 范围型（固定方向）

# ---- 弹道视觉 ----
var arc_height: float = 0.0  ## 弹道最大弧高（格）。> 0 时抛物线视觉弧，不影响逻辑命中
var _start_pos: Vector2 = Vector2.ZERO
var _total_dist: float = 0.0
var _body_base_y: float = 0.0

# ---- 身份信息 ----
var team: String = "player"

# ---- 运行时状态 ----
var target = null                      ## 目标节点（单位或塔）
var _last_target_pos: Vector2 = Vector2.ZERO  ## 目标位置（锁定型持续更新，范围型发射时固定）

# ---- 子节点引用 ----
@onready var body_rect: ColorRect = $Body


## 初始化飞行物。由 ProjectileManager.spawn_projectile() 调用。
## spawn_pos: 发射位置（世界坐标）
## target_node: 目标节点
## dmg: 伤害值
## spd: 飞行速度（像素/秒）
## team_name: "player" 或 "enemy"
## is_homing: true = 锁定型（追踪），false = 范围型（固定方向 + 溅射）
## splash: 溅射半径（可选，默认 0 = 单体伤害）
func setup(spawn_pos: Vector2, target_node, dmg: int, spd: float, team_name: String, is_homing: bool = true, splash: float = 0.0) -> void:
	global_position = spawn_pos
	target = target_node
	damage = dmg
	speed = spd
	team = team_name
	homing = is_homing
	splash_radius = splash

	# 记录目标初始位置（范围型此后不再更新）
	if target and is_instance_valid(target):
		_last_target_pos = target.global_position
	else:
		_last_target_pos = spawn_pos

	# 弹道弧度初始化
	_start_pos = spawn_pos
	if target and is_instance_valid(target):
		_total_dist = spawn_pos.distance_to(target.global_position)
	_body_base_y = body_rect.position.y

	# 根据阵营设置颜色
	if team == "player":
		body_rect.color = Color(0.9, 0.85, 0.2)
	else:
		body_rect.color = Color(0.9, 0.5, 0.1)


func _process(delta: float) -> void:
	# 锁定型：目标还活着 → 持续追踪其当前位置
	# 范围型：不追踪，_last_target_pos 在发射时已固定
	if homing and _has_valid_target():
		_last_target_pos = target.global_position

	# 朝目标位置移动
	var to_target = _last_target_pos - global_position
	var distance = to_target.length()

	if distance <= speed * delta:
		# 本帧就能到达 → 命中
		global_position = _last_target_pos
		_on_hit()
		return
	else:
		global_position += to_target.normalized() * speed * delta

	# 弹道抛物线视觉高度（不影响逻辑位置和命中判定）
	if arc_height > 0.0 and _total_dist > 0.0:
		var traveled := _start_pos.distance_to(global_position)
		var progress: float = clampf(traveled / _total_dist, 0.0, 1.0)
		var arc := arc_height * sin(progress * PI) * BattleConstants.CELL_SIZE
		body_rect.position.y = _body_base_y - arc


## 检查目标是否有效（存在、未销毁、未死亡）
func _has_valid_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var dead_val = target.get("is_dead")
	if dead_val != null and dead_val:
		return false
	return true


## 命中处理：造成伤害，发出信号，销毁自身
func _on_hit() -> void:
	if splash_radius > 0.0:
		_deal_splash_damage()
	elif _has_valid_target():
		# 目标仍存活 → 走统一伤害结算入口（含护盾、死亡判定）
		DamageSystem.resolve_impact(target, damage)
	# 目标已死 → 飞行物自然消失，不造成伤害

	SignalBus.projectile_hit.emit(global_position, team)
	queue_free()


## 范围伤害：对溅射半径内的所有敌方目标造成伤害
func _deal_splash_damage() -> void:
	var scene = get_tree().current_scene
	var units_root = scene.get_node_or_null("World/UnitsRoot")
	var towers_root = scene.get_node_or_null("World/TowersRoot")

	if units_root:
		for u in units_root.get_children():
			if _is_valid_enemy(u):
				if global_position.distance_to(u.global_position) <= splash_radius:
					if u.has_method("take_damage"):
						u.take_damage(damage)

	if towers_root:
		for t in towers_root.get_children():
			if _is_valid_enemy(t):
				if global_position.distance_to(t.global_position) <= splash_radius:
					if t.has_method("take_damage"):
						t.take_damage(damage)


## 判断一个节点是否是有效的敌方目标
func _is_valid_enemy(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var dead_val = node.get("is_dead")
	if dead_val != null and dead_val:
		return false
	var node_team = node.get("team")
	if node_team == null or node_team == team:
		return false
	return true
