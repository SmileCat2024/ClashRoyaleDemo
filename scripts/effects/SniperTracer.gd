# 文件名：SniperTracer.gd
# 作用：觉醒女枪狙击弹的飞行子弹视觉。从枪口飞向目标，命中时产生闪光。
#       纯视觉节点（伤害在 _fire_sniper 中即时结算），不参与逻辑。
# 挂载位置：动态创建，add_child 到 UnitsRoot（与单位同层 y-sort）。
# 初学者阅读建议：看 spawn() 工厂方法和 _draw() 子弹绘制即可。
#
# 联机说明：纯视觉。调用方在 host 和 client 两端各 spawn 一次，无需额外 RPC 同步。

class_name SniperTracer
extends Node2D

# ---- 飞行参数 ----
const SPEED: float = 1800.0          ## 飞行速度（像素/秒，~90 格/秒，极快）
const ARRIVAL_THRESHOLD: float = 5.0 ## 到达目标的判定距离（像素）

# ---- 子弹外观 ----
const BULLET_LENGTH: float = 30.0        ## 子弹核心长度（像素）
const BULLET_HALF_WIDTH: float = 4.0     ## 子弹核心半宽
const GLOW_HALF_WIDTH: float = 9.0       ## 光晕半宽
const TRACER_Z_INDEX: int = 58           ## 渲染层级（高于单位和普通投射物）

# ---- 命中闪光 ----
const IMPACT_DURATION: float = 0.18      ## 闪光持续时间（秒）
const IMPACT_MAX_RADIUS: float = 18.0    ## 闪光最大半径

# ---- 运行时状态 ----
var _dest: Vector2 = Vector2.ZERO        ## 目标位置（World 本地游戏空间）
var _angle: float = 0.0                  ## 飞行方向弧度（用于子弹朝向）
var _traveling: bool = true              ## true=飞行中, false=命中闪光阶段
var _impact_elapsed: float = 0.0         ## 闪光已过时间
var _on_arrival: Callable = Callable()   ## 子弹到达目标时的回调（用于延迟伤害结算）


## 工厂方法：创建一发狙击子弹并添加到场景树。
## parent: 父节点（通常是 UnitsRoot）
## from:   发射位置（World 本地游戏空间）
## to:     目标位置
## on_arrival: 可选，子弹到达目标时调用（延迟伤害结算，使伤害时机匹配视觉）
static func spawn(parent: Node, from: Vector2, to: Vector2, on_arrival: Callable = Callable()) -> void:
	var tracer := SniperTracer.new()
	tracer.position = from
	tracer._dest = to
	tracer._angle = (to - from).angle()
	tracer._on_arrival = on_arrival
	tracer.z_index = TRACER_Z_INDEX
	parent.add_child(tracer)


func _process(delta: float) -> void:
	if _traveling:
		var to_dest := _dest - position
		if to_dest.length() <= ARRIVAL_THRESHOLD:
			_traveling = false
			_impact_elapsed = 0.0
			# 子弹到达目标 → 触发回调（延迟伤害结算，使伤害时机匹配视觉）
			if _on_arrival.is_valid():
				_on_arrival.call()
		else:
			position += to_dest.normalized() * SPEED * delta
	else:
		_impact_elapsed += delta
		if _impact_elapsed >= IMPACT_DURATION:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _traveling:
		_draw_bullet()
	else:
		_draw_impact_flash()


## 飞行中的子弹：朝向目标方向的尖锐子弹 + 光晕拖尾 + 明亮弹头。
func _draw_bullet() -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)

	# 1. 外层光晕（宽、暖橙色、半透明）——拖尾效果
	var glow_pts := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(-BULLET_LENGTH - 4.0, -GLOW_HALF_WIDTH),
		Vector2(-BULLET_LENGTH - 8.0, 0.0),
		Vector2(-BULLET_LENGTH - 4.0, GLOW_HALF_WIDTH),
	])
	draw_colored_polygon(glow_pts, Color(1.0, 0.5, 0.1, 0.28))

	# 2. 核心子弹（亮黄白色，尖锐菱形）
	var core_pts := PackedVector2Array([
		Vector2(BULLET_HALF_WIDTH * 0.9, 0.0),                # 尖锐前端
		Vector2(-BULLET_LENGTH, -BULLET_HALF_WIDTH),          # 尾部上
		Vector2(-BULLET_LENGTH - 4.0, 0.0),                   # 尾部中
		Vector2(-BULLET_LENGTH, BULLET_HALF_WIDTH),           # 尾部下
	])
	draw_colored_polygon(core_pts, Color(1.0, 0.92, 0.55, 0.95))

	# 3. 明亮弹头（前端亮点）
	draw_circle(Vector2.ZERO, BULLET_HALF_WIDTH * 0.7, Color(1.0, 1.0, 0.85, 1.0))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 命中闪光：扩散环 + 内侧亮斑，快速渐隐。
func _draw_impact_flash() -> void:
	var t: float = clampf(_impact_elapsed / IMPACT_DURATION, 0.0, 1.0)
	var alpha: float = 1.0 - t
	var radius: float = lerpf(BULLET_HALF_WIDTH * 1.5, IMPACT_MAX_RADIUS, t)
	# 外环
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 16, Color(1.0, 0.8, 0.3, alpha * 0.5), 2.0)
	# 内侧亮斑
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 1.0, 0.8, alpha * 0.6))
