# 文件名：PoisonField.gd
# 作用：毒药法术的持续伤害区域。落地后在地面上停留一段时间，
#       每隔固定间隔造成一次范围伤害（DOT），同时持续减速区域内的敌方单位。
#       典型用例：毒药法术卡（8秒持续，每秒1跳，共8跳92伤害，减速15%）。
#
#       继承 BattlefieldEffect：复用生命周期管理（_elapsed / lifetime / initialized）。
#       _process 调用 super._process() 处理到期 queue_free，然后追加 tick 伤害和减速逻辑。
#
#       与 DelayedDamageEffect（一次性延迟爆炸）的区别：
#         - PoisonField 是持续伤害（多次 tick），DelayedDamageEffect 是单次爆炸
#         - PoisonField 有减速效果，DelayedDamageEffect 没有
#
# 挂载位置：PoisonField.tscn 的根节点，由 SpellManager 直接创建并挂到 EffectsRoot 下
# 初学者阅读建议：先看 setup() 了解参数，再看 _process() 了解 tick 和减速逻辑，最后看 _draw() 了解视觉。

extends BattlefieldEffect

# ---- 伤害参数（setup 时填充）----
var _radius: float = 0.0              ## 作用半径（像素）
var _tick_damage: int = 0             ## 每跳对单位的伤害
var _tick_tower_damage: int = -1      ## 每跳对塔的伤害（-1 = 无减伤）
# team 继承自 BattlefieldEffect

# ---- DOT 参数 ----
# lifetime 继承自 BattlefieldEffect（= duration）
var _tick_interval: float = 1.0       ## 伤害间隔（秒）
var _slow_factor: float = 0.85        ## 减速乘数（0.85 = 减速15%）

# ---- 运行时 ----
# _elapsed 继承自 BattlefieldEffect
var _tick_timer: float = 0.0          ## 距下次伤害 tick 的倒计时（秒）

const FADE_DURATION := 1.0            ## 最后1秒淡出


## 初始化毒药区域。由 SpellManager._create_poison_field() 调用。
## center:     中心位置（World 本地游戏空间坐标）
## radius:     作用半径（像素）
## tick_dmg:   每跳对单位的伤害
## tick_tower_dmg: 每跳对塔的伤害（-1 = 无减伤）
## team_name:  施法方阵营
## duration:   总持续时间（秒）
## interval:   伤害间隔（秒）
## slow:       减速乘数（如 0.85 = 减速15%）
## 注意：父类 BattlefieldEffect.setup 签名不同，此处用 setup_field 避免冲突
func setup_field(center: Vector2, radius: float, tick_dmg: int, tick_tower_dmg: int, \
		team_name: String, duration: float, interval: float, slow: float) -> void:
	super.setup(center, team_name, duration)
	_radius = radius
	_tick_damage = tick_dmg
	_tick_tower_damage = tick_tower_dmg
	_tick_interval = interval
	_slow_factor = slow
	_tick_timer = interval  # 首跳之后，间隔 interval 再跳
	z_index = 5             # 在单位之上、飞行物之下

	# 首跳立即造成伤害（联机 client 端跳过，伤害由 host 计算）
	if not NetworkManager.is_networked_client():
		_deal_tick_damage()

	queue_redraw()


func _process(delta: float) -> void:
	# super._process 处理生命周期：累加 _elapsed，到期时 _on_expire + queue_free
	super._process(delta)
	# 到期后（super 已标记 queue_free），不再执行 tick 逻辑
	if not initialized or _elapsed >= lifetime:
		return

	# 联机 client 端：只更新视觉（脉冲/淡出），不造成伤害/减速
	if NetworkManager.is_networked_client():
		queue_redraw()
		return

	# 每帧减速区域内敌方单位
	_apply_slow()

	# 伤害 tick
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_deal_tick_damage()
		_tick_timer += _tick_interval  # 累加避免浮点漂移

	queue_redraw()


## 单次范围伤害（含塔减伤）
func _deal_tick_damage() -> void:
	DamageSystem.deal_area_damage(position, _radius, _tick_damage, team, _tick_tower_damage)


## 持续减速：每帧对区域内敌方单位施加减速，持续时间略长于 tick 间隔以防间隙
func _apply_slow() -> void:
	var enemies = EntityRegistry.get_enemies_of(team)
	for e in enemies:
		if not (e is UnitBase):
			continue
		if e.is_dead:
			continue
		var e_pos := BattlePathing.game_position_of(e)
		var dist := position.distance_to(e_pos)
		if dist <= _radius + e.hurt_radius:
			e.apply_slow(_slow_factor, _tick_interval + 0.1)


## 绘制：绿色半透明圆 + 脉冲 + 末期淡出
func _draw() -> void:
	if not initialized:
		return

	# 最后 FADE_DURATION 秒淡出
	var alpha_mult := 1.0
	var remaining := get_remaining_time()
	if remaining < FADE_DURATION:
		alpha_mult = clampf(remaining / FADE_DURATION, 0.0, 1.0)

	# 脉冲缩放（±3%）
	var pulse: float = sin(_elapsed * 3.0) * 0.03 + 1.0
	var r := _radius * pulse

	# 外圈半透明填充
	draw_circle(Vector2.ZERO, r, Color(0.2, 0.7, 0.15, 0.18 * alpha_mult))
	# 内圈加深
	draw_circle(Vector2.ZERO, r * 0.55, Color(0.12, 0.45, 0.08, 0.12 * alpha_mult))
	# 边线
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(0.15, 0.5, 0.1, 0.5 * alpha_mult), 2.0)
