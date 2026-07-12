# 文件名：UnitBase.gd
# 作用：控制单位的行为——移动、寻找敌方塔、死亡。
#       D1 阶段：只移动到最近的敌方塔，不攻击（D2 接入 AttackComponent）。
#       战斗属性、受伤逻辑继承自 CombatantBase。
# 挂载位置：UnitBase.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解单位怎么初始化，再看 _process() 了解每帧做什么。

class_name UnitBase
extends CombatantBase

# ---- 身份信息（单位独有）----
var unit_id: String = ""
var display_name: String = ""

# ---- 移动属性（单位独有）----
var move_speed: float = 20.0  # 默认值（1格/秒 × CELL_SIZE）
var movement_type: String = "ground"       ## "ground" | "air"
var base_movement_type: String = "ground"  ## 原始移动类型，跳河临时变 air 后用于恢复
var can_jump_river: bool = false           ## 地面单位是否可以直接跳过河道
var sight_range: float = 120.0
var movement_targeting: String = "any"     ## "any" | "building_only"

# ---- 运行时 ----
var _move_target = null    ## 当前移动目标（CombatantBase 或 null）
var _is_moving: bool = false  ## 本帧是否在移动（供 SpriteAnimator 轮询）

# ---- 联机视觉状态（host 计算并同步，client 直接读取）----
var _net_visual_state: String = "idle"
var _net_facing: String = "front"
var _net_flip_h: bool = false
var _net_is_firing: bool = false
var _net_attack_facing: String = "front"   ## 攻击朝向（front/back/side），由 host 攻击触发 RPC 同步
var _move_sfx_timer: float = 0.0  ## 移动音效间歇计时器（仅 sfx.move 配置的单位使用）
const MOVE_SFX_INTERVAL := 1.5  ## 移动音效播放间隔（秒）
var _last_move_dir: Vector2 = Vector2.ZERO  ## 上一帧实际移动方向（供 CollisionSystem 切向滑动）
# ---- A* 路径缓存 ----
var _path: Array = []                      ## 当前缓存的 A* 路径点（像素坐标，不含起点）
var _path_target: Vector2 = Vector2.ZERO   ## 当前路径的目标位置（检测目标变化时重算）
var _path_repath_timer: float = 0.0        ## 路径重算倒计时（秒）
var is_jumping_river: bool = false
# ---- 冲锋（王子专属，数据驱动；无 charge 配置时 _charge_enabled=false）----
var is_charging: bool = false           ## 是否处于冲锋状态（AttackComponent 命中时读取此标记 + charge_damage）
var charge_damage: int = 0              ## 冲锋命中伤害（AttackComponent 命中时使用）
var _charge_enabled: bool = false
var _charge_min_distance: float = 0.0   ## 进入冲锋所需持续移动距离（像素）
var _charge_move_speed: float = 0.0     ## 冲锋移速（像素/秒）
var _charge_distance_accum: float = 0.0 ## 当前持续移动累计距离（像素）
var _jump_start: Vector2 = Vector2.ZERO
var _jump_end: Vector2 = Vector2.ZERO
var _jump_elapsed: float = 0.0
var _jump_duration: float = 0.3
var _body_base_position: Vector2 = Vector2.ZERO
var _health_bar_base_position: Vector2 = Vector2.ZERO
var _debug_label_base_position: Vector2 = Vector2.ZERO

const RIVER_JUMP_ARC_HEIGHT := 1.25
const RIVER_JUMP_SPEED_MULTIPLIER := 1.25
const RIVER_JUMP_BANK_OFFSET := 1.0
const SEPARATION_RADIUS_CELLS := 0.5   ## 单位间分离探测余量（格），碰撞半径之外额外保持的距离

# ---- A* 寻路（路径缓存 + 重算）----
const PATH_REPATH_INTERVAL := 0.4     ## 路径重算间隔（秒）
const PATH_WAYPOINT_REACHED := 12.0   ## 到达路径点的判定距离（像素，约 0.6 格）

# ---- 部署下落动画（前 DEPLOY_ANIM_DURATION 秒的视觉表现）----
const DEPLOY_ANIM_DURATION := 0.35  ## 部署动画总时长（秒）= 下落 + 着地挤压弹跳
const DEPLOY_DROP_CELLS := 3.5      ## 下落起始高度（格），从高处明显落下
const DEPLOY_GHOST_ALPHA := 0.4     ## 虚影起始透明度（渐变到 1.0 实心，只改 alpha 不变暗）
const DEPLOY_FALL_FRACTION := 0.55  ## 下落占总时长的比例（剩余为挤压弹跳）
const DEPLOY_SQUASH_SCALE_Y := 0.6  ## 着地瞬间 Y 压缩比（高度变 60%）
const DEPLOY_SQUASH_SCALE_X := 1.25 ## 着地瞬间 X 拉伸比（宽度变 125%）

## 影子椭圆纵向压缩比。把正圆按此值压扁成椭圆。
const SHADOW_SQUASH := 0.35

## 影子椭圆水平半径（px）。setup 时从 shadow_size（格）转换。0 = 不画影子。
var _shadow_radius: float = 0.0

