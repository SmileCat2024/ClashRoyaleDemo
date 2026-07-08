# 文件名：test_unit_separation.gd
# 作用：测试 UnitBase._compute_unit_separation() —— 单位间分离转向。
#       覆盖：基础分离、空中豁免、距离过滤、静态障碍排除、切向投影、对称抵消。
# 挂载位置：TestRunner.tscn 中作为子节点（由 TestRunner 实例化）。
# 初学者阅读建议：先看 setup() 了解测试环境搭建，再看各 test_ 方法。

extends TestBase

const UnitBaseScript := preload("res://scripts/entities/UnitBase.gd")
const MockScript := preload("res://scripts/tests/MockCombatant.gd")

var _mocks: Array = []
var _unit: UnitBase

func setup() -> void:
	EntityRegistry.clear()
	_mocks.clear()
	_unit = UnitBaseScript.new()
	_unit.team = "player"
	_unit.movement_type = "ground"
	_unit.collision_radius = 10.0
	_unit.mass = 5
	_unit.position = Vector2(100, 200)
	_unit.initialized = true

func teardown() -> void:
	EntityRegistry.clear()
	for m in _mocks:
		if is_instance_valid(m):
			m.free()
	_mocks.clear()
	if _unit and is_instance_valid(_unit):
		_unit.free()


## 创建一个模拟单位（mass > 0，可被分离逻辑检测到）
func _make_unit(pos: Vector2, radius: float = 10.0, mt: String = "ground") -> CombatantBase:
	var m := MockScript.new()
	m.team = "player"
	m.mass = 5
	m.collision_radius = radius
	m.movement_type = mt
	m.position = pos
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	return m


# ============================================================
#  基础分离
# ============================================================

func test_nearby_unit_produces_separation() -> void:
	_make_unit(Vector2(100, 185))  # 15px ahead, within trigger range (10+10+10=30)
	var move_dir := Vector2(0, -1)  # moving up
	var sep := _unit._compute_unit_separation(move_dir)
	assert_true(sep.length() > 0.01, "附近有单位时应产生分离向量")

func test_no_nearby_unit_zero() -> void:
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_eq(sep, Vector2.ZERO, "无附近单位时分离向量应为零")

func test_air_unit_zero() -> void:
	_unit.movement_type = "air"
	_make_unit(Vector2(100, 185), 10.0, "air")
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_eq(sep, Vector2.ZERO, "空中单位不受分离影响")


# ============================================================
#  距离过滤
# ============================================================

func test_distant_unit_skipped() -> void:
	# trigger_range = 10 + 10 + 10(px) = 30. Unit at 35px away → skip
	_make_unit(Vector2(100, 165))  # 35px ahead
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_eq(sep, Vector2.ZERO, "超出触发范围的单位应被跳过")

func test_different_layer_skipped() -> void:
	_make_unit(Vector2(100, 185), 10.0, "air")  # air unit, _unit is ground
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_eq(sep, Vector2.ZERO, "不同移动层的单位应被跳过")

func test_static_obstacle_skipped() -> void:
	# mass=0 → handled by obstacle avoidance, not separation
	var m := MockScript.new()
	m.team = "enemy"
	m.mass = 0
	m.collision_radius = 30.0
	m.movement_type = "ground"
	m.position = Vector2(100, 185)
	m.initialized = true
	EntityRegistry.register(m)
	_mocks.append(m)
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_eq(sep, Vector2.ZERO, "mass=0 的静态障碍物应由障碍物避让处理，不触发单位分离")


# ============================================================
#  切向投影（核心：侧滑而非停推）
# ============================================================

func test_separation_tangential_dominant() -> void:
	# 单位正前方 → 原始推力纯径向（向后）
	# 切向投影后：径向分量被压缩到 20%，切向分量全保留
	# 正前方时切向=0，径向被压缩 → 结果应很小
	_make_unit(Vector2(100, 185))
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	# 正前方单位的分离力被切向投影大幅削减（只剩 20% 径向 × 0.5 强度）
	assert_true(sep.length() < 0.15, "正前方单位分离力应被切向投影大幅削减（侧滑优先）")

func test_off_center_unit_pushes_sideways() -> void:
	# 单位偏右前方 → 有明显切向分量
	_make_unit(Vector2(115, 190))
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_true(sep.length() > 0.01, "偏侧单位应产生分离向量")
	# move_dir=(0,-1), perp=(1,0). 偏右的单位 → 推力向左 → tangential.x < 0
	assert_true(sep.x < 0.0, "偏右的单位应将分离力推向左侧（切向分量主导）")

func test_directly_behind_ignored() -> void:
	# 身后的单位不产生分离（dist > trigger_range 且方向不符）
	_make_unit(Vector2(100, 215))  # behind
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_eq(sep, Vector2.ZERO, "身后的单位不应触发分离")


# ============================================================
#  多单位交互
# ============================================================

func test_symmetric_units_cancel() -> void:
	# 左右对称的两个单位 → 切向分量相互抵消
	_make_unit(Vector2(85, 195))   # left
	_make_unit(Vector2(115, 195))  # right
	var move_dir := Vector2(0, -1)
	var sep := _unit._compute_unit_separation(move_dir)
	assert_approx(sep.x, 0.0, 0.02, "左右对称单位的切向分离力应相互抵消")

func test_same_side_amplify() -> void:
	var single := _make_unit(Vector2(115, 190))
	var move_dir := Vector2(0, -1)
	var sep1 := _unit._compute_unit_separation(move_dir)

	# 加一个同侧单位
	var double_unit := _make_unit(Vector2(120, 195))
	var sep2 := _unit._compute_unit_separation(move_dir)

	assert_true(sep2.length() > sep1.length(), "同侧多单位应使分离力增大")
	# 清理额外单位避免影响后续测试
	_mocks.erase(double_unit)
	if is_instance_valid(double_unit):
		EntityRegistry.unregister(double_unit)
		double_unit.free()
