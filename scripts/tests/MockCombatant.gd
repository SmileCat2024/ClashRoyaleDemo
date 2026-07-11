# 文件名：MockCombatant.gd
# 作用：测试用的模拟战斗实体。继承 CombatantBase 以满足 AttackComponent.combatant 的类型约束。
#       不放入场景树（不触发 @onready 子节点解析），仅设置属性后直接用于索敌/伤害/攻击组件测试。
#       使用完毕后需手动 free()。
# 挂载位置：不挂载。由测试代码 new() 创建，free() 销毁。
# 初学者阅读建议：看属性声明和 take_damage 即可。

class_name MockCombatant
extends CombatantBase

# ---- 子类属性（CombatantBase 没有，这里补齐方便测试）----
var movement_type: String = "ground"  ## "ground" | "air"
var sight_range: float = 120.0        ## 视野范围（像素）
var tower_type = null                 ## null = 非塔；"king"/"guard" = 塔
# 冲锋相关（王子机制测试用，默认关闭，不影响其它测试）
var is_charging: bool = false         ## 是否处于冲锋状态
var charge_damage: int = 0            ## 冲锋命中伤害

# ---- 测试追踪 ----
var damage_taken_total: int = 0       ## 累计实际受伤（扣盾+扣血）
var _mock_move_dir: Vector2 = Vector2.ZERO  ## 模拟移动方向（供 CollisionSystem 切向滑动测试）
var end_charge_call_count: int = 0    ## _end_charge 被调用次数（验证冲锋退出时机）

## 设置模拟移动方向。CollisionSystem._get_move_direction() 会通过 has_method 调用它。
func set_move_direction(dir: Vector2) -> void:
	_mock_move_dir = dir

func get_move_direction() -> Vector2:
	return _mock_move_dir

## 退出冲锋状态（AttackComponent._execute_attack 命中时通过 has_method 调用）。
## 复刻 UnitBase._end_charge 的核心行为：置 is_charging=false，便于测试验证退出时机。
func _end_charge() -> void:
	is_charging = false
	end_charge_call_count += 1

## 重写 take_damage 以追踪实际伤害量
func take_damage(amount: int) -> void:
	var hp_before := current_hp
	var shield_before := current_shield
	super.take_damage(amount)
	damage_taken_total += (shield_before - current_shield) + (hp_before - current_hp)
