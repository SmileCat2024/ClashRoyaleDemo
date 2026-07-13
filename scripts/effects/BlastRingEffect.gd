# 文件名：BlastRingEffect.gd
# 作用：范围伤害爆炸瞬间的统一视觉载体——红色渐变环（外圈实线 + 内侧渐变到透明），
#       出现后快速渐隐消失。纯视觉节点，不含任何伤害逻辑（伤害由 DamageSystem 在调用方结算）。
#       用于没有自带爆炸视觉载体的场景：ArrowsSpellController（波次伤害）、DelayedDamageEffect（死亡炸弹）。
#       MortarShell / SpellProjectile 自带 exploding 状态，直接在自己的 _draw 里调 RangeVfx，不走本节点。
# 挂载位置：不挂载到场景树。通过 static spawn() 工厂方法创建，add_child 到 World 下的 Node2D 父节点。
# 初学者阅读建议：看 spawn() 了解怎么创建，看 _process 了解渐隐生命周期。
#
# 联机说明：纯视觉。调用方需确保在两端都 spawn（ArrowsSpellController/DelayedDamageEffect 的
#           is_networked_client 检查在 spawn 之后），无需额外 RPC 同步。

class_name BlastRingEffect
extends Node2D

## 默认渐隐时长（秒）——"非常快"
const DEFAULT_DURATION: float = 0.35
## 渲染层级（高于普通投射物 45~50，保证爆炸环不被遮挡）
const BLAST_Z_INDEX: int = 60

var _radius: float = 0.0
var _color: Color = RangeVfx.COLOR_BLAST
var _duration: float = DEFAULT_DURATION
var _elapsed: float = 0.0


## 工厂方法：在 parent 下创建一个爆炸环视觉，自动渐隐并销毁。
## parent: World 下的 Node2D 父节点（EffectsRoot / ProjectilesRoot 等，position 应为原点）
## world_pos: 爆炸中心（World 本地游戏空间坐标）
## radius_px: 爆炸半径（像素）
## color: 环颜色，默认红色 RangeVfx.COLOR_BLAST
## duration: 渐隐时长（秒）
static func spawn(parent: Node, world_pos: Vector2, radius_px: float,
		color: Color = RangeVfx.COLOR_BLAST, duration: float = DEFAULT_DURATION) -> void:
	var ring := BlastRingEffect.new()
	ring.position = world_pos
	ring._radius = radius_px
	ring._color = color
	ring._duration = duration
	ring.z_index = BLAST_Z_INDEX
	parent.add_child(ring)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return
	# alpha 从 1 线性渐隐到 0
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var alpha: float = 1.0 - t
	RangeVfx.draw_gradient_ring(self, Vector2.ZERO, _radius, _color, alpha)
