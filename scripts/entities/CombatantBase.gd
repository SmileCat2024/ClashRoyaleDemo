# 文件名：CombatantBase.gd
# 作用：所有可战斗实体（单位、塔、建筑）的基类。
#       收拢共性逻辑——身份、生存属性（血量/护盾）、受伤结算、死亡。
#       攻击逻辑不在这里——D2 起由 AttackComponent 独立处理。
# 挂载位置：不直接挂载。由 UnitBase / TowerBase / BuildingBase 继承。
# 初学者阅读建议：先看 _init_combat_stats() 了解属性怎么初始化，
#       再看 take_damage() 了解护盾怎么吸收伤害。

class_name CombatantBase
extends Node2D

# ---- 初始化标记 ----
# setup() 完成前为 false，_process / _draw 直接 return。
var initialized: bool = false

# ---- 身份信息 ----
var team: String = "player"

# ---- 生存属性 ----
var max_hp: int = 100
## 当前血量。setter 自动更新血条，确保 client 端 Synchronizer 同步后血条也刷新。
var current_hp: int = 100:
	set(value):
		current_hp = value
		if initialized and health_bar != null:
			health_bar.value = current_hp
var shield: int = 0           ## 护盾上限（0 = 无护盾）
## 当前护盾值。setter 同步血条显示。
var current_shield: int = 0:
	set(value):
		current_shield = value
		if initialized and health_bar != null:
			health_bar.value = current_hp + current_shield

# ---- 死亡状态 ----
var is_dead: bool = false:
	set(value):
		var was_dead := is_dead
		is_dead = value
		# Client 端检测到 host 同步的死亡（false→true），触发远程死亡视觉
		if value and not was_dead and _is_remote():
			_on_remote_death()


# ---- 联机 ----
var network_id: int = 0  ## 联机唯一标识（host 分配），用于 RPC 配对同名节点

# ---- 攻击数据（原始字典数组，由 AttackComponent 读取）----
var attacks_data: Array = []

# ---- 死亡范围伤害（如气球兵的死亡掉落）----
var death_damage: int = 0          ## 死亡时对周围敌方造成的伤害（0 = 无死亡伤害）
var death_radius: float = 0.0      ## 死亡伤害范围（像素）
var death_fuse_time: float = 0.0   ## 死亡炸弹引信时间（秒，0 = 无延迟效果）

# ---- 碰撞几何（碰撞体积系统）----
## 碰撞半径（px）。推挤分离 + 索敌/攻击边缘判定。setup 时从格值转换。
## 大碰撞半径使单位更早进入敌方索敌范围，也更早被攻击到。
var collision_radius: float = 10.0
## 受击半径（px）。法术/溅射/投射物命中判定。默认 = collision_radius。
## 与 collision_radius 拆开可单独调法术蹭塔、建筑受击等细节。
var hurt_radius: float = 10.0
## 质量（推挤权重）。0 = 不可移动（建筑/塔）。值越大越难被推开。
var mass: int = 5

# ---- 离地高度 ----
## 离地高度（格）。地面单位 = 0，飞行单位 > 0。
## 仅影响视觉渲染（Body/HealthBar 向上偏移），不影响逻辑坐标和索敌。
var altitude: float = 0.0

# ---- 攻击组件实例列表（由 _init_combat_stats 动态创建）----
var attack_components: Array = []

# ---- 帧动画驱动器（由 _init_combat_stats 动态创建，无动画数据时为 null）----
var sprite_animator: SpriteAnimator = null

# ---- 状态效果（由 apply_status_effect 管理，_process_status_effects 每帧更新）----
var _status_effects: Array = []

# ---- 子节点引用 ----
# UnitBase.tscn 有 Body 子节点；TowerBase.tscn 无（塔用 sprite 贴图，不再有占位方块）。
@onready var body_rect: ColorRect = get_node_or_null("Body")
@onready var health_bar: ProgressBar = $HealthBar
@onready var debug_label: Label = $DebugLabel


## 从数据字典初始化生存属性。子类的 setup() 应在设置完身份信息后调用此方法。
func _init_combat_stats(data: Dictionary) -> void:
	max_hp = int(data.get("max_hp", 100))
	current_hp = max_hp
	shield = int(data.get("shield", 0))
	current_shield = shield
	attacks_data = data.get("attacks", [])
	_create_attack_components()
	_create_sprite_animator(data)
	_style_health_bar()
	_setup_network_sync()
	# 血条/占位方块/调试标签等 Control 子节点默认 mouse_filter=STOP 会拦截战场点击，
	# 导致点击单位/塔所在格子时 BattleManager._unhandled_input 收不到事件。统一设为穿透。
	_disable_control_mouse()


## 把实体身上所有 Control 子孙节点设为鼠标穿透（MOUSE_FILTER_IGNORE）。
## Body(ColorRect)/HealthBar(ProgressBar)/DebugLabel(Label) 等仅用于显示，
## 不应消费鼠标事件——否则玩家点击单位所在格子时会因命中这些 UI 矩形而无法部署/施法。
func _disable_control_mouse() -> void:
	for c in find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 根据 attacks_data 为每项攻击配置创建一个 AttackComponent（P0 只用第一个）
