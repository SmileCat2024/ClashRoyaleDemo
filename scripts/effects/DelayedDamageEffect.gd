# 文件名：DelayedDamageEffect.gd
# 作用：延迟范围伤害效果——在地面上放置一个炸弹，引信时间过后爆炸，
#       对范围内所有敌方造成全额伤害。典型用例：气球兵死亡掉落炸弹。
#       视觉：引信期间显示脉冲圆圈指示爆炸半径；到期瞬间触发伤害并销毁。
# 挂载位置：DelayedDamageEffect.tscn 的根节点
# 初学者阅读建议：先看 setup_damage() 了解炸弹参数，再看 _on_expire() 了解爆炸逻辑。

extends BattlefieldEffect

# ---- 伤害参数 ----
var damage: int = 0                  ## 爆炸伤害值
var blast_radius: float = 0.0        ## 爆炸半径（像素）

# ---- 子节点引用 ----
@onready var body_rect: ColorRect = $Body


## 初始化炸弹效果的所有参数。
## pos: 炸弹位置（World 本地游戏空间坐标）
## team_name: 伤害来源阵营
## fuse_time: 引信时间（秒）= 生命周期
## dmg: 爆炸伤害
## radius: 爆炸半径（像素）
func setup_damage(pos: Vector2, team_name: String, fuse_time: float, dmg: int, radius: float) -> void:
	super.setup(pos, team_name, fuse_time)
	damage = dmg
	blast_radius = radius
	# 引信期间显示为深色炸弹
	if body_rect:
		body_rect.color = Color(0.2, 0.2, 0.25)
		var s: float = BattleConstants.CELL_SIZE * 0.5
		body_rect.size = Vector2(s, s)
		body_rect.position = Vector2(-s / 2.0, -s / 2.0)
	queue_redraw()


## 到期爆炸：对范围内所有敌方造成伤害，发出信号
func _on_expire() -> void:
	if damage > 0 and blast_radius > 0.0:
		DamageSystem.deal_area_damage(position, blast_radius, damage, team)
		SignalBus.impact_resolved.emit(position, "splash", blast_radius, team)
		print("[DelayedDamageEffect] exploded: dmg=%d radius=%.0f team=%s" % [damage, blast_radius, team])


## 绘制爆炸半径指示圈（脉冲效果）
func _draw() -> void:
	if not initialized or blast_radius <= 0.0:
		return
	# 脉冲透明度：引信期间持续显示，接近爆炸时变红
	var progress := get_progress()
	var alpha: float = 0.06 + sin(_elapsed * 6.0) * 0.03  # 轻微脉冲
	if progress > 0.7:
		alpha += (progress - 0.7) * 0.3  # 临近爆炸时渐亮

	var fill_color := Color(1.0, 0.4, 0.1, alpha)
	draw_circle(Vector2.ZERO, blast_radius, fill_color)
	# 半径边线
	var ring_color := Color(1.0, 0.5, 0.2, 0.12 + progress * 0.2)
	draw_arc(Vector2.ZERO, blast_radius, 0, TAU, 64, ring_color, 1.5)


func _process(delta: float) -> void:
	if not initialized:
		return
	_elapsed += delta
	if _elapsed >= lifetime:
		# 爆炸瞬间范围视觉（两端都显示，在 is_client 检查之前）
		BlastRingEffect.spawn(get_parent(), position, blast_radius)
		# 仅 host：造成伤害（与父类 BattlefieldEffect._process 逻辑一致）
		if not NetworkManager.is_networked_client():
			_on_expire()
		queue_free()
		return
	queue_redraw()  # 引信期间每帧重绘脉冲预警圈
