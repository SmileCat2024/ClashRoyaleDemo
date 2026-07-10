# 文件名：UnitBase.gd
# 作用：控制单位的行为——移动、寻找敌方塔、死亡。
#       D1 阶段：只移动到最近的敌方塔，不攻击（D2 接入 AttackComponent）。
#       战斗属性、受伤逻辑继承自 CombatantBase。
# 挂载位置：UnitBase.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解单位怎么初始化，再看 _process() 了解每帧做什么。

class_name UnitBase
extends CombatantBase

# ---- 身份信息（单位独有）----
var unit_id: String = ""
var display_name: String = ""

# ---- 移动属性（单位独有）----
var move_speed: float = 20.0  # 默认值（1格/秒 × CELL_SIZE）
var movement_type: String = "ground"       ## "ground" | "air"
var base_movement_type: String = "ground"  ## 原始移动类型，跳河临时变 air 后用于恢复
var can_jump_river: bool = false           ## 地面单位是否可以直接跳过河道
var sight_range: float = 120.0
var movement_targeting: String = "any"     ## "any" | "building_only"

# ---- 运行时 ----
var _move_target = null    ## 当前移动目标（CombatantBase 或 null）
var _is_moving: bool = false  ## 本帧是否在移动（供 SpriteAnimator 轮询）
var _move_sfx_timer: float = 0.0  ## 移动音效间歇计时器（仅 sfx.move 配置的单位使用）
const MOVE_SFX_INTERVAL := 1.5  ## 移动音效播放间隔（秒）
var _last_move_dir: Vector2 = Vector2.ZERO  ## 上一帧实际移动方向（供 CollisionSystem 切向滑动）
var is_jumping_river: bool = false
# ---- 冲锋（王子专属，数据驱动；无 charge 配置时 _charge_enabled=false）----
var is_charging: bool = false           ## 是否处于冲锋状态（AttackComponent 命中时读取此标记 + charge_damage）
var charge_damage: int = 0              ## 冲锋命中伤害（AttackComponent 命中时使用）
var _charge_enabled: bool = false
var _charge_min_distance: float = 0.0   ## 进入冲锋所需持续移动距离（像素）
var _charge_move_speed: float = 0.0     ## 冲锋移速（像素/秒）
var _charge_distance_accum: float = 0.0 ## 当前持续移动累计距离（像素）
var _jump_start: Vector2 = Vector2.ZERO
var _jump_end: Vector2 = Vector2.ZERO
var _jump_elapsed: float = 0.0
var _jump_duration: float = 0.3
var _body_base_position: Vector2 = Vector2.ZERO
var _health_bar_base_position: Vector2 = Vector2.ZERO
var _debug_label_base_position: Vector2 = Vector2.ZERO

const RIVER_JUMP_ARC_HEIGHT := 1.25
const RIVER_JUMP_SPEED_MULTIPLIER := 1.25
const RIVER_JUMP_BANK_OFFSET := 1.0
const OBSTACLE_LOOK_AHEAD_CELLS := 1.5  ## 前方避障探测距离（格），超出此距离的障碍物不触发避让
const SEPARATION_RADIUS_CELLS := 0.5   ## 单位间分离探测余量（格），碰撞半径之外额外保持的距离

## 影子椭圆纵向压缩比。把正圆按此值压扁成椭圆。
const SHADOW_SQUASH := 0.35

## 影子椭圆水平半径（px）。setup 时从 shadow_size（格）转换。0 = 不画影子。
var _shadow_radius: float = 0.0


