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

# ---- 炮弹贴图 ----
# 美术提供的迫击炮炮弹 PNG（263×284）。加载一次缓存，找不到时退回圆形绘制。
var _shell_texture: Texture2D = null
const SHELL_TEX_SCALE := 0.075    ## 贴图基础缩放（屏幕约 20×23px）
const FALLBACK_SHELL_RADIUS := 8.0  ## 无贴图时圆形兜底绘制半径（像素）

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
	# 炮弹本体由 _draw() 用贴图绘制，因此设为不可见
	body_rect.visible = false
	# 加载炮弹贴图（load 失败返回 null 时 _draw 退回圆形兜底）
	if _shell_texture == null:
		var tex_path := "res://assets/sprites/mortar/mortar_shell.png"
		if ResourceLoader.exists(tex_path):
			_shell_texture = load(tex_path)
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
	AudioManager.play("mortar_impact", _last_target_pos)
	_state = "exploding"
	_explode_timer = 0.0
	body_rect.visible = false
	# 联机 client 端：不造成伤害（由 host 计算），只显示爆炸视觉
	if not NetworkManager.is_networked_client():
		DamageSystem.deal_area_damage(_last_target_pos, _splash_radius, damage, team)


func _draw() -> void:
	if _state == "flying":
		# 地面影子（逻辑位置 = Vector2.ZERO，不受弧高偏移影响）。
		# draw_set_transform Y 压扁正圆为扁平椭圆，配合炮弹视觉。
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 炮弹本体：位置随 body_rect 的弧线偏移上移
		var stone_y: float = body_rect.position.y - _body_base_y
		var stone_pos := Vector2(0.0, stone_y)
		if _shell_texture != null:
			# 贴图绘制：Y 方向补偿 World 压缩保持原始宽高比
			var w: float = _shell_texture.get_width() * SHELL_TEX_SCALE
			var h: float = _shell_texture.get_height() * SHELL_TEX_SCALE / BattleConstants.Y_COMPRESS
			var tex_rect := Rect2(stone_pos - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
			draw_texture_rect(_shell_texture, tex_rect, false)
		else:
			# 无贴图兜底：圆形灰褐色石头 + 高光
			draw_circle(stone_pos, FALLBACK_SHELL_RADIUS, Color(0.42, 0.38, 0.34))
			draw_circle(stone_pos + Vector2(-2.5, -2.5), 3.0, Color(0.60, 0.56, 0.50))
	elif _state == "exploding":
		# 爆炸范围视觉：红色渐变环（固定半径，alpha 随爆炸进度渐隐）
		var t: float = _explode_timer / EXPLODE_DURATION
		RangeVfx.draw_gradient_ring(self, Vector2.ZERO, _splash_radius,
				RangeVfx.COLOR_BLAST, 1.0 - t)
