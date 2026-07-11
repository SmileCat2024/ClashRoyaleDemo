# 文件名：ProjectileBase.gd
# 作用：飞行物基类——提供共享飞行基础设施（_fly_toward / _fly_progress / _apply_arc_offset），
#       子类 SpellProjectile（法术弹道）和 ArrowProjectile（箭矢）复用这些方法，不各自重写飞行逻辑。
#
#       本类自身也是可用的完整飞行物：
#         锁定型（homing = true）：持续追踪目标，命中后单体伤害。
#         范围型（homing = false）：发射时锁定方向，不追踪，到达后对范围内所有敌方造成溅射伤害。
#
#       如果目标在飞行途中死亡：
#         锁定型仍飞向目标最后位置，到达时因目标已死而不造成伤害，自然消失。
#         范围型不受影响——它本来就是飞向固定位置，到达后照常溅射。
# 挂载位置：Projectile.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解飞行物怎么初始化，再看 _process() 了解每帧的移动和命中判定。

class_name ProjectileBase
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
# 使用 get_node_or_null 以支持无 Body 子节点的子类（如 ArrowProjectile 纯 _draw 渲染）
@onready var body_rect: ColorRect = get_node_or_null("Body")


## 初始化飞行物。由 ProjectileManager.spawn_projectile() 调用。
## spawn_pos: 发射位置（World 本地游戏空间坐标）
## target_node: 目标节点
## dmg: 伤害值
## spd: 飞行速度（像素/秒）
## team_name: "player" 或 "enemy"
## is_homing: true = 锁定型（追踪），false = 范围型（固定方向 + 溅射）
## splash: 溅射半径（可选，默认 0 = 单体伤害）
func setup(spawn_pos: Vector2, target_node, dmg: int, spd: float, team_name: String, is_homing: bool = true, splash: float = 0.0) -> void:
	position = spawn_pos
	target = target_node
	damage = dmg
	speed = spd
	team = team_name
	homing = is_homing
	splash_radius = splash

	# 记录目标初始位置（范围型此后不再更新）
	if target and is_instance_valid(target):
		_last_target_pos = BattlePathing.game_position_of(target)
	else:
		_last_target_pos = spawn_pos

	# 弹道弧度初始化
	_start_pos = spawn_pos
	if target and is_instance_valid(target):
		_total_dist = spawn_pos.distance_to(BattlePathing.game_position_of(target))
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
		_last_target_pos = BattlePathing.game_position_of(target)

	# 通用定点飞行步进
	if _fly_toward(_last_target_pos, delta):
		_on_hit()


## 通用定点飞行：沿直线向 dest 移动 speed（像素/秒），施加抛物线弧高视觉偏移。
## 返回 true 表示本帧已到达目标位置。子类（SpellProjectile / ArrowProjectile）共享此方法，
## 各自只需在 setup() 中设置 _start_pos / _total_dist / speed / arc_height，然后在 _process 中调用。
func _fly_toward(dest: Vector2, delta: float) -> bool:
	var to_dest := dest - position
	var dist := to_dest.length()
	if dist <= speed * delta:
		position = dest
		return true
	position += to_dest.normalized() * speed * delta
	_apply_arc_offset()
	return false


## 返回当前飞行进度 [0, 1]。用于子类的 _draw() 弧高计算。
func _fly_progress() -> float:
	if _total_dist <= 0.0:
		return 1.0
	return clampf(_start_pos.distance_to(position) / _total_dist, 0.0, 1.0)


## 施加当前弧高偏移到 body_rect（基于飞行进度）。无 body_rect 时跳过（ArrowProjectile 自行 _draw）。
func _apply_arc_offset() -> void:
	if body_rect == null:
		return
	if arc_height > 0.0 and _total_dist > 0.0:
		body_rect.position.y = _body_base_y - compute_arc_offset(arc_height, _fly_progress())


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
	# 联机 client 端：不造成伤害（由 host 计算），只发信号 + 销毁
	if not NetworkManager.is_networked_client():
		if splash_radius > 0.0:
			_deal_splash_damage()
		elif _has_valid_target():
			# 目标仍存活 → 走统一伤害结算入口（含护盾、死亡判定）
			DamageSystem.resolve_impact(target, damage)
	# 目标已死 → 飞行物自然消失，不造成伤害

	SignalBus.projectile_hit.emit(position, team)
	queue_free()


## 范围伤害：统一走 DamageSystem.deal_area_damage（含 EntityRegistry 查询 + 塔减伤支持）
func _deal_splash_damage() -> void:
	DamageSystem.deal_area_damage(position, splash_radius, damage, team)


## 计算抛物线弧高视觉偏移（像素）。子类（SpellProjectile 等）共享此方法。
## arc_height_grids: 弧高（格），progress: 飞行进度 [0, 1]
static func compute_arc_offset(arc_height_grids: float, progress: float) -> float:
	return arc_height_grids * sin(progress * PI) * BattleConstants.CELL_SIZE