## 初始化单位属性。由 SpawnManager 在生成单位后调用。
func setup(unit_data: Dictionary, team_name: String) -> void:
	unit_id = unit_data.get("id", "")
	display_name = unit_data.get("display_name", "")
	team = team_name
	move_speed = BattleConstants.px(float(unit_data.get("move_speed", 1.0)))
	base_movement_type = unit_data.get("movement_type", "ground")
	movement_type = base_movement_type
	can_jump_river = bool(unit_data.get("can_jump_river", false))
	sight_range = BattleConstants.px(float(unit_data.get("sight_range", 6.0)))
	movement_targeting = unit_data.get("movement_targeting", "any")

	# 初始化战斗属性（基类方法）
	_init_combat_stats(unit_data)

	# 冲锋机制配置（王子专属，无 charge 字段则禁用）
	var charge_cfg: Dictionary = unit_data.get("charge", {})
	_charge_enabled = not charge_cfg.is_empty()
	if _charge_enabled:
		_charge_min_distance = BattleConstants.px(float(charge_cfg.get("min_charge_distance", 2.5)))
		_charge_move_speed = BattleConstants.px(float(charge_cfg.get("charge_move_speed", 2.0)))
		charge_damage = int(charge_cfg.get("charge_damage", 0))

	# 死亡范围伤害配置（如气球兵的死亡掉落）
	death_damage = int(unit_data.get("death_damage", 0))
	death_radius = BattleConstants.px(float(unit_data.get("death_radius", 0.0)))
	death_fuse_time = float(unit_data.get("death_fuse_time", 0.0))

	# 碰撞几何参数（格 → 像素）
	collision_radius = BattleConstants.px(float(unit_data.get("collision_radius", 0.5)))
	hurt_radius = BattleConstants.px(float(unit_data.get("hurt_radius", 0.5)))
	mass = int(unit_data.get("mass", 5))

	# 影子大小（格 → 像素）。未配置时退化为 collision_radius。
	_shadow_radius = BattleConstants.px(float(unit_data.get("shadow_size", unit_data.get("collision_radius", 0.5))))

	# 视觉设置：统一方块大小，颜色按阵营区分
	var size: int = 16
	if team == "player":
		body_rect.color = BattleConstants.COLOR_PLAYER
	else:
		body_rect.color = BattleConstants.COLOR_ENEMY
	body_rect.size = Vector2(size, size)
	body_rect.position = Vector2(-size / 2.0, -size / 2.0)

	# 血条
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	var hb_w: float = size + 12
	var hb_y: float = -size / 2.0 - 8
	# 有动画配置的单位，血条位置可由数据覆盖（贴图较大时需要上移）
	var anim_cfg: Dictionary = unit_data.get("animation", {})
	if not anim_cfg.is_empty():
		hb_y = float(anim_cfg.get("health_bar_y", hb_y))
	health_bar.size = Vector2(hb_w, 4)
	health_bar.position = Vector2(-hb_w / 2.0, hb_y)

	# 调试标签（有动画模型的单位隐藏）
	debug_label.text = display_name
	debug_label.position = Vector2(-15, size / 2.0 + 2)
	if sprite_animator and sprite_animator._has_animation:
		debug_label.visible = false
	_store_visual_base_positions()

	# 飞行单位设置离地高度（仅视觉，不影响逻辑坐标和索敌）
	if movement_type == "air":
		altitude = 2.5
	_set_visual_altitude(altitude)

	initialized = true
	queue_redraw()
	print("[UnitBase] setup:", unit_id, team, "hp:", max_hp)


