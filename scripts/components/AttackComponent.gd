# 文件名：AttackComponent.gd
# 作用：独立攻击组件。挂在 CombatantBase 下，负责索敌、冷却、执行攻击。
#       与 owner 的移动逻辑完全解耦：本组件只管"打谁、什么时候打、怎么打"。
#       UnitBase 通过 get_primary_attack() 读取本组件的 current_target 来决定追击或停步。
# 挂载位置：CombatantBase 的子节点（由 CombatantBase._init_combat_stats 动态创建）。
# 初学者阅读建议：先看 setup() 了解攻击配置怎么读取，再看 _process() 了解每帧的索敌→冷却→攻击流程。

class_name AttackComponent
extends Node

# ---- 攻击配置（从 attack_data 字典读取）----
var attack_name: String = ""
var targeting: String = "any"           ## "any" | "building_only"
var attack_ground: bool = true
var attack_air: bool = true
var attack_range: float = 30.0          ## 攻击射程（在此距离内才能出手）
var attack_interval: float = 1.0        ## 两次攻击之间的冷却时间（秒）
var first_attack_delay: float = 0.0     ## 首次出手前摇（秒），进入射程后不会瞬间攻击
var damage_delay: float = 0.0           ## 出手到造成伤害的延迟（秒），匹配攻击动画的抬手帧
var delivery: String = "instant"        ## "instant" | "projectile"
var damage: int = 10
var projectile_speed: float = 250.0     ## 仅 delivery=projectile 时使用
var min_attack_range: float = 0.0       ## 最小射程/盲区（像素）。>0 时中心距离小于此值的目标无法锁定/攻击（迫击炮）
var trajectory: String = ""             ## "" | "linear" | "ballistic"（ballistic=高抛溅射，发射 MortarShell）
var impact_type: String = "single"      ## "single" | "splash"（splash=命中后范围溅射）
var impact_radius: float = 0.0          ## 溅射半径（像素）
var arc_height: float = 0.0             ## 弹道弧高峰值（格），仅 trajectory=ballistic 时传给飞行物
var max_range: float = 0.0              ## 穿透最大射程（像素），仅 impact_type=piercing 时用
var pierce_radius: float = 0.0          ## 穿透判定半径（像素），仅 impact_type=piercing 时用
var projectile_appearance: String = "stone"  ## ballistic 投射物外观："stone"(石块) | "arrow"(箭矢)

# ---- 运行时状态 ----
var current_target = null               ## 当前锁定的目标（CombatantBase 或 null）
var cooldown: float = 0.0               ## 攻击冷却剩余时间（秒）
var _is_firing: bool = false            ## 本帧是否出手（只读标记，供 SpriteAnimator 轮询）
var _windup_timer: float = 0.0          ## 伤害延迟计时器（>0 时等待，到 0 才结算伤害）
var _is_winding_up: bool = false        ## 是否处于抬手→命中延迟阶段

# ---- 嘲讽（强制目标）----
## 嘲讽不修改单位的攻击配置，而是在索敌入口之前临时覆盖 current_target。
## UnitBase 的追击逻辑直接读取 current_target，因此会自然沿用同一目标进行寻路。
var _taunt_target = null
var _taunt_timer: float = 0.0
var _taunt_aura: TauntAuraEffect = null

# ---- 递增伤害（地狱塔光束）----
## 持续锁定同一目标时伤害按阶段递增。目标切换/丢失/离开射程时重置累计。
var _is_ramp: bool = false              ## 是否启用递增伤害
var _ramp_damage: Array = []            ## 各阶段伤害值（与 _ramp_thresholds 一一对应）
var _ramp_thresholds: Array = []        ## 各阶段锁定时间阈值（秒，升序）
var _lock_target = null                 ## 当前递增锁定的目标
var _lock_time: float = 0.0             ## 对当前目标的累计锁定时间（秒）

# ---- owner 引用 ----
var combatant: CombatantBase            ## 挂载本组件的实体，由 _init_combat_stats 设置


