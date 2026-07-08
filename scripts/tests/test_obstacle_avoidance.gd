# 文件名：test_obstacle_avoidance.gd
# 作用：障碍物避让转向（steering avoidance）的单元测试。
#       覆盖：前方有障碍物产生避让、无障碍物返回零、空中单位不避让、
#       当前目标不避让、超出范围/身后/侧面过滤、避让方向正确性、多障碍物叠加。
# 挂载位置：由 TestRunner 自动加载。

extends TestBase

const UnitBaseScript := preload("res://scripts/entities/UnitBase.gd")
const MockScript := preload("res://scripts/tests/MockCombatant.gd")

var _mocks: Array = []
var _unit: UnitBase


func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()
	# 创建 UnitBase 实例（不放入场景树，_compute_obstacle_avoidance 不依赖 @onready 子节点）
	_unit = UnitBaseScript.new()
	_unit.team = "player"
	_unit.movement_type = "ground"
	_unit.collision_radius = 10.0
	_unit.position = Vector2(100, 200)
	_unit._move_target = null


func teardown() -> void:
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()
	if _unit and is_instance_valid(_unit):
		_unit.free()


## 创建 mock 障碍物并注册到 EntityRegistry
func _make_obstacle(pos: Vector2, radius: float = 30.0) -> CombatantBase:
	var m: CombatantBase = MockScript.new()
	m.team = "enemy"
	m.mass = 0
	m.collision_radius = radius
	m.position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# ============================================================
#  基础避让
# ============================================================

func test_obstacle_ahead_produces_avoidance() -> void:
	_make_obstacle(Vector2(100, 170), 30.0)
	var move_dir := Vector2(0, -1)
	var avoidance := _unit._compute_obstacle_avoidance(move_dir)
	assert_true(avoidance.length() > 0.01, "正前方有障碍物时应产生非零避让向量")
	# 移动方向为纯 y → 避让向量应在 x 方向上（垂直于移动方向）
	assert_approx(absf(avoidance.x), avoidance.length(), 0.01, "避让向量应垂直于移动方向")
	assert_approx(avoidance.y, 0.0, 0.01, "y方向移动时避让向量y分量应≈0")


func test_no_obstacle_zero_avoidance() -> void:
	var avoidance := _unit._compute_obstacle_avoidance(Vector2(0, -1))
	assert_eq(avoidance, Vector2.ZERO, "无障碍物时避让向量应为零")


func test_air_unit_no_avoidance() -> void:
	_unit.movement_type = "air"
	_make_obstacle(Vector2(100, 170), 30.0)
	var avoidance := _unit._compute_obstacle_avoidance(Vector2(0, -1))
	assert_eq(avoidance, Vector2.ZERO, "空中单位不受地面障碍物影响")


# ============================================================
#  跳过当前目标
# ============================================================

func test_skip_move_target() -> void:
	var tower := _make_obstacle(Vector2(100, 170), 30.0)
	_unit._move_target = tower
	var avoidance := _unit._compute_obstacle_avoidance(Vector2(0, -1))
	assert_eq(avoidance, Vector2.ZERO, "当前移动目标（正在接近的塔）不应触发避让")


# ============================================================
#  范围过滤
# ============================================================

func test_obstacle_too_far_no_avoidance() -> void:
	# 距离100px，look_ahead(40)+obs_r(30)=70 → 超出探测范围
	_make_obstacle(Vector2(100, 100), 30.0)
	var avoidance := _unit._compute_obstacle_avoidance(Vector2(0, -1))
	assert_eq(avoidance, Vector2.ZERO, "超出探测范围的障碍物不应触发避让")


func test_obstacle_behind_no_avoidance() -> void:
	# 在单位身后（y > 200，单位向上移动）
	_make_obstacle(Vector2(100, 250), 30.0)
	var avoidance := _unit._compute_obstacle_avoidance(Vector2(0, -1))
	assert_eq(avoidance, Vector2.ZERO, "身后的障碍物不应触发避让")


func test_obstacle_far_lateral_no_avoidance() -> void:
	# 在前方但横向距离 > total_radius，不会碰撞
	# to_obs = (30, -15)，forward_dist=15，lateral_dist=30，total_radius=20 → 30>=20
	_make_obstacle(Vector2(130, 185), 10.0)
	var avoidance := _unit._compute_obstacle_avoidance(Vector2(0, -1))
	assert_eq(avoidance, Vector2.ZERO, "侧面太远的障碍物不应触发避让")


# ============================================================
#  避让方向正确性
# ============================================================

func test_avoidance_pushes_left_when_obstacle_right() -> void:
	# 障碍物在前方偏右 → 单位应向左偏转（x < 0）
	_make_obstacle(Vector2(105, 170), 20.0)
	var move_dir := Vector2(0, -1)
	var avoidance := _unit._compute_obstacle_avoidance(move_dir)
	assert_true(avoidance.x < 0.0, "障碍物偏右时应向左偏转（avoidance.x < 0）")


func test_avoidance_pushes_right_when_obstacle_left() -> void:
	# 障碍物在前方偏左 → 单位应向右偏转（x > 0）
	_make_obstacle(Vector2(95, 170), 20.0)
	var move_dir := Vector2(0, -1)
	var avoidance := _unit._compute_obstacle_avoidance(move_dir)
	assert_true(avoidance.x > 0.0, "障碍物偏左时应向右偏转（avoidance.x > 0）")


func test_avoidance_consistent_direction() -> void:
	# 同一配置多次计算应得到一致的避让方向（不抖动）
	_make_obstacle(Vector2(100, 170), 30.0)
	var move_dir := Vector2(0, -1)
	var a1 := _unit._compute_obstacle_avoidance(move_dir)
	var a2 := _unit._compute_obstacle_avoidance(move_dir)
	assert_eq(a1, a2, "同一配置多次计算应得到一致的避让方向")


# ============================================================
#  多障碍物叠加
# ============================================================

func test_symmetric_obstacles_cancel() -> void:
	# 两个对称障碍物（一左一右）→ 横向避让相互抵消
	_make_obstacle(Vector2(90, 170), 20.0)
	_make_obstacle(Vector2(110, 170), 20.0)
	var move_dir := Vector2(0, -1)
	var avoidance := _unit._compute_obstacle_avoidance(move_dir)
	assert_approx(avoidance.x, 0.0, 0.01, "对称障碍物的横向避让应相互抵消")


func test_two_obstacles_same_side_additive() -> void:
	# 两个同侧障碍物 → 避让强度应大于单个
	var tower1 := _make_obstacle(Vector2(100, 175), 30.0)

	var move_dir := Vector2(0, -1)
	var single := _unit._compute_obstacle_avoidance(move_dir)
	tower1.free()
	_mocks.erase(tower1)

	# 重新创建两个障碍物
	_make_obstacle(Vector2(100, 175), 30.0)
	_make_obstacle(Vector2(100, 180), 30.0)
	var combined := _unit._compute_obstacle_avoidance(move_dir)

	assert_true(combined.length() > single.length(),
		"两个障碍物的叠加避让强度应大于单个（%f > %f）" % [combined.length(), single.length()])
