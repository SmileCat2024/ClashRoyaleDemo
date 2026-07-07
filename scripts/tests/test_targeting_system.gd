# 文件名：test_targeting_system.gd
# 作用：测试 TargetingSystem 的三重过滤索敌逻辑（阵营→ground/air→distance）。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 setup/teardown 了解 mock 怎么创建和清理，再看各 test_ 方法。

extends TestBase

const MockScript := preload("res://scripts/tests/MockCombatant.gd")

var _mocks: Array = []


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()


func teardown() -> void:
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()


## 创建一个敌方 mock 并注册到 EntityRegistry
func _make_enemy(pos: Vector2, movement: String = "ground", is_tower: bool = false) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.movement_type = movement
	m.global_position = pos
	m.initialized = true
	if is_tower:
		m.tower_type = "guard"
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# ============================================================
#  is_enemy
# ============================================================

func test_is_enemy_different_teams() -> void:
	assert_true(TargetingSystem.is_enemy("player", "enemy"))


func test_is_enemy_same_team() -> void:
	assert_false(TargetingSystem.is_enemy("player", "player"))


# ============================================================
#  find_best_target — 基础索敌
# ============================================================

func test_find_nearest_enemy() -> void:
	_make_enemy(Vector2(50, 0))   # 近
	_make_enemy(Vector2(200, 0))  # 远
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "any", true, false)
	assert_not_null(target, "应找到敌人")
	assert_eq(target.global_position, Vector2(50, 0), "应返回最近的")


func test_returns_null_when_no_enemies() -> void:
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "any", true, false)
	assert_null(target, "无敌人时返回 null")


func test_returns_null_when_out_of_range() -> void:
	_make_enemy(Vector2(500, 0))  # 超出搜索范围
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "any", true, false)
	assert_null(target, "超出范围时返回 null")


# ============================================================
#  find_best_target — ground/air 过滤
# ============================================================

func test_ground_attacker_cannot_target_air() -> void:
	_make_enemy(Vector2(30, 0), "air")
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 100.0, "any",
		true,   # attack_ground
		false)  # attack_air
	assert_null(target, "地面攻击者不能打空中单位")


func test_air_attacker_can_target_air() -> void:
	_make_enemy(Vector2(30, 0), "air")
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 100.0, "any",
		false, # attack_ground
		true)  # attack_air
	assert_not_null(target, "对空攻击者可以打空中单位")


func test_attacker_can_target_both() -> void:
	_make_enemy(Vector2(30, 0), "ground")
	_make_enemy(Vector2(40, 0), "air")
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 100.0, "any", true, true)
	assert_not_null(target, "双向攻击者应找到最近敌人")
	# 30px 比 40px 近，应选地面那个
	assert_eq(target.global_position, Vector2(30, 0))


# ============================================================
#  find_best_target — building_only 过滤
# ============================================================

func test_building_only_ignores_units() -> void:
	_make_enemy(Vector2(30, 0), "ground", false)  # 普通单位
	_make_enemy(Vector2(100, 0), "ground", true)  # 塔
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "building_only", true, true)
	assert_not_null(target, "building_only 应找到塔")
	assert_eq(target.tower_type, "guard", "应锁定塔而非单位")


func test_building_only_no_towers_returns_null() -> void:
	_make_enemy(Vector2(30, 0))  # 只有单位，没有塔
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "building_only", true, true)
	assert_null(target, "building_only 无塔时返回 null")


# ============================================================
#  find_best_target — 死亡过滤
# ============================================================

func test_ignores_dead_enemies() -> void:
	var dead := _make_enemy(Vector2(30, 0))
	dead.is_dead = true
	_make_enemy(Vector2(100, 0))  # 活着的
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "any", true, false)
	assert_not_null(target, "应跳过死亡的，找到活着的")
	assert_eq(target.global_position, Vector2(100, 0))
