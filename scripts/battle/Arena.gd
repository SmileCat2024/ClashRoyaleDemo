# 文件名：Arena.gd
# 作用：管理战场背景绘制、部署区域判定。
#       负责回答"这个位置玩家能不能放单位"等问题。
# 挂载位置：BattleScene/Arena（Arena.tscn 的根节点）
# 初学者阅读建议：先看 is_player_deploy_position()，了解部署区域怎么判断。

extends Node2D

## 是否绘制调试网格（每格 20 像素的辅助线）
@export var show_debug_grid: bool = true

@onready var _map_bg: Sprite2D = $MapBackground


func _ready() -> void:
	# 地图底板脱离 World 的 Y 压缩变换，保持原始比例不变形
	_map_bg.top_level = true
	var img_w: float = _map_bg.texture.get_width()
	var s: float = float(BattleConstants.VIEWPORT_WIDTH) / img_w
	_map_bg.scale = Vector2(s, s)
	# 居中于竞技场游戏区域（不受视口高度变化影响）
	_map_bg.position = Vector2(
		BattleConstants.VIEWPORT_WIDTH * 0.5,
		BattleConstants.ARENA_TOP_OFFSET_Y + BattleConstants.ARENA_SCREEN_HEIGHT * 0.5,
	)
	_map_bg.z_index = -1  # 底板下沉，所有游戏元素画在其上


## 判断一个世界坐标是否在玩家可部署区域内（己方半场，河道下方）
func is_player_deploy_position(pos: Vector2) -> bool:
	return pos.y >= BattleConstants.PLAYER_DEPLOY_Y_MIN \
		and pos.y <= BattleConstants.PLAYER_DEPLOY_Y_MAX \
		and pos.x >= BattleConstants.px(0.5) and pos.x <= BattleConstants.ARENA_WIDTH - BattleConstants.px(0.5)


## 判断一个世界坐标是否在敌方可部署区域内（敌方半场，河道上方）
func is_enemy_deploy_position(pos: Vector2) -> bool:
	return pos.y >= BattleConstants.ENEMY_DEPLOY_Y_MIN \
		and pos.y <= BattleConstants.ENEMY_DEPLOY_Y_MAX \
		and pos.x >= BattleConstants.px(0.5) and pos.x <= BattleConstants.ARENA_WIDTH - BattleConstants.px(0.5)


## 在敌方部署区域内随机选一个位置
func get_random_enemy_deploy_position() -> Vector2:
	var x = randf_range(BattleConstants.px(1.5), BattleConstants.ARENA_WIDTH - BattleConstants.px(1.5))
	var y = randf_range(
		BattleConstants.ENEMY_DEPLOY_Y_MIN + BattleConstants.CELL_SIZE,
		BattleConstants.ENEMY_DEPLOY_Y_MAX - BattleConstants.CELL_SIZE
	)
	return Vector2(x, y)


## 找到离给定位置最近的路线 X 坐标（左路或右路）
func get_nearest_lane_x(pos: Vector2) -> float:
	var dist_left = abs(pos.x - BattleConstants.LEFT_LANE_X)
	var dist_right = abs(pos.x - BattleConstants.RIGHT_LANE_X)
	if dist_left <= dist_right:
		return BattleConstants.LEFT_LANE_X
	return BattleConstants.RIGHT_LANE_X


