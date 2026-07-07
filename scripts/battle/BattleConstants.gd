# 文件名：BattleConstants.gd
# 作用：集中存放战斗相关的常量（坐标、尺寸、颜色等）。
#       核心设计：所有尺寸用"格"定义，通过 CELL_SIZE 转为像素。
#       调整 CELL_SIZE 即可整体缩放画面，无需改任何数据。
# 挂载位置：不需要挂载到节点。通过 class_name 注册为全局类型。
# 初学者阅读建议：先看 CELL_SIZE 和画面布局，再看分区坐标。

class_name BattleConstants

# ============================================================
#  核心度量单位：格系统
# ============================================================
#  一格对应的像素边长。调整此值即可整体缩放画面。
#  所有距离/速度/范围在 DataRegistry 中以格为单位，
#  在实体 setup() 时通过 BattleConstants.px() 转为像素。
# ============================================================

const CELL_SIZE := 20

## 2.5D 透视 Y 压缩比。
## 1.0 = 无压缩（正交俯视）；< 1.0 = Y 方向压缩（模拟俯视透视）。
## 调整此值即可改变 2.5D 透视强弱，无需改任何其他代码。
const Y_COMPRESS := 0.7863

## 格 → 像素（便捷转换）
static func px(cells: float) -> float:
	return cells * CELL_SIZE

# ============================================================
#  画面布局（格）
# ============================================================

const MAP_TILES_W := 18     ## 竞技场宽度（格）
const MAP_TILES_H := 32     ## 竞技场高度（格，游戏空间。屏幕高度 = 此值 × Y_COMPRESS）
const VIEW_EXTRA_ROWS := 4  ## 底部卡牌槽位区（格）
const VIEWPORT_BORDER_CELLS := 2  ## 视口左右各比竞技场多出的边距格数（显示地图底板边框）

## 游戏空间尺寸（逻辑坐标，所有实体的 position 在此空间）
const ARENA_WIDTH := MAP_TILES_W * CELL_SIZE    ## 360
const ARENA_HEIGHT := MAP_TILES_H * CELL_SIZE   ## 640（游戏空间高度）

## 屏幕空间尺寸（玩家实际看到的）
const ARENA_SCREEN_HEIGHT := ARENA_HEIGHT * Y_COMPRESS  ## 480
const VIEWPORT_WIDTH := (MAP_TILES_W + VIEWPORT_BORDER_CELLS * 2) * CELL_SIZE  ## 440
## 必须与 project.godot 一致（竞技场压缩高度 + 上下留白 + 卡牌区）
const VIEWPORT_HEIGHT := 780

## 地图底板在视口中的垂直定位参考值。
## 注意：这不是逻辑坐标，也不是寻路坐标；战斗逻辑只使用 World 本地游戏空间。
const ARENA_TOP_OFFSET_Y := 99.0  ## 固定值，不随视口高度变化
## 视口左右留白的设计宽度。只用于视口/底板/UI 对齐，不参与战斗逻辑。
const ARENA_OFFSET_X := VIEWPORT_BORDER_CELLS * CELL_SIZE                        ## 40

# ============================================================
#  坐标体系说明（视口 / 游戏空间 / 地图底板三者独立）
# ============================================================
#  1) 视口空间：
#    project.godot 的窗口裁剪范围，当前 440×780。
#    BattleScene / World / CanvasLayer 可以为了显示对齐而有 position/offset。
#
#  2) World 本地游戏空间（唯一逻辑坐标，所有 BattleConstants 坐标都在此空间）：
#    原点(0,0)在左上角，y 增大 = 往下走
#    竞技场区域：x=0–360, y=0–640（32格 × CELL_SIZE）
#    实体自身移动用 position；跨父节点读目标时先转成 World.to_local(global_position)。
#    禁止把 global_position 直接和河道/桥/塔常量混算。
#
#  3) 地图底板图：
#    MapBackground top_level=true，脱离 World 的 Y 压缩。
#    它的位置只影响底图显示，不改变游戏空间里的河道、桥、塔坐标。
#
#  鼠标输入通过 world.get_local_mouse_position() 自动逆变换回游戏空间。
#  改 Y_COMPRESS 后，屏幕高度自动变化，project.godot 视口需同步。
# ============================================================

# ============================================================
#  河道与桥（CELL_SIZE 推导）
# ============================================================

## 河道：格 y=15–17 区间（地图中心 y=16，镜像对称）
const RIVER_Y_MIN := CELL_SIZE * 15.0   ## 300
const RIVER_Y_MAX := CELL_SIZE * 17.0   ## 340

