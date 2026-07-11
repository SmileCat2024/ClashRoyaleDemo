# 文件名：SpellProjectile.gd
# 作用：法术飞行物——从发射点沿抛物线弧飞向目标位置，落地即时范围伤害 + 击退 + 爆炸扩散圆视觉。
#       当前用于火球法术（spell_type=fireball）。毒药法术不走飞行物，由 SpellManager 直接部署 PoisonField。
#
#       继承 ProjectileBase：飞行+弧高逻辑由基类 _fly_toward / _apply_arc_offset 统一处理，
#       本类仅保留法术参数（伤害/半径/击退）和爆炸状态机。
#
#       2.5D 实现：
#         节点 position 在 World 本地游戏空间中线性移动（Y 方向被 World 的 Y_COMPRESS 压缩）。
#         body_rect（红球）获得基于 sin(progress * PI) 的视觉高度偏移，模拟抛物线弧。
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

# body_rect 继承自 ProjectileBase（SpellProjectile.tscn 有 Body 子节点）


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

	_body_base_y = body_rect.position.y
	_state = "flying"
	z_index = 50

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
	body_rect.visible = false
	# 联机 client 端：不造成伤害/击退（由 host 计算），只显示爆炸视觉
	if not NetworkManager.is_networked_client():
		DamageSystem.deal_area_damage(_last_target_pos, _radius, _damage, team, _tower_damage)
		if _knockback_distance > 0.0:
			_apply_knockback()


## 对爆炸范围内所有敌方单位施加击退（塔免疫，由 knockback 内部判定）
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
