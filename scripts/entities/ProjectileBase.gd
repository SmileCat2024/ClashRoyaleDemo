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
var piercing: bool = false  ## 穿透：实体长箭沿固定方向飞行，命中箭身触及的敌人但不消失
var max_range: float = 0.0  ## 穿透最大飞行距离（像素）
var pierce_radius: float = 0.0  ## 穿透命中判定半径（像素），敌人离飞行中心线 ≤ 此值则命中
var _hit_targets: Array = []  ## 已命中目标集合（同一敌人只打一次）
var _fly_dir: Vector2 = Vector2.ZERO  ## 穿透飞行方向（发射时固定，不追踪）
# ---- 穿透箭视觉（神箭游侠）----
# 穿透箭是实体长箭而非激光：拉弓时逐渐显形，完整露出后脱手飞行，抵达末端后箭尾没入终点。
const PIERCE_ARROW_LENGTH := 130.0      ## 超长箭身（6.5 格），视觉上明显区别于普通投射物
const PIERCE_ARROW_HALF_W := 7.0        ## 宽箭杆半宽（像素）
const PIERCE_DRAW_DURATION := 0.32      ## 从弓上慢慢露出完整箭身的时间（秒）
const PIERCE_EMBED_DURATION := 0.28     ## 箭头抵达终点后，箭尾完全没入的时间（秒）
const PIERCE_ARROW_CORE := Color(0.50, 0.91, 1.0, 0.60) ## 明亮天空蓝箭杆内芯（不混白）
const PIERCE_ARROW_EDGE := Color(0.34, 0.78, 1.0, 0.20) ## 浅亮透明蓝边缘，不形成硬描边
var _piercing_phase: String = "drawing" ## "drawing" | "flying" | "embedding"
var _piercing_phase_time: float = 0.0
var _piercing_visible_length: float = 0.0

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
		_piercing_phase = "drawing"
		_piercing_phase_time = 0.0
		_piercing_visible_length = 0.0

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


## 穿透模式：先从弓上逐渐露出，再让实体长箭脱手飞行；箭头抵达终点后箭尾继续没入。
func _process_piercing(delta: float) -> void:
	match _piercing_phase:
		"drawing":
			_piercing_phase_time += delta
			var reveal := clampf(_piercing_phase_time / PIERCE_DRAW_DURATION, 0.0, 1.0)
			_piercing_visible_length = PIERCE_ARROW_LENGTH * reveal
			if reveal >= 1.0:
				# 节点原点代表箭头；完整露出后让箭头从弓前端脱手，避免视觉跳回发射点。
				position += _fly_dir * PIERCE_ARROW_LENGTH
				_piercing_phase = "flying"
				_piercing_phase_time = 0.0
				_check_pierce_hits()
		"flying":
			var travelled := _start_pos.distance_to(position)
			var remaining := maxf(max_range - travelled, 0.0)
			var step := minf(speed * delta, remaining)
			position += _fly_dir * step
			_check_pierce_hits()
			if remaining <= step:
				# 箭头钻入最大射程终点，留下的箭身继续向前消失。
				_piercing_phase = "embedding"
				_piercing_phase_time = 0.0
				_piercing_visible_length = PIERCE_ARROW_LENGTH
				SignalBus.projectile_hit.emit(position, team)
		"embedding":
			_piercing_phase_time += delta
			var embed := clampf(_piercing_phase_time / PIERCE_EMBED_DURATION, 0.0, 1.0)
			_piercing_visible_length = PIERCE_ARROW_LENGTH * (1.0 - embed)
			if embed >= 1.0:
				queue_free()
	queue_redraw()


## 穿透命中检测：只检测正在飞行的实体箭身，而非发射点到箭头的整段路径。
func _check_pierce_hits() -> void:
	if NetworkManager.is_networked_client():
		return
	var dir := _fly_dir if _fly_dir != Vector2.ZERO else Vector2.RIGHT
	var arrow_tail := position - dir * PIERCE_ARROW_LENGTH
	for e in EntityRegistry.get_enemies_of(team):
		if e in _hit_targets or not is_instance_valid(e):
			continue
		var e_pos := BattlePathing.game_position_of(e)
		var hr := float(e.get("hurt_radius"))
		# 敌人受击体与当前箭身相交即命中。箭经过后不再保留伤害带，避免成为激光。
		if _dist_point_to_segment(e_pos, arrow_tail, position) <= pierce_radius + hr:
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


## 绘制半透明浅蓝实体长箭。drawing 阶段从弓上露出，flying 阶段脱手，embedding 阶段从箭头方向没入终点。
func _draw_piercing_arrow() -> void:
	var dir := _fly_dir if _fly_dir != Vector2.ZERO else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	var head := Vector2.ZERO
	var tail: Vector2
	if _piercing_phase == "drawing":
		tail = Vector2.ZERO
		head = dir * _piercing_visible_length
	elif _piercing_phase == "embedding":
		tail = -dir * _piercing_visible_length
	else:
		tail = -dir * PIERCE_ARROW_LENGTH
	# 以三层低透明度蓝色柔化边缘，不使用生硬高亮或激光感描边。
	draw_line(tail, head, Color(0.28, 0.72, 1.0, 0.10), PIERCE_ARROW_HALF_W * 3.2)
	draw_line(tail, head, PIERCE_ARROW_EDGE, PIERCE_ARROW_HALF_W * 2.0)
	draw_line(tail, head, PIERCE_ARROW_CORE, PIERCE_ARROW_HALF_W * 0.82)
	# 羽尾：箭身已完整显形后始终保留，没入阶段随可见长度一起缩短。
	if _piercing_visible_length > 4.0:
		var feather_tip := tail - dir * minf(6.0, _piercing_visible_length * 0.3)
		draw_line(tail, feather_tip + perp * 2.4, PIERCE_ARROW_EDGE, 1.2)
		draw_line(tail, feather_tip - perp * 2.4, PIERCE_ARROW_EDGE, 1.2)


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