## 计算攻击触及距离 = 攻击范围 + 自身碰撞半径 + 目标受击半径。
## UnitBase（追击/停步判定）和 AttackComponent（锁定/出手判定）共用此方法，
## 保证四处判定逻辑完全一致。
static func compute_reach(atk_range: float, self_cr: float, target) -> float:
	var hr: float = 0.0
	if target != null:
		var hr_val = target.get("hurt_radius")
		if hr_val != null:
			hr = float(hr_val)
	return atk_range + self_cr + hr


## 从攻击数据字典初始化。由 CombatantBase._init_combat_stats 在 add_child 后调用。
func setup(attack_data: Dictionary) -> void:
	attack_name = attack_data.get("name", "")
	targeting = attack_data.get("targeting", "any")
	attack_ground = bool(attack_data.get("attack_ground", true))
	attack_air = bool(attack_data.get("attack_air", true))
	attack_range = BattleConstants.px(float(attack_data.get("attack_range", 1.5)))
	attack_interval = float(attack_data.get("attack_interval", 1.0))
	first_attack_delay = float(attack_data.get("first_attack_delay", 0.0))
	damage_delay = float(attack_data.get("damage_delay", 0.0))
	delivery = attack_data.get("delivery", "instant")
	damage = int(attack_data.get("damage", 10))
	projectile_speed = BattleConstants.px(float(attack_data.get("projectile_speed", 12.5)))
	min_attack_range = BattleConstants.px(float(attack_data.get("min_attack_range", 0.0)))
	trajectory = attack_data.get("trajectory", "")
	impact_type = attack_data.get("impact_type", "single")
	impact_radius = BattleConstants.px(float(attack_data.get("impact_radius", 0.0)))
	arc_height = float(attack_data.get("arc_height", 0.0))
	max_range = BattleConstants.px(float(attack_data.get("max_range", 0.0)))
	pierce_radius = BattleConstants.px(float(attack_data.get("pierce_radius", 0.0)))
	projectile_appearance = attack_data.get("projectile_appearance", "stone")
	# 首次出手前摇：进入射程后等 first_attack_delay 秒才能第一次攻击
	cooldown = first_attack_delay
	# 递增伤害配置（地狱塔光束）。配置了 ramp_damage 即启用
	_ramp_damage = attack_data.get("ramp_damage", [])
	_ramp_thresholds = attack_data.get("ramp_thresholds", [])
	_is_ramp = not _ramp_damage.is_empty()


func _process(delta: float) -> void:
	_is_firing = false
	# 联机 client 端：不跑索敌/冷却/攻击逻辑（伤害由 host 计算）
	if NetworkManager.is_networked_client():
		return
	_process_taunt(delta)
	# 抬手→命中延迟阶段：等待 damage_delay 到期才结算伤害
	if _is_winding_up:
		# 瘫痪时暂停抬手计时（眩晕/冰冻中断攻击动作）
		if combatant == null or not combatant.initialized or combatant.is_dead:
			return
		if combatant.is_stunned():
			return
		_windup_timer -= delta * combatant.get_attack_speed_mult()
		if _windup_timer <= 0.0:
			if has_valid_target():
				_execute_attack()
			_is_winding_up = false
			cooldown = attack_interval
		return
	if combatant == null or not combatant.initialized or combatant.is_dead:
		return
	# 建筑部署期间不能攻击（地狱塔 deploy_time）。is_deployed 不存在时视为已部署。
	if combatant.get("is_deployed") == false:
		return
	if combatant.get("is_jumping_river") == true:
		return
	# 瘫痪时不能攻击
	if combatant.is_stunned():
		return

	_update_targeting()

	if has_valid_target():
		var from_pos := BattlePathing.game_position_of(combatant)
		var target_pos := BattlePathing.game_position_of(current_target)
		var dist = BattlePathing.path_distance(
			from_pos,
			target_pos,
			_get_movement_type(),
			_get_can_jump_river()
		)
		var reach := compute_reach(attack_range, combatant.collision_radius, current_target)
		# 盲区内不攻击（迫击炮最小射程）
		if dist <= reach and not (min_attack_range > 0.0 and dist < min_attack_range):
			# 递增伤害锁定时间累加（地狱塔光束）：持续锁定同一目标时加热，
			# 目标切换/离开射程时 _lock_target 失配，自动重置累计。
			if _is_ramp:
				if current_target != _lock_target:
					_lock_target = current_target
					_lock_time = 0.0
				_lock_time += delta
			# 冲锋状态（王子）：进入射程停下的那一刻立即触发冲锋爆发伤害，
			# 无视起手延迟（first_attack_delay）和抬手延迟（damage_delay）。
			# _execute_attack 内部用 charge_damage 并调用 _end_charge() 退出冲锋，
			# 随后 cooldown = attack_interval 进入正常攻击节奏。
			if combatant.get("is_charging") == true:
				_is_firing = true
				_notify_attack_visual()
				_execute_attack()
				cooldown = attack_interval
			else:
				if cooldown > 0.0:
					cooldown -= delta * combatant.get_attack_speed_mult()
				if cooldown <= 0.0:
					_is_firing = true  # 触发攻击动画
					_notify_attack_visual()
					if damage_delay > 0.0:
						# 有抬手延迟：标记 firing（动画立即开始），延迟结算伤害
						_is_winding_up = true
						_windup_timer = damage_delay
					else:
						# 无延迟：立刻结算（向后兼容）
						_execute_attack()
						cooldown = attack_interval


