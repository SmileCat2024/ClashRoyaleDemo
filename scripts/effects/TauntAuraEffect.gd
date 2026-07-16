# 文件名：TauntAuraEffect.gd
# 作用：被「圣光嘲讽」单位身上的淡金色状态标识。纯视觉，生命周期由 AttackComponent 刷新/解除。

class_name TauntAuraEffect
extends Node2D

const NODE_NAME := "TauntAuraEffect"
# 状态标识与法阵使用同一套偏黄色圣光，只降低透明度以免遮挡单位。
const GOLD := Color(1.0, 0.90, 0.08)
const FADE_DURATION := 0.22
const Z_INDEX := 65

var _remaining: float = 0.0
var _elapsed: float = 0.0


## 附着到被嘲讽实体。已有标识时直接刷新，避免多攻击组件造成重复光效。
static func attach(owner: Node2D, duration: float) -> TauntAuraEffect:
	var existing := owner.get_node_or_null(NodePath(NODE_NAME)) as TauntAuraEffect
	if existing != null:
		existing.refresh(duration)
		return existing
	var aura := TauntAuraEffect.new()
	aura.name = NODE_NAME
	aura._remaining = duration
	aura.z_index = Z_INDEX
	owner.add_child(aura)
	return aura


## 刷新至完整持续时间，用于同一单位被多次施加嘲讽的情形。
func refresh(duration: float) -> void:
	_remaining = maxf(duration, 0.0)


## 嘲讽解除后快速淡出，不会突然消失。
func expire() -> void:
	_remaining = minf(_remaining, FADE_DURATION)


func _process(delta: float) -> void:
	_elapsed += delta
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var owner_radius := 10.0
	var parent_node := get_parent()
	if parent_node != null:
		var value = parent_node.get("collision_radius")
		if value != null:
			owner_radius = float(value)
	var radius := maxf(owner_radius + 4.0, 14.0)
	var fade_in := clampf(_elapsed / 0.14, 0.0, 1.0)
	var fade_out := clampf(_remaining / FADE_DURATION, 0.0, 1.0)
	var alpha := 0.34 * fade_in * minf(fade_out, 1.0)
	var foot_center := Vector2(0.0, 4.0)
	# 低透明度脚下光环：不遮挡模型，但在混战中能看出嘲讽目标。
	draw_arc(foot_center, radius, 0.0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, alpha), 1.3)
	draw_arc(foot_center, radius * 0.72, 0.0, TAU, 40, Color(1.0, 0.97, 0.42, alpha * 0.55), 1.0)
	# 四个缓慢环绕的微光点，为状态增加一点圣光感而不制造高亮噪声。
	for i in range(4):
		var angle := _elapsed * 2.4 + TAU * float(i) / 4.0
		var offset := Vector2(cos(angle), sin(angle) * 0.42) * radius * 0.83
		draw_circle(foot_center + offset, 1.8, Color(1.0, 0.96, 0.34, alpha * 0.85))
