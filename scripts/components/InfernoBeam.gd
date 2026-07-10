## ============================================================
## 文件：InfernoBeam.gd
## 作用：地狱塔递增光束视觉组件（2.5D）
## 挂载：UnitBase 子节点（按需创建），坐标系 = 父单位本地坐标
## 阅读：set_params() 由 UnitBase 每帧驱动 → _draw() 分层叠加绘制
## ============================================================
class_name InfernoBeam
extends Node2D

## 移植自 HTML 原型「地狱塔射线：窄束清晰版 v6」
## CanvasItemMaterial = ADD 混合，多层粗细递减模拟 shadowBlur 光晕
## 三阶段参数递进：锁定时间越长，光束越粗、波幅越大、端点越亮

# 每阶段参数表（视觉宽度单位 = 原型像素，由 _pixel_scale 缩放）
# [core_w, glow_w, aura_w, aura_a, edge_amp, edge_n, edge_len, edge_a,
#  streak_amp, streak_n, streak_len, rough, speed, end_glow, sparks_n]
const STAGES: Array[Array] = [
	[2.2, 4.6, 14.0, 0.12, 3.1, 10, 0.060, 0.28, 2.2, 2, 0.14, 0.16, 0.85, 18.0, 3],
	[2.9, 5.8, 20.0, 0.16, 4.8, 14, 0.070, 0.38, 3.8, 3, 0.16, 0.24, 1.12, 25.0, 5],
	[3.8, 7.2, 29.0, 0.20, 7.2, 20, 0.080, 0.50, 6.2, 4, 0.18, 0.34, 1.48, 34.0, 8],
]

# ---- 颜色（移植自原型 rgba）----
const C_AURA_PINK  := Color(1.0, 0.153, 0.443)  # rgba(255,39,113)
const C_AURA_ORANGE:= Color(1.0, 0.360, 0.125)  # rgba(255,92,32)
const C_GLOW       := Color(1.0, 0.592, 0.102, 0.62)  # rgba(255,151,26)
const C_CORE       := Color(1.0, 0.871, 0.192, 0.96)  # rgba(255,222,49)
const C_WHITE      := Color(1.0, 1.0, 0.824, 0.70)    # rgba(255,255,210)
const C_EDGE       := Color(1.0, 0.902, 0.290)        # rgba(255,230,74)
const C_STREAK     := Color(1.0, 0.910, 0.373)        # rgba(255,232,95)

const CORE_SEGMENTS := 36  # 核心束采样段数（原型150，降采样保性能）

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _stage: int = 0
var _time: float = 0.0
var _pixel_scale: float = 1.0


func _ready() -> void:
	## ADD 混合：所有 draw_* 叠加增亮（模拟原型 globalCompositeOperation='lighter'）
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	z_index = 5  # 相对父单位略高，光束画在 sprite 上方


func _process(delta: float) -> void:
	_time += delta


## 由 UnitBase 每帧调用，设置光束起止/阶段并触发重绘
func set_params(from_l: Vector2, to_l: Vector2, stage: int, pixel_scale: float) -> void:
	_from = from_l
	_to = to_l
	_stage = clampi(stage, 0, 2)
	_pixel_scale = pixel_scale
	queue_redraw()


# ---- 数学工具（复刻原型 noise / hash）----

static func _hash01(n: float) -> float:
	return fposmod(sin(n * 12.9898 + 78.233) * 43758.5453123, 1.0)

## 多频率正弦叠加 → 热颤 noise（复刻原型 noise 函数）
static func _noise(s: float, t: float, seedv: float) -> float:
	return (
		sin(s * 18.1 + t * 1.7 + seedv) * 0.46 +
		sin(s * 41.7 - t * 2.1 + seedv * 1.3) * 0.30 +
		sin(s * 96.0 + t * 0.8 - seedv * 1.9) * 0.16 +
		sin(s * 151.0 - t * 3.0 + seedv * 0.7) * 0.08
	)

## 沿采样点集插值取点（复刻原型 pointAt）
static func _point_at(pts: PackedVector2Array, s: float) -> Vector2:
	var last := float(pts.size() - 1)
	var idx := clampf(s * last, 0.0, last)
	var i := int(idx)
	var f := idx - float(i)
	var a: Vector2 = pts[i]
	var b: Vector2 = pts[mini(i + 1, int(last))]
	return a.lerp(b, f)


