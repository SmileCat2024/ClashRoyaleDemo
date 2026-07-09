# 文件名：MortarShell.gd
# 作用：迫击炮炮弹——从迫击炮位置沿高抛弧线飞向目标落点，落地后范围溅射伤害 + 尘土爆炸视觉。
#       继承 ProjectileBase：飞行步进和弧高偏移由基类 _fly_toward / _apply_arc_offset 统一处理。
#       本类保留炮弹参数（溅射半径）和飞行→爆炸状态机。
#
#       2.5D 实现：
#         节点 position 在 World 本地游戏空间中线性移动（Y 方向被 World Y_COMPRESS 压缩）。
#         body_rect（灰色石块）获得基于 sin(progress*PI) 的视觉高度偏移，模拟高抛弧线。
#         地面影子在 _draw() 绘制于逻辑位置（Vector2.ZERO），与飞行高度形成视觉纵深。
# 挂载位置：MortarShell.tscn 的根节点
# 初学者阅读建议：先看 setup_shell() 了解初始化，再看 _process() 了解飞行→爆炸流程。

extends ProjectileBase

# ---- 炮弹参数 ----
var _splash_radius: float = 0.0  ## 溅射半径（像素）
const SHELL_RADIUS := 8.0        ## 石头绘制半径（像素），旧版 ColorRect 的 2 倍

# ---- 状态 ----
var _state: String = "flying"  ## "flying" | "exploding"
var _explode_timer: float = 0.0
const EXPLODE_DURATION := 0.3

# body_rect 继承自 ProjectileBase（MortarShell.tscn 有 Body 子节点）


## 初始化迫击炮炮弹。由 ProjectileManager.spawn_mortar_shell() 调用。
## spawn_pos: 发射位置（World 本地游戏空间坐标）
## target_node: 目标节点（取其当前位置为落点，此后不追踪）
## dmg: 范围伤害 | splash_px: 溅射半径（像素）| speed_px: 飞行速度（像素/秒）
## team_name: 阵营 | arc_grids: 弧高峰值（格），决定抛物线视觉高度
func setup_shell(spawn_pos: Vector2, target_node, dmg: int, splash_px: float, speed_px: float, team_name: String, arc_grids: float) -> void:
	position = spawn_pos
	_start_pos = spawn_pos
	target = target_node
	damage = dmg
	_splash_radius = splash_px
	speed = speed_px
	team = team_name
	homing = false  # 范围型，不追踪
	arc_height = arc_grids

	# 落点 = 目标当前位置（发射时固定）
	if target and is_instance_valid(target):
		_last_target_pos = BattlePathing.game_position_of(target)
	else:
		_last_target_pos = spawn_pos
	_total_dist = spawn_pos.distance_to(_last_target_pos)
	_body_base_y = body_rect.position.y

	# body_rect 仅作为弧线偏移锚点（基类 _apply_arc_offset 操作其 position），
	# 石头本体由 _draw() 绘制为圆形，因此设为不可见
	body_rect.visible = false
	_state = "flying"
	z_index = 45
	queue_redraw()


func _process(delta: float) -> void:
	if _state == "flying":
		if _fly_toward(_last_target_pos, delta):
			_on_impact()
			return
		queue_redraw()
	elif _state == "exploding":
		_explode_timer += delta
		queue_redraw()
		if _explode_timer >= EXPLODE_DURATION:
			queue_free()


## 落地：范围溅射伤害 + 爆炸视觉
func _on_impact() -> void:
	SignalBus.projectile_hit.emit(_last_target_pos, team)
	_state = "exploding"
	_explode_timer = 0.0
	body_rect.visible = false
	DamageSystem.deal_area_damage(_last_target_pos, _splash_radius, damage, team)


func _draw() -> void:
	if _state == "flying":
		# 地面影子（逻辑位置 = Vector2.ZERO，不受弧高偏移影响）。
		# draw_set_transform Y 压扁正圆为扁平椭圆，配合大石头视觉。
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 石头本体（圆形灰褐色），位置随 body_rect 的弧线偏移上移
		var stone_y: float = body_rect.position.y - _body_base_y
		var stone_pos := Vector2(0.0, stone_y)
		draw_circle(stone_pos, SHELL_RADIUS, Color(0.42, 0.38, 0.34))
		# 石头高光（左上偏亮，增加立体质感）
		draw_circle(stone_pos + Vector2(-2.5, -2.5), 3.0, Color(0.60, 0.56, 0.50))
	elif _state == "exploding":
		# 爆炸扩散圆（灰褐色尘土，逐渐淡出）
		var t: float = _explode_timer / EXPLODE_DURATION
		var r := lerpf(0.0, _splash_radius, t)
		draw_circle(Vector2.ZERO, r, Color(0.7, 0.6, 0.45, 0.45 * (1.0 - t)))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(0.5, 0.4, 0.3, 0.8 * (1.0 - t)), 2.0)
