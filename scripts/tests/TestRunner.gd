# 文件名：TestRunner.gd
# 作用：测试运行器。自动加载 scripts/tests/ 下所有 test_*.gd 套件并执行，
#       汇总打印结果。作为 TestRunner.tscn 的根脚本，在 Godot 编辑器中直接运行即可。
# 挂载位置：scenes/test/TestRunner.tscn 根节点。
# 初学者阅读建议：看 _ready() 了解启动流程，看 _register_suites() 了解怎么添加新测试。

extends Node

# 手动注册测试套件（preload 确保编译期检查）
const SUITES := [
	preload("res://scripts/tests/test_battle_constants.gd"),
	preload("res://scripts/tests/test_battle_pathing.gd"),
	preload("res://scripts/tests/test_targeting_system.gd"),
	preload("res://scripts/tests/test_damage_system.gd"),
	preload("res://scripts/tests/test_deck_manager.gd"),
	preload("res://scripts/tests/test_data_registry.gd"),
	preload("res://scripts/tests/test_attack_targeting.gd"),
	preload("res://scripts/tests/test_river_jump.gd"),
	preload("res://scripts/tests/test_tower_attack.gd"),
	preload("res://scripts/tests/test_death_damage.gd"),
	preload("res://scripts/tests/test_king_tower_activation.gd"),
	preload("res://scripts/tests/test_collision_system.gd"),
	preload("res://scripts/tests/test_spell_system.gd"),
]


func _ready() -> void:
	print("\n")
	print("========================================")
	print("         TEST RUNNER START")
	print("========================================")

	var total_pass := 0
	var total_fail := 0
	var failed_suites: Array[String] = []

	for suite_script in SUITES:
		var suite: TestBase = suite_script.new()
		add_child(suite)
		var result: Dictionary = suite.run_all()
		total_pass += result["passed"]
		total_fail += result["failed"]
		if result["failed"] > 0:
			failed_suites.append(result["name"])
		suite.queue_free()

	print("\n========================================")
	if total_fail == 0:
		print("  ALL PASS  |  %d assertions passed" % total_pass)
	else:
		print("  FAILED    |  %d passed, %d failed" % [total_pass, total_fail])
		print("  Failed suites: %s" % ", ".join(failed_suites))
	print("========================================\n")

	# 自动退出：命令行 headless 运行时必须退出，否则进程挂起
	# 编辑器 F6 运行也会退出，但结果已在 Output 面板打印
	get_tree().quit(1 if total_fail > 0 else 0)
