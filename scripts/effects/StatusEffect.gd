# 文件名：StatusEffect.gd
# 作用：状态效果数据对象。描述一个施加在 CombatantBase 上的临时效果（减速、眩晕、中毒DoT 等）。
#       这是一个纯数据+行为对象（RefCounted），不挂场景树，由 CombatantBase._status_effects 列表管理。
#
#       当前已支持的效果类型：
#         "slow"   — 移动减速（move_speed_mult < 1.0）。多个 slow 取最强（最小 mult）+ 最长剩余时间。
#         "stun"   — 眩晕（完全不能移动和攻击）。新 stun 刷新 duration。
#         "freeze" — 冰冻（与 stun 相同的完全瘫痪效果，独立类型用于视觉/来源区分）。新 freeze 刷新 duration。
#         "rage"   — 狂暴增益（移动速度 + 攻击速度提升，mult > 1.0）。取最强 buff + 最长剩余时间。
#         "poison" — 持续中毒（每 tick_interval 秒受 tick_damage 伤害）。DoT 类型。
#
#       扩展新效果只需：
#         1. 在此文件加 type 名称和对应字段
#         2. 在 CombatantBase._process_status_effects() 中处理 tick 逻辑
#         3. 在 CombatantBase.get_move_speed_mult() / get_attack_speed_mult() 或 AttackComponent 中读取效果
# 初学者阅读建议：看 _init() 了解参数，看 merge() 了解同类叠加规则。

class_name StatusEffect
extends RefCounted

## 效果类型标识
var type: String = ""

## 总持续时间（秒）
var duration: float = 0.0

## 已经过时间（秒），由 CombatantBase 每帧累加
var elapsed: float = 0.0

# ---- slow / stun / freeze 通用 ----
## 移动速度乘数（1.0 = 无影响，0.85 = 减速15%，0.0 = 完全不能动）。slow 用。
var move_speed_mult: float = 1.0

# ---- rage（狂暴增益）----
## 攻击速度乘数（1.0 = 无影响，1.35 = 攻速+35%）。rage 用。
var attack_speed_mult: float = 1.0

# ---- poison (DoT) ----
## DoT 伤害间隔（秒）
var tick_interval: float = 0.0
## DoT 伤害计时器
var tick_timer: float = 0.0
## 每跳伤害值
var tick_damage: int = 0
## 伤害来源阵营（DoT 不应误伤友方）
var source_team: String = ""


func _init(p_type: String = "", p_duration: float = 0.0) -> void:
	type = p_type
	duration = p_duration


## 是否已过期
func is_expired() -> bool:
	return elapsed >= duration


## 剩余持续时间
func get_remaining() -> float:
	return max(0.0, duration - elapsed)


## 将同类型的新效果合并到已有效果上（同类叠加规则）。
## slow: 取更强减速（更小 mult）+ 更长剩余时间。
## stun / freeze: 取更长剩余时间（完全瘫痪效果相同，按类型分开仅用于视觉/来源区分）。
## rage: 取更强 buff（更大 move/attack mult）+ 更长剩余时间。
## poison: 取更高 tick_damage + 刷新 duration。
func merge(new_effect: StatusEffect) -> void:
	match type:
		"slow":
			move_speed_mult = minf(move_speed_mult, new_effect.move_speed_mult)
			duration = elapsed + maxf(get_remaining(), new_effect.duration - new_effect.elapsed)
		"stun":
			duration = elapsed + maxf(get_remaining(), new_effect.duration - new_effect.elapsed)
		"freeze":
			duration = elapsed + maxf(get_remaining(), new_effect.duration - new_effect.elapsed)
		"rage":
			move_speed_mult = maxf(move_speed_mult, new_effect.move_speed_mult)
			attack_speed_mult = maxf(attack_speed_mult, new_effect.attack_speed_mult)
			duration = elapsed + maxf(get_remaining(), new_effect.duration - new_effect.elapsed)
		"poison":
			tick_damage = maxi(tick_damage, new_effect.tick_damage)
			duration = elapsed + maxf(get_remaining(), new_effect.duration - new_effect.elapsed)
		_:
			duration = elapsed + maxf(get_remaining(), new_effect.duration - new_effect.elapsed)
