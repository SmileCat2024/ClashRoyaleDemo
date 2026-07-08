# 文件名：DeployPreview.gd
# 作用：卡牌选中后，在鼠标位置显示部署预览。
#       坐标吸附到最近的格中心（snap_to_cell_center）。
#       单位卡：根据 spawn_offsets 显式偏移或确定性圆形分布，显示每个单位的精确落点。
#       法术卡：显示法术半径圆（绿色 = 可施放，红色 = 不可施放）。
#       绿色 = 可部署，红色 = 不可部署。
# 挂载位置：BattleScene/World/DeployPreview
# 初学者阅读建议：先看 show_preview() 了解偏移怎么算，再看 _draw() 了解怎么画。

extends Node2D

## 是否处于激活状态（有卡牌被选中）
var _active: bool = false

## 每个单位相对于部署中心的偏移（World 本地游戏空间，像素）
var _offsets: Array = []

## 当前吸附后的格中心位置（World 本地游戏空间）
var _snapped_pos: Vector2 = Vector2.ZERO

## 当前位置是否在可部署区域内
var _valid: bool = false

## 是否是法术卡牌预览
var _is_spell: bool = false

## 法术半径（像素，仅法术卡有效）
var _spell_radius: float = 0.0

## 预览方块半边长（匹配 UnitBase body size 16px → 半边 8）
const PREVIEW_HALF := 8.0

## Arena 引用，用于校验部署位置
@onready var _arena: Node2D = get_node_or_null("../Arena")


## 设置当前选中的卡牌数据，计算预览内容并显示。
func show_preview(card_data: Dictionary) -> void:
	_is_spell = (card_data.get("card_type") == "spell")
	if _is_spell:
		_spell_radius = BattleConstants.px(float(card_data.get("spell_radius", 0)))
		_offsets = []
	else:
		var count := int(card_data.get("spawn_count", 1))
		var spread_px := BattleConstants.px(float(card_data.get("spawn_spread", 0.0)))
		var offsets_data = card_data.get("spawn_offsets", null)
		_offsets = SpawnManager.get_spawn_offsets(count, spread_px, offsets_data)
	_active = true
	queue_redraw()


## 隐藏预览（取消选中或部署完成后调用）。
func hide_preview() -> void:
	_active = false
	_is_spell = false
	queue_redraw()


func _process(_delta: float) -> void:
	if not _active:
		return
	# 鼠标位置吸附到格中心
	var raw_pos := get_local_mouse_position()
	_snapped_pos = BattleConstants.snap_to_cell_center(raw_pos)
	_valid = _check_valid()
	queue_redraw()


## 检查中心格是否在可部署区域内（法术卡用全图判定）。
func _check_valid() -> bool:
	if _arena == null:
		return false
	if _is_spell:
		if not _arena.has_method("is_spell_deploy_position"):
			return false
		return _arena.is_spell_deploy_position(_snapped_pos)
	if not _arena.has_method("is_player_deploy_position"):
		return false
	return _arena.is_player_deploy_position(_snapped_pos)


func _draw() -> void:
	if not _active:
		return
	var color := Color(0.3, 0.85, 0.3) if _valid else Color(0.9, 0.25, 0.2)
	var fill := Color(color.r, color.g, color.b, 0.3)

	if _is_spell:
		# 法术：画半径圆 + 中心标记
		draw_circle(_snapped_pos, _spell_radius, fill)
		draw_arc(_snapped_pos, _spell_radius, 0, TAU, 64, color, 2.0)
		# 中心十字标记
		draw_line(_snapped_pos - Vector2(6, 0), _snapped_pos + Vector2(6, 0), color, 1.5)
		draw_line(_snapped_pos - Vector2(0, 6), _snapped_pos + Vector2(0, 6), color, 1.5)
	else:
		# 单位：画每个落点方块
		for offset in _offsets:
			var pos: Vector2 = _snapped_pos + offset
			var rect := Rect2(pos.x - PREVIEW_HALF, pos.y - PREVIEW_HALF, PREVIEW_HALF * 2, PREVIEW_HALF * 2)
			draw_rect(rect, fill, true)
			draw_rect(rect, color, false, 1.5)
