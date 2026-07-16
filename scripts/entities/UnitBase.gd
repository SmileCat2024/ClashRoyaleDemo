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
var is_awakened: bool = false  ## 是否为觉醒版（数据驱动效果已应用，可用于视觉标识）

# ---- 精英技能（由卡牌 elite_skill 配置驱动，无配置时为空）----
var elite_skill_data: Dictionary = {}   ## 精英技能配置（来自 card_data.elite_skill）
var _skill_cooldown_timer: float = 0.0  ## 技能冷却剩余（秒，0=可用）
var _skill_total_cooldown: float = 0.0  ## 技能总冷却时间（秒）

# ---- 精英技能：圣光嘲讽法阵 ----
## 法阵先完成短暂的展开，再对完成瞬间仍处于范围内的敌方攻击组件施加嘲讽。
var _holy_taunt_formation_timer: float = 0.0
var _pending_holy_taunt_effect: Dictionary = {}

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
var _path_obstacle_revision: int = -1      ## 生成当前路径时的静态障碍布局版本
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
const PATH_WAYPOINT_REACHED := 12.0   ## 到达路径点的判定距离（像素，约 0.6 格）
const MOVE_FACING_EPSILON := 0.05     ## 移动方向分量低于此值时保持目标/既有朝向，避免近水平/垂直移动抖动

# ---- 部署下落动画（前 DEPLOY_ANIM_DURATION 秒的视觉表现）----
const DEPLOY_ANIM_DURATION := 0.35  ## 部署动画总时长（秒）= 下落 + 着地挤压弹跳
const DEPLOY_DROP_CELLS_DEFAULT := 3.5  ## 下落起始高度默认值（格）
## 下落起始高度（格）。凤凰蛋从凤凰 altitude 高度下落（与死亡模型位置一致）。
var _deploy_drop_cells: float = DEPLOY_DROP_CELLS_DEFAULT
const DEPLOY_GHOST_ALPHA := 0.4     ## 虚影起始透明度（渐变到 1.0 实心，只改 alpha 不变暗）
const DEPLOY_FALL_FRACTION := 0.55  ## 下落占总时长的比例（剩余为挤压弹跳）
const DEPLOY_SQUASH_SCALE_Y := 0.6  ## 着地瞬间 Y 压缩比（高度变 60%）
const DEPLOY_SQUASH_SCALE_X := 1.25 ## 着地瞬间 X 拉伸比（宽度变 125%）

# ---- 觉醒狙击射击硬直 + 锁定 ----
const SNIPER_FIRE_LOCK := 0.4      ## 射击时站定不动的时间（秒），播放攻击动画
const SNIPER_STRIP_DURATION := 0.8 ## 紫色锁定条持续时间（秒，锁定新目标时显示一次）
const SNIPER_LOCK_DELAY := 0.15    ## 新锁定后首发射击延迟（秒，让紫色条先作为预警出现）

## 影子椭圆纵向压缩比。把正圆按此值压扁成椭圆。
const SHADOW_SQUASH := 0.35

## 影子椭圆水平半径（px）。setup 时从 shadow_size（格）转换。0 = 不画影子。
var _shadow_radius: float = 0.0
## 影子垂直偏移（px）。正值=下移。贴图脚部偏上的单位（如哥布林）下移影子对齐视觉脚底。
var _shadow_offset_y: float = 0.0

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
# ---- 孵化重生（凤凰蛋专属；无 hatch_unit_id 配置时不启用）----
## 孵化出的单位 id（空 = 不可孵化）。蛋在 hatch_time 内未被摧毁，则到期生成此单位。
var hatch_unit_id: String = ""
## 孵化所需时间（秒）。仅 hatch_unit_id 非空时有意义。
var hatch_time: float = 0.0
var _hatch_timer: float = 0.0
## 蛋孵化前的蛋碎动画时长（秒）。_hatch_timer 递减到此阈值内时切换为 hatch 视觉。
const HATCH_BREAK_DURATION := 0.4
## 蛋碎开始后是否已生成重生凤凰（防止重复生成）。
var _hatched: bool = false
# ---- 落地冲击（凤凰蛋专属；无 spawn_damage 配置时不启用）----
## 部署完成时从空中落下造成的范围伤害（0 = 无落地伤害）。
var spawn_damage: int = 0
## 落地伤害范围（像素，setup 时从格转换）。
var spawn_radius: float = 0.0
var _spawn_damage_dealt: bool = false
## 被动圣水生产（圣水收集器）。部署完成后才开始计时。
var _elixir_generation_interval: float = 0.0
var _elixir_generation_amount: int = 0
var _elixir_generation_timer: float = 0.0
var _elixir_on_death: int = 0
var _elixir_death_paid: bool = false
## 光束发射点 Y 偏移（像素，负=上移）。仅地狱塔配置，其他单位 = 0（无光束）。
var beam_emit_offset_y: float = 0.0
var _beam: InfernoBeam = null
## Client 端光束同步状态（host 通过 RPC 同步，client 端 _update_beam_visual 读取替代 AttackComponent）
var _sync_beam_active: bool = false
var _sync_beam_target: Vector2 = Vector2.ZERO
var _sync_beam_stage: int = 0

# ---- 精英技能：冲刺（死亡俯冲等 dash 类技能的运行时状态机）----
## 是否正在冲刺。冲刺期间禁用普通 AI（索敌/移动/攻击），直线飞向 _dash_target_pos。
## 类似 is_jumping_river，在 _process 中优先检查并提前 return。
var is_dashing: bool = false
var _dash_target_pos: Vector2 = Vector2.ZERO   ## 冲刺目标位置（World 本地游戏空间）
var _dash_speed: float = 0.0                    ## 冲刺速度（像素/秒）
var _dash_damage: int = 0                       ## 冲刺到达后造成的范围伤害（对单位）
var _dash_tower_damage: int = 0                 ## 冲刺到达后对塔的伤害（减伤值）
var _dash_radius: float = 0.0                   ## 冲刺伤害范围（像素）
var _dash_target = null                         ## 冲刺目标单位引用（冲刺中持续追踪实时位置）
## 到达判定的最小距离容差（像素）。小于此值视为到达，触发伤害结算。
const DASH_ARRIVAL_THRESHOLD := 6.0

# ---- 精英技能：被动标记（技能可用时持续标记血量最低敌人）----
## 被动标记间隔（秒）。每隔此时长重新扫描最弱敌人，防止目标频繁切换。
const PASSIVE_MARK_SCAN_INTERVAL := 0.4
var _passive_mark: DeathMark = null      ## 当前被动标记节点（持续模式，跟随目标）
var _passive_mark_target = null          ## 当前被标记的目标单位（CombatantBase 或 null）
var _passive_scan_timer: float = 0.0     ## 扫描倒计时

