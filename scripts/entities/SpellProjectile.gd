# 文件名：SpellProjectile.gd
# 作用：法术飞行物——从发射点沿抛物线弧飞向目标位置，落地即时范围伤害 + 击退 + 爆炸扩散圆视觉。
#       当前用于火球法术（spell_type=fireball）。毒药法术不走飞行物，由 SpellManager 直接部署 PoisonField。
#
#       继承 ProjectileBase：飞行+弧高逻辑由基类 _fly_toward / _apply_arc_offset 统一处理，
#       本类仅保留法术参数（伤害/半径/击退）和爆炸状态机。
#
#       2.5D 实现：
#         节点 position 在 World 本地游戏空间中线性移动（Y 方向被 World 的 Y_COMPRESS 压缩）。
#         FireballSprite（火球三帧动画）获得基于 sin(progress * PI) 的视觉高度偏移，模拟抛物线弧。
#         地面影子在 _draw() 中绘制于逻辑位置（Vector2.ZERO），与飞行高度形成视觉纵深。
#         弧高按飞行距离自适应：距离越远弧越高（上限 4 格），符合 2.5D 透视。
# 挂载位置：SpellProjectile.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解初始化，再看 _process() 了解飞行和爆炸状态，最后看 _on_impact() 了解伤害结算。

extends ProjectileBase

# ---- 法术参数（setup 时从 card_data 填充）----
var _damage: int = 0              ## 对单位的伤害
var _tower_damage: int = -1       ## 对塔的伤害（-1 = 无减伤，与 _damage 相同）
var _radius: float = 0.0          ## 爆炸半径（像素）
var _knockback_distance: float = 0.0  ## 击退距离（像素，0 = 无击退）
# speed / arc_height / _start_pos / _total_dist / _body_base_y 继承自 ProjectileBase
# team 继承自 ProjectileBase

# ---- 爆炸状态 ----
var _state: String = "flying"     ## "flying" | "exploding"
var _explode_timer: float = 0.0
const EXPLODE_DURATION := 0.3

# 素材的火球头朝向图片正下方；飞行中按速度方向旋转，使火球头始终朝向目标。
const FIREBALL_FRAMES := [
	preload("res://assets/sprites/fireball/fireball_01.png"),
	preload("res://assets/sprites/fireball/fireball_02.png"),
	preload("res://assets/sprites/fireball/fireball_03.png"),
]
const FIREBALL_FRAME_SCALES := [0.0616, 0.0982, 0.1001]
const FIREBALL_FRAME_SEQUENCE := [0, 1, 2, 1]
const FIREBALL_FRAME_DURATION := 0.09
const FIREBALL_SHADOW_RADIUS := 12.0
const FIREBALL_SHADOW_SQUASH := 0.35

@onready var fireball_sprite: Sprite2D = $FireballSprite
var _fireball_frame_index := 0
var _fireball_frame_timer := 0.0


## 初始化法术飞行物。由 SpellManager.cast_spell() 调用。
## origin: 发射位置（World 本地游戏空间坐标，通常是国王塔位置）
## target_pos: 目标位置（World 本地游戏空间坐标）
## spell_data: 卡牌数据字典（含 spell_damage, tower_damage, spell_radius 等）
## team_name: "player" 或 "enemy"
## 注意：父类 ProjectileBase.setup 签名不同，此处用 setup_spell 避免冲突
func setup_spell(origin: Vector2, target_pos: Vector2, spell_data: Dictionary, team_name: String) -> void:
	position = origin
	_start_pos = origin
	_last_target_pos = target_pos
	team = team_name

	_damage = int(spell_data.get("spell_damage", 0))
	var td = spell_data.get("tower_damage", null)
	_tower_damage = int(td) if td != null else -1
	_radius = BattleConstants.px(float(spell_data.get("spell_radius", 0)))
	speed = BattleConstants.px(float(spell_data.get("projectile_speed", 10.0)))
	_knockback_distance = BattleConstants.px(float(spell_data.get("knockback_distance", 0)))

	_total_dist = origin.distance_to(target_pos)
	# 弧高随飞行距离自适应（格），上限 4 格
	var dist_grids := _total_dist / BattleConstants.CELL_SIZE
	arc_height = minf(dist_grids * 0.3, 4.0)

	_state = "flying"
	z_index = 50
	_fireball_frame_index = 0
	_fireball_frame_timer = 0.0
	fireball_sprite.visible = true
	_set_fireball_frame()
	_update_fireball_visual(0.0)

	queue_redraw()