func _draw() -> void:
	var d := _to - _from
	if d.length() < 2.0:
		return
	var p: Array = STAGES[_stage]
	var sc := _pixel_scale
	var core_w: float = p[0] * sc
	var glow_w: float = p[1] * sc
	var aura_w: float = p[2] * sc
	var aura_a: float = p[3]
	var edge_amp: float = p[4] * sc
	var edge_n: int = p[5]
	var edge_len: float = p[6]
	var edge_a: float = p[7]
	var streak_amp: float = p[8] * sc
	var streak_n: int = p[9]
	var streak_len: float = p[10]
	var rough: float = p[11]
	var speed: float = p[12]
	var end_glow: float = p[13] * sc
	var sparks_n: int = p[14]
	var t := _time
	var n_vec := Vector2(-d.y, d.x).normalized()

	# ---- 构建核心束采样点（noise 抖动 + sin包络）----
	var pts := PackedVector2Array()
	pts.resize(CORE_SEGMENTS)
	for i in CORE_SEGMENTS:
		var s := float(i) / float(CORE_SEGMENTS - 1)
		var env := sin(PI * s)
		var off := _noise(s, t * speed, 2.1) * rough * 1.2 * env
		pts[i] = _from.lerp(_to, s) + n_vec * off

	# ---- 1-2. 红色外光晕（两层粗低alpha，模拟 shadowBlur）----
	_stroke(pts, func(s) -> float: return aura_w * (0.56 + 0.24 * sin(PI * s)),
		Color(C_AURA_PINK.r, C_AURA_PINK.g, C_AURA_PINK.b, aura_a))
	_stroke(pts, func(s) -> float: return aura_w * 0.48 * (0.55 + 0.20 * sin(PI * s)),
		Color(C_AURA_ORANGE.r, C_AURA_ORANGE.g, C_AURA_ORANGE.b, 0.13))

	# ---- 3. 橙色发光层（noise 粗糙度 + beads 颗粒脉动）----
	_stroke(pts, func(s) -> float:
		var r := 1.0 + _noise(s, t * speed * 2.2, 12.0) * rough * 0.45
		var b: float = 0.88 + 0.18 * max(0.0, sin(s * 80.0 - t * speed * 6.0))
		return glow_w * r * b
	, C_GLOW)

	# ---- 4. 黄色核心束（清晰窄束）----
	_stroke(pts, func(s) -> float:
		return core_w * (1.0 + _noise(s, t * speed * 2.8, 20.0) * rough * 0.32)
	, C_CORE)

	# ---- 5. 白色高光芯（极细）----
	_stroke(pts, func(s) -> float: return max(0.55, core_w * 0.22), C_WHITE)

	# ---- 6. 边缘闪烁波纹（两侧短波，热颤）----
	_draw_edge_flicker(pts, n_vec, edge_n, edge_amp, edge_len, edge_a, core_w, speed, t)

	# ---- 7. 波纹条（两侧断续短波丝）----
	_draw_wave_streaks(pts, n_vec, streak_n, streak_amp, streak_len, core_w, speed, t)

	# ---- 8. 端点光球（多层同心圆模拟径向渐变）----
	_draw_glow(_from, end_glow * 0.82)
	_draw_glow(_to, end_glow)

	# ---- 9. 沿线游走火花 ----
	_draw_sparks(pts, n_vec, sparks_n, aura_w, speed, t)


## 分段绘制（每段宽度可变，复刻原型 strokeSegments）
func _stroke(pts: PackedVector2Array, width_fn: Callable, color: Color) -> void:
	var N := pts.size()
	for i in range(1, N):
		var s := (float(i - 1) + float(i)) * 0.5 / float(N - 1)
		var w: float = width_fn.call(s)
		if w < 0.3:
			continue
		draw_line(pts[i - 1], pts[i], color, w)


