# 文件名：BattleHUD.gd
# 作用：战斗界面的总控制器。显示时间、能量、卡牌等信息。
#       HUD 只负责显示和把玩家输入转发出去，不直接生成单位。
# 挂载位置：BattleScene/CanvasLayer/BattleHUD
# 初学者阅读建议：先看 _ready() 了解初始化，再看各 _on_xxx 方法了解显示怎么更新。

extends Control

const TIMER_NORMAL_COLOR := Color.WHITE
const TIMER_WARNING_COLOR := Color(0.95, 0.12, 0.08)
const DARK_OUTLINE_COLOR := Color.BLACK
const COUNTDOWN_COLOR := Color(1.0, 0.68, 0.16)

var _announcement_time_left: float = 0.0
var _announcement_persistent: bool = false
var _presentation_initialized: bool = false
var _last_phase: String = ""
var _last_multiplier: int = -1
var _last_countdown_second: int = -1
var _final_countdown_announced: bool = false


func _ready() -> void:
	SignalBus.energy_changed.connect(_on_energy_changed)
	SignalBus.battle_ended.connect(_on_battle_ended)
	SignalBus.unit_spawned.connect(_on_unit_spawned)
	SignalBus.unit_died.connect(_on_unit_died)
	SignalBus.tower_destroyed.connect(_on_tower_destroyed)
	$EndPanel/VBoxContainer/RestartButton.pressed.connect(_on_restart_button_pressed)
	$EndPanel/VBoxContainer/MenuButton.pressed.connect(_on_menu_button_pressed)
	# 非交互区域穿透鼠标（让点击直达战场），CardBar 保持可交互
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disable_mouse_filter_recursive($TopBar)
	_disable_mouse_filter_recursive($BottomInfo)
	_disable_mouse_filter_recursive($TimerPanel)
	_disable_mouse_filter_recursive($MultiplierIcon)
	_disable_mouse_filter_recursive($BattleAnnouncement)
	$CenterMessageLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 创建精英技能栏（屏幕右侧，卡槽上方；动态创建/移除技能按钮）
	# CanvasLayer offset=(40,0)，viewport 宽 440 → HUD x 必须 ≤ 400-按钮宽 才不被裁
	var skill_bar := SkillBar.new()
	skill_bar.position = Vector2(336, 478)
	skill_bar.size = Vector2(56, 120)
	add_child(skill_bar)
	print("[BattleHUD] ready")


## 递归设置所有子 Control 的 mouse_filter 为 IGNORE
func _disable_mouse_filter_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_disable_mouse_filter_recursive(child)


func _process(_delta: float) -> void:
	if _announcement_time_left > 0.0 and not _announcement_persistent:
		_announcement_time_left -= _delta
		if _announcement_time_left <= 0.0:
			$BattleAnnouncement.visible = false
	# 右上角倒计时：常规时间与加时赛均显示当前阶段剩余时间。
	var bm = get_node_or_null("../../Managers/BattleManager")
	if bm and bm.battle_running:
		var phase_end: float = bm.max_battle_time
		if bm.battle_phase == "overtime":
			phase_end += bm.overtime_duration
		var time_left: int = max(0, int(ceil(phase_end - bm.battle_time)))
		$TimerPanel/TimeLabel.text = "%d:%02d" % [int(time_left / 60), time_left % 60]
		# 最后十秒按 10 红、9 白、8 红……交替提醒。
		var is_warning_second := time_left > 0 and time_left <= 10 and time_left % 2 == 0
		$TimerPanel/TimeLabel.add_theme_color_override(
			"font_color", TIMER_WARNING_COLOR if is_warning_second else TIMER_NORMAL_COLOR)
		_update_match_presentation(bm, time_left)


