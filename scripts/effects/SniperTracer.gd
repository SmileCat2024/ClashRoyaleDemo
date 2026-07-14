# 文件名：SniperTracer.gd
# 作用：觉醒女枪狙击弹的飞行子弹视觉 + 命中爆炸特效。
#       子弹阶段：大尺寸发光弹丸 + 拖尾光带，高速飞向目标。
#       命中阶段：白色闪爆 + 扩散冲击波 + 放射状火花线 + 余光渐隐。
#       纯视觉节点，伤害通过 on_arrival 回调延迟结算。
# 挂载位置：动态创建，add_child 到 UnitsRoot（与单位同层 y-sort）。
# 初学者阅读建议：看 spawn() 工厂方法和 _draw_* 系列方法即可。
#
# 联机说明：纯视觉。调用方在 host 和 client 两端各 spawn 一次，无需额外 RPC 同步。

class_name SniperTracer
extends Node2D

# ---- 飞行参数 ----
const SPEED: float = 2200.0          ## 飞行速度（像素/秒，~110 格/秒）
const ARRIVAL_THRESHOLD: float = 6.0 ## 到达目标的判定距离（像素）

# ---- 子弹外观（加大加粗，更醒目）----
const BULLET_LENGTH: float = 42.0        ## 子弹核心长度（像素）
const BULLET_HALF_WIDTH: float = 6.0     ## 子弹核心半宽
const GLOW_HALF_WIDTH: float = 14.0      ## 光晕半宽
const TRAIL_LENGTH: float = 55.0         ## 拖尾光带长度
const TRACER_Z_INDEX: int = 58           ## 渲染层级（高于单位和普通投射物）

# ---- 命中爆炸 ----
const IMPACT_DURATION: float = 0.35      ## 爆炸总持续时间（秒）
const IMPACT_FLASH_RADIUS: float = 36.0  ## 初始白闪半径
const IMPACT_RING_MAX: float = 55.0      ## 冲击波最大半径
const SPARK_COUNT: int = 8               ## 放射状火花线数量
const SPARK_MAX_LEN: float = 32.0        ## 火花最大长度

# ---- 运行时状态 ----
var _dest: Vector2 = Vector2.ZERO        ## 目标位置（World 本地游戏空间）
var _angle: float = 0.0                  ## 飞行方向弧度（用于子弹朝向）
var _traveling: bool = true              ## true=飞行中, false=命中爆炸阶段
var _impact_elapsed: float = 0.0         ## 爆炸已过时间
var _on_arrival: Callable = Callable()   ## 子弹到达目标时的回调（延迟伤害结算）


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
		var distance := to_dest.length()
		var step := SPEED * delta
		# 本帧能跨过终点时直接吸附到目标，避免高速弹丸在终点两侧来回越界。
		# 越界会导致 tracer 长时间悬停、与后续狙击弹叠加，且命中特效延迟出现。
		if distance <= ARRIVAL_THRESHOLD or step >= distance:
			position = _dest
			_traveling = false
			_impact_elapsed = 0.0
			# 子弹到达目标 → 触发回调（延迟伤害结算）
			if _on_arrival.is_valid():
				_on_arrival.call()
		else:
			position += to_dest / distance * step
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
		_draw_impact()


# ===== 子弹飞行阶段 =====

