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
var sight_range: float = 120.0
var movement_targeting: String = "any"     ## "any" | "building_only"

# ---- 运行时 ----
var _move_target = null    ## 当前移动目标（CombatantBase 或 null）


## 初始化单位属性。由 SpawnManager 在生成单位后调用。
func setup(unit_data: Dictionary, team_name: String) -> void:
	unit_id = unit_data.get("id", "")
	display_name = unit_data.get("display_name", "")
	team = team_name
	move_speed = BattleConstants.px(float(unit_data.get("move_speed", 1.0)))
	movement_type = unit_data.get("movement_type", "ground")
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

	# 飞行单位设置离地高度（仅视觉，不影响逻辑坐标和索敌）
	if movement_type == "air":
		altitude = 2.5
	_apply_altitude_offset()

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

	var attack = get_primary_attack()

	# 有攻击目标：追击或在射程内停下（让 AttackComponent 自己攻击）
	if attack and attack.has_valid_target():
		var dist = global_position.distance_to(attack.current_target.global_position)
		if dist > attack.attack_range:
			# 超出射程，移动靠近目标
			var dir = (attack.current_target.global_position - global_position).normalized()
			global_position += dir * move_speed * delta
		# else: 在射程内，停下不动，AttackComponent 会自动出手
		return

	# 无攻击目标：向最近敌方塔移动（推进行为）
	_move_target = _find_nearest_enemy_tower()
	if _move_target:
		var dist = global_position.distance_to(_move_target.global_position)
		var stop_dist = _get_primary_attack_range()
		if dist > stop_dist:
			var dir = (_move_target.global_position - global_position).normalized()
			global_position += dir * move_speed * delta


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
		var d = global_position.distance_to(e.global_position)
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
