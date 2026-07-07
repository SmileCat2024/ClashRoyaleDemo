# 文件名：test_death_damage.gd
# 作用：验证单位死亡延迟伤害的完整链路——
#       Layer 1: CombatantBase.die() 正确发出 death_damage_triggered 信号（含参数校验）
#       Layer 2: DelayedDamageEffect._on_expire() 正确结算范围伤害（含边界、友方免疫）
#       Layer 3: DataRegistry 气球兵配置完整性
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 setup 了解 mock 怎么创建，再看 test_die_emits_signal 了解信号验证。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

var _mocks: Array = []
var _signal_received: Array = []  ## 捕获 death_damage_triggered 信号参数


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()
	_signal_received.clear()
	# 连接信号，捕获参数到 _signal_received
	SignalBus.death_damage_triggered.connect(_on_death_damage_triggered)


func teardown() -> void:
	SignalBus.death_damage_triggered.disconnect(_on_death_damage_triggered)
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()


## 信号捕获回调
func _on_death_damage_triggered(pos: Vector2, damage: int, radius: float, fuse: float, team: String) -> void:
	_signal_received.append({"pos": pos, "damage": damage, "radius": radius, "fuse": fuse, "team": team})


## 创建一个带死亡伤害配置的 mock 单位（模拟气球兵）
func _make_balloon(team: String, pos: Vector2, dmg: int = 240, radius_px: float = 40.0, fuse: float = 3.0) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = team
	m.max_hp = 100
	m.current_hp = 100
	m.death_damage = dmg
	m.death_radius = radius_px
	m.death_fuse_time = fuse
	m.global_position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


## 创建一个普通 mock 目标
func _make_target(team: String, pos: Vector2, hp: int = 1000) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = team
	m.max_hp = hp
	m.current_hp = hp
	m.global_position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# ============================================================
#  Layer 1: die() 发出死亡伤害信号
# ============================================================

func test_die_emits_death_damage_signal() -> void:
	var balloon := _make_balloon("player", Vector2(100, 200), 240, 40.0, 3.0)
	balloon.die()

	assert_eq(_signal_received.size(), 1, "应发出一次 death_damage_triggered 信号")
	if _signal_received.size() > 0:
		var s = _signal_received[0]
		assert_eq(s.pos, Vector2(100, 200), "信号应包含死亡位置")
		assert_eq(s.damage, 240, "信号应包含伤害值")
		assert_eq(s.radius, 40.0, "信号应包含半径")
		assert_eq(s.fuse, 3.0, "信号应包含引信时间")
		assert_eq(s.team, "player", "信号应包含阵营")


func test_die_no_signal_without_death_damage() -> void:
	var unit := _make_target("player", Vector2.ZERO)
	unit.death_damage = 0
	unit.death_radius = 0.0
	unit.death_fuse_time = 0.0
	unit.die()

	assert_eq(_signal_received.size(), 0, "无 death_damage 的单位不应发出信号")


func test_take_damage_triggers_death_signal() -> void:
	var balloon := _make_balloon("player", Vector2(50, 50), 240, 40.0, 3.0)
	balloon.take_damage(200)  # 气球 100hp，一击必杀

	assert_true(balloon.is_dead, "气球兵应已死亡")
	assert_eq(_signal_received.size(), 1, "通过 take_damage 触发死亡后应发出信号")


# ============================================================
#  Layer 2: DelayedDamageEffect._on_expire() 伤害结算
#  （直接调用 _on_expire 模拟引信到期，绕过 Timer）
# ============================================================

func _make_effect(pos: Vector2, team: String, dmg: int, radius: float, fuse: float) -> Node:
	var effect = preload("res://scripts/effects/DelayedDamageEffect.gd").new()
	effect.setup_damage(pos, team, fuse, dmg, radius)
	return effect


func test_expire_deals_damage_to_enemies_in_radius() -> void:
	var enemy_near := _make_target("enemy", Vector2(30, 0), 1000)
	var enemy_far := _make_target("enemy", Vector2(100, 0), 1000)

	var effect := _make_effect(Vector2.ZERO, "player", 240, 40.0, 3.0)
	effect._on_expire()
	effect.free()

	assert_eq(enemy_near.current_hp, 1000 - 240, "范围内敌方应受到 240 伤害")
	assert_eq(enemy_far.current_hp, 1000, "范围外敌方不应受伤")


func test_expire_does_not_hit_allies() -> void:
	var ally := _make_target("player", Vector2(20, 0), 1000)
	var enemy := _make_target("enemy", Vector2(20, 0), 1000)

	var effect := _make_effect(Vector2.ZERO, "player", 240, 40.0, 3.0)
	effect._on_expire()
	effect.free()

	assert_eq(ally.current_hp, 1000, "爆炸不应误伤友方")
	assert_eq(enemy.current_hp, 1000 - 240, "爆炸应只打敌方")


func test_expire_boundary_exact_radius() -> void:
	var enemy := _make_target("enemy", Vector2(40, 0), 1000)

	var effect := _make_effect(Vector2.ZERO, "player", 240, 40.0, 3.0)
	effect._on_expire()
	effect.free()

	assert_eq(enemy.current_hp, 1000 - 240, "恰好在半径边界上的敌人应受伤")


func test_effect_lifecycle_progress() -> void:
	var effect := _make_effect(Vector2.ZERO, "player", 240, 40.0, 3.0)
	assert_approx(effect.get_progress(), 0.0, 0.01, "初始进度应为 0")
	assert_approx(effect.get_remaining_time(), 3.0, 0.01, "初始剩余时间应为 3.0")
	effect._process(1.5)
	assert_approx(effect.get_progress(), 0.5, 0.01, "1.5s 后进度应为 0.5")
	assert_approx(effect.get_remaining_time(), 1.5, 0.01, "1.5s 后剩余应为 1.5s")
	effect.free()


# ============================================================
#  Layer 3: DataRegistry 气球兵配置验证
# ============================================================

func test_balloon_has_death_damage_config() -> void:
	var data := DataRegistry.get_unit_data("balloon")
	assert_eq(int(data.get("death_damage", 0)), 240, "气球兵应配置 death_damage=240")
	assert_eq(float(data.get("death_radius", 0)), 2.0, "气球兵应配置 death_radius=2.0格")
	assert_eq(float(data.get("death_fuse_time", 0)), 3.0, "气球兵应配置 death_fuse_time=3.0秒")


func test_balloon_card_data_exists() -> void:
	var card := DataRegistry.get_card_data("card_balloon")
	assert_eq(str(card.get("unit_id", "")), "balloon", "气球兵卡牌应关联 balloon 单位")


func test_other_units_have_no_death_damage() -> void:
	for uid in ["knight", "hog_rider", "musketeer", "mini_pekka"]:
		var data := DataRegistry.get_unit_data(uid)
		assert_eq(int(data.get("death_damage", 0)), 0, "%s 不应有 death_damage" % uid)
