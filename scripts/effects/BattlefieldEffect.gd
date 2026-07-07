# 文件名：BattlefieldEffect.gd
# 作用：战场临时效果的基类。表示一个存在于地面上、有有限生命周期的视觉效果/逻辑实体。
#       生命周期到期后调用 _on_expire()（子类重写实现具体效果），然后自动销毁。
#       这是法术爆炸、死亡炸弹、召唤特效等"非战斗实体但需要在战场上短暂存在的东西"的基础。
# 挂载位置：不直接挂载。由子类（如 DelayedDamageEffect）继承，场景文件引用子类脚本。
# 初学者阅读建议：先看 setup() 和 _process() 了解生命周期，再看 _on_expire() 了解到期回调。

class_name BattlefieldEffect
extends Node2D

# ---- 初始化标记 ----
var initialized: bool = false

# ---- 基础属性 ----
var team: String = "player"          ## 效果所属阵营（用于伤害来源判定）
var lifetime: float = 1.0            ## 存活时间（秒）
var _elapsed: float = 0.0            ## 已经过时间（秒）


## 初始化效果的基础属性。子类应在自己的 setup 方法中调用 super.setup()。
func setup(pos: Vector2, team_name: String, life: float) -> void:
	position = pos
	team = team_name
	lifetime = life
	initialized = true


func _process(delta: float) -> void:
	if not initialized:
		return
	_elapsed += delta
	if _elapsed >= lifetime:
		_on_expire()
		queue_free()


## 返回剩余存活时间（秒），用于 UI 或其他系统查询
func get_remaining_time() -> float:
	return max(0.0, lifetime - _elapsed)


## 返回已过时间占生命周期的比例 [0, 1]
func get_progress() -> float:
	if lifetime <= 0.0:
		return 1.0
	return clampf(_elapsed / lifetime, 0.0, 1.0)


## 效果到期回调。子类重写此方法实现具体效果（造成伤害、施加状态等）。
func _on_expire() -> void:
	pass
