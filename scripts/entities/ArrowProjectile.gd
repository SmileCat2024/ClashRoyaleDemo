# 文件名：ArrowProjectile.gd
# 作用：单根箭矢实体——从国王塔区域沿抛物线飞向落点，插在地上后停留，渐隐消失。
#       万箭齐发法术的视觉组成单元，由 ArrowsSpellController 批量生成。
#       用白色细线渲染，飞行中带地面影子（2.5D）。
# 挂载位置：由 ArrowsSpellController 用 .new() 创建，add_child 到 ProjectilesRoot
# 初学者阅读建议：看 setup() 了解初始化参数，看 _draw_flying() 了解抛物线箭矢朝向计算。

extends Node2D

const ARROW_LENGTH: float = 10.0       ## 箭杆长度（像素）
const STUCK_DURATION: float = 2.0      ## 插地停留时间（秒）
const FADE_DURATION: float = 0.8       ## 渐隐时间（秒）
const STUCK_VISIBLE_RATIO: float = 0.55 ## 插地后可见部分占箭杆比例
const FLETCHING_LEN: float = 3.0       ## 羽尾长度（像素）
const FLETCHING_SPREAD: float = 1.5    ## 羽尾展开宽度（像素）
const FLETCHING_ALPHA: float = 0.4     ## 羽尾透明度（弱点缀）

var _state: String = "flying"  ## flying → stuck → fading → queue_free

# 飞行参数
var _origin: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _speed: float = 0.0           ## 像素/秒
var _flight_dist: float = 0.0
var _arc_height_px: float = 0.0   ## 抛物线峰值高度（像素）

# 停留 / 渐隐
var _timer: float = 0.0
var _alpha: float = 1.0

# 插地随机倾斜
var _tilt: float = 0.0


## origin: 发射点 | target: 落点 | speed_grids: 速度（格/秒）| arc_grids: 弧高（格）
func setup(origin: Vector2, target: Vector2, speed_grids: float, arc_grids: float) -> void:
	_origin = origin
	_target = target
	position = origin
	_speed = BattleConstants.px(speed_grids)
	_flight_dist = origin.distance_to(target)
	_arc_height_px = arc_grids * BattleConstants.CELL_SIZE
	_tilt = randf_range(-0.35, 0.35)
	z_index = 30
	_state = "flying"


func _process(delta: float) -> void:
	match _state:
		"flying":
			var to_target := _target - position
			var dist := to_target.length()
			if dist <= _speed * delta or dist < 0.5:
				position = _target
				_state = "stuck"
				_timer = 0.0
				queue_redraw()
			else:
				position += to_target.normalized() * _speed * delta
				queue_redraw()
		"stuck":
			_timer += delta
			if _timer >= STUCK_DURATION:
				_state = "fading"
				_timer = 0.0
		"fading":
			_timer += delta
			_alpha = 1.0 - (_timer / FADE_DURATION)
			if _timer >= FADE_DURATION:
				queue_free()
			queue_redraw()


func _draw() -> void:
	if _state == "flying":
		_draw_flying()
	else:
		_draw_stuck()


func _draw_flying() -> void:
	var progress := 0.0
	if _flight_dist > 0.5:
		progress = clampf(_origin.distance_to(position) / _flight_dist, 0.0, 1.0)

	# 抛物线视觉高度偏移
	var arc_offset := _arc_height_px * sin(progress * PI)
	var head := Vector2(0, -arc_offset)

	# 抛物线切线方向 = 水平位移 + 弧高导数
	var dx := _target.x - _origin.x
	var dy := (_target.y - _origin.y) - _arc_height_px * PI * cos(progress * PI)
	var tangent := Vector2(dx, dy)
	if tangent.length() > 0.5:
		tangent = tangent.normalized()
	else:
		tangent = (_target - _origin).normalized() if _flight_dist > 0.5 else Vector2.DOWN

	var tail := head - tangent * ARROW_LENGTH

	# 地面影子
	draw_rect(Rect2(-1.5, -1.0, 3.0, 2.0), Color(0, 0, 0, 0.12))
	# 箭矢
	draw_line(tail, head, Color(1, 1, 1, 1.0), 1.5)
	# 羽尾：尾部两片淡羽毛（弱点缀）
	var perp := Vector2(-tangent.y, tangent.x)
	var fc := Color(0.85, 0.85, 0.92, FLETCHING_ALPHA)
	var fletch_back := tail - tangent * FLETCHING_LEN
	draw_line(tail, fletch_back + perp * FLETCHING_SPREAD, fc, 1.0)
	draw_line(tail, fletch_back - perp * FLETCHING_SPREAD, fc, 1.0)


func _draw_stuck() -> void:
	var visible_len := ARROW_LENGTH * STUCK_VISIBLE_RATIO
	var head := Vector2(sin(_tilt) * visible_len, -cos(_tilt) * visible_len)
	draw_line(Vector2.ZERO, head, Color(1, 1, 1, _alpha), 1.5)
	# 羽尾：顶端两片淡羽毛（弱点缀）
	var dir := head.normalized() if head.length() > 0.5 else Vector2.UP
	var perp := Vector2(-dir.y, dir.x)
	var fc := Color(0.85, 0.85, 0.92, _alpha * FLETCHING_ALPHA)
	var fletch_tip := head + dir * FLETCHING_LEN
	draw_line(head, fletch_tip + perp * FLETCHING_SPREAD, fc, 1.0)
	draw_line(head, fletch_tip - perp * FLETCHING_SPREAD, fc, 1.0)
