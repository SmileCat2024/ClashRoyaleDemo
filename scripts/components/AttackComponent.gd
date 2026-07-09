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

# ---- 运行时状态 ----
var current_target = null               ## 当前锁定的目标（CombatantBase 或 null）
var cooldown: float = 0.0               ## 攻击冷却剩余时间（秒）
var _is_firing: bool = false            ## 本帧是否出手（只读标记，供 SpriteAnimator 轮询）
var _windup_timer: float = 0.0          ## 伤害延迟计时器（>0 时等待，到 0 才结算伤害）
var _is_winding_up: bool = false        ## 是否处于抬手→命中延迟阶段

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
	# 首次出手前摇：进入射程后等 first_attack_delay 秒才能第一次攻击
	cooldown = first_attack_delay


func _process(delta: float) -> void:
	_is_firing = false
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
		if dist <= reach:
			if cooldown > 0.0:
				cooldown -= delta * combatant.get_attack_speed_mult()
			if cooldown <= 0.0:
				_is_firing = true  # 触发攻击动画
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


## 索敌逻辑（两阶段）：
## 1. 当前目标在 attack_range 内 → 保持锁定，原地攻击直到目标离开攻击范围
## 2. 目标超出 attack_range（或无目标）→ 每帧重新搜索视野内最近的敌人
##    追击过程中可随时切换到更近的目标，不会死追一个
func _update_targeting() -> void:
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
			return  # 目标在攻击范围内（含双方半径），保持锁定原地攻击
	# 目标超出攻击范围（或无目标）→ 重新搜索视野内最近的敌人
	current_target = _find_nearest_target()


## 在视野范围内找最近的合法目标。委托给 TargetingSystem 三重过滤。
func _find_nearest_target() -> Node:
	return TargetingSystem.find_best_target(
		BattlePathing.game_position_of(combatant),
		combatant.team,
		_get_sight_range(),
		targeting,
		attack_ground,
		attack_air,
		_get_movement_type(),
		_get_can_jump_river()
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


## 执行一次攻击，按 delivery 分支
func _execute_attack() -> void:
	match delivery:
		"instant":
			DamageSystem.resolve_impact(current_target, damage)
		"projectile":
			_fire_projectile()


## 发射飞行物（塔和远程单位使用）
## 优先通过 ProjectileManager 统一入口；DebugBattle 等无 Manager 的场景回退到直接创建。
func _fire_projectile() -> void:
	var spawn_pos := BattlePathing.game_position_of(combatant)
	var scene := get_tree().current_scene
	var pm := scene.get_node_or_null("Managers/ProjectileManager")
	if pm and pm.has_method("spawn_projectile"):
		pm.spawn_projectile(spawn_pos, current_target, damage, projectile_speed, combatant.team, true)
		return
	# 回退：DebugBattle 等场景无 ProjectileManager
	var proj = preload("res://scenes/entities/Projectile.tscn").instantiate()
	var projectiles_root := scene.get_node_or_null("World/ProjectilesRoot") as Node2D
	if projectiles_root:
		projectiles_root.add_child(proj)
	else:
		scene.add_child(proj)
	proj.setup(spawn_pos, current_target, damage, projectile_speed, combatant.team, true)
	SignalBus.projectile_spawned.emit(proj, combatant.team)