func _update_match_presentation(bm: Node, time_left: int) -> void:
	if not _presentation_initialized:
		_presentation_initialized = true
		_last_phase = bm.battle_phase
		_last_multiplier = bm.current_elixir_multiplier
		_update_multiplier_label(_last_multiplier)
		return

	if _last_phase != bm.battle_phase:
		_last_phase = bm.battle_phase
		if bm.battle_phase == "overtime":
			_show_announcement("OVERTIME")

	if _last_multiplier != bm.current_elixir_multiplier:
		var old_multiplier: int = _last_multiplier
		_last_multiplier = bm.current_elixir_multiplier
		_update_multiplier_label(_last_multiplier)
		# 经典模式的 1→2、2→3 切换均以“60 秒”中央播报提示。
		if old_multiplier > 0 and _last_multiplier > old_multiplier and _last_multiplier <= 3:
			_show_announcement("60 SECONDS LEFT", "X%d ELIXIR" % _last_multiplier)

	if time_left > 12:
		_final_countdown_announced = false
		_last_countdown_second = -1
		return
	if not _final_countdown_announced and time_left > 10:
		_final_countdown_announced = true
		_show_announcement("BATTLE ENDS IN...", "", 1.4)
	if time_left <= 10 and time_left > 0 and time_left != _last_countdown_second:
		_last_countdown_second = time_left
		_show_countdown(time_left)


func _update_multiplier_label(multiplier: int) -> void:
	$MultiplierIcon.visible = multiplier != 1
	if multiplier != 1:
		$MultiplierIcon/ValueLabel.text = "X%d" % multiplier


func _show_announcement(title: String, subtitle: String = "", duration: float = 2.2) -> void:
	_announcement_persistent = duration < 0.0
	_announcement_time_left = duration
	$BattleAnnouncement/TitleLabel.add_theme_font_size_override("font_size", 24)
	$BattleAnnouncement/TitleLabel.add_theme_constant_override("outline_size", 7)
	$BattleAnnouncement/TitleLabel.add_theme_color_override("font_color", Color(1, 0.96, 0.75))
	$BattleAnnouncement/TitleLabel.add_theme_color_override("font_outline_color", DARK_OUTLINE_COLOR)
	$BattleAnnouncement/TitleLabel.text = title
	$BattleAnnouncement/SubtitleLabel.text = subtitle
	$BattleAnnouncement/SubtitleLabel.visible = not subtitle.is_empty()
	$BattleAnnouncement.visible = true


func _show_countdown(second: int) -> void:
	_announcement_persistent = false
	_announcement_time_left = 1.05
	$BattleAnnouncement/TitleLabel.add_theme_font_size_override("font_size", 48)
	$BattleAnnouncement/TitleLabel.add_theme_constant_override("outline_size", 8)
	$BattleAnnouncement/TitleLabel.add_theme_color_override("font_color", COUNTDOWN_COLOR)
	$BattleAnnouncement/TitleLabel.add_theme_color_override("font_outline_color", DARK_OUTLINE_COLOR)
	$BattleAnnouncement/TitleLabel.text = str(second)
	$BattleAnnouncement/SubtitleLabel.visible = false
	$BattleAnnouncement.visible = true
	# 倒计时音效：首次进入 10 秒阶段时播放完整 countdown_10s。
	# 音频约 12 秒（10 声滴答 + 头尾留白），与屏幕上 10-1 数字自然同步。
	# overtime 末尾会因 _last_countdown_second 在 time_left>12 时被重置而再次触发。
	if second == 10:
		AudioManager.play("countdown_10s")


## 能量变化时更新显示
func _on_energy_changed(_team_name: String, _current: int, _max_value: int) -> void:
	pass


## 单位生成
func _on_unit_spawned(_unit: Node, _team: String) -> void:
	pass


## 单位死亡
func _on_unit_died(_unit: Node, _team: String) -> void:
	pass


## 塔被摧毁
func _on_tower_destroyed(_tower_id: String, _team: String, _tower_type: String) -> void:
	pass


## 战斗结束
func _on_battle_ended(result: String) -> void:
	_show_announcement("MATCH OVER!", "", -1.0)
	$CenterMessageLabel.visible = false
	$EndPanel.visible = true
	# 结束面板可见时，恢复按钮的鼠标响应
	$EndPanel.mouse_filter = Control.MOUSE_FILTER_STOP
	$EndPanel/VBoxContainer/RestartButton.mouse_filter = Control.MOUSE_FILTER_STOP
	$EndPanel/VBoxContainer/MenuButton.mouse_filter = Control.MOUSE_FILTER_STOP
	print("[BattleHUD] battle ended:", result)


## 点击"重新开始"按钮
func _on_restart_button_pressed() -> void:
	Game.restart_battle()


## 点击"返回菜单"按钮
func _on_menu_button_pressed() -> void:
	Game.return_to_menu()
