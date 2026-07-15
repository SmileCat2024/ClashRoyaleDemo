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


func test_ground_targeting_uses_reachable_distance_across_river() -> void:
	_make_enemy(Vector2(180, 260))  # 直线近，但需要绕桥
	_make_enemy(Vector2(40, 380))   # 直线远一点，但同侧可达更近
	var target = TargetingSystem.find_best_target(
		Vector2(180, 380), "player", 300.0, "any", true, false, "ground")
	assert_not_null(target, "应找到可达距离最近的敌人")
	assert_eq(target.global_position, Vector2(40, 380),
		"地面索敌应按桥路径排序，不应被隔河直线距离误导")


func test_air_targeting_keeps_direct_distance_across_river() -> void:
	_make_enemy(Vector2(180, 260))  # 空中直线更近
	_make_enemy(Vector2(40, 380))
	var target = TargetingSystem.find_best_target(
		Vector2(180, 380), "player", 300.0, "any", true, false, "air")
	assert_not_null(target, "空中单位应找到直线距离最近的敌人")
	assert_eq(target.global_position, Vector2(180, 260),
		"空中索敌不受河道绕桥距离影响")


func test_jump_river_targeting_uses_jump_reachable_distance() -> void:
	_make_enemy(Vector2(180, 260))  # 跳过去更近
	_make_enemy(Vector2(40, 380))   # 普通地面会优先选它
	var target = TargetingSystem.find_best_target(
		Vector2(180, 380), "player", 300.0, "any", true, false, "ground", true)
	assert_not_null(target, "可跳河单位应找到跳跃距离最近的敌人")
	assert_eq(target.global_position, Vector2(180, 260),
		"可跳河单位索敌应按跳河可达距离排序")


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


func test_building_only_targets_building_unit() -> void:
	# 建筑单位（mass=0，无 tower_type，如迫击炮）
	var building := _make_enemy(Vector2(80, 0))
	building.mass = 0
	# 普通单位（应被忽略，即便更近）
	_make_enemy(Vector2(30, 0))
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "building_only", true, true)
	assert_not_null(target, "building_only 应能锁定建筑单位（mass=0）")
	assert_eq(target, building, "应锁定建筑单位而非普通单位")


func test_building_only_picks_nearest_among_tower_and_building() -> void:
	# 塔（远）+ 建筑单位（近），building_only 应选最近的建筑单位
	_make_enemy(Vector2(200, 0), "ground", true)  # 塔
	var building := _make_enemy(Vector2(50, 0))    # 建筑单位
	building.mass = 0
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "building_only", true, true)
	assert_not_null(target, "塔和建筑单位都应被纳入索敌")
	assert_eq(target, building, "应选最近的建筑（此处为建筑单位）")


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


# ============================================================
#  find_best_target — 碰撞/受击半径偏移
# ============================================================

func test_target_hurt_radius_extends_effective_sight() -> void:
	# 两个敌人都在 125px（超出 sight_range=120），但受击半径不同。
	# 大受击半径(30px)有效距离 = 125-30 = 95 < 120 → 可发现；
	# 小受击半径(1px)有效距离 = 125-1 = 124 > 120 → 不可发现。
	var big := _make_enemy(Vector2(-125, 0))
	big.hurt_radius = 30.0
	var small := _make_enemy(Vector2(125, 0))
	small.hurt_radius = 1.0
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 120.0, "any", true, false)
	assert_not_null(target, "应找到大半径目标")
	assert_eq(target, big, "大半径目标在有效视野内，小半径目标不在")


func test_self_collision_radius_closes_attack_sight_dead_zone() -> void:
	# 火枪手式场景：视野120px、自身半径10px，公主塔受击半径30px。
	# 塔中心距160px时，攻击触及距离 = 120+10+30=160；索敌也必须成功，
	# 否则 UnitBase 会在攻击距离停步，却没有攻击目标而永久发呆。
	var tower := _make_enemy(Vector2(160, 0), "ground", true)
	tower.collision_radius = 30.0
	tower.hurt_radius = 30.0
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 120.0, "any", true, false,
		"ground", false, 0.0, 10.0)
	assert_eq(target, tower,
		"攻击触及边界上的公主塔必须进入视野，不能形成停步死区")


# ============================================================
#  find_best_target — 盲区过滤（min_range，迫击炮最小射程）
# ============================================================

func test_dead_zone_excludes_close_target() -> void:
	# 近处敌人(30px)在盲区内，远处敌人(100px)在有效区
	_make_enemy(Vector2(30, 0))
	_make_enemy(Vector2(100, 0))
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "any", true, false,
		"ground", false, 50.0)  # min_range=50px
	assert_not_null(target, "盲区内应跳过近处目标")
	assert_eq(target.global_position, Vector2(100, 0), "应选中盲区外的远处目标")


func test_dead_zone_all_in_zone_returns_null() -> void:
	_make_enemy(Vector2(30, 0))
	_make_enemy(Vector2(40, 0))
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "any", true, false,
		"ground", false, 50.0)
	assert_null(target, "所有目标都在盲区内时返回 null")


func test_no_dead_zone_keeps_default_behavior() -> void:
	_make_enemy(Vector2(30, 0))
	_make_enemy(Vector2(100, 0))
	var target = TargetingSystem.find_best_target(
		Vector2.ZERO, "player", 300.0, "any", true, false,
		"ground", false, 0.0)  # min_range=0 = 无盲区
	assert_not_null(target, "无盲区时正常索敌")
	assert_eq(target.global_position, Vector2(30, 0), "应选中最近的")
