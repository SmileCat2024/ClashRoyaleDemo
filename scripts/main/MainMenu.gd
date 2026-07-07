# 文件名：MainMenu.gd
# 作用：处理主菜单的按钮点击——开始战斗、退出游戏。
# 挂载位置：MainMenu.tscn 的根节点
# 初学者阅读建议：看 _on_start_button_pressed()，理解点击按钮后场景怎么跳转。

extends Control


func _ready() -> void:
	$VBoxContainer/StartButton.pressed.connect(_on_start_button_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_button_pressed)
	print("[MainMenu] ready")


## 点击"开始战斗"按钮
func _on_start_button_pressed() -> void:
	print("[MainMenu] start button pressed")
	Game.start_battle()


## 点击"退出游戏"按钮
func _on_quit_button_pressed() -> void:
	print("[MainMenu] quit button pressed")
	get_tree().quit()
