# 文件名：RangeVfx.gd
# 作用：范围圆视觉统一样式——渐变环（外圈实线边框 + 内侧较短距离内颜色渐变到透明）。
#       用于两种场景，配色不同：
#         1. 爆炸瞬间范围视觉（红色）：MortarShell / SpellProjectile / ArrowsSpellController / DelayedDamageEffect
#         2. 拖动部署预览范围（白色）：DeployPreview 的法术半径圆 + 建筑攻击范围圆
#       本类只管"怎么画"，不管生命周期/创建销毁——后者由调用方或 BlastRingEffect 负责。
# 挂载位置：不需要挂载。通过 class_name 注册为全局类型，静态方法调用。
# 初学者阅读建议：看 draw_gradient_ring() 一处即可，参数不多。

class_name RangeVfx

## 渐变带默认占半径的比例（"较短距离"≈18%）
const DEFAULT_BAND_RATIO: float = 0.18
## 渐变带叠加层数（同心 arc 数量，越多越平滑）
const GRADIENT_LAYERS: int = 10
## 默认外圈边框线宽（像素）
const DEFAULT_BORDER_WIDTH: float = 2.0
## 默认最大不透明度
const DEFAULT_MAX_ALPHA: float = 0.85

## 爆炸范围视觉默认配色（鲜红）
const COLOR_BLAST: Color = Color(1.0, 0.25, 0.12)
## 拖动预览范围视觉默认配色（白色）
const COLOR_PREVIEW: Color = Color(1.0, 1.0, 1.0)


## 绘制渐变环：外圈实线边框 + 内侧较短距离内颜色从满 alpha 渐变到透明。
## canvas: 执行绘制的 CanvasItem（在 _draw() 中传 self）
## center: 圆心（canvas 本地坐标）
## outer_radius: 外圈半径（像素）
## color: 环颜色（RGB 分量，alpha 由 max_alpha 控制）
## max_alpha: 边框最大不透明度 [0,1]，渐变带 alpha 从此值向内递减
## band_ratio: 渐变带宽度占外圈半径的比例 (0,1]，值越大渐变范围越宽
## border_width: 外圈实线边框宽度（像素）
static func draw_gradient_ring(canvas: CanvasItem, center: Vector2, outer_radius: float,
		color: Color, max_alpha: float = DEFAULT_MAX_ALPHA,
		band_ratio: float = DEFAULT_BAND_RATIO,
		border_width: float = DEFAULT_BORDER_WIDTH) -> void:
	if outer_radius <= 0.0 or max_alpha <= 0.0:
		return
	var band_width: float = outer_radius * band_ratio
	# 外圈实线边框
	canvas.draw_arc(center, outer_radius, 0.0, TAU, 64,
			Color(color.r, color.g, color.b, max_alpha), border_width)
	# 内侧渐变带：从外到内画 N 条同心 arc（细环线），alpha 从高到低。
	# 每个 arc 宽度略大于步进（step+0.5）使相邻环线轻微重叠，避免缝隙，形成连续渐变。
	var step: float = band_width / float(GRADIENT_LAYERS)
	for i in GRADIENT_LAYERS:
		var r: float = outer_radius - step * (float(i) + 0.5)
		if r <= 0.0:
			break
		# t: 0(最外层) → 1(最内层)，alpha 从 max_alpha*0.7 递减到 0
		var t: float = float(i) / float(GRADIENT_LAYERS)
		var a: float = max_alpha * (1.0 - t) * 0.7
		canvas.draw_arc(center, r, 0.0, TAU, 48,
				Color(color.r, color.g, color.b, a), step + 0.5)