func _create_attack_components() -> void:
	# 清除旧组件（场景重用时的安全措施）
	for comp in attack_components:
		if is_instance_valid(comp):
			comp.queue_free()
	attack_components.clear()

	for i in range(attacks_data.size()):
		var attack: Dictionary = attacks_data[i]
		var comp: AttackComponent = AttackComponent.new()
		comp.name = "Attack_" + attack.get("name", str(i))
		add_child(comp)
		comp.combatant = self
		comp.setup(attack)
		attack_components.append(comp)


## 返回主攻击组件（attacks[0] 对应的），无攻击配置时返回 null
func get_primary_attack() -> AttackComponent:
	if attack_components.is_empty():
		return null
	return attack_components[0]


## 如果数据中包含 animation 字段，创建 SpriteAnimator 子节点。
## 无 animation 字段 → 不创建，实体保持 ColorRect 渲染。
func _create_sprite_animator(data: Dictionary) -> void:
	if not data.has("animation"):
		return
	sprite_animator = SpriteAnimator.new()
	sprite_animator.name = "SpriteAnimator"
	add_child(sprite_animator)
	sprite_animator.setup(data, self)


## 返回当前视觉状态名，供 SpriteAnimator 轮询。
## 基类返回 "idle"；子类（UnitBase）根据移动/攻击状态覆写。
func get_visual_state() -> String:
	return "idle"


## 返回当前朝向（"front" = 面朝镜头/向下走，"back" = 背朝镜头/向上走）。
## 供 SpriteAnimator 查找方向专用帧（如 walk_front / walk_back）。
func get_facing() -> String:
	return "front"


## 返回是否需要水平翻转 sprite。美术素材默认面朝左，向右移动时翻转为 true。
func get_flip_h() -> bool:
	return false


## 返回当前移动方向（归一化向量）。基类返回零向量（非移动实体）。
## CollisionSystem 用于切向滑动推挤优化。
func get_move_direction() -> Vector2:
	return Vector2.ZERO


## 按阵营设置血条样式：玩家浅蓝底+正蓝填充，敌方浅红底+正红填充。
func _style_health_bar() -> void:
	if health_bar == null:
		return
	var bg := StyleBoxFlat.new()
	var fill := StyleBoxFlat.new()
	# 圆角 + 描边统一参数
	for sb in [bg, fill]:
		sb.corner_radius_top_left = 1
		sb.corner_radius_top_right = 1
		sb.corner_radius_bottom_left = 1
		sb.corner_radius_bottom_right = 1
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
	# 背景描边（细线）+ 内缩留白，让 fill 不盖住 border
	bg.border_width_left = 1
	bg.border_width_right = 1
	bg.border_width_top = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0, 0, 0, 0.6)
	bg.content_margin_left = 1
	bg.content_margin_right = 1
	bg.content_margin_top = 1
	bg.content_margin_bottom = 1

	if team == "player":
		bg.bg_color = Color(0.55, 0.78, 1.0, 0.5)    # 浅蓝底
		fill.bg_color = Color(0.08, 0.42, 0.92)       # 正蓝
	else:
		bg.bg_color = Color(1.0, 0.62, 0.58, 0.5)    # 浅红底
		fill.bg_color = Color(0.88, 0.12, 0.08)       # 正红

	# fill 自带描边（与 bg 同色），确保血量填充区域始终有可见边框
	fill.border_width_left = 1
	fill.border_width_right = 1
	fill.border_width_top = 1
	fill.border_width_bottom = 1
	fill.border_color = Color(0, 0, 0, 0.6)

	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.add_theme_stylebox_override("fill", fill)


## 将视觉子节点（Body/HealthBar/DebugLabel）按 altitude 向上偏移。
## 在子类 setup() 设置完基础布局后调用。altitude 偏移会随 World 的 Y 压缩自动收缩。
func _apply_altitude_offset() -> void:
	if altitude <= 0.0:
		return
	var dy := -altitude * BattleConstants.CELL_SIZE
	if body_rect:
		body_rect.position.y += dy
	if health_bar:
		health_bar.position.y += dy
	if debug_label:
		debug_label.position.y += dy


# ---- 状态效果系统 ----

## 施加一个状态效果。同类型效果按 merge() 规则叠加（如 slow 取最强减速 + 最长持续）。
func apply_status_effect(effect: StatusEffect) -> void:
	if is_dead:
		return
	for existing in _status_effects:
		if existing.type == effect.type:
			existing.merge(effect)
			return
	_status_effects.append(effect)


## 便捷方法：施加眩晕（完全瘫痪）
func apply_stun(duration: float) -> void:
	apply_status_effect(StatusEffect.new("stun", duration))


## 便捷方法：施加冰冻（与眩晕相同的瘫痪效果，独立类型用于视觉/来源区分）
func apply_freeze(duration: float) -> void:
	apply_status_effect(StatusEffect.new("freeze", duration))