## 本帧是否出手（只读）。SpriteAnimator 轮询此标记触发攻击动画。
## 每帧 _process 开头重置为 false，出手时置 true，下一帧自动清除。
func is_firing() -> bool:
	return _is_firing


## 当前目标是否有效（存在、未销毁、未死亡）
func has_valid_target() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	if current_target.get("is_dead") == true:
		return false
	if not _can_attack_target(current_target):
		return false
	return true


## 施加嘲讽：在 duration 秒内强制以 taunter 为攻击目标。
## 只攻击建筑的攻击组件不应被嘲讽；不能攻击施法者当前地空类型的组件同样跳过。
## 返回是否实际施加，供范围技能统计命中的有效目标数。
func apply_taunt(taunter: Node, duration: float) -> bool:
	if combatant == null or taunter == null or not is_instance_valid(taunter):
		return false
	if duration <= 0.0 or targeting == "building_only":
		return false
	if combatant == taunter or taunter.get("is_dead") == true:
		return false
	var taunter_team = taunter.get("team")
	if taunter_team == null or str(taunter_team) == combatant.team:
		return false
	if not _can_attack_target(taunter):
		return false
	_taunt_target = taunter
	_taunt_timer = duration
	current_target = taunter
	_show_taunt_aura(duration)
	return true


## 当前是否仍处于有效嘲讽。目标死亡、销毁或阵营变化会立即自动解除。
func has_active_taunt() -> bool:
	if _taunt_timer <= 0.0:
		return false
	if _taunt_target == null or not is_instance_valid(_taunt_target):
		return false
	if _taunt_target.get("is_dead") == true:
		return false
	if _taunt_target.get("team") == combatant.team:
		return false
	return _can_attack_target(_taunt_target)


## 推进嘲讽时间。解除时保留 current_target：若已在攻击距离内，既有索敌规则会继续攻击它；
## 若仍在追击，_update_targeting 会在本帧重选普通目标。
func _process_taunt(delta: float) -> void:
	if _taunt_timer <= 0.0:
		return
	_taunt_timer -= delta
	if _taunt_timer <= 0.0 or not has_active_taunt():
		_clear_taunt()


## 仅测试/调试用途：读取强制目标，避免外部直接依赖私有字段。
func get_taunt_target():
	return _taunt_target if has_active_taunt() else null


## 给被嘲讽单位挂淡金色状态标识。重复施加时刷新既有标识，而不是叠加多个光环。
func _show_taunt_aura(duration: float) -> void:
	if combatant == null or not is_instance_valid(combatant):
		return
	if _taunt_aura != null and is_instance_valid(_taunt_aura):
		_taunt_aura.refresh(duration)
		return
	_taunt_aura = TauntAuraEffect.attach(combatant, duration)


