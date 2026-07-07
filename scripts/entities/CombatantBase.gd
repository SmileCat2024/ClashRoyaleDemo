# 文件名：CombatantBase.gd
# 作用：所有可战斗实体（单位、塔、建筑）的基类。
#       收拢共性逻辑——身份、生存属性（血量/护盾）、受伤结算、死亡。
#       攻击逻辑不在这里——D2 起由 AttackComponent 独立处理。
# 挂载位置：不直接挂载。由 UnitBase / TowerBase / BuildingBase 继承。
# 初学者阅读建议：先看 _init_combat_stats() 了解属性怎么初始化，
#       再看 take_damage() 了解护盾怎么吸收伤害。

class_name CombatantBase
extends Node2D

# ---- 初始化标记 ----
# setup() 完成前为 false，_process / _draw 直接 return。
var initialized: bool = false

# ---- 身份信息 ----
var team: String = "player"

# ---- 生存属性 ----
var max_hp: int = 100
var current_hp: int = 100
var shield: int = 0           ## 护盾上限（0 = 无护盾）
var current_shield: int = 0   ## 当前护盾值

# ---- 死亡状态 ----
var is_dead: bool = false

# ---- 攻击数据（原始字典数组，由 AttackComponent 读取）----
var attacks_data: Array = []

# ---- 死亡范围伤害（如气球兵的死亡掉落）----
var death_damage: int = 0          ## 死亡时对周围敌方造成的伤害（0 = 无死亡伤害）
var death_radius: float = 0.0      ## 死亡伤害范围（像素）
var death_fuse_time: float = 0.0   ## 死亡炸弹引信时间（秒，0 = 无延迟效果）

# ---- 离地高度 ----
## 离地高度（格）。地面单位 = 0，飞行单位 > 0。
## 仅影响视觉渲染（Body/HealthBar 向上偏移），不影响逻辑坐标和索敌。
var altitude: float = 0.0

# ---- 攻击组件实例列表（由 _init_combat_stats 动态创建）----
var attack_components: Array = []

# ---- 子节点引用 ----
# UnitBase.tscn / TowerBase.tscn 均有这三个子节点。
@onready var body_rect: ColorRect = $Body
@onready var health_bar: ProgressBar = $HealthBar
@onready var debug_label: Label = $DebugLabel


## 从数据字典初始化生存属性。子类的 setup() 应在设置完身份信息后调用此方法。
func _init_combat_stats(data: Dictionary) -> void:
	max_hp = int(data.get("max_hp", 100))
	current_hp = max_hp
	shield = int(data.get("shield", 0))
	current_shield = shield
	attacks_data = data.get("attacks", [])
	_create_attack_components()


## 根据 attacks_data 为每项攻击配置创建一个 AttackComponent（P0 只用第一个）
func _create_attack_components() -> void:
	# 清除旧组件（场景重用时的安全措施）
	for comp in attack_components:
		if is_instance_valid(comp):
			comp.queue_free()
	attack_components.clear()

	for i in range(attacks_data.size()):
		var attack: Dictionary = attacks_data[i]
		var comp: AttackComponent = AttackComponent.new()
		comp.name = "Attack_" + attack.get("name", str(i))
		add_child(comp)
		comp.combatant = self
		comp.setup(attack)
		attack_components.append(comp)


## 返回主攻击组件（attacks[0] 对应的），无攻击配置时返回 null
func get_primary_attack() -> AttackComponent:
	if attack_components.is_empty():
		return null
	return attack_components[0]


## 将视觉子节点（Body/HealthBar/DebugLabel）按 altitude 向上偏移。
## 在子类 setup() 设置完基础布局后调用。altitude 偏移会随 World 的 Y 压缩自动收缩。
func _apply_altitude_offset() -> void:
	if altitude <= 0.0:
		return
	var dy := -altitude * BattleConstants.CELL_SIZE
	body_rect.position.y += dy
	if health_bar:
		health_bar.position.y += dy
	if debug_label:
		debug_label.position.y += dy


## 受到伤害。护盾存在时，单次伤害至多打掉盾，不溢出到血量。
func take_damage(amount: int) -> void:
	if is_dead:
		return

	# 护盾优先吸收
	if current_shield > 0:
		current_shield = max(0, current_shield - amount)
		if current_shield == 0:
			SignalBus.shield_broken.emit(self)
		return  # 有盾时不掉血

	# 正常扣血
	current_hp -= amount
	if health_bar:
		health_bar.value = current_hp
	if current_hp <= 0:
		current_hp = 0
		die()


## 死亡。基类标记 is_dead 并发出死亡伤害信号（由 EffectManager 接收并生成延迟炸弹效果）。
## 具体死亡表现（注销、信号、queue_free）由子类重写。
func die() -> void:
	is_dead = true
	if death_damage > 0 and death_radius > 0.0:
		SignalBus.death_damage_triggered.emit(
			global_position, death_damage, death_radius, death_fuse_time, team
		)