# ---- 建筑机制（寿命 / 部署 / 自然掉血）----
## 部署时间（秒）。> 0 时建筑部署完成后才开始索敌/攻击/掉血/倒计时。普通单位 = 0。
var deploy_time: float = 0.0
var _deploy_timer: float = 0.0
## Client 端位置插值：RPC 同步的目标位置 + 上一帧目标（检测移动）+ 初始化标志
var _sync_target_pos: Vector2 = Vector2.ZERO
var _last_sync_target: Vector2 = Vector2.ZERO
var _sync_pos_init: bool = false
## 最近一次同步推算的速度（像素/秒），丢包期间沿此方向外推避免单位"漂移减速"
var _sync_velocity: Vector2 = Vector2.ZERO
## 距离上次收到 RPC 的时间（秒），用于外推距离计算
var _sync_time_since_update: float = 0.0
## 外推时间上限（秒），超过此值停止外推避免无限漂移
const MAX_EXTRAPOLATION_TIME := 0.15
## 插值平滑系数（越大越快追上目标，过大会回退为跳变）
const SYNC_LERP_SPEED := 18.0
## 是否已部署完成（可行动）。普通单位默认 true；有 deploy_time 的建筑初始 false。
var is_deployed: bool = true
## 寿命（秒）。> 0 时建筑到期自毁。普通单位 = 0（无寿命）。
var lifespan: float = 0.0
var _lifespan_timer: float = 0.0
## 自然掉血速率（HP/秒）。建筑存在期间持续掉血，寿命到时血量恰好归零。
var _burn_rate: float = 0.0
var _burn_accumulator: float = 0.0
## 光束发射点 Y 偏移（像素，负=上移）。仅地狱塔配置，其他单位 = 0（无光束）。
var beam_emit_offset_y: float = 0.0
var _beam: InfernoBeam = null
## Client 端光束同步状态（host 通过 RPC 同步，client 端 _update_beam_visual 读取替代 AttackComponent）
var _sync_beam_active: bool = false
var _sync_beam_target: Vector2 = Vector2.ZERO
var _sync_beam_stage: int = 0

# ---- 部署下落动画（deploy_time 前期的视觉表现，不影响逻辑）----
var _deploy_anim_timer: float = 0.0   ## 下落动画剩余时间（秒，>0 表示动画进行中）
var _deploy_drop_dy: float = 0.0      ## 当前下落 Y 偏移（px，负=上移，0=无偏移）
var _deploy_alpha: float = 1.0        ## 当前透明度（0~1，只改 modulate.a 不变暗）
var _deploy_scale: Vector2 = Vector2.ONE  ## 部署挤压拉伸当前缩放（着地瞬间压扁→弹回正常）
var _altitude_visual_dy: float = 0.0  ## 当前 altitude 离地视觉偏移（px，负=上移）