## _draw()：在单位脚底（origin）绘制半透明黑色椭圆影子。
## 影子始终在地面位置，不受 altitude 离地偏移影响。
## _draw() 先于子节点（Body/HealthBar/Sprite）绘制，保证影子在最底层。
func _draw() -> void:
	if not initialized or is_dead:
		return
	if _shadow_radius <= 0.0:
		return
	# 飞行单位影子更淡（离地越远越散）
	var alpha := 0.18 if altitude > 0.0 else 0.28
	# 用 Y 压缩把正圆变成扁平椭圆
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_SQUASH))
	draw_circle(Vector2.ZERO, _shadow_radius, Color(0, 0, 0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 施加减速效果（便捷封装，内部创建 StatusEffect）。
## factor: 移动速度乘数（如 0.85 = 减速 15%）
## duration: 持续时间（秒）
func apply_slow(factor: float, duration: float) -> void:
	var effect := StatusEffect.new("slow", duration)
	effect.move_speed_mult = factor
	apply_status_effect(effect)


## 当前实际移动速度（冲锋态用 charge_move_speed，否则基础速度；再 × 状态效果乘数）
func _get_effective_move_speed() -> float:
	var base := _charge_move_speed if is_charging else move_speed
	return base * get_move_speed_mult()


## 累计持续移动距离，达到阈值后进入冲锋状态（王子专属）。
func _accumulate_charge(moved: float) -> void:
	if not _charge_enabled or is_charging:
		return
	_charge_distance_accum += moved
	if _charge_distance_accum >= _charge_min_distance:
		is_charging = true
		AudioManager.play_unit_sfx(unit_id, "charge", BattlePathing.game_position_of(self))
		queue_redraw()


## 退出冲锋状态并重置累计距离。
## 由 AttackComponent._execute_attack（命中后）和 take_damage（受伤打断）调用。
func _end_charge() -> void:
	if not _charge_enabled:
		return
	is_charging = false
	_charge_distance_accum = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not initialized or is_dead:
		return
	# 冲锋累计：上一帧未持续移动则清零（已进入冲锋态的等攻击命中退出）
	if _charge_enabled and not _is_moving:
		_charge_distance_accum = 0.0
	_process_status_effects(delta)
	_is_moving = false
	if is_jumping_river:
		_is_moving = true
		_process_river_jump(delta)
		return

	var attack = get_primary_attack()

	# 有攻击目标：追击或在射程内停下（让 AttackComponent 自己攻击）
	if attack and attack.has_valid_target():
		var target_pos := BattlePathing.game_position_of(attack.current_target)
		var dist = BattlePathing.path_distance(position, target_pos, movement_type, can_jump_river)
		var reach: float = AttackComponent.compute_reach(attack.attack_range, collision_radius, attack.current_target)
		if dist > reach:
			_is_moving = true
			_move_towards_position(target_pos, delta)
		# else: 在射程内，停下不动，AttackComponent 会自动出手
		return

	# 无攻击目标：向最近敌方塔移动（推进行为）
	_move_target = _find_nearest_enemy_tower()
	if _move_target:
		var target_pos := BattlePathing.game_position_of(_move_target)
		var dist = BattlePathing.path_distance(position, target_pos, movement_type, can_jump_river)
		var stop_dist = AttackComponent.compute_reach(_get_primary_attack_range(), collision_radius, _move_target)
		if dist > stop_dist:
			_is_moving = true
			_move_towards_position(target_pos, delta)


## 按单位能力移动：普通地面单位走桥；可跳河单位仅在跳河路线更短时起跳。
## 地面单位额外叠加障碍物避让转向（steering），主动绕开前方塔/建筑而非硬撞后被推。
func _move_towards_position(target_pos: Vector2, delta: float) -> void:
	if _try_move_for_river_jump(target_pos, delta):
		return

	var step := _get_effective_move_speed() * delta
	# 先通过路径系统计算桥/河路由方向
	var next_pos := BattlePathing.advance_position(position, target_pos, step, movement_type)
	var move_vec := next_pos - position
	if move_vec.length() < 0.01:
		return

	var move_dir := move_vec.normalized()

	# 障碍物避让转向：叠加到移动方向上，使单位主动绕开前方静态障碍物
	var avoidance := _compute_obstacle_avoidance(move_dir)
	if avoidance.length() > 0.01:
		move_dir = (move_dir + avoidance).normalized()

	# 同类分离：与附近同层单位保持距离，投影到切向实现侧滑绕过
	var separation := _compute_unit_separation(move_dir)
	if separation.length() > 0.01:
		move_dir = (move_dir + separation).normalized()

	position += move_dir * step
	_last_move_dir = move_dir
	_accumulate_charge(step)
	# 移动音效：间歇播放（仅配了 sfx.move 的单位，如野猪骑士蹄声）
	_move_sfx_timer -= delta
	if _move_sfx_timer <= 0.0:
		AudioManager.play_unit_sfx(unit_id, "move")
		_move_sfx_timer = MOVE_SFX_INTERVAL


## 计算静态障碍物（塔/建筑）的避让转向向量。
## 算法：对前方探测范围内的每个 mass=0 实体，生成垂直于移动方向的推力，
##       强度随横向距离和前方距离衰减。跳过当前攻击/移动目标（单位需要接近它们）。
## 空中单位返回零向量（飞行不受地面障碍物影响）。
func _compute_obstacle_avoidance(move_dir: Vector2) -> Vector2:
	if movement_type == "air":
		return Vector2.ZERO

	var look_ahead := collision_radius + BattleConstants.px(OBSTACLE_LOOK_AHEAD_CELLS)
	var steering := Vector2.ZERO
	var obstacles := EntityRegistry.get_static_obstacles()

	for obs in obstacles:
		# 跳过当前攻击目标——单位需要接近正在攻击的塔
		var attack = get_primary_attack()
		if attack and attack.current_target == obs:
			continue
		# 跳过当前移动目标（无攻击目标时向最近的塔推进）
		if _move_target == obs:
			continue

		var obs_pos := BattlePathing.game_position_of(obs)
		var obs_r_raw = obs.get("collision_radius")
		var obs_r: float = float(obs_r_raw) if obs_r_raw != null else 10.0

		var to_obs := obs_pos - position
		var dist := to_obs.length()
		if dist > look_ahead + obs_r:
			continue  # 超出探测范围

		# 前方距离：障碍物在移动方向上的投影
		var forward_dist := move_dir.dot(to_obs)
		if forward_dist < -collision_radius:
			continue  # 障碍物在身后

		# 横向距离：障碍物到移动路径的垂直距离（2D 叉积标量）
		var cross_z := move_dir.x * to_obs.y - move_dir.y * to_obs.x
		var lateral_dist := absf(cross_z)
		var total_radius := collision_radius + obs_r
		if lateral_dist >= total_radius:
			continue  # 障碍物在路径侧面之外，不会碰撞

		# 确定避让方向：始终从障碍物同一侧绕过（叉积符号决定），减少抖动
		var perp: Vector2
		if cross_z >= 0:
			# 障碍物偏右 → 向左偏转
			perp = Vector2(move_dir.y, -move_dir.x)
		else:
			# 障碍物偏左 → 向右偏转
			perp = Vector2(-move_dir.y, move_dir.x)

		# 强度：横向越近越强 × 前方越近越强
		var lateral_factor := 1.0 - lateral_dist / total_radius
		var forward_factor := 1.0 - clampf(forward_dist / look_ahead, 0.0, 1.0)
		steering += perp * (lateral_factor * forward_factor)

	return steering


## 计算与附近同层单位的分离转向向量。
## 与静态障碍物避让不同，单位间分离力度更柔和，且投影到移动方向的切平面上，
## 创造"侧滑绕过"效果而非"停下互推"。空中单位返回零向量。
func _compute_unit_separation(move_dir: Vector2) -> Vector2:
	if movement_type == "air":
		return Vector2.ZERO

	var margin := BattleConstants.px(SEPARATION_RADIUS_CELLS)
	var steering := Vector2.ZERO
	var all_entities := EntityRegistry.get_all_combatants()

	for other in all_entities:
		if other == self:
			continue
		if not is_instance_valid(other):
			continue
		if other.get("is_dead") == true:
			continue
		# 同层检查
		var other_mt = other.get("movement_type")
		if other_mt != movement_type:
			continue
		# 跳过静态障碍物（由 _compute_obstacle_avoidance 处理）
		var other_mass = other.get("mass")
		if other_mass != null and int(other_mass) <= 0:
			continue

		var to_other: Vector2 = other.position - position
		var dist := to_other.length()
		if dist < 0.01:
			dist = 0.01
			to_other = Vector2(1.0, 0.0)

		var other_cr = other.get("collision_radius")
		var other_cr_val: float = float(other_cr) if other_cr != null else 10.0
		var trigger_range := collision_radius + other_cr_val + margin
		if dist >= trigger_range:
			continue

		# 前方过滤：只对移动方向前方的单位产生分离（身后的不触发）
		var forward_dist := move_dir.dot(to_other)
		if forward_dist < -collision_radius:
			continue

		# 推力强度：越近越强
		var strength := 1.0 - dist / trigger_range
		steering += (-to_other / dist) * strength

	if steering.length() < 0.01:
		return Vector2.ZERO

	# 限制最大强度
	if steering.length() > 1.0:
		steering = steering.normalized()

	# 关键：投影到切平面（垂直于移动方向），保留少量径向分量
	# 这样单位侧滑绕过同伴而非被推回原地
	if move_dir.length() > 0.01:
		var perp := Vector2(-move_dir.y, move_dir.x)
		var tangential := perp * steering.dot(perp)
		var radial := steering - tangential
		steering = tangential + radial * 0.2

	return steering * 0.5


## 返回当前移动方向（归一化向量）。供 CollisionSystem 切向滑动推挤使用。
## 非移动状态返回零向量。
func get_move_direction() -> Vector2:
	return _last_move_dir if _is_moving else Vector2.ZERO


func _try_move_for_river_jump(target_pos: Vector2, delta: float) -> bool:
	if not can_jump_river or base_movement_type != "ground":
		return false

	var from_side := BattlePathing.river_side(position)
	var to_side := BattlePathing.river_side(target_pos)
	if from_side == 0 or to_side == 0 or from_side == to_side:
		return false
	if not BattlePathing.should_jump_river(position, target_pos):
		return false

	var jump_y := _get_jump_start_y(from_side)
	var jump_start := Vector2(position.x, jump_y)
	var to_start := jump_start - position
	var max_distance := _get_effective_move_speed() * delta

	if to_start.length() > BattlePathing.ARRIVAL_EPSILON:
		if to_start.length() <= max_distance:
			position = jump_start
			_start_river_jump(from_side)
		else:
			position += to_start.normalized() * max_distance
		return true

	_start_river_jump(from_side)
	return true


func _start_river_jump(from_side: int) -> void:
	var start_y := _get_jump_start_y(from_side)
	var end_y := _get_jump_end_y(from_side)
	_jump_start = Vector2(position.x, start_y)
	_jump_end = Vector2(position.x, end_y)
	_jump_elapsed = 0.0
	_jump_duration = max(0.15, _jump_start.distance_to(_jump_end) / max(_get_effective_move_speed() * RIVER_JUMP_SPEED_MULTIPLIER, 1.0))
	position = _jump_start
	is_jumping_river = true
	movement_type = "air"
	altitude = 0.01
	_set_visual_altitude(altitude)
	queue_redraw()


func _get_jump_start_y(from_side: int) -> float:
	return BattleConstants.RIVER_Y_MAX + RIVER_JUMP_BANK_OFFSET if from_side > 0 else BattleConstants.RIVER_Y_MIN - RIVER_JUMP_BANK_OFFSET


func _get_jump_end_y(from_side: int) -> float:
	return BattleConstants.RIVER_Y_MIN - RIVER_JUMP_BANK_OFFSET if from_side > 0 else BattleConstants.RIVER_Y_MAX + RIVER_JUMP_BANK_OFFSET


func _process_river_jump(delta: float) -> void:
	_jump_elapsed += delta
	var t := clampf(_jump_elapsed / _jump_duration, 0.0, 1.0)
	position = _jump_start.lerp(_jump_end, t)
	altitude = sin(t * PI) * RIVER_JUMP_ARC_HEIGHT
	_set_visual_altitude(altitude)
	queue_redraw()

	if t >= 1.0:
		position = _jump_end
		altitude = 0.0
		movement_type = base_movement_type
		is_jumping_river = false
		_set_visual_altitude(0.0)
		queue_redraw()


func _store_visual_base_positions() -> void:
	_body_base_position = body_rect.position
	_health_bar_base_position = health_bar.position
	_debug_label_base_position = debug_label.position


func _set_visual_altitude(altitude_cells: float) -> void:
	var dy := -altitude_cells * BattleConstants.CELL_SIZE
	body_rect.position = _body_base_position + Vector2(0, dy)
	if health_bar:
		health_bar.position = _health_bar_base_position + Vector2(0, dy)
	if debug_label:
		debug_label.position = _debug_label_base_position + Vector2(0, dy)
	if sprite_animator:
		sprite_animator.apply_altitude_offset(dy)


## 从 attacks_data 读取主攻击的射程（格→像素），用于决定何时停下
func _get_primary_attack_range() -> float:
	if attacks_data.is_empty():
		return BattleConstants.px(1.5)  # 兜底值
	return BattleConstants.px(float(attacks_data[0].get("attack_range", 1.5)))


## 覆写视觉状态：移动中返回 "walk"，否则返回 "idle"。
## SpriteAnimator 每帧轮询此方法决定播放什么动画。
func get_visual_state() -> String:
	if is_dead:
		return "death"
	if is_jumping_river:
		return "jump"
	if _is_moving:
		return "walk"
	return "idle"


## 覆写朝向：根据当前目标 Y 坐标判定 front（面朝下/镜头）或 back（面朝上/背身）。
func get_facing() -> String:
	return "front" if _get_target_y() >= position.y else "back"


## 覆写水平翻转：目标在右侧时翻转为 true（素材默认面朝左）。
func get_flip_h() -> bool:
	return _get_target_x() > position.x


## 当前关注目标的 X 坐标（攻击目标优先，其次移动目标，无目标返回自身）。
func _get_target_x() -> float:
	var attack = get_primary_attack()
	if attack and attack.has_valid_target():
		return BattlePathing.game_position_of(attack.current_target).x
	if _move_target:
		return BattlePathing.game_position_of(_move_target).x
	return position.x


## 当前关注目标的 Y 坐标（攻击目标优先，其次移动目标，无目标返回自身）。
func _get_target_y() -> float:
	var attack = get_primary_attack()
	if attack and attack.has_valid_target():
		return BattlePathing.game_position_of(attack.current_target).y
	if _move_target:
		return BattlePathing.game_position_of(_move_target).y
	return position.y


## 找无攻击目标时的推进方向（最近的敌方建筑）。
## "any" 单位只认塔（不偏离主路线）；
## "building_only" 单位认所有建筑（塔 + 建筑卡牌，如迫击炮），可被建筑拉扯。
func _find_nearest_enemy_tower():
	var enemies = EntityRegistry.get_enemies_of(team)
	var nearest = null
	var nearest_dist = 999999.0
	for e in enemies:
		# building_only 单位认所有建筑（mass=0，含塔和建筑卡牌）；
		# any 单位只认塔，避免被敌方建筑带偏主推进路线
		if movement_targeting == "building_only":
			var m = e.get("mass")
			if m == null or int(m) > 0:
				continue
		else:
			if e.get("tower_type") == null:
				continue
		var d = BattlePathing.path_distance(
			position,
			BattlePathing.game_position_of(e),
			movement_type,
			can_jump_river
		)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest


## 死亡：触发死亡范围伤害（super.die），从注册表注销，发出信号，销毁
func die() -> void:
	super.die()
	EntityRegistry.unregister(self)
	SignalBus.unit_died.emit(self, team)
	print("[UnitBase] unit died:", unit_id)
	queue_free()
