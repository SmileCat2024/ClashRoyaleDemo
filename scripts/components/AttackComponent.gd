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
var first_attack_delay: float = 0.0     ## 首次出手前摇（秒），部署后不会瞬间攻击
var delivery: String = "instant"        ## "instant" | "projectile"
var damage: int = 10
var projectile_speed: float = 250.0     ## 仅 delivery=projectile 时使用

# ---- 运行时状态 ----
var current_target = null               ## 当前锁定的目标（CombatantBase 或 null）
var cooldown: float = 0.0               ## 攻击冷却剩余时间（秒）

# ---- owner 引用 ----
var combatant: CombatantBase            ## 挂载本组件的实体，由 _init_combat_stats 设置


## 从攻击数据字典初始化。由 CombatantBase._init_combat_stats 在 add_child 后调用。
func setup(attack_data: Dictionary) -> void:
	attack_name = attack_data.get("name", "")
	targeting = attack_data.get("targeting", "any")
	attack_ground = bool(attack_data.get("attack_ground", true))
	attack_air = bool(attack_data.get("attack_air", true))
	attack_range = BattleConstants.px(float(attack_data.get("attack_range", 1.5)))
	attack_interval = float(attack_data.get("attack_interval", 1.0))
	first_attack_delay = float(attack_data.get("first_attack_delay", 0.0))
	delivery = attack_data.get("delivery", "instant")
	damage = int(attack_data.get("damage", 10))
	projectile_speed = BattleConstants.px(float(attack_data.get("projectile_speed", 12.5)))
	# 首次出手前摇：组件就绪后等 first_attack_delay 秒才能第一次攻击
	cooldown = first_attack_delay


func _process(delta: float) -> void:
	if combatant == null or not combatant.initialized or combatant.is_dead:
		return

	# 冷却递减
	if cooldown > 0.0:
		cooldown -= delta

	_update_targeting()

	if has_valid_target():
		var dist = combatant.global_position.distance_to(current_target.global_position)
		if dist <= attack_range and cooldown <= 0.0:
			_execute_attack()
			cooldown = attack_interval


## 当前目标是否有效（存在、未销毁、未死亡）
func has_valid_target() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	if current_target.get("is_dead") == true:
		return false
	return true


## 索敌逻辑（两阶段）：
## 1. 当前目标在 attack_range 内 → 保持锁定，原地攻击直到目标离开攻击范围
## 2. 目标超出 attack_range（或无目标）→ 每帧重新搜索视野内最近的敌人
##    追击过程中可随时切换到更近的目标，不会死追一个
func _update_targeting() -> void:
	if has_valid_target():
		var dist = combatant.global_position.distance_to(current_target.global_position)
		if dist <= attack_range:
			return  # 目标在攻击范围内，保持锁定原地攻击
	# 目标超出攻击范围（或无目标）→ 重新搜索视野内最近的敌人
	current_target = _find_nearest_target()


## 在视野范围内找最近的合法目标。委托给 TargetingSystem 三重过滤。
func _find_nearest_target() -> Node:
	return TargetingSystem.find_best_target(
		combatant.global_position,
		combatant.team,
		_get_sight_range(),
		targeting,
		attack_ground,
		attack_air
	)


## 从 owner 读取视野范围。单位有 sight_range；塔没有，用攻击射程 + 余量代替。
func _get_sight_range() -> float:
	var s = combatant.get("sight_range")
	if s != null:
		return float(s)
	return attack_range + 20.0


## 执行一次攻击，按 delivery 分支
func _execute_attack() -> void:
	match delivery:
		"instant":
			DamageSystem.resolve_impact(current_target, damage)
		"projectile":
			_fire_projectile()


## 发射飞行物（塔和远程单位使用）
func _fire_projectile() -> void:
	var proj = preload("res://scenes/entities/Projectile.tscn").instantiate()
	get_tree().current_scene.add_child(proj)
	proj.setup(
		combatant.global_position,
		current_target,
		damage,
		projectile_speed,
		combatant.team,
		true  # homing = 锁定型追踪
	)
	SignalBus.projectile_spawned.emit(proj, combatant.team)