## 初始化单位属性。由 SpawnManager 在生成单位后调用。
func setup(unit_data: Dictionary, team_name: String) -> void:
	unit_id = unit_data.get("id", "")
	display_name = unit_data.get("display_name", "")
	team = team_name
	move_speed = BattleConstants.px(float(unit_data.get("move_speed", 1.0)))
	base_movement_type = unit_data.get("movement_type", "ground")
	movement_type = base_movement_type
	can_jump_river = bool(unit_data.get("can_jump_river", false))
	sight_range = BattleConstants.px(float(unit_data.get("sight_range", 6.0)))
	movement_targeting = unit_data.get("movement_targeting", "any")

	# 初始化战斗属性（基类方法）
	_init_combat_stats(unit_data)

	# 冲锋机制配置（王子专属，无 charge 字段则禁用）
	var charge_cfg: Dictionary = unit_data.get("charge", {})
	_charge_enabled = not charge_cfg.is_empty()
	if _charge_enabled:
		_charge_min_distance = BattleConstants.px(float(charge_cfg.get("min_charge_distance", 2.5)))
		_charge_move_speed = BattleConstants.px(float(charge_cfg.get("charge_move_speed", 2.0)))
		charge_damage = int(charge_cfg.get("charge_damage", 0))

	# 死亡范围伤害配置（如气球兵的死亡掉落）
	death_damage = int(unit_data.get("death_damage", 0))
	death_radius = BattleConstants.px(float(unit_data.get("death_radius", 0.0)))
	death_fuse_time = float(unit_data.get("death_fuse_time", 0.0))

	# 建筑机制配置（寿命/部署/自然掉血，仅建筑单位使用）
	deploy_time = float(unit_data.get("deploy_time", 0.0))
	if deploy_time > 0.0:
		is_deployed = false
		_deploy_timer = deploy_time
		# 部署下落动画初始化：启动 0.1 秒下落 + 半透明虚影
		_deploy_anim_timer = DEPLOY_ANIM_DURATION
		_deploy_drop_dy = -BattleConstants.px(DEPLOY_DROP_CELLS)
		_deploy_alpha = DEPLOY_GHOST_ALPHA
	lifespan = float(unit_data.get("lifespan", 0.0))
	if lifespan > 0.0:
		_lifespan_timer = lifespan
		_burn_rate = float(unit_data.get("lifespan_damage_per_sec", float(max_hp) / lifespan))
	# 光束发射点偏移（仅地狱塔等递增光束单位配置）
	beam_emit_offset_y = float(unit_data.get("beam_emit_offset_y", 0.0))

	# 碰撞几何参数（格 → 像素）
	collision_radius = BattleConstants.px(float(unit_data.get("collision_radius", 0.5)))
	hurt_radius = BattleConstants.px(float(unit_data.get("hurt_radius", 0.5)))
	mass = int(unit_data.get("mass", 5))

	# 影子大小（格 → 像素）。未配置时退化为 collision_radius。
	_shadow_radius = BattleConstants.px(float(unit_data.get("shadow_size", unit_data.get("collision_radius", 0.5))))

	# 视觉设置：统一方块大小，颜色按阵营区分
	var size: int = 16
	if team == "player":
		body_rect.color = BattleConstants.COLOR_PLAYER
	else:
		body_rect.color = BattleConstants.COLOR_ENEMY
	body_rect.size = Vector2(size, size)
	body_rect.position = Vector2(-size / 2.0, -size / 2.0)
	body_rect.pivot_offset = Vector2(size / 2.0, size / 2.0)  ## 缩放锚点设为中心，挤压拉伸从中心变形

	# 血条（高度 6px，比原始 4px 略粗）
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	var hb_h: float = 6.0
	var hb_w: float = size + 12
	# 默认位置：Body 上方保持 4px 间距（= -size/2 - hb_h - 4）
	var hb_y: float = -size / 2.0 - hb_h - 4.0
	# 有动画配置的单位，血条位置可由数据覆盖（贴图较大时需要上移）
	var anim_cfg: Dictionary = unit_data.get("animation", {})
	if not anim_cfg.is_empty():
		hb_y = float(anim_cfg.get("health_bar_y", hb_y))
	health_bar.size = Vector2(hb_w, hb_h)
	health_bar.position = Vector2(-hb_w / 2.0, hb_y)

	# 调试标签（有动画模型的单位隐藏）
	debug_label.text = display_name
	debug_label.position = Vector2(-15, size / 2.0 + 2)
	if sprite_animator and sprite_animator._has_animation:
		debug_label.visible = false
	_store_visual_base_positions()

	# 飞行单位设置离地高度（仅视觉，不影响逻辑坐标和索敌）
	if movement_type == "air":
		altitude = 2.5
	_set_visual_altitude(altitude)
	# 部署虚影初始视觉（deploy_time > 0 时单位以半透明虚影状态出现）
	if not is_deployed:
		modulate.a = _deploy_alpha

	initialized = true
	queue_redraw()
	print("[UnitBase] setup:", unit_id, team, "hp:", max_hp)