## 大尺寸发光子弹：拖尾光带 + 光晕 + 核心弹体 + 弹头亮点。
func _draw_bullet() -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)

	# 1. 拖尾光带（最长最宽，暖橙→透明渐变三角形）
	var trail_pts := PackedVector2Array([
		Vector2(0.0, -BULLET_HALF_WIDTH * 0.8),
		Vector2(-TRAIL_LENGTH, 0.0),
		Vector2(0.0, BULLET_HALF_WIDTH * 0.8),
	])
	draw_colored_polygon(trail_pts, Color(1.0, 0.6, 0.15, 0.22))

	# 2. 外层光晕（宽、暖橙色，大半透明四边形）
	var glow_pts := PackedVector2Array([
		Vector2(BULLET_HALF_WIDTH, 0.0),
		Vector2(-BULLET_LENGTH, -GLOW_HALF_WIDTH),
		Vector2(-BULLET_LENGTH - 6.0, 0.0),
		Vector2(-BULLET_LENGTH, GLOW_HALF_WIDTH),
	])
	draw_colored_polygon(glow_pts, Color(1.0, 0.55, 0.1, 0.30))

	# 3. 核心弹体（亮黄白色，大尖锐菱形）
	var core_pts := PackedVector2Array([
		Vector2(BULLET_HALF_WIDTH * 1.2, 0.0),              # 尖锐前端
		Vector2(-BULLET_LENGTH, -BULLET_HALF_WIDTH),         # 尾部上
		Vector2(-BULLET_LENGTH - 5.0, 0.0),                  # 尾部中
		Vector2(-BULLET_LENGTH, BULLET_HALF_WIDTH),          # 尾部下
	])
	draw_colored_polygon(core_pts, Color(1.0, 0.95, 0.6, 1.0))

	# 4. 弹头亮白核心（前端最亮点，纯白）
	draw_circle(Vector2.ZERO, BULLET_HALF_WIDTH * 0.85, Color(1.0, 1.0, 1.0, 1.0))

	# 5. 弹头外圈柔光（淡黄白圈，增加存在感）
	draw_arc(Vector2.ZERO, BULLET_HALF_WIDTH * 1.6, 0.0, TAU, 12, Color(1.0, 0.9, 0.5, 0.4), 2.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ===== 命中爆炸阶段 =====

## 多层命中特效：白闪 + 冲击波 + 放射火花 + 中心余光。
func _draw_impact() -> void:
	var t: float = clampf(_impact_elapsed / IMPACT_DURATION, 0.0, 1.0)
	var alpha: float = 1.0 - t

	# 1. 中心白色闪爆（快速缩小，开始几帧几乎全白）
	var flash_t := clampf(t / 0.25, 0.0, 1.0)  # 闪爆在前 25% 时间内完成
	var flash_alpha: float = (1.0 - flash_t) * 0.85
	var flash_r: float = lerpf(IMPACT_FLASH_RADIUS, IMPACT_FLASH_RADIUS * 0.3, flash_t)
	draw_circle(Vector2.ZERO, flash_r, Color(1.0, 1.0, 0.9, flash_alpha))

	# 2. 扩散冲击波环（快速向外扩散，线宽递减）
	var ring_r: float = lerpf(IMPACT_FLASH_RADIUS * 0.5, IMPACT_RING_MAX, t)
	var ring_w: float = lerpf(4.0, 1.0, t)
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 24, Color(1.0, 0.7, 0.2, alpha * 0.7), ring_w)

	# 3. 次级内环（较慢扩散，增加层次感）
	var inner_r: float = lerpf(IMPACT_FLASH_RADIUS * 0.3, IMPACT_RING_MAX * 0.6, t)
	draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 20, Color(1.0, 0.9, 0.4, alpha * 0.4), 2.0)

	# 4. 放射状火花线（8 条向外辐射，长度随时间变化）
	var spark_alpha: float = alpha * 0.8
	if spark_alpha > 0.01:
		for i in SPARK_COUNT:
			var ang: float = (TAU / SPARK_COUNT) * i + _angle
			var spark_len: float = lerpf(SPARK_MAX_LEN * 0.4, SPARK_MAX_LEN, t)
			var inner_off: float = lerpf(IMPACT_FLASH_RADIUS * 0.3, IMPACT_FLASH_RADIUS * 0.6, t)
			var outer_off: float = inner_off + spark_len
			draw_line(
				Vector2(cos(ang) * inner_off, sin(ang) * inner_off),
				Vector2(cos(ang) * outer_off, sin(ang) * outer_off),
				Color(1.0, 0.85, 0.4, spark_alpha),
				2.0
			)

	# 5. 中心余光（持续到结束，暖色光斑缓慢缩小渐隐）
	var glow_r: float = lerpf(IMPACT_FLASH_RADIUS * 0.5, 4.0, t)
	draw_circle(Vector2.ZERO, glow_r, Color(1.0, 0.8, 0.3, alpha * 0.45))