## 左桥：格 x=2.5–4.5
const LEFT_BRIDGE_X_MIN := CELL_SIZE * 2.5   ## 50
const LEFT_BRIDGE_X_MAX := CELL_SIZE * 4.5   ## 90

## 右桥：对称 → 格 x=13.5–15.5
const RIGHT_BRIDGE_X_MIN := CELL_SIZE * 13.5  ## 270
const RIGHT_BRIDGE_X_MAX := CELL_SIZE * 15.5  ## 310

# ============================================================
#  部署区域（CELL_SIZE 推导）
#  玩家只能在己方半场陆地（河道下方）部署
#  敌方只能在敌方半场陆地（河道上方）部署
# ============================================================

const PLAYER_DEPLOY_Y_MIN := CELL_SIZE * 17.0   ## 340 河道下边界
const PLAYER_DEPLOY_Y_MAX := CELL_SIZE * 31.75  ## 635 接近竞技场底部
const ENEMY_DEPLOY_Y_MIN := CELL_SIZE * 0.25    ## 5   接近竞技场顶部
const ENEMY_DEPLOY_Y_MAX := CELL_SIZE * 14.95   ## 299 河道上边界

# ============================================================
#  路线（与桥对齐）
# ============================================================

const LEFT_LANE_X := CELL_SIZE * 3.5    ## 70  格 x=3.5 左桥中心
const RIGHT_LANE_X := CELL_SIZE * 14.5  ## 290 格 x=14.5 右桥中心

# ============================================================
#  塔位置（CELL_SIZE 推导）
# ============================================================

const TOWER_PIXEL_POSITIONS := {
	# 敌方（上方，y 小）— 距上边沿空1格
	"EnemyKingTower":   Vector2(CELL_SIZE * 9.0, CELL_SIZE * 3.0),     ## (180, 60)   格(9, 3)
	"EnemyLeftTower":   Vector2(CELL_SIZE * 3.5, CELL_SIZE * 6.5),     ## (70, 130)   格(3.5, 6.5) 塔边缘距河道边缘7格
	"EnemyRightTower":  Vector2(CELL_SIZE * 14.5, CELL_SIZE * 6.5),    ## (290, 130)  格(14.5, 6.5) 塔边缘距河道边缘7格
	# 玩家（下方，y 大）— 镜像于敌方（32 - 敌方y）
	"PlayerLeftTower":  Vector2(CELL_SIZE * 3.5, CELL_SIZE * 25.5),    ## (70, 510)   格(3.5, 25.5)
	"PlayerRightTower": Vector2(CELL_SIZE * 14.5, CELL_SIZE * 25.5),   ## (290, 510)  格(14.5, 25.5)
	"PlayerKingTower":  Vector2(CELL_SIZE * 9.0, CELL_SIZE * 29.0),    ## (180, 580)  格(9, 29)
}

## 塔占位尺寸（CELL_SIZE 推导）
const KING_TOWER_SIZE := Vector2(CELL_SIZE * 4.0, CELL_SIZE * 4.0)    ## (80, 80) 4×4 格
const GUARD_TOWER_SIZE := Vector2(CELL_SIZE * 3.0, CELL_SIZE * 3.0)   ## (60, 60) 3×3 格

# ============================================================
#  颜色
# ============================================================

const COLOR_PLAYER := Color(0.2, 0.5, 0.9)
const COLOR_ENEMY := Color(0.9, 0.3, 0.2)
const COLOR_PLAYER_TOWER := Color(0.15, 0.35, 0.7)
const COLOR_ENEMY_TOWER := Color(0.75, 0.2, 0.15)

# ============================================================
#  坐标转换工具
# ============================================================

## 设计格坐标（y=0 己方底部，y增大=往上）→ Godot 像素坐标（y增大=往下）
static func tile_to_pixel(tile_x: float, tile_y: float) -> Vector2:
	var px = tile_x * CELL_SIZE
	var py = (float(MAP_TILES_H) - 0.5 - tile_y) * CELL_SIZE
	return Vector2(px, py)


## 将任意像素坐标吸附到最近的格中心。
## 格 n 的中心在 (n + 0.5) * CELL_SIZE，例如格0中心 = 10px，格1中心 = 30px。
## 部署、法术释放等操作都先经过此函数对齐到格中心。
static func snap_to_cell_center(pos: Vector2) -> Vector2:
	var cx := floori(pos.x / CELL_SIZE) * CELL_SIZE + CELL_SIZE / 2
	var cy := floori(pos.y / CELL_SIZE) * CELL_SIZE + CELL_SIZE / 2
	return Vector2(cx, cy)
