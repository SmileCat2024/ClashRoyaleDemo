# 文件名：MockCombatant.gd
# 作用：测试用的模拟战斗实体。继承 CombatantBase 以满足 AttackComponent.combatant 的类型约束。
#       不放入场景树（不触发 @onready 子节点解析），仅设置属性后直接用于索敌/伤害/攻击组件测试。
#       使用完毕后需手动 free()。
# 挂载位置：不挂载。由测试代码 new() 创建，free() 销毁。
# 初学者阅读建议：看属性声明和 take_damage 即可。

extends CombatantBase

# ---- 子类属性（CombatantBase 没有，这里补齐方便测试）----
var movement_type: String = "ground"  ## "ground" | "air"
var sight_range: float = 120.0        ## 视野范围（像素）
var tower_type = null                 ## null = 非塔；"king"/"guard" = 塔

# ---- 测试追踪 ----
var damage_taken_total: int = 0       ## 累计实际受伤（扣盾+扣血）

## 重写 take_damage 以追踪实际伤害量
func take_damage(amount: int) -> void:
	var hp_before := current_hp
	var shield_before := current_shield
	super.take_damage(amount)
	damage_taken_total += (shield_before - current_shield) + (hp_before - current_hp)