## 解除嘲讽并让状态标识短暂淡出。
func _clear_taunt() -> void:
	_taunt_timer = 0.0
	_taunt_target = null
	if _taunt_aura != null and is_instance_valid(_taunt_aura):
		_taunt_aura.expire()
	_taunt_aura = null


## 索敌逻辑（两阶段）：
## 1. 当前目标在 attack_range 内 → 保持锁定，原地攻击直到目标离开攻击范围
## 2. 目标超出 attack_range（或无目标）→ 每帧重新搜索视野内最近的敌人
##    追击过程中可随时切换到更近的目标，不会死追一个
func _update_targeting() -> void:
	# 嘲讽优先级高于一切普通索敌。无论距离、视野或更近的敌人如何变化，
	# 只要嘲讽有效就持续追击/攻击施法者。
	if has_active_taunt():
		current_target = _taunt_target
		return
	if has_valid_target():
		var from_pos := BattlePathing.game_position_of(combatant)
		var target_pos := BattlePathing.game_position_of(current_target)
		var dist = BattlePathing.path_distance(
			from_pos,
			target_pos,
			_get_movement_type(),
			_get_can_jump_river()
		)
		var reach := compute_reach(attack_range, combatant.collision_radius, current_target)
		if dist <= reach:
			# 盲区内的目标放弃锁定（迫击炮最小射程内的敌人打不到）
			if min_attack_range > 0.0 and dist < min_attack_range:
				pass  # 落入盲区，放弃当前目标继续搜索
			else:
				return  # 保持锁定原地攻击
	# 目标超出攻击范围（或无目标）→ 重新搜索视野内最近的敌人
	current_target = _find_nearest_target()


## 在视野范围内找最近的合法目标。委托给 TargetingSystem 三重过滤。
## min_attack_range > 0 时排除盲区内目标（迫击炮最小射程）。
func _find_nearest_target() -> Node:
	return TargetingSystem.find_best_target(
		BattlePathing.game_position_of(combatant),
		combatant.team,
		_get_sight_range(),
		targeting,
		attack_ground,
		attack_air,
		_get_movement_type(),
		_get_can_jump_river(),
		min_attack_range,
		combatant.collision_radius
	)


## 从 owner 读取视野范围。单位有 sight_range；塔没有，用攻击射程 + 余量代替。
func _get_sight_range() -> float:
	var s = combatant.get("sight_range")
	if s != null:
		return float(s)
	return attack_range + 20.0


## 从 owner 读取移动类型。塔和其他非单位实体按地面处理。
func _get_movement_type() -> String:
	var movement = combatant.get("movement_type")
	if movement == null:
		return "ground"
	return str(movement)


func _get_can_jump_river() -> bool:
	var can_jump = combatant.get("can_jump_river")
	if can_jump == null:
		return false
	return bool(can_jump)


## 目标的 ground/air 状态可能运行时变化（例如跳河），锁定后也要重新校验。
func _can_attack_target(target: Node) -> bool:
	var movement = target.get("movement_type")
	if movement == null:
		movement = "ground"
	if movement == "ground" and not attack_ground:
		return false
	if movement == "air" and not attack_air:
		return false
	return true


## 通知宿主触发攻击视觉。联机 host 端由 UnitBase 发 RPC 同步给 client；
## 非联机 / 无动画单位由 UnitBase._on_attack_triggered 内部跳过。
func _notify_attack_visual() -> void:
	if combatant.has_method("_on_attack_triggered"):
		combatant._on_attack_triggered()


