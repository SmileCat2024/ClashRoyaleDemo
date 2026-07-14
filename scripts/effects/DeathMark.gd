# 文件名：DeathMark.gd
# 作用：精英技能「死亡俯冲」的目标标记视觉——目标脚下出现的黑色标志。
#       外圈黑色实线圆环 + 内部半透明填充 + X 形十字，表现"处决标记"的视觉语义。
#       支持两种模式：
#         1. 持续模式（spawn_persistent）：技能可用时被动跟踪血量最低敌人，由外部
#            调用 update_position() 跟随目标移动，调用 expire() 触发渐隐销毁。
#         2. 定时模式（spawn）：一次性出现，duration 秒后自动渐隐销毁（冲刺到达瞬间用）。
# 挂载位置：不挂载到场景树。由 UnitBase 创建/管理。
#
# 联机说明：纯视觉。当前精英技能系统整体未接入联机 RPC（见 CLAUDE.md 局限性 17）。

class_name DeathMark
extends Node2D

## 默认显示时长（秒，定时模式用）。前 70% 全亮度，后 30% 快速渐隐。
const DEFAULT_DURATION: float = 2.0
## 渲染层级（高于普通单位，保证标记不被遮挡）
const MARK_Z_INDEX: int = 55

## 外圈半径（像素）
var _radius: float = 0.0
## 总显示时长（秒，仅定时模式用）
var _duration: float = DEFAULT_DURATION
## 已经过去的时间（秒）
var _elapsed: float = 0.0
## 是否为持续模式（不自动销毁，由外部 expire() 控制）
var _persistent: bool = false
## 是否正在渐隐中
var _fading: bool = false
## 渐隐已用时间
var _fade_elapsed: float = 0.0
## 渐隐总时长
const FADE_DURATION: float = 0.4
## 脉冲动画时间（持续模式下标志轻微呼吸）
var _pulse_time: float = 0.0


## 持续模式工厂：创建一个不自动销毁的标记，由外部 update_position() 跟随 + expire() 销毁。
static func spawn_persistent(parent: Node, world_pos: Vector2, radius_px: float) -> DeathMark:
	var mark := DeathMark.new()
	mark.position = world_pos
	mark._radius = radius_px
	mark._persistent = true
	mark.z_index = MARK_Z_INDEX
	parent.add_child(mark)
	return mark


## 定时模式工厂：创建一个自动渐隐销毁的一次性标记（冲刺到达瞬间用）。
static func spawn(parent: Node, world_pos: Vector2, radius_px: float,
		duration: float = DEFAULT_DURATION) -> void:
	var mark := DeathMark.new()
	mark.position = world_pos
	mark._radius = radius_px
	mark._duration = duration
	mark.z_index = MARK_Z_INDEX
	parent.add_child(mark)


## 更新标记位置（持续模式，跟随目标移动）
func update_position(world_pos: Vector2) -> void:
	position = world_pos


## 触发渐隐销毁（持续模式由外部调用）
func expire() -> void:
	if _fading:
		return
	_fading = true
	_fade_elapsed = 0.0


func _process(delta: float) -> void:
	_pulse_time += delta
	if _fading:
		_fade_elapsed += delta
		if _fade_elapsed >= FADE_DURATION:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return

	# alpha 计算
	var alpha: float = 1.0
	if _fading:
		alpha = 1.0 - _fade_elapsed / FADE_DURATION
	elif not _persistent:
		# 定时模式：前 70% 全亮度，后 30% 线性渐隐
		var fade_start := _duration * 0.7
		if _elapsed > fade_start:
			alpha = 1.0 - (_elapsed - fade_start) / (_duration - fade_start)
	alpha = clampf(alpha, 0.0, 1.0)

	# 持续模式下轻微脉冲呼吸（半径 +2px 波动）
	var pulse: float = 0.0
	if _persistent and not _fading:
		pulse = sin(_pulse_time * 4.0) * 2.0
	var r := _radius + pulse

	var black := Color(0.0, 0.0, 0.0, alpha)

	# 外圈实线圆环（较粗）
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, black, 2.5)
	# 内部半透明填充圆（更暗的地面染色）
	draw_circle(Vector2.ZERO, r * 0.85, Color(0.0, 0.0, 0.0, alpha * 0.35))
	# X 形十字（两条对角线），表现"处决/死亡"标记
	var arm_len := r * 0.6
	draw_line(Vector2(-arm_len, -arm_len), Vector2(arm_len, arm_len), black, 2.0)
	draw_line(Vector2(-arm_len, arm_len), Vector2(arm_len, -arm_len), black, 2.0)