## 边缘闪烁波纹（原型 drawEdgeFlicker，降采样）
func _draw_edge_flicker(core_pts: PackedVector2Array, n_vec: Vector2,
		count: int, amp: float, seg_len_p: float, alpha: float,
		core_w: float, speed: float, t: float) -> void:
	var samples := 5
	for k in count:
		var seedv := 30.0 + k * 5.37
		var s0 := fposmod(_hash01(seedv) + t * 0.038 * speed * (0.4 + _hash01(seedv + 1)), 1.0)
		var sl := seg_len_p * (0.55 + _hash01(seedv + 2) * 1.35)
		var side := 1.0 if _hash01(seedv + 3) > 0.5 else -1.0
		var gate: float = 0.55 + 0.45 * max(0.0, sin(t * speed * 3.1 + seedv))
		var prev := Vector2.ZERO
		var has_prev := false
		for m in samples:
			var s := clampf(s0 + sl * (float(m) / float(samples - 1) - 0.5), 0.0, 1.0)
			var env := sin(PI * s)
			var base := _point_at(core_pts, s)
			var wave := _noise(s, t * speed * 1.95, seedv) * amp * env
			var offset: float = side * (core_w * 0.65 + abs(wave) * 1.15)
			var pt := base + n_vec * offset
			if has_prev:
				var a := (alpha * 0.55 + alpha * 0.45 * _hash01(seedv + 4)) * gate
				draw_line(prev, pt, Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, a),
					0.8 + core_w * 0.20)
			prev = pt
			has_prev = true


## 波纹条（原型 drawWaveStreaks，降采样）
func _draw_wave_streaks(core_pts: PackedVector2Array, n_vec: Vector2,
		count: int, amp: float, seg_len_p: float,
		core_w: float, speed: float, t: float) -> void:
	var samples := 8
	for k in count:
		var side := 1.0 if k % 2 == 0 else -1.0
		var seedv := 500.0 + k * 7.13
		var center := fposmod(_hash01(seedv) + t * 0.03 * (0.6 + _hash01(seedv + 1)), 1.0)
		var sl := seg_len_p * (0.75 + _hash01(seedv + 2) * 0.65)
		var start := clampf(center - sl * 0.5, 0.0, 1.0)
		var end := clampf(center + sl * 0.5, 0.0, 1.0)
		var span := maxf(0.0001, end - start)
		var prev := Vector2.ZERO
		var has_prev := false
		for m in samples:
			var s := lerpf(start, end, float(m) / float(samples - 1))
			var env := sin(PI * ((s - start) / span))
			var beam_env := sin(PI * s)
			var base := _point_at(core_pts, s)
			var wave := _noise(s, t * speed * 1.55, seedv) * amp * env * beam_env
			var offset := side * (core_w * 0.8 + wave)
			var pt := base + n_vec * offset
			if has_prev:
				draw_line(prev, pt, Color(C_STREAK.r, C_STREAK.g, C_STREAK.b, 0.55),
					1.05 + k * 0.04)
			prev = pt
			has_prev = true


## 端点光球（多层同心圆模拟径向渐变，ADD 叠加增亮）
func _draw_glow(pos: Vector2, radius: float) -> void:
	if radius < 1.0:
		return
	draw_circle(pos, radius * 0.72, Color(1.0, 0.173, 0.510, 0.12))  # 粉红外环
	draw_circle(pos, radius * 0.55, Color(1.0, 0.247, 0.435, 0.20))
	draw_circle(pos, radius * 0.42, Color(1.0, 0.600, 0.149, 0.40))  # 橙
	draw_circle(pos, radius * 0.28, Color(1.0, 0.878, 0.250, 0.70))  # 黄
	draw_circle(pos, radius * 0.15, Color(1.0, 0.973, 0.824, 0.90))  # 暖白芯


## 沿线游走火花（原型 sparks）
func _draw_sparks(core_pts: PackedVector2Array, n_vec: Vector2,
		count: int, aura_w: float, speed: float, t: float) -> void:
	for i in count:
		var seedv := 300.0 + i
		var s := fposmod(_hash01(seedv) + sin(t * (1.1 + _hash01(float(i)) * 1.7) + float(i)) * 0.025, 1.0)
		var q := _point_at(core_pts, s)
		var dist := (_hash01(float(i + 5)) - 0.5) * aura_w * 0.65
		var len := 2.0 + _hash01(float(i + 6)) * (2.0 + float(_stage) * 2.2)
		var col := Color(1.0, 0.882, 0.329, 0.58) if i % 3 != 0 else Color(1.0, 0.227, 0.569, 0.48)
		var p1 := q + n_vec * dist
		var p2 := p1 + Vector2((_hash01(float(i + 7)) - 0.5) * len,
				(_hash01(float(i + 8)) - 0.5) * len)
		draw_line(p1, p2, col, 0.8 + float(_stage) * 0.12)