# ---- 觉醒狙击弹（觉醒女枪专属，数据驱动）----
## 狙击弹系统：单位进入战场后持有 _sniper_shots 发狙击弹，持续扫描正前方条带区域，
## 发现远距离（超出普攻射程的）敌方兵种单位时自动发射，伤害为普攻的倍率。
## 弹药用完后回归普通行为。
var _sniper_enabled: bool = false            ## 是否启用狙击弹系统
var _sniper_shots: int = 0                   ## 剩余狙击弹数量
var _sniper_damage: int = 0                  ## 狙击弹伤害（普攻伤害 × damage_mult）
var _sniper_scan_half_width: float = 0.0     ## 正前方扫描条带半宽（像素）
var _sniper_cooldown: float = 0.0            ## 两次狙击射击之间的冷却（秒，= 普攻 attack_interval）
var _sniper_cooldown_timer: float = 0.0      ## 当前冷却剩余（秒）
var _sniper_firing: bool = false             ## 狙击射击硬直中（播放攻击动画 + 禁止移动）
var _sniper_fire_lock: float = 0.0           ## 射击硬直剩余时间（秒）
var _sniper_locked_target: WeakRef = null    ## 当前锁定目标（WeakRef，目标死亡自动失效）
var _sniper_strip_timer: float = 0.0         ## 紫色锁定条显示剩余（秒，>0 时绘制，仅在锁定新目标时触发）

# ---- 部署下落动画（deploy_time 前期的视觉表现，不影响逻辑）----
var _deploy_anim_timer: float = 0.0   ## 下落动画剩余时间（秒，>0 表示动画进行中）
var _deploy_drop_dy: float = 0.0      ## 当前下落 Y 偏移（px，负=上移，0=无偏移）
var _deploy_alpha: float = 1.0        ## 当前透明度（0~1，只改 modulate.a 不变暗）
var _deploy_scale: Vector2 = Vector2.ONE  ## 部署挤压拉伸当前缩放（着地瞬间压扁→弹回正常）
var _altitude_visual_dy: float = 0.0  ## 当前 altitude 离地视觉偏移（px，负=上移）

# ---- 隐身（皇室幽灵，数据驱动；无 stealth 配置时 is_stealth_capable=false）----
## 攻击显形持续时长（秒）：覆盖攻击动作 + 短暂恢复期，过后回到隐身。
## 可被 unit_data.stealth.reveal_duration 覆盖。
const STEALTH_REVEAL_DURATION := 0.7
var is_stealth_capable: bool = false        ## 是否具备隐身能力（unit_data.stealth.enabled）
var _stealth_reveal_duration: float = 0.7   ## 本次显形总时长（秒，默认 STEALTH_REVEAL_DURATION）
var _stealth_reveal_timer: float = 0.0      ## 显形剩余时间（秒，>0 表示当前显形中）
# ---- 攻击溅射范围显示（impact_offset 单位如皇室幽灵；无 impact_offset 时不显示）----
var _attack_splash_radius: float = 0.0  ## 溅射显示半径（像素，0=不显示）
var _attack_splash_offset: float = 0.0  ## 溅射圆心偏移距离（像素，0=不显示/自身中心）


## 初始化单位属性。由 SpawnManager 在生成单位后调用。
## awakening_effects: 觉醒效果配置（来自 AwakeningTracker.record_play 返回值），空字典=普通版。
## p_elite_skill_data: 精英技能配置（来自 card_data.elite_skill），空字典=无技能。
## p_visual_overrides: 卡牌专属视觉覆盖（目前用于精英变种），只允许覆盖 animation 字段。
func setup(unit_data: Dictionary, team_name: String, awakening_effects: Dictionary = {}, p_elite_skill_data: Dictionary = {}, p_visual_overrides: Dictionary = {}) -> void:
	unit_id = unit_data.get("id", "")
	display_name = unit_data.get("display_name", "")
	team = team_name
	# 联机 client 在收到第一段有效位移前没有目标数据，先用阵营推进方向初始化视觉朝向。
	_net_facing = "back" if team == "player" else "front"
	move_speed = BattleConstants.px(float(unit_data.get("move_speed", 1.0)))
	base_movement_type = unit_data.get("movement_type", "ground")
	movement_type = base_movement_type
	can_jump_river = bool(unit_data.get("can_jump_river", false))
	sight_range = BattleConstants.px(float(unit_data.get("sight_range", 6.0)))
	movement_targeting = unit_data.get("movement_targeting", "any")

	# 卡牌专属的视觉覆盖只合并到 animation，保证精英变种可调整模型而不改普通单位数值。
	var visual_data: Dictionary = unit_data
	var animation_overrides: Dictionary = p_visual_overrides.get("animation", {})
	if not animation_overrides.is_empty():
		visual_data = unit_data.duplicate(true)
		var animation_data: Dictionary = visual_data.get("animation", {}).duplicate(true)
		animation_data.merge(animation_overrides, true)
		visual_data["animation"] = animation_data

	# 初始化战斗属性（基类方法）
	_init_combat_stats(visual_data)

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
	# 死亡生成单位（如凤凰死亡留下蛋）；与死亡炸弹可同时生效
	death_spawn_unit_id = str(unit_data.get("death_spawn_unit_id", ""))

	# 建筑机制配置（寿命/部署/自然掉血，仅建筑单位使用）
	deploy_time = float(unit_data.get("deploy_time", 0.0))
	if deploy_time > 0.0:
		is_deployed = false
		_deploy_timer = deploy_time
		# 部署下落动画初始化：启动 0.1 秒下落 + 半透明虚影
		_deploy_anim_timer = DEPLOY_ANIM_DURATION
		_deploy_drop_dy = -BattleConstants.px(_deploy_drop_cells)
		_deploy_alpha = DEPLOY_GHOST_ALPHA
	lifespan = float(unit_data.get("lifespan", 0.0))
	if lifespan > 0.0:
		_lifespan_timer = lifespan
		_burn_rate = float(unit_data.get("lifespan_damage_per_sec", float(max_hp) / lifespan))
	# 孵化重生配置（凤凰蛋专属；到期生成新单位而非死亡，期间不掉血）
	hatch_unit_id = str(unit_data.get("hatch_unit_id", ""))
	hatch_time = float(unit_data.get("hatch_time", 0.0))
	if hatch_time > 0.0:
		_hatch_timer = hatch_time
	# 落地冲击伤害配置（凤凰蛋专属：部署完成时从空中落下造成范围伤害）
	spawn_damage = int(unit_data.get("spawn_damage", 0))
	spawn_radius = BattleConstants.px(float(unit_data.get("spawn_radius", 0.0)))
	# 被动圣水生产。计时器在部署阶段不推进，部署完成后第 interval 秒产出首滴。
	_elixir_generation_interval = float(unit_data.get("elixir_generation_interval", 0.0))
	_elixir_generation_amount = int(unit_data.get("elixir_generation_amount", 0))
	_elixir_generation_timer = _elixir_generation_interval
	_elixir_on_death = int(unit_data.get("elixir_on_death", 0))
	_elixir_death_paid = false
	# 光束发射点偏移（仅地狱塔等递增光束单位配置）
	beam_emit_offset_y = float(unit_data.get("beam_emit_offset_y", 0.0))

	# 隐身配置（皇室幽灵：移动/待机隐身不可被锁定，攻击时显形）
	var stealth_cfg: Dictionary = unit_data.get("stealth", {})
	is_stealth_capable = bool(stealth_cfg.get("enabled", false))
	_stealth_reveal_duration = float(stealth_cfg.get("reveal_duration", STEALTH_REVEAL_DURATION))
	if is_stealth_capable:
		is_stealthed = true  # 出生即隐身（视觉由 SpriteAnimator 播放 walk_stealth 透明素材实现）
	# 攻击溅射范围显示（impact_offset 单位如皇室幽灵）：从主攻击组件读取半径与偏移
	var _primary_atk = get_primary_attack()
	if _primary_atk != null and _primary_atk.impact_radius > 0.0 and _primary_atk.impact_offset > 0.0:
		_attack_splash_radius = _primary_atk.impact_radius
		_attack_splash_offset = _primary_atk.impact_offset

	# 碰撞几何参数（格 → 像素）
	collision_radius = BattleConstants.px(float(unit_data.get("collision_radius", 0.5)))
	hurt_radius = BattleConstants.px(float(unit_data.get("hurt_radius", 0.5)))
	mass = int(unit_data.get("mass", 5))

	# 影子大小（格 → 像素）。未配置时退化为 collision_radius。
	_shadow_radius = BattleConstants.px(float(unit_data.get("shadow_size", unit_data.get("collision_radius", 0.5))))
	_shadow_offset_y = BattleConstants.px(float(unit_data.get("shadow_offset_y", 0.0)))

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
	var anim_cfg: Dictionary = visual_data.get("animation", {})
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
		altitude = float(unit_data.get("altitude", 2.5))
		_set_visual_altitude(altitude)
	# 统一刷新视觉偏移：确保所有单位（含地面单位）在 setup 中立即应用 altitude + deploy 偏移到精灵，
	# 避免首帧渲染时精灵在错误位置，到第一帧 _process 才跳到下落起始位置
	_refresh_visual_offsets()
	# 部署虚影初始视觉（deploy_time > 0 时单位以半透明虚影状态出现）
	if not is_deployed:
		modulate.a = _deploy_alpha

	# 觉醒效果应用（在 initialized=true 之前调用，apply_awakening 内手动更新血条）
	apply_awakening(awakening_effects)

	# 精英技能配置（来自卡牌 elite_skill 字段，空字典=无技能）
	elite_skill_data = p_elite_skill_data

	initialized = true
	queue_redraw()
	print("[UnitBase] setup:", unit_id, team, "hp:", max_hp, "awakened:", is_awakened)


