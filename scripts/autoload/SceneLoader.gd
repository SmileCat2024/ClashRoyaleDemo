# 文件名：SceneLoader.gd
# 作用：统一处理场景切换，避免其他脚本到处直接写 change_scene_to_file。
#       所有场景跳转都通过这里，方便维护和调试。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：只需要知道 load_battle() 会进入战斗场景，load_main_menu() 会回到菜单。

extends Node

## 主菜单场景路径
const MAIN_MENU_PATH := "res://scenes/main/MainMenu.tscn"

## 战斗场景路径
const BATTLE_SCENE_PATH := "res://scenes/battle/BattleScene.tscn"


## 切换到主菜单
func load_main_menu() -> void:
	print("[SceneLoader] -> MainMenu")
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


## 切换到战斗场景
func load_battle() -> void:
	print("[SceneLoader] -> BattleScene")
	get_tree().change_scene_to_file(BATTLE_SCENE_PATH)


## 重新加载当前场景（用于重开战斗）
func reload_current_scene() -> void:
	print("[SceneLoader] reload current scene")
	get_tree().reload_current_scene()