## 执行一次攻击，按 delivery 分支。
## 冲锋状态（owner.is_charging=true）下，instant 攻击使用 charge_damage 并在命中后退出冲锋。
func _execute_attack() -> void:
	_play_attack_sfx()
	# 冲锋伤害加成：owner 处于冲锋态时用 charge_damage 替代普通伤害（王子冲锋突刺）
	var dmg := damage
	var was_charging: bool = combatant.get("is_charging") == true
	if was_charging:
		var cd = combatant.get("charge_damage")
		if cd != null:
			dmg = int(cd)
		if combatant.has_method("_end_charge"):
			combatant._end_charge()
	# 递增伤害（地狱塔光束）：用当前锁定阶段伤害覆盖固定伤害
	if _is_ramp:
		dmg = _get_current_ramp_damage()
	match delivery:
		"instant":
			if impact_type == "splash" and impact_radius > 0.0:
				# 近战范围溅射（瓦基里转斧）：以自身位置为中心，对范围内敌方造成伤害
				# 传 attack_ground/attack_air 让 splash 遵守攻击范围（瓦基里仅地面，不误伤空中）
				var center := BattlePathing.game_position_of(combatant)
				_show_splash_impact_vfx(center)
				DamageSystem.deal_area_damage(center, impact_radius, dmg, combatant.team, -1, attack_ground, attack_air)
			else:
				DamageSystem.resolve_impact(current_target, dmg)
				_play_impact_sfx("charge_impact" if was_charging else "impact")
		"projectile":
			_fire_projectile()


## 发射飞行物（塔和远程单位使用）
## 优先通过 ProjectileManager 统一入口；DebugBattle 等无 Manager 的场景回退到直接创建。
## trajectory=ballistic → 高抛溅射炮弹（迫击炮）；impact_type=splash → 非锁定范围溅射。
func _fire_projectile() -> void:
	var spawn_pos := BattlePathing.game_position_of(combatant)
	# 飞行单位从视觉飞行高度发射投射物（对齐 altitude 离地偏移），地面单位为 0。
	# 塔顶角色等可额外提供 projectile_emit_offset_y，使箭矢从模型手部高度出手，
	# 但仍以 combatant 的逻辑原点计算锁定、射程和命中。
	# 飞行单位额外上移 0.5 格，让子弹从飞行器炮口射出而非身体中心。
	var emit_offset_y := (combatant.altitude + 0.5) * BattleConstants.CELL_SIZE if combatant.altitude > 0.0 else 0.0
	emit_offset_y += combatant.projectile_emit_offset_y
	var scene := get_tree().current_scene
	var pm := scene.get_node_or_null("Managers/ProjectileManager")
	# ballistic 轨迹 → 高抛溅射炮弹（迫击炮）
	if trajectory == "ballistic" and pm and pm.has_method("spawn_mortar_shell"):
		# 弧高随距离自适应：近处低、远处高，最大射程(attack_range)处达到配置的 arc_height
		var dyn_arc := arc_height
		if attack_range > 0.0 and current_target:
			var tp := BattlePathing.game_position_of(current_target)
			var ratio := clampf(spawn_pos.distance_to(tp) / attack_range, 0.0, 1.0)
			dyn_arc = arc_height * ratio
		pm.spawn_mortar_shell(spawn_pos, current_target, damage, impact_radius, projectile_speed, combatant.team, dyn_arc, attack_ground, attack_air, combatant.projectile_impact_summon_unit_id, projectile_appearance)
		return
	# 普通飞行物：splash=非锁定范围溅射，piercing=穿透，否则锁定单体
	var is_homing := impact_type != "splash" and impact_type != "piercing"
	var splash_px := impact_radius if impact_type == "splash" else 0.0
	var is_piercing := impact_type == "piercing"
	var max_range_px := max_range if is_piercing else 0.0
	var pierce_radius_px := pierce_radius if is_piercing else 0.0
	var source_unit_id := str(combatant.get("unit_id"))
	var source_hit_event_id := ""
	if combatant.get("is_awakened") == true and source_unit_id == "musketeer":
		source_hit_event_id = "hit_evolved_musketeer"
	if pm and pm.has_method("spawn_projectile"):
		pm.spawn_projectile(spawn_pos, current_target, damage, projectile_speed, combatant.team, is_homing, splash_px, arc_height, emit_offset_y, is_piercing, max_range_px, pierce_radius_px, source_unit_id, source_hit_event_id)
		return
	# 回退：DebugBattle 等场景无 ProjectileManager
	var proj = preload("res://scenes/entities/Projectile.tscn").instantiate()
	var projectiles_root := scene.get_node_or_null("World/ProjectilesRoot") as Node2D
	if projectiles_root:
		projectiles_root.add_child(proj)
	else:
		scene.add_child(proj)
	var spawn_visual := spawn_pos
	spawn_visual.y -= emit_offset_y
	proj.setup(spawn_visual, current_target, damage, projectile_speed, combatant.team, is_homing, splash_px, is_piercing, max_range_px, pierce_radius_px, source_unit_id, source_hit_event_id)
	proj.arc_height = arc_height
	SignalBus.projectile_spawned.emit(proj, combatant.team)


