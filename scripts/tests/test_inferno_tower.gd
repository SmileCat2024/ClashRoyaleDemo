# 文件名：test_inferno_tower.gd
# 作用：验证地狱塔的核心机制——递增伤害光束（ramp）。
#
#   期望行为：
#     1. 配置了 ramp_damage 的攻击启用递增伤害（_is_ramp=true）
#     2. _get_current_ramp_damage 按锁定时间阈值切换三阶段伤害（43 → 158 → 847）
#     3. get_ramp_intensity 随锁定时间线性增长（0.0~1.0）
#     4. _process 持续锁定同一目标时累加锁定时间；目标切换时重置
#     5. has_beam_target 仅在有效锁定目标时为 true
#     6. 普通（无 ramp 配置）单位不受递增机制影响（向后兼容）
#     7. DataRegistry 中 inferno_tower 配置完整（寿命/部署/建筑属性）
#
# 挂载位置：由 TestRunner 实例化。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

# 地狱塔光束攻击配置（与 DataRegistry 一致，attack_range 6 格）
const RAMP_ATTACK_DATA := {
	"name": "inferno_beam",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": true,
	"attack_range": 6.0,
	"attack_interval": 0.4,
	"first_attack_delay": 0.0,
	"delivery": "instant",
	"damage": 43,
	"ramp_damage": [43, 158, 847],
	"ramp_thresholds": [0.0, 2.0, 4.0],
}

# 普通攻击配置（无 ramp，用于验证向后兼容）
const PLAIN_ATTACK_DATA := {
	"name": "test_plain",
	"targeting": "any",
	"attack_ground": true,
	"attack_air": false,
	"attack_range": 1.5,
	"attack_interval": 1.0,
	"first_attack_delay": 0.0,
	"delivery": "instant",
	"damage": 10,
}

var _mocks: Array = []
var _attacker: CombatantBase
var _comp: AttackComponent


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()

	_attacker = MockScript.new()
	_attacker.team = "player"
	_attacker.sight_range = 120.0  # 6 格
	_attacker.global_position = Vector2.ZERO
	_attacker.initialized = true
	_attacker.collision_radius = 10.0
	_attacker.hurt_radius = 10.0

	_comp = AttackComponent.new()
	_comp.combatant = _attacker
	_comp.setup(RAMP_ATTACK_DATA)


func teardown() -> void:
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()
	if _comp and is_instance_valid(_comp):
		_comp.free()
	if _attacker and is_instance_valid(_attacker):
		_attacker.free()


## 创建高血量敌方 mock（避免攻击致死干扰锁定时间测试）并注册到 EntityRegistry
func _make_enemy(pos: Vector2) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.global_position = pos
	m.initialized = true
	m.collision_radius = 10.0
	m.hurt_radius = 10.0
	m.max_hp = 100000
	m.current_hp = 100000
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# ============================================================
#  配置加载
# ============================================================

func test_ramp_config_loaded() -> void:
	assert_true(_comp._is_ramp, "配置了 ramp_damage 的攻击应启用递增伤害")
	assert_eq(_comp._ramp_damage, [43, 158, 847], "ramp_damage 应正确读取")
	assert_eq(_comp._ramp_thresholds, [0.0, 2.0, 4.0], "ramp_thresholds 应正确读取")


# ============================================================
#  递增伤害三阶段
# ============================================================

func test_ramp_damage_stage_1() -> void:
	_comp._lock_time = 0.0
	assert_eq(_comp._get_current_ramp_damage(), 43, "锁定 0 秒应为第 1 阶段(43)")
	_comp._lock_time = 1.9
	assert_eq(_comp._get_current_ramp_damage(), 43, "锁定 1.9 秒仍未达 2 秒阈值，应为第 1 阶段(43)")


func test_ramp_damage_stage_2() -> void:
	_comp._lock_time = 2.0
	assert_eq(_comp._get_current_ramp_damage(), 158, "锁定达 2 秒阈值应进入第 2 阶段(158)")
	_comp._lock_time = 3.9
	assert_eq(_comp._get_current_ramp_damage(), 158, "锁定 3.9 秒仍未达 4 秒阈值，应为第 2 阶段(158)")


func test_ramp_damage_stage_3() -> void:
	_comp._lock_time = 4.0
	assert_eq(_comp._get_current_ramp_damage(), 847, "锁定达 4 秒阈值应进入第 3 阶段满热(847)")
	_comp._lock_time = 100.0
	assert_eq(_comp._get_current_ramp_damage(), 847, "超过最高阈值应保持满热(847)")


# ============================================================
#  递增强度（光束视觉用）
# ============================================================

