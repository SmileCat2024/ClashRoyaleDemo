# 文件名：SkillButton.gd
# 作用：单个精英技能按钮。圆形深色背景 + 金色描边 + 中心费用 + 冷却遮罩。
#       可用时金色脉冲呼吸提醒玩家点击，冷却中变暗显示倒计时。
#       由 SkillBar 动态创建（精英单位生成时）和销毁（单位死亡时）。
# 挂载位置：SkillBar 下动态创建（不放在 .tscn 里）。
# 初学者阅读建议：先看 setup() 了解初始化，再看 _draw() 了解视觉绘制。

class_name SkillButton
extends Button

var _unit: Node = null              ## 关联的精英单位
var _skill_data: Dictionary = {}    ## 技能配置

var _cooldown_remaining: float = 0.0  ## 当前冷却剩余（秒，本地递减）
var _cooldown_total: float = 0.0      ## 总冷却时间
var _is_ready: bool = true            ## 当前是否可用（无冷却）
var _pulse_time: float = 0.0          ## 脉冲动画累加（可用时呼吸效果）

# ── 视觉配色 ──
const BG_READY     := Color(0.18, 0.12, 0.32, 0.92)   # 深紫底（精英品质感）
const BG_COOLDOWN  := Color(0.10, 0.10, 0.10, 0.85)   # 冷却暗灰底
const BORDER_GOLD  := Color(1.0, 0.82, 0.30)          # 金色描边
const BORDER_DIM   := Color(0.40, 0.40, 0.40)         # 冷却灰描边
const BORDER_HOVER := Color(1.0, 1.0, 0.55)           # hover 亮金
const COST_COLOR   := Color(0.55, 0.90, 1.0)          # 青色费用数字
const COOLDOWN_TEXT_COLOR := Color(0.95, 0.95, 0.95)  # 白色倒计时


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	# 不使用 Button 默认渲染，完全自定义 _draw
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("disabled", empty)
	# 不用 Button.text（我们自己画）
	text = ""
	clip_contents = false
	pressed.connect(_on_pressed)


## 初始化按钮内容。由 SkillBar 在创建后调用。
func setup(unit: Node, skill_data: Dictionary) -> void:
	_unit = unit
	_skill_data = skill_data
	_is_ready = true
	_cooldown_remaining = 0.0


## 点击按钮 → 请求释放技能（BattleManager 做能量检查和瞄准处理）
func _on_pressed() -> void:
	if _unit and is_instance_valid(_unit) and not _unit.is_dead:
		SignalBus.elite_skill_requested.emit(_unit, _skill_data)


## 更新冷却显示。由 SkillBar 转发 elite_skill_cooldown_changed 信号调用。
func update_cooldown(remaining: float, total: float) -> void:
	_cooldown_total = total
	_cooldown_remaining = remaining
	if remaining > 0:
		disabled = true
		_is_ready = false
	else:
		disabled = false
		_is_ready = true
	queue_redraw()


func _process(delta: float) -> void:
	# 本地冷却倒计时平滑递减（不依赖每帧 RPC）
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta
		if _cooldown_remaining <= 0:
			update_cooldown(0.0, _cooldown_total)
		else:
			queue_redraw()
	# 可用时脉冲呼吸动画
	if _is_ready:
		_pulse_time += delta
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius: float = min(size.x, size.y) / 2.0 - 3.0

	# ── 背景圆 ──
	var bg := BG_READY if _is_ready else BG_COOLDOWN
	# 可用时轻微脉冲（亮度随 sin 呼吸）
	if _is_ready:
		var pulse := 0.5 + 0.5 * sin(_pulse_time * 3.0)  # 0~1
		bg = bg.lerp(Color(0.30, 0.20, 0.50, 0.92), pulse * 0.4)
	draw_circle(center, radius, bg)

	# ── 描边 ──
	var border_color: Color
	if not _is_ready:
		border_color = BORDER_DIM
	elif is_hovered():
		border_color = BORDER_HOVER
	else:
		# 可用时描边也跟着脉冲
		var pulse := 0.5 + 0.5 * sin(_pulse_time * 3.0)
		border_color = BORDER_GOLD.lerp(BORDER_HOVER, pulse * 0.35)
	# 外圈粗描边 + 内圈细线双重视觉
	draw_arc(center, radius, 0, TAU, 36, border_color, 2.5)
	draw_arc(center, radius - 3.0, 0, TAU, 36, border_color.lerp(Color.BLACK, 0.3), 1.0)

	# ── 中心内容 ──
	if _is_ready:
		_draw_cost(center)
	else:
		_draw_cooldown(center)


## 绘制费用数字（可用状态）
func _draw_cost(center: Vector2) -> void:
	var cost := int(_skill_data.get("cost", 0))
	var name := str(_skill_data.get("display_name", "?"))
	var font := get_theme_default_font()
	# 费用数字（大号，居中偏上）
	var cost_str := str(cost)
	var cost_size := 20
	var cost_y := center.y - 4
	draw_string(font, Vector2(center.x - 7, cost_y + 6), cost_str,
		HORIZONTAL_ALIGNMENT_CENTER, -1, cost_size, COST_COLOR)
	# 加粗描边效果（画一遍黑色偏移）
	for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(font, Vector2(center.x - 7 + offset.x, cost_y + 6 + offset.y), cost_str,
			HORIZONTAL_ALIGNMENT_CENTER, -1, cost_size, Color.BLACK)
	draw_string(font, Vector2(center.x - 7, cost_y + 6), cost_str,
		HORIZONTAL_ALIGNMENT_CENTER, -1, cost_size, COST_COLOR)

	# 技能名缩写（小字，底部）——取前 2 字
	var short_name := name.substr(0, 2)
	draw_string(font, Vector2(center.x - 7, center.y + 14), short_name,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.85, 0.85, 0.85))


## 绘制冷却倒计时（冷却状态）
func _draw_cooldown(center: Vector2) -> void:
	# 半透明黑色遮罩圆（加深暗化感）
	draw_circle(center, min(size.x, size.y) / 2.0 - 6.0, Color(0, 0, 0, 0.35))
	var font := get_theme_default_font()
	var remain_str := "%.1f" % max(0.0, _cooldown_remaining)
	# 描边
	for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(font, Vector2(center.x - 10 + offset.x, center.y + 6 + offset.y), remain_str,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.BLACK)
	draw_string(font, Vector2(center.x - 10, center.y + 6), remain_str,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 14, COOLDOWN_TEXT_COLOR)
