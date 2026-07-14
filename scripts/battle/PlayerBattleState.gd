# 文件名：PlayerBattleState.gd
# 作用：封装单方战斗状态（能量 + 圣水积累进度）。
#       BattleManager 持有两个实例（player / enemy），替代散装变量，
#       使双方状态管理对称，为未来扩展（2v2、回放、旁观者）预留结构。
# 初学者阅读建议：看 can_spend / spend / gain_energy 了解能量操作。

class_name PlayerBattleState
extends RefCounted

## 阵营标识
var team: String = "player"

## 当前能量
var energy: int = 5

## 能量上限
var max_energy: int = 10

## 当前正在积累的那一滴圣水的完成度（0.0~1.0），供 UI 平滑显示
var energy_progress: float = 0.0


func _init(p_team: String = "player", p_max_energy: int = 10) -> void:
	team = p_team
	max_energy = p_max_energy
	energy = 5


## 是否有足够能量
func can_spend(cost: int) -> bool:
	return energy >= cost


## 扣除能量（不低于 0）
func spend(cost: int) -> void:
	energy = maxi(0, energy - cost)


## 增加 1 点能量（不超过上限），返回是否实际增加了
func gain_energy() -> bool:
	if energy < max_energy:
		energy += 1
		return true
	return false


## 增加指定数量的能量，返回实际增加量（满圣水时为 0）。
func gain_energy_amount(amount: int) -> int:
	var before := energy
	energy = mini(max_energy, energy + maxi(0, amount))
	return energy - before


## 重置到初始状态
func reset() -> void:
	energy = 5
	energy_progress = 0.0