## 播放攻击音效。迫击炮（ballistic）用专用发射音；其他单位走 unit_data.sfx.attack。
func _play_attack_sfx() -> void:
	if trajectory == "ballistic":
		var ballistic_event := "mortar_launch"
		if combatant.get("is_awakened") == true and str(combatant.get("unit_id")) == "mortar":
			ballistic_event = "attack_evolved_mortar"
		AudioManager.play(ballistic_event, BattlePathing.game_position_of(combatant))
		return
	var uid = combatant.get("unit_id")
	if uid == null:
		return
	AudioManager.play_unit_sfx(uid, "attack", BattlePathing.game_position_of(combatant))
	AudioManager.play_unit_sfx(uid, "attack_voice", BattlePathing.game_position_of(combatant))


## 播放瞬发攻击的专属命中音。未配置 impact 的单位静默跳过。
func _play_impact_sfx(sfx_key: String = "impact") -> void:
	var uid = combatant.get("unit_id")
	if uid == null:
		return
	AudioManager.play_unit_sfx(uid, sfx_key, BattlePathing.game_position_of(combatant))


## 显示瞬发范围攻击的地面警示环。
## 优先交给 UnitBase 做本地显示 + 联机 RPC；测试桩或其他战斗实体则只尝试本地显示。
func _show_splash_impact_vfx(center: Vector2) -> void:
	if combatant != null and combatant.has_method("show_splash_impact_vfx"):
		combatant.show_splash_impact_vfx(center, impact_radius)
		return
	_spawn_splash_impact_vfx_local(center, impact_radius)


## 非 UnitBase 的战斗实体兜底路径（例如测试桩）。
func _spawn_splash_impact_vfx_local(center: Vector2, radius: float) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var effects_root := tree.current_scene.get_node_or_null("World/EffectsRoot") as Node2D
	if effects_root == null:
		return
	BlastRingEffect.spawn(effects_root, center, radius)


# ============================================================================
# 递增伤害（地狱塔光束）辅助方法
# ============================================================================

## 根据当前锁定时间返回对应阶段的伤害值。
## 阈值升序排列，从高到低找第一个满足 _lock_time >= threshold 的阶段。
func _get_current_ramp_damage() -> int:
	if _ramp_damage.is_empty():
		return damage
	for i in range(_ramp_damage.size() - 1, -1, -1):
		if _lock_time >= float(_ramp_thresholds[i]):
			return int(_ramp_damage[i])
	return int(_ramp_damage[0])


## 当前递增强度（0.0~1.0）= 锁定时间 / 最高阶段阈值。供光束视觉调色/调宽。
func get_ramp_intensity() -> float:
	if not _is_ramp or _ramp_thresholds.is_empty():
		return 0.0
	var max_threshold := float(_ramp_thresholds[-1])
	if max_threshold <= 0.0:
		return 0.0
	return clampf(_lock_time / max_threshold, 0.0, 1.0)


## 当前递增伤害阶段索引（0=刚锁定, 1=升温, 2=满热）。供光束视觉选择阶段参数。
func get_ramp_stage_index() -> int:
	if _ramp_thresholds.is_empty():
		return 0
	for i in range(_ramp_thresholds.size() - 1, -1, -1):
		if _lock_time >= float(_ramp_thresholds[i]):
			return i
	return 0


## 是否有有效的光束锁定目标（供 UnitBase._draw 绘制光束线判定）。
func has_beam_target() -> bool:
	return _is_ramp and _lock_target != null and is_instance_valid(_lock_target) \
		and _lock_target.get("is_dead") != true


## 返回当前光束锁定目标。
func get_beam_target():
	return _lock_target