func _process(delta: float) -> void:
	if _state == "flying":
		_process_flight(delta)
	elif _state == "exploding":
		_process_explode(delta)


## 飞行阶段：使用基类 _fly_toward 统一定点飞行 + 弧高视觉偏移
func _process_flight(delta: float) -> void:
	if _fly_toward(_last_target_pos, delta):
		_on_impact()
		return
	_update_fireball_visual(delta)
	queue_redraw()


## 爆炸阶段：扩散圆 + 淡出
func _process_explode(delta: float) -> void:
	_explode_timer += delta
	queue_redraw()
	if _explode_timer >= EXPLODE_DURATION:
		queue_free()


## 落地：即时范围伤害 + 击退 + 爆炸视觉
func _on_impact() -> void:
	SignalBus.projectile_hit.emit(_last_target_pos, team)
	AudioManager.play("fireball_impact", _last_target_pos)

	_state = "exploding"
	_explode_timer = 0.0
	fireball_sprite.visible = false
	# 联机 client 端：不造成伤害/击退（由 host 计算），只显示爆炸视觉
	if not NetworkManager.is_networked_client():
		DamageSystem.deal_area_damage(_last_target_pos, _radius, _damage, team, _tower_damage)
		if _knockback_distance > 0.0:
			_apply_knockback()


## 对爆炸范围内所有敌方单位施加击退（免疫判定由 CombatantBase.knockback 统一处理）
func _apply_knockback() -> void:
	var enemies = EntityRegistry.get_enemies_of(team)
	for e in enemies:
		if not e.has_method("knockback"):
			continue
		var e_pos := BattlePathing.game_position_of(e)
		var hr = e.get("hurt_radius")
		var hurt_r: float = float(hr) if hr != null else 0.0
		if _last_target_pos.distance_to(e_pos) <= _radius + hurt_r:
			var dir := (e_pos - _last_target_pos).normalized()
			e.knockback(dir, _knockback_distance)


## 绘制：飞行中画地面影子，爆炸中画扩散圆
func _draw() -> void:
	if _state == "flying":
		# 地面影子与单位保持一致：扁椭圆，而非方形块。
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, FIREBALL_SHADOW_SQUASH))
		draw_circle(Vector2.ZERO, FIREBALL_SHADOW_RADIUS, Color(0, 0, 0, 0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif _state == "exploding":
		# 爆炸范围视觉：红色渐变环（固定半径，alpha 随爆炸进度渐隐）
		var t: float = _explode_timer / EXPLODE_DURATION
		RangeVfx.draw_gradient_ring(self, Vector2.ZERO, _radius,
				RangeVfx.COLOR_BLAST, 1.0 - t)


## 更新火球三帧往返动画和朝向。
## 素材默认向下飞行，因此需要用目标方向减去 PI/2 来换算 Sprite2D 旋转角。
func _update_fireball_visual(delta: float) -> void:
	var direction := _last_target_pos - position
	if direction.length_squared() > 0.0:
		fireball_sprite.rotation = direction.angle() - PI / 2.0

	# 抛物线仅抬高画面中的火球，不改变实际命中位置。
	fireball_sprite.position = Vector2(0.0,
			-compute_arc_offset(arc_height, _fly_progress()))

	_fireball_frame_timer += delta
	while _fireball_frame_timer >= FIREBALL_FRAME_DURATION:
		_fireball_frame_timer -= FIREBALL_FRAME_DURATION
		_fireball_frame_index = (_fireball_frame_index + 1) % FIREBALL_FRAME_SEQUENCE.size()
		_set_fireball_frame()


## 原始三帧的画布尺寸不同，按内容高度分别缩放，避免循环时火球忽大忽小。
func _set_fireball_frame() -> void:
	var texture_index: int = FIREBALL_FRAME_SEQUENCE[_fireball_frame_index]
	fireball_sprite.texture = FIREBALL_FRAMES[texture_index]
	fireball_sprite.scale = Vector2.ONE * FIREBALL_FRAME_SCALES[texture_index]
