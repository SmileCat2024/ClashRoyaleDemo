# 文件名：DeathMark.gd
# 作用：精英技能「死亡俯冲」的目标标记视觉——目标脚下出现的处决标志。
#       外圈实线圆环 + 内部半透明填充 + X 形十字，表现"处决标记"的视觉语义。
#       敌我颜色区分：我方重甲亡灵锁定的标志泛蓝，敌方锁定的标志泛红（主体仍为深色）。
#       支持两种模式：
#         1. 持续模式（spawn_persistent）：技能可用时被动跟踪血量最低敌人，由外部
#            调用 update_position() 跟随目标移动，调用 expire() 立即销毁（无渐隐，
#            目标切换时旧标志直接消失再出现新标志，切换干脆）。
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

## 我方重甲亡灵锁定敌方时的标志基色（深蓝黑，整体偏黑稍微泛蓝）
const COLOR_PLAYER_TINT := Color(0.04, 0.12, 0.28)
## 敌方重甲亡灵锁定我方时的标志基色（深红黑，整体偏黑稍微泛红）
const COLOR_ENEMY_TINT := Color(0.30, 0.08, 0.06)

## 外圈半径（像素）
var _radius: float = 0.0
## 总显示时长（秒，仅定时模式用）
var _duration: float = DEFAULT_DURATION
## 已经过去的时间（秒）
var _elapsed: float = 0.0
## 是否为持续模式（不自动销毁，由外部 expire() 控制）
var _persistent: bool = false
## 标志主色（线条/X 十字用，按释放方 team 区分蓝/红倾向）
var _mark_color: Color = COLOR_PLAYER_TINT
## 脉冲动画时间（持续模式下标志轻微呼吸）
var _pulse_time: float = 0.0


## 持续模式工厂：创建一个不自动销毁的标记，由外部 update_position() 跟随 + expire() 销毁。
## team 为释放技能的单位阵营（"player" 泛蓝 / "enemy" 泛红），用于敌我颜色区分。
static func spawn_persistent(parent: Node, world_pos: Vector2, radius_px: float,
		team: String = "player") -> DeathMark:
	var mark := DeathMark.new()
	mark.position = world_pos
	mark._radius = radius_px
	mark._persistent = true
	mark._mark_color = COLOR_PLAYER_TINT if team == "player" else COLOR_ENEMY_TINT
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


## 立即销毁标记（持续模式由外部调用）。无渐隐——目标切换时旧标志直接消失，
## 新标志随后出现，实现干脆的切换效果。
func expire() -> void:
	queue_free()


func _process(delta: float) -> void:
	_pulse_time += delta
	if not _persistent:
		_elapsed += delta
		if _elapsed >= _duration:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return

	# alpha 计算（仅定时模式末期渐隐；持续模式始终全亮度，由 expire() 直接销毁）
	var alpha: float = 1.0
	if not _persistent:
		var fade_start := _duration * 0.7
		if _elapsed > fade_start:
			alpha = 1.0 - (_elapsed - fade_start) / (_duration - fade_start)
	alpha = clampf(alpha, 0.0, 1.0)

	# 持续模式下轻微脉冲呼吸（半径 +2px 波动）
	var pulse: float = 0.0
	if _persistent:
		pulse = sin(_pulse_time * 4.0) * 2.0
	var r := _radius + pulse

	var line_color := Color(_mark_color.r, _mark_color.g, _mark_color.b, alpha)

	# 外圈实线圆环（较粗）
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, line_color, 2.5)
	# 内部半透明填充圆（更暗的地面染色）
	draw_circle(Vector2.ZERO, r * 0.85, Color(_mark_color.r, _mark_color.g, _mark_color.b, alpha * 0.35))
	# X 形十字（两条对角线），表现"处决/死亡"标记
	var arm_len := r * 0.6
	draw_line(Vector2(-arm_len, -arm_len), Vector2(arm_len, arm_len), line_color, 2.0)
	draw_line(Vector2(-arm_len, arm_len), Vector2(arm_len, -arm_len), line_color, 2.0)
