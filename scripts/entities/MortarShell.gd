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
var _attack_ground: bool = true  ## 是否伤害地面单位（继承自攻击方 AttackComponent）
var _attack_air: bool = true     ## 是否伤害空中单位
## 非空时，在落点伤害结算完成后召唤该 unit_id 对应的一只单位（觉醒迫击炮）。
var _impact_summon_unit_id: String = ""
var _appearance: String = "stone"  ## 外观："stone"(迫击炮石块) | "arrow"(箭矢，抄箭雨白线+羽尾)

# ---- 箭矢外观常量（appearance=arrow 时使用，抄 ArrowProjectile）----
const ARROW_LENGTH: float = 10.0       ## 箭杆长度（像素）
const FLETCHING_LEN: float = 5.0       ## 羽尾长度（像素）
const FLETCHING_SPREAD: float = 2.5    ## 羽尾展开宽度（像素）
const FLETCHING_ALPHA: float = 0.4     ## 羽尾透明度
const FLETCHING_COLOR := Color(0.95, 0.20, 0.18)  ## 羽尾颜色（皇室战争风红色）

# ---- 箭矢扇形散布（appearance=arrow 时使用）----
const ARROW_FAN_HALF: int = 2          ## 中心两侧各几根箭（2 = 共 5 根）
const ARROW_FAN_SPREAD: float = 7.0    ## 相邻箭矢间距（像素，沿垂直飞行方向）
const ARROW_FAN_ANGLE: float = 0.15    ## 外侧箭矢偏角（弧度，≈8.6°，形成扇形）

# ---- 炮弹贴图 ----
# 美术提供的普通/觉醒迫击炮炮弹 PNG。按是否携带落点召唤效果选择贴图，找不到时退回圆形绘制。
var _shell_texture: Texture2D = null
const SHELL_TEX_SCALE := 0.075    ## 普通炮弹（263×284）显示约 20×21px
const AWAKENED_SHELL_TEX_SCALE := 0.035  ## 觉醒炮弹（可见本体约 29px，接近原版大号炮弹体积）
var _shell_texture_scale: float = SHELL_TEX_SCALE
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
## impact_summon_unit_id: 非空时，落点伤害结算后召唤一只该单位
func setup_shell(spawn_pos: Vector2, target_node, dmg: int, splash_px: float, speed_px: float, team_name: String, arc_grids: float, attack_ground: bool = true, attack_air: bool = true, impact_summon_unit_id: String = "", appearance: String = "stone") -> void:
	position = spawn_pos
	_start_pos = spawn_pos
	target = target_node
	damage = dmg
	_splash_radius = splash_px
	speed = speed_px
	team = team_name
	homing = false  # 范围型，不追踪
	arc_height = arc_grids
	_attack_ground = attack_ground
	_attack_air = attack_air
	_impact_summon_unit_id = impact_summon_unit_id
	_appearance = appearance

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
	# 觉醒迫击炮（带落点召唤）使用专属炮弹；普通迫击炮继续使用原石块炮弹。
	# load 失败返回 null 时 _draw() 退回圆形绘制。
	var tex_path := "res://assets/sprites/mortar/mortar_shell.png"
	_shell_texture_scale = SHELL_TEX_SCALE
	if not _impact_summon_unit_id.is_empty():
		tex_path = "res://assets/sprites/mortar/mortar_shell_awakened.png"
		_shell_texture_scale = AWAKENED_SHELL_TEX_SCALE
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
		DamageSystem.deal_area_damage(_last_target_pos, _splash_radius, damage, team, -1, _attack_ground, _attack_air)
		_summon_impact_unit()


## 觉醒迫击炮炮弹专用：先完成落地伤害，再在同一落点生成一只友方单位。
## 单位经 SpawnManager 创建，因而复用实体注册、部署状态及 Host→Client 生成同步。
func _summon_impact_unit() -> void:
	if _impact_summon_unit_id.is_empty():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var spawn_manager := scene.get_node_or_null("Managers/SpawnManager")
	if spawn_manager and spawn_manager.has_method("spawn_unit_by_id"):
		spawn_manager.spawn_unit_by_id(_impact_summon_unit_id, team, _last_target_pos)
	else:
		push_error("[MortarShell] Missing SpawnManager for impact summon")


func _draw() -> void:
	if _state == "flying":
		if _appearance == "arrow":
			_draw_arrow_flying()
			return
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
			var w: float = _shell_texture.get_width() * _shell_texture_scale
			var h: float = _shell_texture.get_height() * _shell_texture_scale / BattleConstants.Y_COMPRESS
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


## 箭矢外观飞行绘制（抄 ArrowProjectile._draw_flying）。appearance=arrow 时使用。
## 复用 body_rect 弧高锚点（基类 _apply_arc_offset 已偏移 body_rect.position.y）；
## 落地爆炸圈由 _draw 的 exploding 分支共用（与石块外观一致）。
func _draw_arrow_flying() -> void:
	var progress := _fly_progress()
	# 弧高偏移：body_rect.position.y 已被基类 _apply_arc_offset 偏移
	var arc_y: float = body_rect.position.y - _body_base_y
	# 抛物线切线方向（水平位移 + 弧高导数）
	var dx := _last_target_pos.x - _start_pos.x
	var dy := (_last_target_pos.y - _start_pos.y) - arc_height * BattleConstants.CELL_SIZE * PI * cos(progress * PI)
	var tangent := Vector2(dx, dy)
	if tangent.length() > 0.5:
		tangent = tangent.normalized()
	else:
		tangent = (_last_target_pos - _start_pos).normalized() if _total_dist > 0.5 else Vector2.DOWN
	var perp := Vector2(-tangent.y, tangent.x)
	# 地面影子
	draw_rect(Rect2(-1.5, -1.0, 3.0, 2.0), Color(0, 0, 0, 0.12))
	# 5 根箭矢扇形散布（中心 + 上下各 2 根）：head 沿垂直飞行方向偏移，切线略微旋转
	var base_head := Vector2(0.0, arc_y)
	for i in range(-ARROW_FAN_HALF, ARROW_FAN_HALF + 1):
		var head := base_head + perp * (float(i) * ARROW_FAN_SPREAD)
		var t_dir := tangent.rotated(float(i) * ARROW_FAN_ANGLE)
		var tail := head - t_dir * ARROW_LENGTH
		var alpha: float = 1.0 - absf(float(i)) * 0.12  # 中心最亮，外侧略淡
		_draw_single_arrow(head, tail, t_dir, alpha)


## 绘制单根箭矢（白线箭杆 + 红色羽尾）。供 _draw_arrow_flying 扇形散布复用。
func _draw_single_arrow(head: Vector2, tail: Vector2, tangent: Vector2, alpha: float) -> void:
	draw_line(tail, head, Color(1, 1, 1, alpha), 1.5)
	var perp := Vector2(-tangent.y, tangent.x)
	var fc := Color(FLETCHING_COLOR, FLETCHING_ALPHA * alpha)
	var fletch_back := tail - tangent * FLETCHING_LEN
	draw_line(tail, fletch_back + perp * FLETCHING_SPREAD, fc, 1.5)
	draw_line(tail, fletch_back - perp * FLETCHING_SPREAD, fc, 1.5)