## _draw()：绘制调试网格 + 河道/桥/塔/路线/坐标，帮助校验 18×32 布局
func _draw() -> void:
	if not show_debug_grid:
		return

	var ts := BattleConstants.CELL_SIZE
	var w := BattleConstants.ARENA_WIDTH
	var h := BattleConstants.ARENA_HEIGHT

	# --- 河道填充 ---
	var river_h := BattleConstants.RIVER_Y_MAX - BattleConstants.RIVER_Y_MIN
	draw_rect(Rect2(0, BattleConstants.RIVER_Y_MIN, w, river_h), Color(0.15, 0.35, 0.75, 0.2))

	# --- 桥填充 ---
	var bridge_color := Color(0.7, 0.55, 0.25, 0.55)
	draw_rect(Rect2(BattleConstants.LEFT_BRIDGE_X_MIN, BattleConstants.RIVER_Y_MIN, \
		BattleConstants.LEFT_BRIDGE_X_MAX - BattleConstants.LEFT_BRIDGE_X_MIN, river_h), bridge_color)
	draw_rect(Rect2(BattleConstants.RIGHT_BRIDGE_X_MIN, BattleConstants.RIVER_Y_MIN, \
		BattleConstants.RIGHT_BRIDGE_X_MAX - BattleConstants.RIGHT_BRIDGE_X_MIN, river_h), bridge_color)

	# --- 网格线（含边界，0~18 竖线 / 0~32 横线，游戏空间坐标）---
	var grid_color := Color(1, 0.9, 0.4, 0.35)
	for x in range(0, BattleConstants.MAP_TILES_W + 1):
		draw_line(Vector2(x * ts, 0), Vector2(x * ts, h), grid_color)
	for y in range(0, BattleConstants.MAP_TILES_H + 1):
		draw_line(Vector2(0, y * ts), Vector2(w, y * ts), grid_color)

	# --- 路线中心线（黄色虚线）---
	_draw_dashed_vline(BattleConstants.LEFT_LANE_X, 0, h, ts * 0.5, Color(1, 1, 0, 0.3))
	_draw_dashed_vline(BattleConstants.RIGHT_LANE_X, 0, h, ts * 0.5, Color(1, 1, 0, 0.3))

	# --- 塔占位框（矩形边框 + 中心十字 + 半透明填充）---
	var ec := Color(0.9, 0.3, 0.2)
	var pc := Color(0.2, 0.5, 0.9)
	_draw_tower_footprint(BattleConstants.TOWER_PIXEL_POSITIONS["EnemyKingTower"], BattleConstants.KING_TOWER_SIZE, ec)
	_draw_tower_footprint(BattleConstants.TOWER_PIXEL_POSITIONS["EnemyLeftTower"], BattleConstants.GUARD_TOWER_SIZE, ec)
	_draw_tower_footprint(BattleConstants.TOWER_PIXEL_POSITIONS["EnemyRightTower"], BattleConstants.GUARD_TOWER_SIZE, ec)
	_draw_tower_footprint(BattleConstants.TOWER_PIXEL_POSITIONS["PlayerLeftTower"], BattleConstants.GUARD_TOWER_SIZE, pc)
	_draw_tower_footprint(BattleConstants.TOWER_PIXEL_POSITIONS["PlayerRightTower"], BattleConstants.GUARD_TOWER_SIZE, pc)
	_draw_tower_footprint(BattleConstants.TOWER_PIXEL_POSITIONS["PlayerKingTower"], BattleConstants.KING_TOWER_SIZE, pc)

	# --- 坐标标注（列号在顶部，行号在左侧）---
	var font := ThemeDB.fallback_font
	var lc := Color(1, 1, 0.3, 0.7)
	for x in range(0, BattleConstants.MAP_TILES_W):
		draw_string(font, Vector2(x * ts + 2, ts - 3), str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)
	for y in range(0, BattleConstants.MAP_TILES_H):
		draw_string(font, Vector2(2, y * ts + ts - 3), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)


## 绘制塔占位框：半透明填充 + 矩形边框 + 中心十字
func _draw_tower_footprint(center: Vector2, size: Vector2, color: Color) -> void:
	var rect := Rect2(center.x - size.x * 0.5, center.y - size.y * 0.5, size.x, size.y)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.12))
	draw_rect(rect, color, false, 2.0)
	draw_line(Vector2(center.x - 4, center.y), Vector2(center.x + 4, center.y), color, 1.0)
	draw_line(Vector2(center.x, center.y - 4), Vector2(center.x, center.y + 4), color, 1.0)


## 绘制竖直虚线
func _draw_dashed_vline(x: float, y_min: float, y_max: float, dash_len: float, color: Color) -> void:
	var y := y_min
	while y < y_max:
		draw_line(Vector2(x, y), Vector2(x, min(y + dash_len, y_max)), color)
		y += dash_len * 2.0
