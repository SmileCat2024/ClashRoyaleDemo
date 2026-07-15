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

# ---- 穿透模式（神箭游侠）----
var piercing: bool = false  ## 穿透：沿发射方向直线飞，命中路径上敌人但不消失，飞到 max_range 消失
var max_range: float = 0.0  ## 穿透最大飞行距离（像素）
var pierce_radius: float = 0.0  ## 穿透命中判定半径（像素），敌人离飞行中心线 ≤ 此值则命中
var _hit_targets: Array = []  ## 已命中目标集合（同一敌人只打一次）
var _fly_dir: Vector2 = Vector2.ZERO  ## 穿透飞行方向（发射时固定，不追踪）
# ---- 穿透箭视觉（神箭游侠）----
const PIERCE_CORE_ALPHA := 0.80   ## 范围带中心（路径线侧）白色透明度
const PIERCE_EDGE_ALPHA := 0.22   ## 范围带边缘泛蓝透明度
const PIERCE_TRAIL_ALPHA := 0.90  ## 中心路径线白色透明度
const ARROW_LEN := 8.0            ## 箭头长度（像素）
const ARROW_HALF_W := 5.5         ## 箭头半宽（像素）

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
func setup(spawn_pos: Vector2, target_node, dmg: int, spd: float, team_name: String, is_homing: bool = true, splash: float = 0.0, p_piercing: bool = false, p_max_range: float = 0.0, p_pierce_radius: float = 0.0) -> void:
	position = spawn_pos
	target = target_node
	damage = dmg
	speed = spd
	team = team_name
	homing = is_homing
	splash_radius = splash
	piercing = p_piercing
	max_range = p_max_range
	pierce_radius = p_pierce_radius

	# 记录目标初始位置（范围型此后不再更新）
	if target and is_instance_valid(target):
		_last_target_pos = BattlePathing.game_position_of(target)
	else:
		_last_target_pos = spawn_pos
	# 穿透模式：固定发射方向（不追踪），朝目标方向直线飞
	if piercing:
		_fly_dir = (_last_target_pos - spawn_pos).normalized() if _last_target_pos != spawn_pos else Vector2.RIGHT

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
	# 穿透模式：隐藏默认 Body 色块，改用 _draw 绘制穿透长箭（箭头 + 攻击范围长杆）
	if piercing and body_rect:
		body_rect.visible = false


func _process(delta: float) -> void:
	# 穿透模式：沿发射方向直线飞，飞行中命中路径敌人，飞到 max_range 消失
	if piercing:
		_process_piercing(delta)
		return
	# 锁定型：目标还活着 → 持续追踪其当前位置
	# 范围型：不追踪，_last_target_pos 在发射时已固定
	if homing and _has_valid_target():
		_last_target_pos = BattlePathing.game_position_of(target)

	# 通用定点飞行步进
	if _fly_toward(_last_target_pos, delta):
		_on_hit()


## 穿透模式飞行：沿发射方向直线飞，命中路径上敌人但不消失，飞到 max_range 消失
func _process_piercing(delta: float) -> void:
	position += _fly_dir * speed * delta
	_apply_arc_offset()
	queue_redraw()  # 重绘穿透箭视觉（position 变化已触发重绘，此处显式保证）
	# 命中检测（host 端，client 端只飞视觉）
	_check_pierce_hits()
	# 超过最大飞行距离 → 消失
	if _start_pos.distance_to(position) >= max_range:
		SignalBus.projectile_hit.emit(position, team)
		queue_free()


## 穿透命中检测：检测当前位置附近（pierce_radius 内）的未命中敌人，造成伤害并记录
func _check_pierce_hits() -> void:
	if NetworkManager.is_networked_client():
		return
	for e in EntityRegistry.get_enemies_of(team):
		if e in _hit_targets or not is_instance_valid(e):
			continue
		var e_pos := BattlePathing.game_position_of(e)
		var hr := float(e.get("hurt_radius"))
		# 敌人受击体与飞行范围带相交即命中：敌人中心到飞行线段（发射点→箭头）
		# 的距离 ≤ 穿透半径 + 敌人受击半径，使范围带碰到敌人任何部分都扣血
		if _dist_point_to_segment(e_pos, _start_pos, position) <= pierce_radius + hr:
			DamageSystem.resolve_impact(e, damage)
			_hit_targets.append(e)


## 点 p 到线段 ab 的最短距离（用于穿透箭判定敌人是否进入飞行范围带）
static func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 穿透箭视觉入口。非穿透模式直接返回，不影响其它投射物子类（它们各自重写 _draw）。
func _draw() -> void:
	if not piercing:
		return
	_draw_piercing_arrow()


## 绘制穿透长箭（神箭游侠）：箭头 + 从发射点延伸的攻击范围长杆（宽度=2×pierce_radius）+ 中心路径线。
## 全部基于两端均有的本地数据（position/_start_pos/_fly_dir/pierce_radius/team），对联机透明。
func _draw_piercing_arrow() -> void:
	var dir := _fly_dir if _fly_dir != Vector2.ZERO else Vector2.RIGHT
	var local_start := _start_pos - position  # 发射点局部坐标（节点无旋转，世界差=局部）
	var perp := Vector2(-dir.y, dir.x)         # 飞行方向的垂直向量
	var hw := pierce_radius                    # 范围带半宽（像素）= 穿透判定半径
	# 颜色：中心路径线白色，向外渐变泛蓝
	var white_core := Color(1.0, 1.0, 1.0, PIERCE_CORE_ALPHA)  # 中心（路径线侧）白色
	var blue_edge := Color(0.30, 0.58, 1.0, PIERCE_EDGE_ALPHA) # 边缘泛蓝
	var base_center := -dir * ARROW_LEN        # 箭头底部（长杆前端衔接处）
	# 1. 攻击范围长杆：中心白→边缘蓝（沿宽度方向渐变），分左右两半各用顶点色绘制
	var cols_edge := PackedColorArray([white_core, blue_edge, blue_edge, white_core])
	var pts_l := PackedVector2Array([
		base_center,              # 头部中心（白）
		base_center - perp * hw,  # 头部左边缘（蓝）
		local_start - perp * hw,  # 尾部左边缘（蓝）
		local_start,              # 尾部中心（白）
	])
	draw_polygon(pts_l, cols_edge)
	var pts_r := PackedVector2Array([
		base_center,              # 头部中心（白）
		base_center + perp * hw,  # 头部右边缘（蓝）
		local_start + perp * hw,  # 尾部右边缘（蓝）
		local_start,              # 尾部中心（白）
	])
	draw_polygon(pts_r, cols_edge)
	# 2. 中心路径线：白色，贯穿发射点到箭头底部
	draw_line(local_start, base_center, Color(1.0, 1.0, 1.0, PIERCE_TRAIL_ALPHA), 1.5)
	# 3. 箭头本体：白色箭尖在当前位置（节点原点=判定中心），朝飞行方向
	var b1 := base_center + perp * ARROW_HALF_W
	var b2 := base_center - perp * ARROW_HALF_W
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, b1, b2]), Color(1.0, 1.0, 1.0, 0.95))


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
