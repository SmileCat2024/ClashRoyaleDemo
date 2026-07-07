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
var is_jumping_river: bool = false
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
	health_bar.size = Vector2(size + 12, 4)
	health_bar.position = Vector2(-(size + 12) / 2.0, -size / 2.0 - 8)

	# 调试标签
	debug_label.text = display_name
	debug_label.position = Vector2(-15, size / 2.0 + 2)
	_store_visual_base_positions()

	# 飞行单位设置离地高度（仅视觉，不影响逻辑坐标和索敌）
	if movement_type == "air":
		altitude = 2.5
	_set_visual_altitude(altitude)

	initialized = true
	print("[UnitBase] setup:", unit_id, team, "hp:", max_hp)


## _draw()：飞行单位在地面位置绘制影子（位置 = 实体 origin，不受 altitude 偏移影响）
func _draw() -> void:
	if not initialized or is_dead:
		return
	if altitude > 0.0:
		var sw := body_rect.size.x * 0.6
		var sh := sw * 0.35
		draw_rect(Rect2(-sw / 2.0, -sh / 2.0, sw, sh), Color(0, 0, 0, 0.25))


func _process(delta: float) -> void:
	if not initialized or is_dead:
		return
	if is_jumping_river:
		_process_river_jump(delta)
		return

	var attack = get_primary_attack()

	# 有攻击目标：追击或在射程内停下（让 AttackComponent 自己攻击）
	if attack and attack.has_valid_target():
		var target_pos := BattlePathing.game_position_of(attack.current_target)
		var dist = BattlePathing.path_distance(position, target_pos, movement_type, can_jump_river)
		if dist > attack.attack_range:
			_move_towards_position(target_pos, delta)
		# else: 在射程内，停下不动，AttackComponent 会自动出手
		return

	# 无攻击目标：向最近敌方塔移动（推进行为）
	_move_target = _find_nearest_enemy_tower()
	if _move_target:
		var target_pos := BattlePathing.game_position_of(_move_target)
		var dist = BattlePathing.path_distance(position, target_pos, movement_type, can_jump_river)
		var stop_dist = _get_primary_attack_range()
		if dist > stop_dist:
			_move_towards_position(target_pos, delta)


## 按单位能力移动：普通地面单位走桥；可跳河单位仅在跳河路线更短时起跳。
func _move_towards_position(target_pos: Vector2, delta: float) -> void:
	if _try_move_for_river_jump(target_pos, delta):
		return

	position = BattlePathing.advance_position(
		position,
		target_pos,
		move_speed * delta,
		movement_type
	)


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
	var max_distance := move_speed * delta

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
	_jump_duration = max(0.15, _jump_start.distance_to(_jump_end) / max(move_speed * RIVER_JUMP_SPEED_MULTIPLIER, 1.0))
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


## 从 attacks_data 读取主攻击的射程（格→像素），用于决定何时停下
func _get_primary_attack_range() -> float:
	if attacks_data.is_empty():
		return BattleConstants.px(1.5)  # 兜底值
	return BattleConstants.px(float(attacks_data[0].get("attack_range", 1.5)))


## 找最近的敌方塔（用于无攻击目标时的推进方向）
func _find_nearest_enemy_tower():
	var enemies = EntityRegistry.get_enemies_of(team)
	var nearest = null
	var nearest_dist = 999999.0
	for e in enemies:
		# 只找塔（有 tower_type 属性的实体）
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


## 死亡：从注册表注销，发出信号，销毁
func die() -> void:
	super.die()
	EntityRegistry.unregister(self)
	SignalBus.unit_died.emit(self, team)
	print("[UnitBase] unit died:", unit_id)
	queue_free()
