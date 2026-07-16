# 文件名：TauntHolyCircleEffect.gd
# 作用：精英骑士「圣光嘲讽」的金色法阵视觉。法阵由内向外快速建立，随后柔和淡出。
#       仅负责表现；范围筛选和嘲讽状态由 UnitBase / AttackComponent 处理。

class_name TauntHolyCircleEffect
extends Node2D

# 更偏亮黄的圣光，与红色爆炸环和白色预览环明显区分。
const GOLD := Color(1.0, 0.90, 0.08)
const INNER_GOLD := Color(1.0, 0.97, 0.42)
const HOLD_DURATION := 0.28
const Z_INDEX := 55

var _radius: float = 0.0
var _formation_duration: float = 0.35
var _elapsed: float = 0.0


static func spawn(parent: Node, world_pos: Vector2, radius_px: float,
		formation_duration: float = 0.35) -> void:
	var effect := TauntHolyCircleEffect.new()
	effect.position = world_pos
	effect._radius = radius_px
	effect._formation_duration = maxf(formation_duration, 0.01)
	effect.z_index = Z_INDEX
	parent.add_child(effect)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _formation_duration + HOLD_DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return
	var build_t := clampf(_elapsed / _formation_duration, 0.0, 1.0)
	var ease_t := 1.0 - pow(1.0 - build_t, 3.0)
	var fade_t := 1.0
	if _elapsed > _formation_duration:
		fade_t = 1.0 - clampf((_elapsed - _formation_duration) / HOLD_DURATION, 0.0, 1.0)
	var radius := _radius * ease_t
	var alpha := 0.85 * fade_t
	# 双环 + 内侧渐变光晕，形成圣光边界。
	RangeVfx.draw_gradient_ring(self, Vector2.ZERO, radius, GOLD, alpha, 0.15, 2.6)
	RangeVfx.draw_gradient_ring(self, Vector2.ZERO, radius * 0.68, INNER_GOLD, alpha * 0.55, 0.12, 1.4)
	# 六向辐射线与短横符文，使它更像可辨识的法阵而非普通范围提示。
	for i in range(6):
		var angle := TAU * float(i) / 6.0 - PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var start := direction * radius * 0.73
		var end := direction * radius * 0.93
		draw_line(start, end, Color(INNER_GOLD.r, INNER_GOLD.g, INNER_GOLD.b, alpha * 0.75), 1.6)
		var rune_center := direction * radius * 0.80
		var tangent := Vector2(-direction.y, direction.x)
		draw_line(rune_center - tangent * 4.0, rune_center + tangent * 4.0,
			Color(GOLD.r, GOLD.g, GOLD.b, alpha * 0.70), 1.4)
