# 文件名：ArrowProjectile.gd
# 作用：单根箭矢实体——从国王塔区域沿抛物线飞向落点，插在地上后停留，渐隐消失。
#       万箭齐发法术的视觉组成单元，由 ArrowsSpellController 批量生成。
#       用白色细线渲染，飞行中带地面影子（2.5D）。
#
#       继承 ProjectileBase：飞行步进和进度追踪由基类 _fly_toward / _fly_progress 统一处理。
#       本类无 Body 子节点（纯 _draw 渲染），基类 body_rect 为 null 时自动跳过弧高偏移。
# 挂载位置：由 ArrowsSpellController 用 .new() 创建，add_child 到 ProjectilesRoot
# 初学者阅读建议：看 setup() 了解初始化参数，看 _draw_flying() 了解抛物线箭矢朝向计算。

extends ProjectileBase

const ARROW_LENGTH: float = 10.0       ## 箭杆长度（像素）
const STUCK_DURATION: float = 2.0      ## 插地停留时间（秒）
const FADE_DURATION: float = 0.8       ## 渐隐时间（秒）
const STUCK_VISIBLE_RATIO: float = 0.55 ## 插地后可见部分占箭杆比例
const FLETCHING_LEN: float = 3.0       ## 羽尾长度（像素）
const FLETCHING_SPREAD: float = 1.5    ## 羽尾展开宽度（像素）
const FLETCHING_ALPHA: float = 0.4     ## 羽尾透明度（弱点缀）

var _state: String = "flying"  ## flying → stuck → fading → queue_free

# 飞行参数使用基类字段：_start_pos / _last_target_pos / speed / _total_dist / arc_height

# 停留 / 渐隐
var _timer: float = 0.0
var _alpha: float = 1.0

# 插地随机倾斜
var _tilt: float = 0.0


## origin: 发射点 | target: 落点 | speed_grids: 速度（格/秒）| arc_grids: 弧高（格）
## 注意：父类 ProjectileBase.setup 签名不同，此处用 setup_flight 避免冲突
func setup_flight(origin: Vector2, target: Vector2, speed_grids: float, arc_grids: float) -> void:
	position = origin
	_start_pos = origin
	_last_target_pos = target
	speed = BattleConstants.px(speed_grids)
	_total_dist = origin.distance_to(target)
	arc_height = arc_grids
	_tilt = randf_range(-0.35, 0.35)
	z_index = 30
	_state = "flying"


func _process(delta: float) -> void:
	match _state:
		"flying":
			if _fly_toward(_last_target_pos, delta):
				_state = "stuck"
				_timer = 0.0
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
	var progress := _fly_progress()

	# 抛物线视觉高度偏移
	var arc_offset := compute_arc_offset(arc_height, progress)
	var head := Vector2(0, -arc_offset)

	# 抛物线切线方向 = 水平位移 + 弧高导数
	var dx := _last_target_pos.x - _start_pos.x
	var dy := (_last_target_pos.y - _start_pos.y) - arc_height * BattleConstants.CELL_SIZE * PI * cos(progress * PI)
	var tangent := Vector2(dx, dy)
	if tangent.length() > 0.5:
		tangent = tangent.normalized()
	else:
		tangent = (_last_target_pos - _start_pos).normalized() if _total_dist > 0.5 else Vector2.DOWN

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