func test_ramp_intensity() -> void:
	_comp._lock_time = 0.0
	assert_approx(_comp.get_ramp_intensity(), 0.0, 0.01, "锁定 0 秒强度应为 0.0")
	_comp._lock_time = 2.0
	assert_approx(_comp.get_ramp_intensity(), 0.5, 0.01, "锁定 2 秒(中点)强度应为 0.5")
	_comp._lock_time = 4.0
	assert_approx(_comp.get_ramp_intensity(), 1.0, 0.01, "锁定 4 秒(满热)强度应为 1.0")
	_comp._lock_time = 10.0
	assert_approx(_comp.get_ramp_intensity(), 1.0, 0.01, "超过满热强度应钳制为 1.0")


# ============================================================
#  光束目标判定
# ============================================================

func test_has_beam_target() -> void:
	assert_false(_comp.has_beam_target(), "无锁定目标时应为 false")
	var enemy := _make_enemy(Vector2(100, 0))
	_comp._lock_target = enemy
	assert_true(_comp.has_beam_target(), "有有效锁定目标时应为 true")
	enemy.is_dead = true
	assert_false(_comp.has_beam_target(), "锁定目标死亡后应为 false")


# ============================================================
#  锁定时间累加（_process 集成）
# ============================================================

func test_lock_accumulates_in_process() -> void:
	var enemy := _make_enemy(Vector2(100, 0))  # 在 reach(140px) 内
	_comp.current_target = enemy
	_comp._process(0.5)
	_comp._process(0.5)
	assert_eq(_comp._lock_target, enemy, "锁定目标应记录为该敌人")
	assert_approx(_comp._lock_time, 1.0, 0.01, "持续锁定 1 秒后累计锁定时间应为 1.0")


func test_lock_resets_on_target_switch() -> void:
	var a := _make_enemy(Vector2(100, 0))
	var b := _make_enemy(Vector2(-100, 0))  # 另一侧，也在射程内
	_comp.current_target = a
	_comp._process(0.5)
	_comp._process(0.5)
	assert_approx(_comp._lock_time, 1.0, 0.01, "锁定 A 累计 1 秒")
	# 模拟目标切换到 B
	_comp.current_target = b
	_comp._process(0.5)
	assert_eq(_comp._lock_target, b, "切换目标后锁定目标应变更为 B")
	assert_approx(_comp._lock_time, 0.5, 0.01, "切换目标后锁定时间应重置并重新累计（仅本帧 0.5 秒）")


# ============================================================
#  向后兼容（无 ramp 配置的普通单位）
# ============================================================

func test_non_ramp_unit_unaffected() -> void:
	var plain := AttackComponent.new()
	plain.combatant = _attacker
	plain.setup(PLAIN_ATTACK_DATA)
	assert_false(plain._is_ramp, "无 ramp 配置的单位不应启用递增伤害")
	assert_eq(plain._get_current_ramp_damage(), 10, "普通单位应返回固定伤害值")
	assert_eq(plain.get_ramp_intensity(), 0.0, "普通单位递增强度应为 0")
	assert_false(plain.has_beam_target(), "普通单位不应有光束目标")
	plain.free()


# ============================================================
#  DataRegistry 地狱塔配置校验
# ============================================================

func test_inferno_tower_data_config() -> void:
	var data := DataRegistry.get_unit_data("inferno_tower")
	assert_eq(data.get("id"), "inferno_tower", "单位 id 应为 inferno_tower")
	assert_eq(int(data.get("max_hp")), 1748, "11 级生命值应为 1748")
	assert_eq(int(data.get("mass")), 0, "建筑 mass 应为 0（不可移动，寻路障碍）")
	assert_eq(float(data.get("move_speed")), 0.0, "建筑移速应为 0")
	assert_approx(float(data.get("deploy_time")), 1.0, 0.01, "部署时间应为 1.0 秒")
	assert_approx(float(data.get("lifespan")), 30.0, 0.01, "寿命应为 30.0 秒")
	# 攻击配置
	var atk: Dictionary = data["attacks"][0]
	assert_true(bool(atk.get("attack_air")), "地狱塔应对空")
	assert_true(bool(atk.get("attack_ground")), "地狱塔应对地")
	assert_approx(float(atk.get("attack_range")), 6.0, 0.01, "射程应为 6.0 格")
	assert_approx(float(atk.get("attack_interval")), 0.4, 0.01, "攻速间隔应为 0.4 秒")
	assert_eq(atk.get("ramp_damage"), [43, 158, 847], "三阶段伤害应为 43/158/847")
	assert_eq(atk.get("ramp_thresholds"), [0.0, 2.0, 4.0], "阈值应为 0/2/4 秒")


func test_inferno_tower_card_config() -> void:
	var card := DataRegistry.get_card_data("card_inferno_tower")
	assert_eq(card.get("id"), "card_inferno_tower", "卡牌 id 应为 card_inferno_tower")
	assert_eq(int(card.get("cost")), 5, "圣水费用应为 5")
	assert_eq(str(card.get("card_type")), "troop", "建筑卡 card_type 应为 troop（通过 unit_id 关联）")
	assert_eq(str(card.get("unit_id")), "inferno_tower", "应关联 inferno_tower 单位")
