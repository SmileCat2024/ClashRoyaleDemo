# 文件名：test_battle_constants.gd
# 作用：测试 BattleConstants 的格→像素转换和坐标常量。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：看各 test_ 方法了解 BattleConstants 的用法。

extends TestBase


func test_px_converts_cells_to_pixels() -> void:
	assert_eq(BattleConstants.px(1.0), 20.0, "1格=20px")
	assert_eq(BattleConstants.px(2.5), 50.0, "2.5格=50px")
	assert_eq(BattleConstants.px(0.0), 0.0, "0格=0px")


func test_cell_size() -> void:
	assert_eq(BattleConstants.CELL_SIZE, 20, "CELL_SIZE 应为 20")


func test_arena_dimensions() -> void:
	assert_eq(BattleConstants.ARENA_WIDTH, 360, "18格宽=360px")
	assert_eq(BattleConstants.ARENA_HEIGHT, 640, "32格高=640px")


func test_river_position() -> void:
	assert_eq(BattleConstants.RIVER_Y_MIN, 300.0, "河道上界=15格=300px")
	assert_eq(BattleConstants.RIVER_Y_MAX, 340.0, "河道下界=17格=340px")


func test_bridge_positions() -> void:
	assert_eq(BattleConstants.LEFT_BRIDGE_X_MIN, 50.0, "左桥左界")
	assert_eq(BattleConstants.LEFT_BRIDGE_X_MAX, 90.0, "左桥右界")
	assert_eq(BattleConstants.RIGHT_BRIDGE_X_MIN, 270.0, "右桥左界")
	assert_eq(BattleConstants.RIGHT_BRIDGE_X_MAX, 310.0, "右桥右界")


func test_tower_positions_exist() -> void:
	var keys = BattleConstants.TOWER_PIXEL_POSITIONS.keys()
	assert_true(keys.has("EnemyKingTower"), "应包含敌方国王塔")
	assert_true(keys.has("PlayerKingTower"), "应包含玩家国王塔")
	assert_true(keys.has("EnemyLeftTower"), "应包含敌方左公主塔")
	assert_true(keys.has("PlayerRightTower"), "应包含玩家右公主塔")
	# 检查总数
	assert_eq(keys.size(), 6, "共6座塔")