## 应用觉醒效果。由 setup() 在 initialized=true 之前调用。
## effects 来自 card_data.awakening.effects，数据驱动：每个 key 对应一种效果类型。
## 当前支持的效果 key：
##   "shield"          - 出生自带额外护盾（叠加到 shield / current_shield）
##   "max_hp_bonus"    - 最大血量提升（max_hp / current_hp 同步增加，保持满血）
##   "death_damage"    - 死亡时触发范围伤害（覆盖 death_damage 字段）
##   "death_radius"    - 死亡伤害半径（格，配合 death_damage 使用）
##   "death_fuse_time" - 死亡炸弹引信延迟（秒，配合 death_damage 使用）
##   "sniper_shots"   - 觉醒狙击弹（持有 N 发，扫描正前方远距离敌方兵种自动发射）
##   "projectile_impact_summon_unit_id" - 弹道投射物落点在伤害结算后召唤一只指定单位
## 未识别的 key 会打印警告但不报错，便于逐步扩展新效果类型。
func apply_awakening(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	is_awakened = true

	# 护盾加成（叠加到基础护盾上）
	if effects.has("shield"):
		var bonus_shield := int(effects["shield"])
		shield += bonus_shield
		current_shield += bonus_shield

	# 血量提升（max_hp / current_hp 同步增加，觉醒版保持满血）
	if effects.has("max_hp_bonus"):
		var bonus_hp := int(effects["max_hp_bonus"])
		max_hp += bonus_hp
		current_hp += bonus_hp

	# 死亡炸弹（覆盖原有 death_damage 配置，觉醒版死亡时爆炸）
	if effects.has("death_damage"):
		death_damage = int(effects["death_damage"])
		death_radius = BattleConstants.px(float(effects.get("death_radius", 1.5)))
		death_fuse_time = float(effects.get("death_fuse_time", 0.0))

	# 炮弹落点召唤（觉醒迫击炮）：具体召唤时机由 MortarShell 落地时执行，
	# 这里仅把数据驱动效果保存在攻击者身上，供 AttackComponent 创建炮弹时透传。
	if effects.has("projectile_impact_summon_unit_id"):
		projectile_impact_summon_unit_id = str(effects["projectile_impact_summon_unit_id"])

	# 觉醒狙击弹（觉醒女枪专属）
	if effects.has("sniper_shots"):
		var cfg: Dictionary = effects["sniper_shots"]
		_sniper_enabled = true
		_sniper_shots = int(cfg.get("count", 3))
		var dmg_mult := float(cfg.get("damage_mult", 2.0))
		if not attacks_data.is_empty():
			_sniper_damage = int(float(attacks_data[0].get("damage", 100)) * dmg_mult)
		_sniper_scan_half_width = BattleConstants.px(float(cfg.get("scan_half_width", 1.0)))
		# 狙击射击间隔 = 普攻攻击间隔
		if not attacks_data.is_empty():
			_sniper_cooldown = float(attacks_data[0].get("attack_interval", 1.0))
		else:
			_sniper_cooldown = 1.0

	# 手动更新血条（此时 initialized 仍为 false，setter 不会自动触发）
	if health_bar:
		health_bar.max_value = max_hp + shield
		health_bar.value = current_hp + current_shield

	# 视觉标识：觉醒版 debug_label 加后缀
	if debug_label:
		debug_label.text = display_name + "·觉醒"

	# 检测未识别的效果 key（仅警告，不阻断运行）
	for key in effects:
		match key:
			"shield", "max_hp_bonus", "death_damage", "death_radius", "death_fuse_time", "sniper_shots":
				pass  # 已支持
			_:
				push_warning("[UnitBase] 未识别的觉醒效果 key: %s（单位 %s）" % [key, unit_id])


# ==============================================================================
# 精英技能
# ==============================================================================

## 精英技能是否可用（已部署完成 + 冷却结束 + 未死亡 + 有技能配置）
func is_skill_ready() -> bool:
	if not initialized or is_dead:
		return false
	if not is_deployed:
		return false
	if elite_skill_data.is_empty():
		return false
	return _skill_cooldown_timer <= 0.0


## 触发精英技能。由 EliteSkillManager（经 BattleManager 能量检查后）调用。
## target_pos: targeted 技能的目标位置（instant 技能忽略此参数）。
## 按 effect.type 数据驱动分流，当前支持：
##   "self_rage"       - 自身狂暴（移速+攻速提升，复用 StatusEffect.rage 系统）
##   "dash_to_weakest" - 锁定场上血量最低的敌方单位，在其脚下生成黑色标志，
##                        然后自身高速冲刺至目标位置，到达后造成范围伤害
##   "holy_taunt"      - 在自身周围展开金色圣光法阵，对阵内可攻击部队的敌人强制锁敌
## 未识别的 type 会打印警告但不报错，便于逐步扩展新技能效果。
func trigger_skill(target_pos: Vector2) -> void:
	if not is_skill_ready():
		return
	var effect: Dictionary = elite_skill_data.get("effect", {})
	var effect_type: String = effect.get("type", "")
	var skill_consumed := true  ## 本次释放是否消耗冷却（某些分支在无有效目标时中止）
	match effect_type:
		"self_rage":
			var duration := float(effect.get("duration", 3.0))
			var move_mult := float(effect.get("move_mult", 1.35))
			var attack_mult := float(effect.get("attack_mult", 1.35))
			apply_rage(move_mult, attack_mult, duration)
		"dash_to_weakest":
			skill_consumed = _trigger_dash_to_weakest(effect)
		"holy_taunt":
			skill_consumed = _trigger_holy_taunt(effect)
		_:
			push_warning("[UnitBase] 未识别的精英技能效果类型: %s（单位 %s）" % [effect_type, unit_id])
	if not skill_consumed:
		# 无有效目标，技能未实际释放，不消耗冷却也不广播
		print("[UnitBase] 精英技能未找到有效目标，取消释放:", unit_id, effect_type)
		return
	# 启动冷却
	_skill_total_cooldown = float(elite_skill_data.get("cooldown", 0.0))
	_skill_cooldown_timer = _skill_total_cooldown
	# 广播技能释放 + 冷却开始（SkillBar 启动倒计时动画）
	SignalBus.elite_skill_cast.emit(self, elite_skill_data, target_pos)
	SignalBus.elite_skill_cooldown_changed.emit(self, _skill_cooldown_timer, _skill_total_cooldown)
	print("[UnitBase] 精英技能释放:", unit_id, effect_type)


## 「圣光嘲讽」：先播放短暂的金色法阵展开，法阵完成时按当前位置做一次范围快照。
## effect 字段：radius（格）/ duration（秒）/ formation_duration（秒）。
func _trigger_holy_taunt(effect: Dictionary) -> bool:
	var radius := BattleConstants.px(float(effect.get("radius", 8.5)))
	var taunt_duration := float(effect.get("duration", 4.0))
	var formation_duration := float(effect.get("formation_duration", 0.35))
	if radius <= 0.0 or taunt_duration <= 0.0:
		return false
	_pending_holy_taunt_effect = {
		"radius": radius,
		"duration": taunt_duration,
	}
	_holy_taunt_formation_timer = maxf(formation_duration, 0.0)
	_spawn_holy_taunt_vfx(radius, _holy_taunt_formation_timer)
	# 允许配置 0 秒展开，以便数据调试或特殊版本即时结算。
	if _holy_taunt_formation_timer <= 0.0:
		_apply_holy_taunt()
	return true


## 每帧推进法阵展开；仅 host/单机执行实际的锁敌逻辑。
func _process_holy_taunt(delta: float) -> void:
	if _pending_holy_taunt_effect.is_empty():
		return
	_holy_taunt_formation_timer -= delta
	if _holy_taunt_formation_timer <= 0.0:
		_apply_holy_taunt()


## 在法阵完成的当前位置，对范围内敌方实体的攻击组件逐一施加嘲讽。
## AttackComponent 会在之后的每帧索敌前强制使用本单位为目标，因此 UnitBase 的寻路也自动跟随。
func _apply_holy_taunt() -> void:
	if _pending_holy_taunt_effect.is_empty() or is_dead:
		_pending_holy_taunt_effect.clear()
		return
	var radius: float = float(_pending_holy_taunt_effect.get("radius", 0.0))
	var duration: float = float(_pending_holy_taunt_effect.get("duration", 0.0))
	_pending_holy_taunt_effect.clear()
	_holy_taunt_formation_timer = 0.0
	var affected_components := 0
	for enemy in EntityRegistry.get_enemies_of(team):
		if not (enemy is CombatantBase):
			continue
		# 只有 UnitBase 才拥有部署状态；塔和测试用 CombatantBase 不应被误判为未部署。
		if enemy is UnitBase and not enemy.is_deployed:
			continue
		var distance := BattlePathing.game_position_of(self).distance_to(BattlePathing.game_position_of(enemy))
		var hurt_radius = enemy.get("hurt_radius")
		if hurt_radius != null:
			distance = maxf(0.0, distance - float(hurt_radius))
		if distance > radius:
			continue
		for attack in enemy.attack_components:
			if attack is AttackComponent and attack.apply_taunt(self, duration):
				affected_components += 1
	print("[UnitBase] 圣光嘲讽生效:", unit_id, "components:", affected_components)


## 在 EffectsRoot 创建金色法阵。没有专用 EffectsRoot 的测试场景回退到当前单位父节点。
func _spawn_holy_taunt_vfx(radius: float, formation_duration: float) -> void:
	var parent: Node = get_parent()
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var effects_root := tree.current_scene.get_node_or_null("World/EffectsRoot")
		if effects_root != null:
			parent = effects_root
	if parent != null:
		TauntHolyCircleEffect.spawn(parent, BattlePathing.game_position_of(self), radius, formation_duration)


## 「死亡俯冲」技能分支：冲向当前被动标记锁定的血量最低敌方单位。
## 被动标记由 _update_passive_mark() 在技能可用时持续维护（目标脚下一直显示黑色标志）。
## 释放时销毁被动标记，进入冲刺状态。返回 true 表示成功（消耗冷却），false 表示无有效目标（中止）。
## effect 字段：dash_speed_cells（或 dash_speed_mult）/ impact_damage / impact_radius(格) / tower_damage_ratio
func _trigger_dash_to_weakest(effect: Dictionary) -> bool:
	# 优先使用被动标记锁定的目标；若标记不存在则实时扫描一次
	var target = _passive_mark_target
	if target == null or not is_instance_valid(target) or target.get("is_dead") == true:
		target = _find_weakest_enemy_unit()
	if target == null:
		return false
	# 锁定目标位置（目标单位当前 position，即"脚下"）
	var target_pos := BattlePathing.game_position_of(target)
	# 销毁被动标记（冲刺开始，不再需要持续标记）
	_clear_passive_mark()
	# 进入冲刺状态
	_dash_target = target
	_dash_target_pos = target_pos
	# 冲刺速度：优先用固定格速（dash_speed_cells），否则回退到 move_speed × 倍率
	var dash_cells := float(effect.get("dash_speed_cells", 0.0))
	if dash_cells > 0.0:
		_dash_speed = BattleConstants.px(dash_cells)
	else:
		_dash_speed = move_speed * float(effect.get("dash_speed_mult", 4.0))
	_dash_damage = int(effect.get("impact_damage", 0))
	var ratio := float(effect.get("tower_damage_ratio", 0.5))
	_dash_tower_damage = int(round(_dash_damage * ratio))
	_dash_radius = BattleConstants.px(float(effect.get("impact_radius", 1.5)))
	is_dashing = true
	_is_moving = true
	queue_redraw()
	AudioManager.play_unit_sfx(unit_id, "deploy")  # 复用部署音效作为冲刺音效（临时）
	return true


## 查找场上血量最低的敌方单位（含飞行和地面）。返回 CombatantBase 或 null。
## 跳过已死亡单位、未部署完成的建筑。塔（tower_type != null）不参与（只锁敌普通单位）。
func _find_weakest_enemy_unit():
	var enemies = EntityRegistry.get_enemies_of(team)
	var weakest = null
	var lowest_hp := 99999999
	for e in enemies:
		if not is_instance_valid(e):
			continue
		# Object.get() 只接受 1 个参数（与 Dictionary.get(key, default) 不同）
		if e.get("is_dead") == true:
			continue
		# 只锁定普通单位，跳过塔（tower_type != null）
		if e.get("tower_type") != null:
			continue
		# 跳过未部署完成的实体（is_deployed 是 UnitBase 属性，塔无此属性时 get 返回 null，不误过滤）
		if e.get("is_deployed") == false:
			continue
		# 隐身过滤：隐身单位不可被索敌锁定（含精英技能锁定）
		if e.get("is_stealthed") == true:
			continue
		var hp_val = e.get("current_hp")
		if hp_val == null:
			continue
		var hp: int = int(hp_val)
		if hp < lowest_hp:
			lowest_hp = hp
			weakest = e
	return weakest


## 被动标记维护：技能可用（冷却结束 + 已部署）且非冲刺时，持续在场上血量最低的
## 敌方单位脚下显示黑色标志。每 PASSIVE_MARK_SCAN_INTERVAL 秒重新选择目标，
## 每帧更新标记位置跟随目标移动。目标消失/无敌人时清除标记。
func _update_passive_mark(delta: float) -> void:
	# 仅 dash_to_weakest 类型技能才做被动标记
	var effect: Dictionary = elite_skill_data.get("effect", {})
	if effect.get("type", "") != "dash_to_weakest":
		return
	# 技能不可用（冷却中 / 未部署 / 死亡）时不标记
	if not is_skill_ready():
		_clear_passive_mark()
		return
	# 每帧更新现有标记位置（跟随目标移动）
	if _passive_mark and is_instance_valid(_passive_mark) and _passive_mark_target and is_instance_valid(_passive_mark_target):
		_passive_mark.update_position(BattlePathing.game_position_of(_passive_mark_target))
	# 定期重新扫描最弱敌人（目标可能因受伤/死亡而变化）
	_passive_scan_timer -= delta
	if _passive_scan_timer > 0.0:
		return
	_passive_scan_timer = PASSIVE_MARK_SCAN_INTERVAL
	var new_target = _find_weakest_enemy_unit()
	# 目标未变化：保持现有标记
	if new_target == _passive_mark_target:
		return
	# 目标变化或标记丢失：销毁旧标记
	_clear_passive_mark()
	if new_target == null:
		return
	# 创建新标记
	_passive_mark_target = new_target
	var mark_radius := BattleConstants.px(0.7)
	# 传入释放方 team：我方标志泛蓝 / 敌方标志泛红，便于一眼区分是谁施加的处决标记
	_passive_mark = DeathMark.spawn_persistent(get_parent(), BattlePathing.game_position_of(new_target), mark_radius, team)


## 清除被动标记（目标变化 / 技能释放 / 单位死亡时调用）
func _clear_passive_mark() -> void:
	_passive_mark_target = null
	if _passive_mark and is_instance_valid(_passive_mark):
		_passive_mark.expire()
	_passive_mark = null


## 每帧推进冲刺。锁敌追踪——目标存活时每帧更新冲刺终点为目标实时位置。
## 直线高速移动，到达后造成范围伤害并退出冲刺状态。
func _process_dash(delta: float) -> void:
	# 锁敌追踪：目标存活时每帧更新冲刺终点
	if _dash_target and is_instance_valid(_dash_target) and not _dash_target.get("is_dead"):
		_dash_target_pos = BattlePathing.game_position_of(_dash_target)
	var to_target := _dash_target_pos - position
	var dist := to_target.length()
	# 到达判定
	if dist <= DASH_ARRIVAL_THRESHOLD:
		_arrive_dash()
		return
	var step := _dash_speed * delta
	if step >= dist:
		position = _dash_target_pos
		_arrive_dash()
		return
	position += to_target.normalized() * step
	_last_move_dir = to_target.normalized()


## 冲刺到达：结算范围伤害 + 退出冲刺状态，恢复正常 AI。
func _arrive_dash() -> void:
	# 造成范围伤害（对单位全额，对塔减伤；同时攻击地面和空中）
	if _dash_damage > 0:
		DamageSystem.deal_area_damage(_dash_target_pos, _dash_radius, _dash_damage, team, _dash_tower_damage)
		BlastRingEffect.spawn(get_parent(), _dash_target_pos, _dash_radius)
	# 退出冲刺状态
	is_dashing = false
	_dash_target = null
	_dash_damage = 0
	_dash_tower_damage = 0
	_is_moving = false
	queue_redraw()
	print("[UnitBase] 冲刺到达:", unit_id)


## 每帧更新精英技能冷却。冷却结束时 emit 信号（SkillBar 恢复可点击）。
func _process_skill_cooldown(delta: float) -> void:
	if _skill_cooldown_timer <= 0.0:
		return
	_skill_cooldown_timer -= delta
	if _skill_cooldown_timer <= 0.0:
		_skill_cooldown_timer = 0.0
		SignalBus.elite_skill_cooldown_changed.emit(self, 0.0, _skill_total_cooldown)


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
		draw_set_transform(Vector2(0, _shadow_offset_y), 0.0, Vector2(1.0, SHADOW_SQUASH))
		draw_circle(Vector2.ZERO, _shadow_radius, Color(0, 0, 0, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 攻击溅射范围指示（impact_offset 单位如皇室幽灵的前方落点溅射）：仅攻击时显示
	if _attack_splash_offset > 0.0 and is_attacking():
		_draw_attack_splash()
	# 狙击锁定条（锁定新目标时显示一次，持续到 SNIPER_STRIP_DURATION 结束）
	if _sniper_strip_timer > 0.0:
		_draw_sniper_lock_strip()
	# 地狱塔递增光束由独立子节点 InfernoBeam 绘制（ADD 混合），此处不处理


## 狙击锁定条：射击时从自身位置向敌方底边画一条紫色光晕条带（视觉锁定提示）。
## 与 DeployPreview 拖动预览的紫色条带配色一致，敌我觉醒女枪均显示。
func _draw_sniper_lock_strip() -> void:
	var half_w := _sniper_scan_half_width
	# 条带终点 Y（本地坐标）：player 向上到竞技场顶，enemy 向下到底
	var strip_end_y: float
	if team == "player":
		strip_end_y = -position.y                     # 向上到 y=0
	else:
		strip_end_y = BattleConstants.ARENA_HEIGHT - position.y  # 向下到 y=640
	var top_y: float = minf(0.0, strip_end_y)
	var bot_y: float = maxf(0.0, strip_end_y)
	var height := bot_y - top_y
	# 三层渐变紫色光晕（外宽淡 → 内窄亮）
	var purple := Color(0.6, 0.3, 0.9)
	draw_rect(Rect2(-half_w * 1.8, top_y, half_w * 3.6, height), Color(purple.r, purple.g, purple.b, 0.06))
	draw_rect(Rect2(-half_w * 1.3, top_y, half_w * 2.6, height), Color(purple.r, purple.g, purple.b, 0.10))
	draw_rect(Rect2(-half_w, top_y, half_w * 2.0, height), Color(purple.r, purple.g, purple.b, 0.15))
	# 左右边线
	draw_line(Vector2(-half_w, top_y), Vector2(-half_w, bot_y), Color(purple.r, purple.g, purple.b, 0.35), 1.0)
	draw_line(Vector2(half_w, top_y), Vector2(half_w, bot_y), Color(purple.r, purple.g, purple.b, 0.35), 1.0)


## 绘制攻击溅射范围（impact_offset 单位如皇室幽灵）：以脚底朝目标方向 offset 处为圆心、radius 为半径的圆。
## 地面投影——交由 World 的 Y_COMPRESS 自动压扁成椭圆，符合 2.5D 透视。
## 隐身时由 modulate.a 统一淡化（淡但可见），显形时清晰。
func _draw_attack_splash() -> void:
	var center := _get_attack_splash_center()
	var fill := Color(0.45, 0.32, 0.85, 0.22)
	var border := Color(0.60, 0.48, 0.95, 0.55)
	draw_circle(center, _attack_splash_radius, fill)
	draw_arc(center, _attack_splash_radius, 0.0, TAU, 40, border, 1.2)


## 攻击溅射圆心（本地坐标）。有锁定目标时在朝目标方向 offset 处；无目标时朝推进方向 offset 处。
## Client 端不跑索敌，current_target 为 null，退化为推进方向。
func _get_attack_splash_center() -> Vector2:
	var dir := Vector2(0.0, -1.0) if team == "player" else Vector2(0.0, 1.0)
	var atk = get_primary_attack()
	if atk != null and is_instance_valid(atk) and atk.current_target != null and is_instance_valid(atk.current_target):
		var d: Vector2 = BattlePathing.game_position_of(atk.current_target) - position
		if d.length_squared() > 1.0:
			dir = d.normalized()
	return dir * _attack_splash_offset


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


## 获取场景中的 SpawnManager（死亡生成单位 / 孵化生成单位复用）。沿用 MortarShell 同款查找。
## 返回 Node（需调用方 has_method 判定后动态调用 spawn_unit_by_id）。
func _get_spawn_manager() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var sm := scene.get_node_or_null("Managers/SpawnManager")
	if sm and sm.has_method("spawn_unit_by_id"):
		return sm
	return null


## 孵化重生（凤凰蛋专属）。部署完成后倒计时，到期在原地生成 hatch_unit_id 指定的单位并销毁自身。
## 蛋若在孵化前被攻击摧毁（take_damage → die），则不会到达此处，即不重生。
func _process_hatching(delta: float) -> void:
	_hatch_timer -= delta
	if is_dead:
		return
	# 蛋碎开始（_hatch_timer ≤ HATCH_BREAK_DURATION）：立刻生成重生凤凰，不等蛋碎播完
	if _hatch_timer <= HATCH_BREAK_DURATION and not _hatched:
		_hatched = true
		var spawn_manager := _get_spawn_manager()
		if spawn_manager:
			var reborn := spawn_manager.spawn_unit_by_id(hatch_unit_id, team, position) as UnitBase
			if reborn != null:
				# 重生凤凰不再留蛋：凤凰只能复活一次
				reborn.death_spawn_unit_id = ""
	# 蛋碎播完后销毁蛋
	if _hatch_timer <= 0.0:
		die()


## 死亡生成单位（如凤凰死亡留下凤凰蛋）。在死亡位置生成 death_spawn_unit_id 指定的单位。
## 经 SpawnManager.spawn_unit_by_id 创建，Host→Client 联机生成自动同步。
func _spawn_death_unit_if_any() -> void:
	if death_spawn_unit_id.is_empty():
		return
	var spawn_manager := _get_spawn_manager()
	if spawn_manager:
		var egg: Node = spawn_manager.spawn_unit_by_id(death_spawn_unit_id, team, position)
		# 蛋从凤凰模型位置（altitude 高度）开始下落到地面
		if egg is UnitBase and altitude > 0.0:
			egg._deploy_drop_cells = altitude
			egg._deploy_drop_dy = -BattleConstants.px(altitude)
			egg._refresh_visual_offsets()
	else:
		push_error("[UnitBase] Missing SpawnManager for death spawn: " + unit_id)


## 推进被动圣水生产。满圣水时 BattleManager 不会增加能量，因此本次产出直接舍弃。
func _process_elixir_generation(delta: float) -> void:
	if _elixir_generation_interval <= 0.0 or _elixir_generation_amount <= 0:
		return
	# 冰冻/眩晕暂停生产；减速和狂暴按当前状态的速度倍率调整生产计时。
	# 这里复用状态系统的 move_speed_mult：建筑本身不可移动，但该倍率仍准确表达控制效果。
	var production_speed := get_move_speed_mult()
	if production_speed <= 0.0:
		return
	_elixir_generation_timer -= delta * production_speed
	while _elixir_generation_timer <= 0.0 and not is_dead:
		SignalBus.elixir_generated.emit(position, team, _elixir_generation_amount, false)
		_elixir_generation_timer += _elixir_generation_interval


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
	# 攻击溅射圆心随目标方向变化，需每帧重绘（impact_offset 单位如皇室幽灵）
	if _attack_splash_offset > 0.0:
		queue_redraw()
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
		# Client 不运行本地寻路，用同步速度恢复 host 的实际移动方向，供行走动画和碰撞分离读取。
		if _is_moving and _sync_velocity.length_squared() > 0.01:
			_last_move_dir = _sync_velocity.normalized()
		if not is_deployed:
			_deploy_timer -= delta
			_update_deploy_anim(delta)
			if _deploy_timer <= 0.0:
				is_deployed = true
				_finish_deploy_anim()
		# 地狱塔光束视觉更新（用 RPC 同步的状态驱动，client 端不跑索敌逻辑）
		_update_beam_visual()
		# 隐身视觉（client 端 is_stealthed 由 _rpc_sync_units 同步，直接读取）
		if is_stealth_capable:
			_update_stealth_visual()
		# client 端蛋孵化视觉计时（纯视觉，不生成单位；生成由 host RPC 同步）
		if not hatch_unit_id.is_empty() and is_deployed:
			_hatch_timer -= delta
		return
	# 部署倒计时（deploy_time 期间不能行动；部署完成后才开始寿命/掉血/攻击）
	if not is_deployed:
		_deploy_timer -= delta
		_update_deploy_anim(delta)
		if _deploy_timer <= 0.0:
			is_deployed = true
			_finish_deploy_anim()
		return
	# 落地冲击（凤凰蛋专属）：部署完成时从空中落下造成范围伤害（只触发一次）
	if spawn_damage > 0 and not _spawn_damage_dealt:
		_spawn_damage_dealt = true
		DamageSystem.deal_area_damage(position, spawn_radius, spawn_damage, team)
	# 隐身状态维护（皇室幽灵）：攻击显形计时器递减，过期回隐身
	if is_stealth_capable:
		if _stealth_reveal_timer > 0.0:
			_stealth_reveal_timer -= delta
		is_stealthed = _stealth_reveal_timer <= 0.0
		_update_stealth_visual()
	# 建筑寿命 + 自然掉血（仅 lifespan > 0 的建筑，部署完成后才开始）
	if lifespan > 0.0:
		_process_lifespan(delta)
		if is_dead:
			return
	# 孵化重生（凤凰蛋专属；到期生成新单位并销毁自身，期间不掉血）
	if not hatch_unit_id.is_empty():
		_process_hatching(delta)
		if is_dead:
			return
	_process_elixir_generation(delta)
	# 冲锋累计：上一帧未持续移动则清零（已进入冲锋态的等攻击命中退出）
	if _charge_enabled and not _is_moving:
		_charge_distance_accum = 0.0
	_process_status_effects(delta)
	# 精英技能冷却更新（host 端每帧）
	_process_skill_cooldown(delta)
	# 精英骑士圣光法阵：展开完成时才结算范围嘲讽。
	_process_holy_taunt(delta)
	# 精英技能被动标记：技能可用时持续标记血量最低敌人
	_update_passive_mark(delta)
	# 地狱塔递增光束视觉更新（InfernoBeam 子节点）
	_update_beam_visual()
	_is_moving = false
	if is_jumping_river:
		_is_moving = true
		_process_river_jump(delta)
		return

	# 精英技能冲刺：冲刺期间禁用索敌/攻击/普通移动，直线飞向目标
	if is_dashing:
		_is_moving = true
		_process_dash(delta)
		return

	# 觉醒狙击弹：独立于普攻的远程扫描射击（觉醒女枪专属）
	_process_sniper(delta)

	# 狙击射击硬直：站定不动，播放攻击动画（像普攻一样）
	if _sniper_fire_lock > 0.0:
		_sniper_fire_lock -= delta
		if _sniper_fire_lock <= 0.0:
			_sniper_firing = false
			queue_redraw()
		_is_moving = false
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
	var next_pos := _get_move_waypoint(target_pos)

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


## 获取当前移动的下一个路径点。地面单位使用 A* 寻路绕过静态障碍物（塔/建筑/河道）。
## 已选路线会持续执行；只有目标明显移动、建筑布局变化或路径走完时才重算，避免左右横跳。
func _get_move_waypoint(target_pos: Vector2) -> Vector2:
	# 空中单位不需要寻路，直线飞向目标
	if movement_type == "air":
		return target_pos

	# 目标变化超过 1 格、塔/建筑增减，或当前路径耗尽 → 重算。
	# 不再按固定时间间隔重算：相邻格的等价路径会因此反复切换，造成前进后退的视觉抖动。
	var target_moved := target_pos.distance_to(_path_target) > BattleConstants.CELL_SIZE
	var obstacle_changed := _path_obstacle_revision != EntityRegistry.get_static_obstacle_revision()
	if _path.is_empty() or target_moved or obstacle_changed:
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
	_path_obstacle_revision = EntityRegistry.get_static_obstacle_revision()


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
		_last_move_dir = to_start.normalized()
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
	var jump_move := _jump_end - _jump_start
	if jump_move.length_squared() > 0.01:
		_last_move_dir = jump_move.normalized()
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
	var start_dy := -BattleConstants.px(_deploy_drop_cells)

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


## 隐身视觉：隐身透明由 SpriteAnimator 播放 walk_stealth 素材实现，不再用 modulate.a。
## is_stealthed 仅控制索敌过滤（不可被锁定）+ SpriteAnimator 动画切换（walk↔walk_stealth），
## 不改变整体透明度。保留为 _process 钩子点（部署完成后调用）。
func _update_stealth_visual() -> void:
	pass


## 从 attacks_data 读取主攻击的射程（格→像素），用于决定何时停下
func _get_primary_attack_range() -> float:
	if attacks_data.is_empty():
		return BattleConstants.px(1.5)  # 兜底值
	return BattleConstants.px(float(attacks_data[0].get("attack_range", 1.5)))


## SpriteAnimator 用：当前是否在攻击（client 端读网络同步值，host 端读 AttackComponent / 狙击射击硬直）
func is_attacking() -> bool:
	if _is_remote():
		return _net_is_firing
	if _sniper_firing:
		return true
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


## AttackComponent 每次出手时调用（仅 host 端，client 不跑 AttackComponent 逻辑）。
## 隐身单位进入显形态：启动显形计时器，覆盖攻击动作 + 短暂恢复期后回到隐身。
func _on_attack_started() -> void:
	if is_stealth_capable:
		_stealth_reveal_timer = _stealth_reveal_duration


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


## 显示范围攻击命中时的地面警示环，并同步给联机 client。
## AttackComponent 在真正结算 instant+splash 伤害的时刻调用，保证和伤害帧对齐。
func show_splash_impact_vfx(center: Vector2, radius: float) -> void:
	_spawn_splash_impact_vfx_local(center, radius)
	if NetworkManager.is_networked() and NetworkManager.is_server():
		_rpc_splash_impact_vfx.rpc(center, radius)


## 在本地 World/EffectsRoot 创建范围攻击视觉。
func _spawn_splash_impact_vfx_local(center: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var effects_root := tree.current_scene.get_node_or_null("World/EffectsRoot") as Node2D
	if effects_root == null:
		return
	BlastRingEffect.spawn(effects_root, center, radius)


## Host → Client：同步一次范围攻击命中的纯视觉事件。
@rpc("authority", "call_remote", "reliable")
func _rpc_splash_impact_vfx(center: Vector2, radius: float) -> void:
	if NetworkManager.is_server():
		return
	_spawn_splash_impact_vfx_local(BattleConstants.mirror(center), radius)


## SpriteAnimator 检测到攻击动画播完后调用，清除一次性攻击标记。
func _clear_attack_flag() -> void:
	_net_is_firing = false


## 覆写视觉状态：移动中返回 "walk"，否则返回 "idle"。
## SpriteAnimator 每帧轮询此方法决定播放什么动画。
func get_visual_state() -> String:
	# 凤凰蛋孵化临近：最后 HATCH_BREAK_DURATION 秒播放蛋碎（host/client 共享，需部署完成且存活）
	if not hatch_unit_id.is_empty() and not is_dead and is_deployed and _hatch_timer <= HATCH_BREAK_DURATION:
		return "hatch"
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
		# 冲锋状态优先返回 charge（配 charge_朝向 动画播放冲刺美术）
		# 注：Client 端 is_charging 未 RPC 同步，联机下 Client 冲锋仍显示 walk（仅动画差异，不影响功能）
		if is_charging:
			return "charge"
		return "walk"
	# Host 端顺便更新网络变量（供 Synchronizer 同步到 client）
	var state := "idle"
	var attack = get_primary_attack()
	_net_is_firing = attack != null and attack.is_firing()
	_net_visual_state = state
	return state


## 覆写朝向：移动时按 A* 路径/分离修正后的实际方向判定；静止时按目标方向判定。
## 这样单位为绕开障碍物短暂后退时，walk 动画会跟随路径，而攻击/待机仍朝向目标。
func get_facing() -> String:
	# 部署期间无目标，按阵营强制朝向（player 向上走=back，enemy 向下走=front）
	if not is_deployed:
		var f := "back" if team == "player" else "front"
		_net_facing = f
		return f

	var move_dir := get_move_direction()
	if absf(move_dir.y) > MOVE_FACING_EPSILON:
		var move_facing := "front" if move_dir.y > 0.0 else "back"
		_net_facing = move_facing
		return move_facing

	if _is_remote():
		# Client 没有本地索敌数据；近水平移动或静止时保留最近朝向，首次则按阵营兜底。
		if _net_facing == "front" or _net_facing == "back":
			return _net_facing
		var remote_facing := "back" if team == "player" else "front"
		_net_facing = remote_facing
		return remote_facing

	var facing := "front" if _get_target_y() >= position.y else "back"
	_net_facing = facing
	return facing


## 覆写水平翻转：移动时按实际移动方向；静止/攻击时按目标方向（素材默认面朝左）。
func get_flip_h() -> bool:
	if _is_remote():
		# 攻击期间单位静止（位置不变，移动方向推断失效），用 host 同步的翻转值
		if _net_is_firing:
			return _net_flip_h

	var move_dir := get_move_direction()
	if absf(move_dir.x) > MOVE_FACING_EPSILON:
		var move_flip := move_dir.x > 0.0
		_net_flip_h = move_flip
		return move_flip

	if _is_remote():
		# 纯纵向移动时左右镜像没有新的信息，保持最近一次同步推断结果。
		return _net_flip_h

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


# ==============================================================================
# 觉醒狙击弹系统（觉醒女枪专属）
# ==============================================================================
# 机制：单位持有 N 发狙击弹，持续扫描正前方条带区域（朝对方方向的纵向直线，
# 左右各 scan_half_width 宽度），寻找远距离（超出普攻射程的）敌方兵种单位。
# 发现目标后发射一发狙击弹（即时伤害 + 弹道线视觉），弹药耗尽后回归普通行为。
# 狙击与普攻独立运作：近处敌人由 AttackComponent 普攻处理，远处敌人由狙击处理。

## 每帧驱动狙击弹系统：锁定目标持续射击，目标失效后重新扫描。
## 锁定规则：扫描到新目标 → 锁定并显示紫色条 → 持续射击该目标直到其死亡/离开扫描区。
## 同一锁定目标的后续射击不再重复显示紫色条，仅在切换目标时触发一次。
func _process_sniper(delta: float) -> void:
	# 紫色锁定条倒计时（无条件执行，确保条带即使在被眩晕/弹药耗尽时也不会卡住）
	var _strip_was_showing := _sniper_strip_timer > 0.0
	if _sniper_strip_timer > 0.0:
		_sniper_strip_timer -= delta
	if _sniper_strip_timer > 0.0 or _strip_was_showing:
		queue_redraw()
	# 狙击扫描/射击逻辑需要激活 + 有弹药 + 非眩晕
	if not _sniper_enabled or _sniper_shots <= 0:
		return
	if is_stunned():
		return
	_sniper_cooldown_timer -= delta
	# 检查锁定目标是否仍然有效（存活 + 在扫描区内）
	if _sniper_locked_target != null:
		var t = _sniper_locked_target.get_ref()
		if t != null and is_instance_valid(t) and _is_valid_sniper_target(t):
			# 锁定有效：冷却到了就继续射击（不重新扫描，不重新显示紫色条）
			if _sniper_cooldown_timer <= 0.0:
				_fire_sniper(t)
			return
		# 锁定失效（目标死亡或离开扫描区）→ 清除锁定
		_sniper_locked_target = null
	# 无锁定目标 → 扫描新目标
	if _sniper_cooldown_timer > 0.0:
		return
	var new_target = _scan_sniper_target()
	if new_target == null:
		return
	# 新锁定！显示紫色预警条 + 首发延迟（让锁定条先出现）
	_sniper_locked_target = weakref(new_target)
	_sniper_strip_timer = SNIPER_STRIP_DURATION
	_sniper_cooldown_timer = SNIPER_LOCK_DELAY
	queue_redraw()


## 判断指定目标是否仍是有效的狙击锁定对象（存活 + 兵种单位 + 在正前方扫描条带内 + 超出普攻射程）。
func _is_valid_sniper_target(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t.get("is_dead") == true:
		return false
	if t.get("tower_type") != null:
		return false
	var e_pos := BattlePathing.game_position_of(t)
	# 横向：在扫描条带宽度内
	var hr_val = t.get("hurt_radius")
	var hr: float = float(hr_val) if hr_val != null else 0.0
	if abs(e_pos.x - position.x) > _sniper_scan_half_width + hr:
		return false
	# 纵向：在正前方
	var forward_sign: float = -1.0 if team == "player" else 1.0
	if forward_sign * (e_pos.y - position.y) <= 0.0:
		return false
	# 距离：仍在普攻射程之外
	var normal_reach: float = _get_primary_attack_range()
	var primary_atk = get_primary_attack()
	if primary_atk:
		normal_reach = AttackComponent.compute_reach(primary_atk.attack_range, collision_radius, null)
	if position.distance_to(e_pos) <= normal_reach:
		return false
	return true


## 扫描正前方条带区域，返回最近的合格狙击目标（敌方兵种单位，非皇家塔，超出普攻射程）。
func _scan_sniper_target():
	var enemies = EntityRegistry.get_enemies_of(team)
	# 普攻触及距离：在此范围内的目标由 AttackComponent 处理，不消耗狙击弹
	var normal_reach: float = _get_primary_attack_range()
	var primary_atk = get_primary_attack()
	if primary_atk:
		normal_reach = AttackComponent.compute_reach(primary_atk.attack_range, collision_radius, null)

	# 正前方方向：player 向上（-Y），enemy 向下（+Y）
	var forward_sign: float = -1.0 if team == "player" else 1.0

	var nearest = null
	var nearest_dist: float = INF
	for e in enemies:
		# 排除皇家塔（只打兵种单位）
		if e.get("tower_type") != null:
			continue
		var e_pos := BattlePathing.game_position_of(e)
		# 横向：在扫描条带宽度内（含目标受击半径，大体积单位更容易被扫到）
		var hr_val = e.get("hurt_radius")
		var hr: float = float(hr_val) if hr_val != null else 0.0
		var dx: float = abs(e_pos.x - position.x)
		if dx > _sniper_scan_half_width + hr:
			continue
		# 纵向：在正前方（朝对方方向），身后或同位置的不扫
		var dy: float = e_pos.y - position.y
		if forward_sign * dy <= 0.0:
			continue
		# 距离判定：必须在普攻射程之外（远距离目标才消耗狙击弹）
		var dist: float = position.distance_to(e_pos)
		if dist <= normal_reach:
			continue
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e
	return nearest


## 发射一发狙击弹：飞行子弹视觉 + 攻击音效 + 射击硬直 + 弹药消耗。
## 伤害延迟到子弹命中时结算（on_arrival 回调），使伤害时机与视觉匹配。
func _fire_sniper(target) -> void:
	var target_pos := BattlePathing.game_position_of(target)
	# 射击硬直：站定不动，播放攻击动画（联机同步给 client）
	_sniper_firing = true
	_sniper_fire_lock = SNIPER_FIRE_LOCK
	_on_attack_triggered()
	queue_redraw()
	# 狙击弹使用觉醒专属音效；普通普攻仍沿用火枪手常规攻击音。
	AudioManager.play_unit_sfx(unit_id, "sniper_attack", BattlePathing.game_position_of(self))
	# 飞行子弹视觉 + 延迟伤害结算（子弹到达目标时才造成伤害）
	var dmg := _sniper_damage
	SniperTracer.spawn(get_parent(), position, target_pos, func():
		DamageSystem.resolve_impact(target, dmg)
	)
	# 弹药消耗
	_sniper_shots -= 1
	_sniper_cooldown_timer = _sniper_cooldown
	if _sniper_shots <= 0:
		_sniper_enabled = false


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
	if is_dead:
		return
	_clear_passive_mark()
	if not _is_remote() and _elixir_on_death > 0 and not _elixir_death_paid:
		_elixir_death_paid = true
		SignalBus.elixir_generated.emit(position, team, _elixir_on_death, true)
	super.die()
	if _is_remote():
		# Client 端：不注销（未注册）、不触发死亡逻辑链，只播放视觉
		return
	_spawn_death_unit_if_any()  # 死亡生成单位（如凤凰死亡留下蛋），client 端已在上方 return 跳过
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
