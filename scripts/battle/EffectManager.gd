# 文件名：EffectManager.gd
# 作用：统一的战场效果生成入口。所有 BattlefieldEffect 子类实例都通过这里创建。
#       监听 SignalBus.death_damage_triggered 信号，自动生成延迟伤害炸弹效果。
#       参考 ProjectileManager / SpawnManager 的模式，保持一致的架构风格。
# 挂载位置：BattleScene/Managers/EffectManager
# 依赖节点：EffectsRoot（效果的父容器，已在 BattleScene.tscn 中声明）
# 初学者阅读建议：看 _ready() 了解信号连接，看 spawn_delayed_damage() 了解炸弹怎么生成。

extends Node

## 延迟伤害炸弹的场景（预加载）
const DELAYED_DAMAGE_SCENE := preload("res://scenes/effects/DelayedDamageEffect.tscn")

## 效果的父容器（所有生成的效果都挂在这里下面）
@onready var effects_root: Node2D = $"../../World/EffectsRoot"


func _ready() -> void:
	# 联机 client 端：不监听信号（伤害由 host 计算），炸弹由 host 通过 RPC 同步创建
	if NetworkManager.is_networked_client():
		print("[EffectManager] client mode, skip signal monitoring")
		return
	SignalBus.death_damage_triggered.connect(_on_death_damage_triggered)
	print("[EffectManager] initialized")


## 接收死亡伤害信号，生成延迟炸弹效果
func _on_death_damage_triggered(pos: Vector2, damage: int, radius: float, fuse: float, team: String) -> void:
	spawn_delayed_damage(pos, damage, radius, fuse, team)


## 生成一个延迟伤害炸弹效果。
## pos: 炸弹位置（World 本地游戏空间坐标）
## damage: 爆炸伤害
## radius: 爆炸半径（像素）
## fuse: 引信时间（秒）
## team: 伤害来源阵营
## 返回: 生成的效果节点
func spawn_delayed_damage(pos: Vector2, damage: int, radius: float, fuse: float, team: String) -> Node2D:
	var effect: Node2D = DELAYED_DAMAGE_SCENE.instantiate()
	effects_root.add_child(effect)
	effect.setup_damage(pos, team, fuse, damage, radius)
	# Host 端：通知 client 也创建炸弹视觉效果（client 端 _process early return，不造成伤害）
	if NetworkManager.is_server():
		_rpc_spawn_effect.rpc(pos, damage, radius, fuse, team)
	return effect


## 联机 RPC：Host → Client，让 client 端也创建延迟炸弹视觉效果
@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_effect(pos: Vector2, damage: int, radius: float, fuse: float, team: String) -> void:
	if NetworkManager.is_server():
		return
	var effect: Node2D = DELAYED_DAMAGE_SCENE.instantiate()
	effects_root.add_child(effect)
	effect.setup_damage(pos, team, fuse, damage, radius)