## _draw()：在单位脚底（origin）绘制半透明黑色椭圆影子。
## 影子始终在地面位置，不受 altitude 离地偏移影响。
## _draw() 先于子节点（Body/HealthBar/Sprite）绘制，保证影子在最底层。
func _draw() -> void:
	if not initialized or is_dead:
		return
	# 影子椭圆（在 origin 处绘制，Y 压缩变扁）
	if _shadow_radius > 0.0:
		# 飞行单位影子更淡（离地越远越散）
		var alpha := 0.18 if altitude > 0.0 else 0.28
		# 用 Y 压缩把正圆变成扁平椭圆
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_SQUASH))
		draw_circle(Vector2.ZERO, _shadow_radius, Color(0, 0, 0, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 地狱塔递增光束由独立子节点 InfernoBeam 绘制（ADD 混合），此处不处理


## 地狱塔递增光束视觉更新：按需创建/隐藏 InfernoBeam 子节点，每帧传入起止/阶段。
## InfernoBeam 是 ADD 混合的 Node2D，专门负责多层叠加光束绘制（复刻 HTML 原型）。
func _update_beam_visual() -> void:
	# Client 端：用 RPC 同步的光束状态替代 AttackComponent 查询（client 不跑索敌逻辑）
	if _is_remote():
		if not _sync_beam_active:
			if _beam != null and is_instance_valid(_beam):
				_beam.visible = false
			return
		if _beam == null or not is_instance_valid(_beam):
			_beam = InfernoBeam.new()
			add_child(_beam)
		var from_pos_c := Vector2(0.0, beam_emit_offset_y)
		var to_pos_c := _sync_beam_target - position + Vector2(0.0, -10.0)
		_beam.set_params(from_pos_c, to_pos_c, _sync_beam_stage, 1.0)
		_beam.visible = true
		return
	var attack = get_primary_attack()
	if attack == null or not attack.has_method("has_beam_target"):
		return
	if not attack.has_beam_target():
		if _beam != null and is_instance_valid(_beam):
			_beam.visible = false
		return
	var target = attack.get_beam_target()
	if target == null or not is_instance_valid(target):
		if _beam != null and is_instance_valid(_beam):
			_beam.visible = false
		return
	# 首次激活时创建光束节点
	if _beam == null or not is_instance_valid(_beam):
		_beam = InfernoBeam.new()
		add_child(_beam)
	# 起点：塔顶喷口（本地坐标）；终点：目标逻辑位置（转父节点本地坐标 + 身体偏移）
	var from_pos := Vector2(0.0, beam_emit_offset_y)
	var to_pos := BattlePathing.game_position_of(target) - position + Vector2(0.0, -10.0)
	_beam.set_params(from_pos, to_pos, attack.get_ramp_stage_index(), 1.0)
	_beam.visible = true


## Client 端：接收 host 同步的光束状态（由 BattleManager._rpc_sync_beams 调用）。
## target_pos 已由 BattleManager 做过镜像。
func update_beam_from_sync(active: bool, target_pos: Vector2, stage: int) -> void:
	_sync_beam_active = active
	_sync_beam_target = target_pos
	_sync_beam_stage = stage


## 建筑寿命倒计时 + 自然掉血。每帧扣除 burn_rate HP，寿命到期 die() 兜底。
func _process_lifespan(delta: float) -> void:
	_lifespan_timer -= delta
	_burn_accumulator += _burn_rate * delta
	var burn_int := int(_burn_accumulator)
	if burn_int > 0:
		_burn_accumulator -= burn_int
		take_damage(burn_int)
	# 寿命到期兜底（防止掉血速率计算误差导致血量未归零）
	if _lifespan_timer <= 0.0 and not is_dead:
		die()


## 施加减速效果（便捷封装，内部创建 StatusEffect）。
## factor: 移动速度乘数（如 0.85 = 减速 15%）
## duration: 持续时间（秒）
func apply_slow(factor: float, duration: float) -> void:
	var effect := StatusEffect.new("slow", duration)
	effect.move_speed_mult = factor
	apply_status_effect(effect)


## 当前实际移动速度（冲锋态用 charge_move_speed，否则基础速度；再 × 状态效果乘数）
func _get_effective_move_speed() -> float:
	var base := _charge_move_speed if is_charging else move_speed
	return base * get_move_speed_mult()


## 累计持续移动距离，达到阈值后进入冲锋状态（王子专属）。
func _accumulate_charge(moved: float) -> void:
	if not _charge_enabled or is_charging:
		return
	_charge_distance_accum += moved
	if _charge_distance_accum >= _charge_min_distance:
		is_charging = true
		AudioManager.play_unit_sfx(unit_id, "charge", BattlePathing.game_position_of(self))
		queue_redraw()


## 退出冲锋状态并重置累计距离。
## 由 AttackComponent._execute_attack（命中后）和 take_damage（受伤打断）调用。
func _end_charge() -> void:
	if not _charge_enabled:
		return
	is_charging = false
	_charge_distance_accum = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not initialized or is_dead:
		return
	# Client 端：position 由 BattleManager 手动 RPC 同步（已镜像），本地 lerp 插值平滑。
	# _is_moving 由两个 RPC 包的目标位置变化判断（host 端单位是否在移动）。
	# 本地运行部署动画倒计时。
	if _is_remote():
		if _sync_pos_init:
			_sync_time_since_update += delta
			# 外推预测：沿最近速度方向延伸目标，丢包时单位不会减速漂移
			var extrap_time := minf(_sync_time_since_update, MAX_EXTRAPOLATION_TIME)
			var predicted_target := _sync_target_pos + _sync_velocity * extrap_time
			position = position.lerp(predicted_target, clampf(delta * SYNC_LERP_SPEED, 0.0, 1.0))
		_is_moving = _sync_target_pos.distance_to(_last_sync_target) > 0.5
		if not is_deployed:
			_deploy_timer -= delta
			_update_deploy_anim(delta)
			if _deploy_timer <= 0.0:
				is_deployed = true
				_finish_deploy_anim()
		# 地狱塔光束视觉更新（用 RPC 同步的状态驱动，client 端不跑索敌逻辑）
		_update_beam_visual()
		return
	# 部署倒计时（deploy_time 期间不能行动；部署完成后才开始寿命/掉血/攻击）
	if not is_deployed:
		_deploy_timer -= delta
		_update_deploy_anim(delta)
		if _deploy_timer <= 0.0:
			is_deployed = true
			_finish_deploy_anim()
		return
	# 建筑寿命 + 自然掉血（仅 lifespan > 0 的建筑，部署完成后才开始）
	if lifespan > 0.0:
		_process_lifespan(delta)
		if is_dead:
			return
	# 冲锋累计：上一帧未持续移动则清零（已进入冲锋态的等攻击命中退出）
	if _charge_enabled and not _is_moving:
		_charge_distance_accum = 0.0
	_process_status_effects(delta)
	# 地狱塔递增光束视觉更新（InfernoBeam 子节点）
	_update_beam_visual()
	_is_moving = false
	if is_jumping_river:
		_is_moving = true
		_process_river_jump(delta)
		return

	var attack = get_primary_attack()

	# 有攻击目标：追击或在射程内停下（让 AttackComponent 自己攻击）
	if attack and attack.has_valid_target():
		var target_pos := BattlePathing.game_position_of(attack.current_target)
		var dist = BattlePathing.path_distance(position, target_pos, movement_type, can_jump_river)
		var reach: float = AttackComponent.compute_reach(attack.attack_range, collision_radius, attack.current_target)
		if dist > reach:
			_is_moving = true
			_move_towards_position(target_pos, delta)
		# else: 在射程内，停下不动，AttackComponent 会自动出手
		return

	# 无攻击目标：向最近敌方塔移动（推进行为）
	_move_target = _find_nearest_enemy_tower()
	if _move_target:
		var target_pos := BattlePathing.game_position_of(_move_target)
		var dist = BattlePathing.path_distance(position, target_pos, movement_type, can_jump_river)
		var stop_dist = AttackComponent.compute_reach(_get_primary_attack_range(), collision_radius, _move_target)
		if dist > stop_dist:
			_is_moving = true
			_move_towards_position(target_pos, delta)


## 按单位能力移动：跳河单位在跳河更短时起跳；其余地面单位沿 A* 路径绕过塔/建筑。
## 空中单位直线飞向目标（不需要寻路）。
func _move_towards_position(target_pos: Vector2, delta: float) -> void:
	if _try_move_for_river_jump(target_pos, delta):
		return

	var step := _get_effective_move_speed() * delta
	# A* 寻路：获取下一个路径点（已处理桥路由和障碍物绕行）
	var next_pos := _get_move_waypoint(target_pos, delta)

	var move_vec := next_pos - position
	if move_vec.length() < 0.01:
		return

	var move_dir := move_vec.normalized()

	# 同类分离：与附近同层单位保持距离，投影到切向实现侧滑绕过
	var separation := _compute_unit_separation(move_dir)
	if separation.length() > 0.01:
		move_dir = (move_dir + separation).normalized()

	position += move_dir * step
	_last_move_dir = move_dir
	_accumulate_charge(step)
	# 移动音效：间歇播放（仅配了 sfx.move 的单位，如野猪骑士蹄声）
	_move_sfx_timer -= delta
	if _move_sfx_timer <= 0.0:
		AudioManager.play_unit_sfx(unit_id, "move")
		_move_sfx_timer = MOVE_SFX_INTERVAL


## 获取当前移动的下一个路径点。地面单位使用 A* 寻路绕过静态障碍物（塔/建筑/河道），
## 路径定期重算以适应障碍物变化（如新部署的建筑）。空中单位直线飞。
func _get_move_waypoint(target_pos: Vector2, delta: float) -> Vector2:
	# 空中单位不需要寻路，直线飞向目标
	if movement_type == "air":
		return target_pos

	_path_repath_timer -= delta
	# 目标变化超过 1 格 → 立即重算；或定时重算
	var target_moved := target_pos.distance_to(_path_target) > BattleConstants.CELL_SIZE
	if _path.is_empty() or target_moved or _path_repath_timer <= 0.0:
		_recompute_path(target_pos)

	# 沿路径前进：跳过已到达的路径点
	while _path.size() > 1:
		if position.distance_to(_path[0]) <= PATH_WAYPOINT_REACHED:
			_path.pop_front()
		else:
			break

	if _path.is_empty():
		return target_pos
	return _path[0]


## 重新计算 A* 路径。
func _recompute_path(target_pos: Vector2) -> void:
	_path = AStarPathfinder.find_path(
		position, target_pos, collision_radius / BattleConstants.CELL_SIZE
	)
	_path_target = target_pos
	_path_repath_timer = PATH_REPATH_INTERVAL


## 计算与附近同层单位的分离转向向量。
## 与静态障碍物避让不同，单位间分离力度更柔和，且投影到移动方向的切平面上，
## 创造"侧滑绕过"效果而非"停下互推"。空中单位返回零向量。
func _compute_unit_separation(move_dir: Vector2) -> Vector2:
	if movement_type == "air":
		return Vector2.ZERO

	var margin := BattleConstants.px(SEPARATION_RADIUS_CELLS)
	var steering := Vector2.ZERO
	var all_entities := EntityRegistry.get_all_combatants()

	for other in all_entities:
		if other == self:
			continue
		if not is_instance_valid(other):
			continue
		if other.get("is_dead") == true:
			continue
		# 同层检查
		var other_mt = other.get("movement_type")
		if other_mt != movement_type:
			continue
		# 跳过静态障碍物（由 _compute_obstacle_avoidance 处理）
		var other_mass = other.get("mass")
		if other_mass != null and int(other_mass) <= 0:
			continue

		var to_other: Vector2 = other.position - position
		var dist := to_other.length()
		if dist < 0.01:
			dist = 0.01
			to_other = Vector2(1.0, 0.0)

		var other_cr = other.get("collision_radius")
		var other_cr_val: float = float(other_cr) if other_cr != null else 10.0
		var trigger_range := collision_radius + other_cr_val + margin
		if dist >= trigger_range:
			continue

		# 前方过滤：只对移动方向前方的单位产生分离（身后的不触发）
		var forward_dist := move_dir.dot(to_other)
		if forward_dist < -collision_radius:
			continue

		# 推力强度：越近越强
		var strength := 1.0 - dist / trigger_range
		steering += (-to_other / dist) * strength

	if steering.length() < 0.01:
		return Vector2.ZERO

	# 限制最大强度
	if steering.length() > 1.0:
		steering = steering.normalized()

	# 关键：投影到切平面（垂直于移动方向），保留少量径向分量
	# 这样单位侧滑绕过同伴而非被推回原地
	if move_dir.length() > 0.01:
		var perp := Vector2(-move_dir.y, move_dir.x)
		var tangential := perp * steering.dot(perp)
		var radial := steering - tangential
		steering = tangential + radial * 0.2

	return steering * 0.5


## 返回当前移动方向（归一化向量）。供 CollisionSystem 切向滑动推挤使用。
## 非移动状态返回零向量。
func get_move_direction() -> Vector2:
	return _last_move_dir if _is_moving else Vector2.ZERO


func _try_move_for_river_jump(target_pos: Vector2, delta: float) -> bool:
	if not can_jump_river or base_movement_type != "ground":
		return false

	var from_side := BattlePathing.river_side(position)
	var to_side := BattlePathing.river_side(target_pos)
	if from_side == 0 or to_side == 0 or from_side == to_side:
		return false
	if not BattlePathing.should_jump_river(position, target_pos):
		return false

	var jump_y := _get_jump_start_y(from_side)
	var jump_start := Vector2(position.x, jump_y)
	var to_start := jump_start - position
	var max_distance := _get_effective_move_speed() * delta

	if to_start.length() > BattlePathing.ARRIVAL_EPSILON:
		if to_start.length() <= max_distance:
			position = jump_start
			_start_river_jump(from_side)
		else:
			position += to_start.normalized() * max_distance
		return true

	_start_river_jump(from_side)
	return true


func _start_river_jump(from_side: int) -> void:
	var start_y := _get_jump_start_y(from_side)
	var end_y := _get_jump_end_y(from_side)
	_jump_start = Vector2(position.x, start_y)
	_jump_end = Vector2(position.x, end_y)
	_jump_elapsed = 0.0
	_jump_duration = max(0.15, _jump_start.distance_to(_jump_end) / max(_get_effective_move_speed() * RIVER_JUMP_SPEED_MULTIPLIER, 1.0))
	position = _jump_start
	is_jumping_river = true
	movement_type = "air"
	altitude = 0.01
	_set_visual_altitude(altitude)
	queue_redraw()


func _get_jump_start_y(from_side: int) -> float:
	return BattleConstants.RIVER_Y_MAX + RIVER_JUMP_BANK_OFFSET if from_side > 0 else BattleConstants.RIVER_Y_MIN - RIVER_JUMP_BANK_OFFSET


func _get_jump_end_y(from_side: int) -> float:
	return BattleConstants.RIVER_Y_MIN - RIVER_JUMP_BANK_OFFSET if from_side > 0 else BattleConstants.RIVER_Y_MAX + RIVER_JUMP_BANK_OFFSET


func _process_river_jump(delta: float) -> void:
	_jump_elapsed += delta
	var t := clampf(_jump_elapsed / _jump_duration, 0.0, 1.0)
	position = _jump_start.lerp(_jump_end, t)
	altitude = sin(t * PI) * RIVER_JUMP_ARC_HEIGHT
	_set_visual_altitude(altitude)
	queue_redraw()

	if t >= 1.0:
		position = _jump_end
		altitude = 0.0
		movement_type = base_movement_type
		is_jumping_river = false
		_set_visual_altitude(0.0)
		queue_redraw()


func _store_visual_base_positions() -> void:
	_body_base_position = body_rect.position
	_health_bar_base_position = health_bar.position
	_debug_label_base_position = debug_label.position


func _set_visual_altitude(altitude_cells: float) -> void:
	_altitude_visual_dy = -altitude_cells * BattleConstants.CELL_SIZE
	_refresh_visual_offsets()


## 统一刷新视觉子节点位置 = base + altitude偏移 + 部署下落偏移。
## altitude 偏移（飞行离地/跳河弧线）和部署下落偏移独立管理，叠加应用。
func _refresh_visual_offsets() -> void:
	var total_dy := _altitude_visual_dy + _deploy_drop_dy
	if body_rect:
		body_rect.position = _body_base_position + Vector2(0, total_dy)
		body_rect.scale = _deploy_scale
	if health_bar:
		health_bar.position = _health_bar_base_position + Vector2(0, total_dy)
	if debug_label:
		debug_label.position = _debug_label_base_position + Vector2(0, total_dy)
	if sprite_animator:
		sprite_animator.apply_altitude_offset(_altitude_visual_dy)
		sprite_animator.set_deploy_offset(_deploy_drop_dy)
		sprite_animator.set_deploy_scale(_deploy_scale)


# ---- 部署下落动画（deploy_time 前期的视觉表现）----

## 每帧推进部署动画，分两阶段：
## 1. 下落阶段（前 DEPLOY_FALL_FRACTION）：ease-in 加速下落 + 透明度渐变，模拟重力。
## 2. 着地弹跳阶段（剩余时间）：着地瞬间挤压（Y压/X拉），用 ease-out-back 弹回正常并轻微过冲。
## 只改 modulate.a（透明度）和视觉缩放，不变暗 RGB，不影响逻辑。
func _update_deploy_anim(delta: float) -> void:
	if _deploy_anim_timer <= 0.0:
		return
	_deploy_anim_timer -= delta
	var t := 1.0 - clampf(_deploy_anim_timer / DEPLOY_ANIM_DURATION, 0.0, 1.0)
	var start_dy := -BattleConstants.px(DEPLOY_DROP_CELLS)

	if t < DEPLOY_FALL_FRACTION:
		# 下落阶段：匀速线性下落 + 透明度渐变
		var tf := t / DEPLOY_FALL_FRACTION
		_deploy_drop_dy = lerpf(start_dy, 0.0, tf)
		_deploy_alpha = lerpf(DEPLOY_GHOST_ALPHA, 1.0, tf)
		_deploy_scale = Vector2.ONE
	else:
		# 着地弹跳阶段：瞬间挤压 → ease-out-back 弹回（带约 10% 过冲）→ 收敛
		_deploy_drop_dy = 0.0
		_deploy_alpha = 1.0
		var tb := (t - DEPLOY_FALL_FRACTION) / (1.0 - DEPLOY_FALL_FRACTION)
		var bounce := _ease_out_back(tb)
		_deploy_scale = Vector2(
			lerpf(DEPLOY_SQUASH_SCALE_X, 1.0, bounce),
			lerpf(DEPLOY_SQUASH_SCALE_Y, 1.0, bounce)
		)

	modulate.a = _deploy_alpha
	_refresh_visual_offsets()


## ease-out-back 缓动：0→1 带过冲（峰值约 1.10），模拟弹性回弹。
static func _ease_out_back(t: float) -> float:
	const c1 := 1.70158
	const c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


## 部署动画结束：恢复实心 + 零偏移 + 正常缩放（is_deployed 由调用方在 deploy_time 到期时设置）。
func _finish_deploy_anim() -> void:
	_deploy_anim_timer = 0.0
	_deploy_drop_dy = 0.0
	_deploy_alpha = 1.0
	_deploy_scale = Vector2.ONE
	modulate.a = 1.0
	_refresh_visual_offsets()


## 从 attacks_data 读取主攻击的射程（格→像素），用于决定何时停下
func _get_primary_attack_range() -> float:
	if attacks_data.is_empty():
		return BattleConstants.px(1.5)  # 兜底值
	return BattleConstants.px(float(attacks_data[0].get("attack_range", 1.5)))


## SpriteAnimator 用：当前是否在攻击（client 端读网络同步值，host 端读 AttackComponent）
func is_attacking() -> bool:
	if _is_remote():
		return _net_is_firing
	var attack = get_primary_attack()
	return attack != null and attack.is_firing()


# ============================================================================
# 联机攻击视觉同步（事件型 reliable RPC）
# ============================================================================
# 背景：从 MultiplayerSynchronizer 迁移到手动 RPC 时，攻击触发状态（_net_is_firing）
# 与攻击朝向的同步通道被遗漏，client 端单位进入攻击时无动画（表现为"僵在原地"）。
# 此处补一条事件型 RPC：host 每次出手时通知 client 播放攻击动画 + 朝向 + 翻转。
# 攻击是低频事件（间隔 0.4~1.4s），用 reliable 保证不漏播，与 _rpc_spawn_projectile 同模式。

## AttackComponent 出手时调用（host 端）：把本次攻击的朝向/翻转同步给 client。
## 无帧动画的单位（ColorRect 兜底）跳过——它们没有 attack 动画可播。
func _on_attack_triggered() -> void:
	if not NetworkManager.is_networked() or not NetworkManager.is_server():
		return
	# 无帧动画的单位不需要同步攻击视觉
	if sprite_animator == null or not sprite_animator._has_animation:
		return
	_rpc_attack_trigger.rpc(get_attack_facing(), get_flip_h())


## Host → Client：同步一次攻击触发。
## attack_facing / flip_h 在 client 端按 180° 镜像规则翻转：
##   side 不变（|dx| 在镜像下不变）；front↔back 互换（dy 变号）；flip_h 取反（左右翻转）。
@rpc("authority", "call_remote", "reliable")
func _rpc_attack_trigger(attack_facing: String, flip_h: bool) -> void:
	if NetworkManager.is_server():
		return
	var mirrored := attack_facing
	if attack_facing == "front":
		mirrored = "back"
	elif attack_facing == "back":
		mirrored = "front"
	_net_attack_facing = mirrored
	_net_flip_h = not flip_h
	_net_is_firing = true


## SpriteAnimator 检测到攻击动画播完后调用，清除一次性攻击标记。
func _clear_attack_flag() -> void:
	_net_is_firing = false


## 覆写视觉状态：移动中返回 "walk"，否则返回 "idle"。
## SpriteAnimator 每帧轮询此方法决定播放什么动画。
func get_visual_state() -> String:
	if _is_remote():
		# Client 端本地推断：_net_visual_state 从未 RPC 同步，改用 _is_moving
		if is_dead:
			return "death"
		if not is_deployed:
			return "walk"
		return "walk" if _is_moving else "idle"
	if is_dead:
		return "death"
	if is_jumping_river:
		return "jump"
	if not is_deployed:
		return "walk"
	if _is_moving:
		return "walk"
	# Host 端顺便更新网络变量（供 Synchronizer 同步到 client）
	var state := "idle"
	var attack = get_primary_attack()
	_net_is_firing = attack != null and attack.is_firing()
	_net_visual_state = state
	return state


## 覆写朝向：根据当前目标 Y 坐标判定 front（面朝下/镜头）或 back（面朝上/背身）。
func get_facing() -> String:
	if _is_remote():
		# Client 端本地推断：坐标镜像 + team 翻转后，按 team 决定朝向恰好正确
		# （player 单位镜像后向上走→back，enemy 单位镜像后向下走→front）
		var f2 := "back" if team == "player" else "front"
		_net_facing = f2
		return f2
	# 部署期间无目标，按阵营强制朝向（player 向上走=back，enemy 向下走=front）
	if not is_deployed:
		var f := "back" if team == "player" else "front"
		_net_facing = f
		return f
	var facing := "front" if _get_target_y() >= position.y else "back"
	_net_facing = facing
	return facing


## 覆写水平翻转：目标在右侧时翻转为 true（素材默认面朝左）。
func get_flip_h() -> bool:
	if _is_remote():
		# 攻击期间单位静止（位置不变，移动方向推断失效），用 host 同步的翻转值
		if _net_is_firing:
			return _net_flip_h
		# Client 端本地推断：用 RPC 目标位置的 X 变化判断左右移动
		var dx := _sync_target_pos.x - _last_sync_target.x
		var flip := dx > 0.3
		_net_flip_h = flip
		return flip
	var flip := _get_target_x() > position.x
	_net_flip_h = flip
	return flip


## 攻击动画朝向（三态）：根据攻击目标相对自身的方向判定。
## - 目标偏水平（|dx| > |dy|，45° 内）→ "side"
## - 目标在正下方（dy 主导且 dy > 0）→ "front"
## - 目标在正上方（dy 主导且 dy < 0）→ "back"
## 无攻击目标时回退到 get_facing()（仅 front/back）。
func get_attack_facing() -> String:
	if _is_remote():
		# Client 端：读 host 同步的攻击朝向（已在 _rpc_attack_trigger 接收时做过镜像翻转）
		return _net_attack_facing
	var tx := _get_target_x()
	var ty := _get_target_y()
	var dx := absf(tx - position.x)
	var dy := ty - position.y
	if dx > absf(dy):
		return "side"
	return "back" if ty < position.y else "front"


## 当前关注目标的 X 坐标（攻击目标优先，其次移动目标，无目标返回自身）。
func _get_target_x() -> float:
	var attack = get_primary_attack()
	if attack and attack.has_valid_target():
		return BattlePathing.game_position_of(attack.current_target).x
	if _move_target:
		return BattlePathing.game_position_of(_move_target).x
	return position.x


## 当前关注目标的 Y 坐标（攻击目标优先，其次移动目标，无目标返回自身）。
func _get_target_y() -> float:
	var attack = get_primary_attack()
	if attack and attack.has_valid_target():
		return BattlePathing.game_position_of(attack.current_target).y
	if _move_target:
		return BattlePathing.game_position_of(_move_target).y
	return position.y


## 找无攻击目标时的推进方向（最近的敌方建筑）。
## "any" 单位只认塔（不偏离主路线）；
## "building_only" 单位认所有建筑（塔 + 建筑卡牌，如迫击炮），可被建筑拉扯。
func _find_nearest_enemy_tower():
	var enemies = EntityRegistry.get_enemies_of(team)
	var nearest = null
	var nearest_dist = 999999.0
	for e in enemies:
		# building_only 单位认所有建筑（mass=0，含塔和建筑卡牌）；
		# any 单位只认塔，避免被敌方建筑带偏主推进路线
		if movement_targeting == "building_only":
			var m = e.get("mass")
			if m == null or int(m) > 0:
				continue
		else:
			if e.get("tower_type") == null:
				continue
		var d = BattlePathing.path_distance(
			position,
			BattlePathing.game_position_of(e),
			movement_type,
			can_jump_river
		)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest


## 死亡：触发死亡范围伤害（super.die），从注册表注销，发出信号，销毁
func die() -> void:
	super.die()
	if _is_remote():
		# Client 端：不注销（未注册）、不触发死亡逻辑链，只播放视觉
		return
	EntityRegistry.unregister(self)
	SignalBus.unit_died.emit(self, team)
	print("[UnitBase] unit died:", unit_id)
	queue_free()


## 联机 client 端：检测到 host 同步的 is_dead=true 后，延迟销毁（留 0.3 秒让死亡视觉播放）
func _on_remote_death() -> void:
	# 变灰 + 淡出
	modulate = Color(0.5, 0.5, 0.5, 0.7)
	# 延迟销毁（让玩家看到死亡瞬间）
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