## 便捷方法：施加狂暴增益（移动速度 + 攻击速度提升）
func apply_rage(move_mult: float, attack_mult: float, duration: float) -> void:
	var effect := StatusEffect.new("rage", duration)
	effect.move_speed_mult = move_mult
	effect.attack_speed_mult = attack_mult
	apply_status_effect(effect)


## 是否拥有指定类型的状态效果
func has_status_type(type_name: String) -> bool:
	for effect in _status_effects:
		if effect.type == type_name:
			return true
	return false


## 每帧更新所有活跃状态效果（过期移除、DoT tick）。子类 _process() 应调用此方法。
func _process_status_effects(delta: float) -> void:
	if _status_effects.is_empty():
		return
	for i in range(_status_effects.size() - 1, -1, -1):
		var effect: StatusEffect = _status_effects[i]
		effect.elapsed += delta
		# poison DoT tick
		if effect.type == "poison" and effect.tick_interval > 0.0:
			effect.tick_timer += delta
			if effect.tick_timer >= effect.tick_interval:
				effect.tick_timer -= effect.tick_interval
				take_damage(effect.tick_damage)
		if effect.is_expired():
			_status_effects.remove_at(i)


## 返回当前移动速度乘数（受 slow / freeze / stun / rage 影响）。
## 减益（slow）取最强（最小 mult），增益（rage）取最强（最大 mult），两者相乘。
## stun / freeze 直接返回 0.0（完全不能动）。
func get_move_speed_mult() -> float:
	var debuff_mult := 1.0
	var buff_mult := 1.0
	for effect in _status_effects:
		match effect.type:
			"slow":
				debuff_mult = minf(debuff_mult, effect.move_speed_mult)
			"stun", "freeze":
				return 0.0
			"rage":
				buff_mult = maxf(buff_mult, effect.move_speed_mult)
	return debuff_mult * buff_mult


## 返回当前攻击速度乘数（受 rage 影响，> 1.0 = 更快冷却）。
func get_attack_speed_mult() -> float:
	var mult := 1.0
	for effect in _status_effects:
		if effect.type == "rage":
			mult = maxf(mult, effect.attack_speed_mult)
	return mult


## 返回是否处于瘫痪状态（眩晕或冰冻，完全不能行动和攻击）。
func is_stunned() -> bool:
	for effect in _status_effects:
		if effect.type == "stun" or effect.type == "freeze":
			return true
	return false


## 受到伤害。护盾存在时，单次伤害至多打掉盾，不溢出到血量。
func take_damage(amount: int) -> void:
	if is_dead:
		return
	if _is_remote():
		return  # Client 端不处理伤害，血量由 Synchronizer 同步

	# 护盾优先吸收
	if current_shield > 0:
		current_shield = max(0, current_shield - amount)
		if current_shield == 0:
			SignalBus.shield_broken.emit(self)
		return  # 有盾时不掉血

	# 正常扣血
	current_hp -= amount
	if health_bar:
		health_bar.value = current_hp
	if current_hp <= 0:
		current_hp = 0
		die()


## 死亡。基类标记 is_dead 并发出死亡伤害信号（由 EffectManager 接收并生成延迟炸弹效果）。
## 具体死亡表现（注销、信号、queue_free）由子类重写。
func die() -> void:
	is_dead = true
	if _is_remote():
		return  # Client 端不发死亡信号（由 host 的 Synchronizer 同步 is_dead）
	if death_damage > 0 and death_radius > 0.0:
		SignalBus.death_damage_triggered.emit(
			global_position, death_damage, death_radius, death_fuse_time, team
		)


## 击退：沿 direction 方向瞬移 distance 像素。mass=0（塔/建筑）免疫。
## 位置钳制到竞技场范围内，CollisionSystem 下一帧处理重叠/河道回弹。
func knockback(direction: Vector2, distance: float) -> void:
	if is_dead or mass == 0 or distance <= 0.0:
		return
	position += direction.normalized() * distance
	# 钳制到竞技场边界（World 本地游戏空间）
	position.x = clampf(position.x, BattleConstants.CELL_SIZE * 0.5,
		BattleConstants.ARENA_WIDTH - BattleConstants.CELL_SIZE * 0.5)
	position.y = clampf(position.y, BattleConstants.CELL_SIZE * 0.5,
		BattleConstants.ARENA_HEIGHT - BattleConstants.CELL_SIZE * 0.5)


# =============================================================================
# 联机同步
# =============================================================================

## 当前是否为 client 端（非权威端）。Client 端不执行战斗逻辑，只接收 host 同步的状态。
func _is_remote() -> bool:
	return NetworkManager.is_networked() and not NetworkManager.is_server()

## 联机同步初始化。手动 RPC 同步方案：不再使用 MultiplayerSynchronizer。
## 单位/塔状态由 BattleManager._sync_state_to_client() 定频 RPC 同步。
func _setup_network_sync() -> void:
	pass

## Client 端检测到 host 同步的死亡时调用。子类覆写以播放死亡视觉。
func _on_remote_death() -> void:
	pass
