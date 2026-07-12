## ArrowsSpellController.gd
## 万箭齐发法术控制器：编排 3 波箭雨（发射 → 飞行 → 落地伤害）。
## 挂载位置：由 SpellManager.cast_spell() 用 .new() 创建，add_child 到 SpellManager 自身。
extends Node

# ── 常量 ──────────────────────────────────────────────
const ARROWS_PER_WAVE: int = 15          ## 每波箭矢数量
const WAVE_INTERVAL: float = 0.18        ## 波次间隔（秒）
const ARC_HEIGHT_MULT: float = 0.4       ## 弧高系数（× 飞行距离格数）
const ARC_HEIGHT_MAX: float = 4.5        ## 弧高上限（格）
const ORIGIN_SPREAD_GRIDS: float = 2.0   ## 发射阵型宽度（格，垂直于飞行方向的横线展开）
const GOLDEN_ANGLE: float = 2.39996323   ## 黄金角（弧度），用于向日葵均匀分布

const ArrowProjectile = preload("res://scripts/entities/ArrowProjectile.gd")

# ── 参数（setup 注入）────────────────────────────────
var _origin: Vector2 = Vector2.ZERO       ## 发射中心（国王塔位置）
var _target: Vector2 = Vector2.ZERO       ## 落区中心
var _radius: float = 0.0                  ## 落区半径（像素）
var _damage: int = 0                      ## 每波对单位伤害
var _tower_damage: int = 0               ## 每波对塔伤害
var _speed_grids: float = 0.0            ## 箭矢飞行速度（格/秒）
var _team: String = ""                    ## 施法方
var _waves: int = 3                       ## 波数
var _arrows_root: Node = null            ## 箭矢挂载节点（ProjectilesRoot）

# ── 内部状态 ─────────────────────────────────────────
var _elapsed: float = 0.0
var _pending: Array = []                  ## 定时事件队列 {time, type, wave}
var _done: bool = false


func setup(origin: Vector2, target: Vector2, card: Dictionary, team: String, arrows_root: Node) -> void:
	_origin = origin
	_target = target
	_radius = BattleConstants.px(float(card.get("spell_radius", 0.0)))
	_damage = int(card.get("spell_damage", 0))
	_tower_damage = int(card.get("tower_damage", _damage))
	_speed_grids = float(card.get("projectile_speed", 10.0))
	_team = team
	_waves = int(card.get("spell_waves", 1))
	_arrows_root = arrows_root

	# 按飞行时间编排发射 + 落地伤害时间表
	var flight_dist_grids := origin.distance_to(target) / BattleConstants.CELL_SIZE
	var flight_time := flight_dist_grids / _speed_grids

	for wave in range(_waves):
		var launch_time := wave * WAVE_INTERVAL
		_pending.append({"time": launch_time, "type": "launch", "wave": wave})
		_pending.append({"time": launch_time + flight_time, "type": "damage", "wave": wave})

	_pending.sort_custom(func(a, b): return a["time"] < b["time"])


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta

	# 处理到期事件
	while not _pending.is_empty() and _pending[0]["time"] <= _elapsed:
		var entry: Dictionary = _pending.pop_front()
		if entry["type"] == "launch":
			_spawn_wave(int(entry["wave"]))
		elif entry["type"] == "damage":
			_deal_wave_damage()

	# 全部事件处理完毕 → 自毁（箭矢自行管理生命周期）
	if _pending.is_empty():
		_done = true
		queue_free()


func _spawn_wave(wave_idx: int) -> void:
	var spread_px := BattleConstants.px(ORIGIN_SPREAD_GRIDS)

	# 全波统一参数：同步齐射的基础
	var center_dist_grids := _origin.distance_to(_target) / BattleConstants.CELL_SIZE
	var common_arc := minf(center_dist_grids * ARC_HEIGHT_MULT, ARC_HEIGHT_MAX)
	var common_flight_time := center_dist_grids / _speed_grids

	# 垂直于飞行方向的单位向量（横线阵型展开方向）
	var flight_dir := (_target - _origin).normalized()
	var perp := Vector2(-flight_dir.y, flight_dir.x)

	var mid := float(ARROWS_PER_WAVE - 1) / 2.0

	for i in ARROWS_PER_WAVE:
		# 落点：向日葵均匀分布（黄金角，确定性无随机），每波偏移半角避免完全重合
		var theta := (float(i) + wave_idx * 0.5) * GOLDEN_ANGLE
		var landing_r := _radius * sqrt((float(i) + 0.5) / float(ARROWS_PER_WAVE))
		var landing := _target + Vector2(cos(theta), sin(theta)) * landing_r

		# 发射点：垂直于飞行方向的横线阵型，均匀展开
		var formation_t: float = (float(i) - mid) / mid if mid > 0.0 else 0.0
		var arrow_origin := _origin + perp * formation_t * spread_px

		# 按各自实际距离反推速度，确保全波同步到达（齐射落点）
		var arrow_dist_px := arrow_origin.distance_to(landing)
		var arrow_speed_grids := arrow_dist_px / common_flight_time / BattleConstants.CELL_SIZE

		var arrow := ArrowProjectile.new()
		_arrows_root.add_child(arrow)
		arrow.setup_flight(arrow_origin, landing, arrow_speed_grids, common_arc)


func _deal_wave_damage() -> void:
	# 联机 client 端：不造成伤害（由 host 计算），仅保留箭矢飞行视觉
	if NetworkManager.is_networked_client():
		return
	DamageSystem.deal_area_damage(_target, _radius, _damage, _team, _tower_damage)
	SignalBus.projectile_hit.emit(_target, _team)
