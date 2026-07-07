# 文件名：BattleHUD.gd
# 作用：战斗界面的总控制器。显示时间、能量、卡牌等信息。
#       HUD 只负责显示和把玩家输入转发出去，不直接生成单位。
# 挂载位置：BattleScene/CanvasLayer/BattleHUD
# 初学者阅读建议：先看 _ready() 了解初始化，再看各 _on_xxx 方法了解显示怎么更新。

extends Control


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
	$CenterMessageLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("[BattleHUD] ready")


## 递归设置所有子 Control 的 mouse_filter 为 IGNORE
func _disable_mouse_filter_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_disable_mouse_filter_recursive(child)


func _process(_delta: float) -> void:
	# 更新顶部时间显示
	var bm = get_node_or_null("../../Managers/BattleManager")
	if bm and bm.battle_running:
		var time_left = int(bm.max_battle_time - bm.battle_time)
		$TopBar/TimerLabel.text = "时间: %d" % time_left

	# 更新单位数量
	var units_root = get_node_or_null("../../UnitsRoot")
	if units_root:
		var count = units_root.get_child_count()
		$BottomInfo/UnitCountLabel.text = "场上单位: %d" % count


## 能量变化时更新显示
func _on_energy_changed(team_name: String, current: int, max_value: int) -> void:
	if team_name == "player":
		$TopBar/EnergyLabel.text = "能量: %d / %d" % [current, max_value]
	else:
		$TopBar/EnemyEnergyLabel.text = "敌方: %d / %d" % [current, max_value]


## 单位生成
func _on_unit_spawned(_unit: Node, _team: String) -> void:
	pass


## 单位死亡
func _on_unit_died(_unit: Node, _team: String) -> void:
	pass


## 塔被摧毁
func _on_tower_destroyed(tower_id: String, _team: String, _tower_type: String) -> void:
	$BottomInfo/EventLog.text = "塔被摧毁: " + tower_id


## 战斗结束
func _on_battle_ended(result: String) -> void:
	var text = "胜利！" if result == "victory" else "失败..."
	if result == "draw":
		text = "平局"
	$CenterMessageLabel.text = text
	$CenterMessageLabel.visible = true
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
