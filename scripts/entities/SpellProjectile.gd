# 文件名：SpellProjectile.gd
# 作用：法术飞行物——从发射点沿抛物线弧飞向目标位置，落地后造成范围伤害 + 击退。
#       与 ProjectileBase 的区别：目标是一个固定位置（不是追踪节点），有塔减伤、击退和爆炸视觉。
#
#       2.5D 实现：
#         节点 position 在 World 本地游戏空间中线性移动（Y 方向被 World 的 Y_COMPRESS 压缩）。
#         body_rect（红球）获得基于 sin(progress * PI) 的视觉高度偏移，模拟抛物线弧。
#         地面影子在 _draw() 中绘制于逻辑位置（Vector2.ZERO），与飞行高度形成视觉纵深。
#         弧高按飞行距离自适应：距离越远弧越高（上限 4 格），符合 2.5D 透视。
# 挂载位置：SpellProjectile.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解初始化，再看 _process() 了解飞行和弧高，最后看 _on_impact() 了解伤害结算。

extends Node2D

# ---- 法术参数（setup 时从 card_data 填充）----
var _damage: int = 0              ## 对单位的伤害
var _tower_damage: int = -1       ## 对塔的伤害（-1 = 无减伤，与 _damage 相同）
var _radius: float = 0.0          ## 爆炸半径（像素）
var _speed: float = 200.0         ## 飞行速度（像素/秒）
var _knockback_distance: float = 0.0  ## 击退距离（像素，0 = 无击退）
var team: String = "player"

# ---- 飞行状态 ----
var _origin: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _flight_dist: float = 0.0     ## 总飞行距离（像素）
var _arc_height: float = 0.0      ## 弧高（格）

# ---- 爆炸状态 ----
var _state: String = "flying"     ## "flying" | "exploding"
var _explode_timer: float = 0.0
const EXPLODE_DURATION := 0.3

# ---- 视觉基础值 ----
var _body_base_y: float = 0.0

# ---- 子节点引用 ----
@onready var body_rect: ColorRect = $Body


## 初始化法术飞行物。由 SpellManager.cast_spell() 调用。
## origin: 发射位置（World 本地游戏空间坐标，通常是国王塔位置）
## target_pos: 目标位置（World 本地游戏空间坐标）
## spell_data: 卡牌数据字典（含 spell_damage, tower_damage, spell_radius 等）
## team_name: "player" 或 "enemy"
func setup(origin: Vector2, target_pos: Vector2, spell_data: Dictionary, team_name: String) -> void:
	position = origin
	_origin = origin
	_target = target_pos
	team = team_name

	_damage = int(spell_data.get("spell_damage", 0))
	var td = spell_data.get("tower_damage", null)
	_tower_damage = int(td) if td != null else -1
	_radius = BattleConstants.px(float(spell_data.get("spell_radius", 0)))
	_speed = BattleConstants.px(float(spell_data.get("projectile_speed", 10.0)))
	_knockback_distance = BattleConstants.px(float(spell_data.get("knockback_distance", 0)))

	_flight_dist = origin.distance_to(target_pos)
	# 弧高随飞行距离自适应（格），上限 4 格
	var dist_grids := _flight_dist / BattleConstants.CELL_SIZE
	_arc_height = minf(dist_grids * 0.3, 4.0)

	_body_base_y = body_rect.position.y
	_state = "flying"
	z_index = 50

	queue_redraw()


func _process(delta: float) -> void:
	if _state == "flying":
		_process_flight(delta)
	elif _state == "exploding":
		_process_explode(delta)


## 飞行阶段：线性移动 + 抛物线弧高偏移
func _process_flight(delta: float) -> void:
	var to_target := _target - position
	var dist := to_target.length()

	if dist <= _speed * delta:
		# 本帧到达 → 命中
		position = _target
		_on_impact()
		return

	position += to_target.normalized() * _speed * delta

	# 抛物线弧高视觉偏移（World 本地像素，会被 World Y_COMPRESS 压缩）
	if _flight_dist > 0.0 and _arc_height > 0.0:
		var traveled := _origin.distance_to(position)
		var progress: float = clampf(traveled / _flight_dist, 0.0, 1.0)
		var arc := _arc_height * sin(progress * PI) * BattleConstants.CELL_SIZE
		body_rect.position.y = _body_base_y - arc

	queue_redraw()


## 爆炸阶段：扩散圆 + 淡出
func _process_explode(delta: float) -> void:
	_explode_timer += delta
	queue_redraw()
	if _explode_timer >= EXPLODE_DURATION:
		queue_free()


## 落地：范围伤害 + 击退 + 切换到爆炸视觉
func _on_impact() -> void:
	_state = "exploding"
	_explode_timer = 0.0
	body_rect.visible = false

	# 范围伤害（含塔减伤）
	DamageSystem.deal_area_damage(_target, _radius, _damage, team, _tower_damage)

	# 击退
	if _knockback_distance > 0.0:
		_apply_knockback()

	SignalBus.projectile_hit.emit(_target, team)


## 对爆炸范围内所有敌方单位施加击退（塔免疫，由 knockback 内部判定）
func _apply_knockback() -> void:
	var enemies = EntityRegistry.get_enemies_of(team)
	for e in enemies:
		if not e.has_method("knockback"):
			continue
		var e_pos := BattlePathing.game_position_of(e)
		var hr = e.get("hurt_radius")
		var hurt_r: float = float(hr) if hr != null else 0.0
		if _target.distance_to(e_pos) <= _radius + hurt_r:
			var dir := (e_pos - _target).normalized()
			e.knockback(dir, _knockback_distance)


## 绘制：飞行中画地面影子，爆炸中画扩散圆
func _draw() -> void:
	if _state == "flying":
		# 地面影子（逻辑位置 = Vector2.ZERO，不受弧高偏移影响）
		var sw := 10.0
		var sh := 4.0
		draw_rect(Rect2(-sw / 2.0, -sh / 2.0, sw, sh), Color(0, 0, 0, 0.3))
	elif _state == "exploding":
		# 爆炸扩散圆（橙红色，逐渐淡出）
		var t: float = _explode_timer / EXPLODE_DURATION
		var r := lerpf(0.0, _radius, t)
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.45, 0.1, 0.5 * (1.0 - t)))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 0.3, 0.05, 0.9 * (1.0 - t)), 2.0)
