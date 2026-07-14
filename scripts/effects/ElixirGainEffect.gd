# 文件名：ElixirGainEffect.gd
# 作用：圣水收集器产出时的纯视觉提示。以 World 本地坐标生成，不参与战斗结算。

class_name ElixirGainEffect
extends Node2D

const ELIXIR_TEXTURE := preload("res://assets/ui/圣水.png")


static func spawn(parent: Node, world_pos: Vector2, amount: int, is_death: bool) -> void:
	if parent == null or amount <= 0:
		return
	var effect := ElixirGainEffect.new()
	effect.position = world_pos
	effect.z_index = 80
	parent.add_child(effect)
	effect._setup(amount, is_death)


func _setup(amount: int, is_death: bool) -> void:
	var icon := Sprite2D.new()
	icon.texture = ELIXIR_TEXTURE
	icon.position = Vector2(0.0, -34.0)
	icon.scale = Vector2(0.032, 0.032 / BattleConstants.Y_COMPRESS)
	add_child(icon)

	var label := Label.new()
	label.text = "+%d" % amount
	label.position = Vector2(14.0, -49.0)
	label.scale = Vector2(1.0, 1.0 / BattleConstants.Y_COMPRESS)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("f4d5ff"))
	label.add_theme_color_override("font_outline_color", Color("56206d"))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

	if is_death:
		icon.modulate = Color("ffd4ff")
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 24.0, 0.75)
	tween.tween_property(self, "modulate:a", 0.0, 0.75).set_delay(0.2)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
