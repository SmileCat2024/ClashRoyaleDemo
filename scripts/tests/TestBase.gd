# 文件名：TestBase.gd
# 作用：所有测试套件的基类。提供断言方法和自动发现 test_ 方法的运行机制。
#       子类只需写 test_xxx() 方法，调用 assert_eq / assert_true 等断言即可。
# 挂载位置：不需要直接挂载。由 TestRunner 实例化。
# 初学者阅读建议：看 run_all() 了解测试怎么自动发现和执行，看 assert_xxx 了解断言用法。

class_name TestBase
extends Node

# ---- 统计 ----
var _pass_count: int = 0
var _fail_count: int = 0
var _current_test: String = ""


## 运行所有 test_ 前缀的方法。在运行前后自动调 setup / teardown（如果存在）。
func run_all() -> Dictionary:
	_pass_count = 0
	_fail_count = 0
	var suite_name := _get_suite_name()
	print("\n--- %s ---" % suite_name)

	var has_setup := has_method("setup")
	var has_teardown := has_method("teardown")

	for method in get_method_list():
		var m_name: String = method["name"]
		if not m_name.begins_with("test_"):
			continue
		_current_test = m_name
		if has_setup:
			call("setup")
		call(m_name)
		if has_teardown:
			call("teardown")

	var status := "PASS" if _fail_count == 0 else "FAIL"
	print("  [%s] %d passed, %d failed" % [status, _pass_count, _fail_count])
	return {"passed": _pass_count, "failed": _fail_count, "name": suite_name}


func _get_suite_name() -> String:
	var p: String = get_script().resource_path.get_file().get_basename()
	return p if p != "" else "UnknownSuite"


# ============================================================
#  断言方法
# ============================================================

func assert_eq(actual, expected, msg: String = "") -> void:
	if actual == expected:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL %s.%s: expected [%s] got [%s] %s" % [
			_get_suite_name(), _current_test, str(expected), str(actual), msg])


func assert_true(value: bool, msg: String = "") -> void:
	assert_eq(value, true, msg)


func assert_false(value: bool, msg: String = "") -> void:
	assert_eq(value, false, msg)


func assert_null(value, msg: String = "") -> void:
	assert_eq(value, null, msg)


func assert_not_null(value, msg: String = "") -> void:
	if value != null:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL %s.%s: expected non-null %s" % [
			_get_suite_name(), _current_test, msg])


func assert_approx(actual: float, expected: float, tolerance: float = 0.01, msg: String = "") -> void:
	if absf(actual - expected) <= tolerance:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL %s.%s: expected ~%f (±%f) got %f %s" % [
			_get_suite_name(), _current_test, expected, tolerance, actual, msg])


func assert_ne(actual, expected, msg: String = "") -> void:
	if actual != expected:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL %s.%s: expected != [%s] but got [%s] %s" % [
			_get_suite_name(), _current_test, str(expected), str(actual), msg])
