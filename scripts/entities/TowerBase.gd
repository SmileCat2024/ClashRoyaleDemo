# 文件名：TowerBase.gd
# 作用：控制塔的行为——受伤、死亡。
#       塔不会移动。主塔（king）死亡时战斗结束。
#       D1 阶段：塔只存在，不攻击（D2 接入 AttackComponent）。
# 挂载位置：TowerBase.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解塔怎么初始化。

class_name TowerBase
extends CombatantBase

# ---- 身份信息（塔独有）----
var tower_id: String = ""
var tower_type: String = "guard"  ## "king" 或 "guard"


## 初始化塔属性。由 DebugBattle / BattleManager 在场景启动时调用。
func setup(tower_data: Dictionary, team_name: String, tower_name: String) -> void:
	tower_id = tower_name
	team = team_name
	tower_type = tower_data.get("tower_type", "guard")

	# 初始化战斗属性（基类方法）
	_init_combat_stats(tower_data)

	# 塔尺寸：主塔 4x4 格(80x80px)，公主塔 3x3 格(60x60px)
	var body_size: Vector2
	if tower_type == "king":
		body_size = BattleConstants.KING_TOWER_SIZE
	else:
		body_size = BattleConstants.GUARD_TOWER_SIZE

	# 颜色按阵营区分
	if team == "player":
		body_rect.color = BattleConstants.COLOR_PLAYER_TOWER
	else:
		body_rect.color = BattleConstants.COLOR_ENEMY_TOWER

	body_rect.size = body_size
	body_rect.position = Vector2(-body_size.x / 2.0, -body_size.y / 2.0)

	health_bar.max_value = max_hp
	health_bar.value = current_hp
	health_bar.size = Vector2(body_size.x + 10, 6)
	health_bar.position = Vector2(-(body_size.x + 10) / 2.0, -body_size.y / 2.0 - 12)

	debug_label.text = tower_name
	debug_label.position = Vector2(-30, body_size.y / 2.0 + 4)

	initialized = true
	queue_redraw()
	print("[TowerBase] setup:", tower_id, team, tower_type, "hp:", max_hp)


## _draw()：绘制攻击范围圆圈（调试用）
func _draw() -> void:
	if not initialized or is_dead:
		return
	if attacks_data.is_empty():
		return
	var range_val = BattleConstants.px(float(attacks_data[0].get("attack_range", 0)))
	if range_val <= 0:
		return
	# 射程填充色（很淡）
	var fill_color: Color
	if team == "player":
		fill_color = Color(0.3, 0.6, 1.0, 0.05)
	else:
		fill_color = Color(1.0, 0.3, 0.2, 0.05)
	draw_circle(Vector2.ZERO, range_val, fill_color)
	# 射程边线
	var ring_color = Color(1, 1, 1, 0.08)
	draw_arc(Vector2.ZERO, range_val, 0, TAU, 64, ring_color, 1.0)


func _process(_delta: float) -> void:
	if not initialized or is_dead:
		return
	# D1：塔不做任何事。D2 接入 AttackComponent 后才有攻击逻辑。


## 死亡：变灰，从注册表注销，发出信号（塔不 queue_free，留在战场作为残骸）
func die() -> void:
	super.die()
	EntityRegistry.unregister(self)
	if body_rect:
		body_rect.color = Color(0.3, 0.3, 0.3, 0.5)
	if health_bar:
		health_bar.visible = false
	queue_redraw()
	SignalBus.tower_destroyed.emit(tower_id, team, tower_type)
	print("[TowerBase] tower destroyed:", tower_id, team, tower_type)
