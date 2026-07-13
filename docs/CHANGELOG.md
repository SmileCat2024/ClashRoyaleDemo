# CHANGELOG

## [0.21.0] - 2026-07-13 — 瓦基里武神新卡 + instant+splash 近战溅射机制 + splash ground/air 过滤修复

### 新增
- **瓦基里武神（valkyrie）新单位/卡牌**：4 费地面近战，以自身为中心的转斧范围伤害，清兵利器。HP 1500 / 中速 1.0 / 碰撞 0.5 / 质量 6 / 视野 5.0。攻击 `axe_spin`：射程 1.0 格 / 溅射半径 **2.0 格**（以自身为中心）/ 间隔 1.8 秒 / 起手 0.6 秒 / 伤害延迟 0.08 秒（对齐转斧命中第 2 帧）/ 仅地面 / 伤害 169。帧动画接入（11 帧 walk/attack × front/back，横向 2335×1856 中性贴图）+ 卡面 `valkyrie.png`。
- **instant+splash 近战溅射机制（新）**：首个 `instant`（近战即时命中）+ `splash`（范围溅射）组合单位。此前所有 instant 单位都是 single（单体），splash 只有迫击炮（projectile）。`AttackComponent._execute_attack` 的 instant 分支扩展：`impact_type=splash` 时以攻击者自身位置为中心调 `DamageSystem.deal_area_damage`；`impact_type=single` 的现有单位走原逻辑不受影响。

### 修复
- **splash 范围伤害 ground/air 过滤缺失**：`DamageSystem.deal_area_damage` 此前只按距离判定，不区分地面/空中，导致 `attack_air=false` 的单位（瓦基里、迫击炮）splash 会误伤空中单位。修复：`deal_area_damage` 加 `attack_ground/attack_air` 可选参数（默认 true/true，法术行为不变），AttackComponent instant+splash 和 MortarShell（迫击炮炮弹）调用时传入攻击方的过滤条件。迫击炮沿 `AttackComponent → ProjectileManager.spawn_mortar_shell → MortarShell.setup_shell → _on_impact` 链路传参（5 处改动）。注：`ProjectileBase` 通用 splash 分支当前无单位使用，未改动。

### 修改
- `scripts/autoload/DataRegistry.gd`：+unit_data.valkyrie（含 animation + damage_delay）/ +card_data.card_valkyrie（含 icon）
- `scripts/components/AttackComponent.gd`：_execute_attack instant 分支 +splash 判定；_fire_projectile 迫击炮调用传 attack_ground/attack_air
- `scripts/systems/DamageSystem.gd`：deal_area_damage +attack_ground/attack_air 参数 + ground/air 过滤
- `scripts/entities/MortarShell.gd`：+_attack_ground/_attack_air 成员 + setup_shell 接收 + _on_impact 传参
- `scripts/battle/ProjectileManager.gd`：spawn_mortar_shell +参数透传给 setup_shell
- `scripts/tests/test_instant_splash.gd`（新增，4 用例）：范围内多目标命中 / 中心是攻击者自身 / attack_air=false 跳过空中 / single 回归
- `scripts/tests/TestRunner.gd`：+test_instant_splash 套件
- `assets/sprites/valkyrie/`（新增 11 PNG）+ `assets/ui/cards/valkyrie.png`（卡面）
- `docs/兵种数据.md`：+§3.13 瓦基里卡片 + 数据规模（12→13 单位/15→16 卡）/ 三个横向对比表 / 卡牌总表加行

## [0.20.1] - 2026-07-13 — 重甲亡灵帧动画接入（首个飞行单位动画）

### 新增
- **重甲亡灵（mega_minion）帧动画接入**：首个接入序列帧动画的飞行单位。中性单套贴图（10 张 PNG，2200×2240，linear 过滤）：walk front/back 各 1 帧 + attack front 3 帧 / back 2 帧 / side 3 帧。攻击三方向由 `UnitBase.get_attack_facing()` 按目标相对方向自动选择（水平偏移为主→side，正下→front，正上→back），侧面移动回退 front/back 行走帧（SpriteAnimator 降级链自动处理）。idle 复用 walk 首帧。
- **攻击 duration 节奏校准**：快起手→命中帧停顿→收势（front/side `[0.06,0.10,0.07]`、back `[0.07,0.11]`），缓解 3 帧素材低帧率（≈10fps）卡顿感。3 帧是素材固有限制，duration 调整为缓解手段，治本需美术补帧。

### 设计决策
- **projectile 单位不加 damage_delay**：重甲亡灵是投射物单位，伤害由投射物飞行命中结算（非攻击动画某帧），与 archers/musketeer 一致，不配置 damage_delay。

### 修改
- `scripts/autoload/DataRegistry.gd`：mega_minion +animation 配置（states: walk/idle/attack × front/back/side；visual_scale 0.0225 / visual_offset_y -25 / health_bar_y -50 / hide_placeholder true / texture_filter linear）
- `assets/sprites/mega_minion/`（新增 10 PNG）：walk_front_01 / walk_back_01 / attack_front_01~03 / attack_back_01~02 / attack_side_01~03（源自美术素材「重甲幽灵」，规范命名后复制）
- `docs/兵种数据.md`：§3.10 mega_minion 视觉小节由「ColorRect 兜底」更新为帧动画配置

## [0.20.0] - 2026-07-12 — A* 网格寻路替代 steering 避让 + mini_pekka 帧动画 + UI 预告牌优化

### 新增
- **A* 网格寻路系统**：新增 `AStarPathfinder`（class_name 全局类型），对地面单位做格系统 A* 动态网格寻路，绕开塔和可部署建筑（`mass=0` 的静态障碍物），替代早期 0.8.8 的 steering 避让方案（`_compute_obstacle_avoidance`），彻底解决塔群密集区域（双公主塔 + 国王塔 + 敌方建筑挤在一起）单位卡死、绕不出来的问题。空中单位跳过 A\* 直接走 BattlePathing 的直线/过桥路径。单位移动升级为三层架构：**路径路由**（BattlePathing：河道/桥/跳河）→ **A\* 网格寻路**（绕塔/建筑）→ **同类分离 + 碰撞分离**（UnitBase._compute_unit_separation + CollisionSystem）。
  - 关键接口 `find_path(from, to, mover_radius_cells)` 返回像素路径点数组，按单位碰撞半径膨胀障碍物留出缓冲，含 line-of-sight 路径平滑。
  - 不做动态重规划：单位仅在目标切换时重新算路径（`UnitBase._recompute_path`）；障碍物在移动中途出现时，单位会在撞到时才重算。
- **mini_pekka 帧动画接入**：mini_pekka 首次接入帧动画，walk/attack × front/back/side 三方向。攻击动画三态按目标相对方向选择（水平偏移为主→side，正下→front，正上→back），side 素材默认朝左、目标在右侧时 `flip_h` 自动镜像。新增 `damage_delay: 0.2s` 对齐"劈下"动画关键帧。
- **部署吸附系统测试**：新增 `test_deploy_snapping` 测试套件，覆盖建筑冲突检测、可部署区域综合判定、非法位置自动吸附到最近合法格、法术全图（含河道）可施放。

### 变更
- **5 单位美术校准**：knight / hog_rider / musketeer / archers / goblins 添加 `hide_placeholder`（校准后隐藏 ColorRect 占位方块）；5 单位 `shadow_size` 增大约 0.2 格（knight 0.5→0.75、hog_rider 0.55→0.8、musketeer 0.5→0.75、archers 0.35→0.55、goblins 0.3→0.5）使影子更明显。
- **预告牌卡面对齐底板**：预告牌卡面重新定位，左右填满底板预告牌框（不再被压成小块）；删除 `NextTitleLabel` 节点（"下一张"标题已印在底板图上）。
- **卡名显示逻辑调整**：CardSlot / CardBar 的卡牌名称显示判断从「单位有动画模型」改为「卡牌有卡面图片」——有卡面时图片即标识、不再显示文字，更合理。

### 修复
- **联机万箭齐发 client 端重复伤害**：`ArrowsSpellController._deal_wave_damage` 在联机 client 端会重复执行伤害结算（client 只应渲染箭矢飞行视觉，伤害由 host 计算）。修复：client 端提前 return 跳过 `deal_area_damage`。

### 文档
- 删除 6 份废弃文档（ARCHITECTURE / GODOT_LEARNING_NOTES / PROJECT_OVERVIEW / TODO / TWO_WEEK_PLAN / VISUAL_HANDOFF），均与 CLAUDE.md 职责重叠或已过时。
- `docs/SYSTEM_DESIGN.md`：新增 6.4.2 A\* 网格寻路系统章节 + 更新当前局限性（寻路 / 帧动画两条）。

### 修改
- `scripts/battle/AStarPathfinder.gd`（新增，330 行）：A\* 网格寻路核心
- `scripts/tests/test_astar_pathfinder.gd`（新增）：A\* 寻路测试（无障碍直线 / 绕塔 / 河道阻挡+桥通行 / 目标在障碍内修正 / 窄通道 / 路径平滑 / 起点在障碍内 / 无路径兜底）
- `scripts/tests/test_obstacle_avoidance.gd`（删除）：旧 steering 避让测试
- `scripts/tests/test_deploy_snapping.gd`（新增）：部署吸附测试
- `scripts/tests/TestRunner.gd`：替换 obstacle_avoidance→astar_pathfinder，新增 deploy_snapping
- `scripts/autoload/DataRegistry.gd`：mini_pekka +animation 三方向 / 5 单位 +hide_placeholder / 5 单位 shadow_size 调整
- `scripts/ui/CardBar.gd` + `scenes/ui/CardBar.tscn`：预告牌卡面定位 / 删 NextTitleLabel / 名称显示逻辑
- `scripts/ui/CardSlot.gd`：名称显示判断改用卡面
- `scripts/battle/ArrowsSpellController.gd`：client 端跳过伤害结算

## [0.19.1] - 2026-07-12 — 修复联机攻击动作不同步

### 修复
- **联机攻击动画不同步**：从 MultiplayerSynchronizer 迁移到手动 RPC 时，攻击触发状态（`_net_is_firing`）和攻击朝向的同步通道被遗漏——字段定义了但从未通过 RPC 传输，导致 client 端 `is_attacking()` 恒为 false，单位攻击时无动画、表现为"僵住"。修复：补一条事件型 reliable RPC 同步通道，host 端 AttackComponent 出手时通知 UnitBase 发 RPC（传 attack_facing + flip_h），client 端按镜像规则翻转（front↔back 互换、side 不变、flip_h 取反）后置 `_net_is_firing=true`，SpriteAnimator 检测到后播放攻击动画。

### 修改
- `scripts/entities/UnitBase.gd`：新增 `_net_attack_facing` 字段 + `_on_attack_triggered()` host 端回调 + `@rpc _rpc_attack_trigger(facing, flip_h)` client 端接收 + `_clear_attack_flag()` 攻击动画播完清除标记；`get_attack_facing()` client 分支改读同步值；`get_flip_h()` client 分支攻击期间改用同步翻转值
- `scripts/components/AttackComponent.gd`：新增 `_notify_attack_visual()`，冲锋/普通冷却两条出手路径在 `_is_firing=true` 后调用通知宿主
- `scripts/components/SpriteAnimator.gd`：攻击动画播完（`_attack_anim_playing` true→false）时回调 `_clear_attack_flag()`

## [0.19.0] - 2026-07-11 — 迫击炮团队色双套贴图 + 单位团队色区分机制 + 国王塔子弹修复

### 新增
- **迫击炮建筑贴图接入**：mortar 首次接入帧动画（idle/walk 常态 + attack 发射两帧）。素材为蓝/红双套（314×464，linear 过滤）：player 用蓝方贴图（`mortar_idle_blue.png` / `mortar_fire_blue.png`），enemy 用红方贴图（`mortar_idle_red.png` / `mortar_fire_red.png`）。attack 状态为发射时亮一帧（括号2），`mode = "once"` 播放后自动切回 idle（括号1）。我方蓝、敌方红。
- **单位团队色区分机制（首次引入，迫击炮为首例）**：为单位（非塔）引入 player/enemy 双套贴图能力。`SpriteRegistry.get_sprite_frames()` 新增 `team` 参数，缓存键改为 `"unit_id:team"`；`animation.states` 内每个 state 的 `frames` 字段支持两种形式——数组（中性贴图，所有队伍共用，默认）或字典 `{"player":[...], "enemy":[...]}`（红蓝双套，按 team 取帧）。新增 `SpriteRegistry.is_team_colored()` 判定。`SpriteAnimator` 对团队色单位跳过中性色调微调（modulate = Color.WHITE）保持红蓝原色。`DeployPreview` 预览传 `"player"`。仅当美术提供了红/蓝两套贴图时才用字典形式，现有中性单位完全不受影响。
- **迫击炮炮弹贴图**：`MortarShell` 飞行态用 `mortar_shell.png`（263×284）替换原来的灰色圆形石块 `_draw` 绘制（保留地面影子 + 落地爆炸尘土），Y 方向补偿 World 透视压缩保持比例；贴图加载失败时退回圆形兜底。

### 修复
- **国王塔子弹误用迫击炮炮弹**：`king_tower` 的 `attacks` 中 `trajectory` 误设为 `"ballistic"`，导致开火时走 `AttackComponent._fire_projectile` 的 ballistic 分支调用 `ProjectileManager.spawn_mortar_shell()` 发射迫击炮高抛炮弹（显然不合理）。修复为 `"homing"`，与公主塔一致发射普通追踪子弹。

### 联机同步
- 团队色机制对联机完全透明：复用现有 `team` 字段（client 端已在单位创建时做 player↔enemy 翻转 + 坐标镜像），无需额外 RPC。两端各自按翻转后的 team 取红/蓝贴图，每个玩家始终看到己方迫击炮为蓝、敌方为红。

### 修改
- `scripts/autoload/SpriteRegistry.gd`：`get_sprite_frames` +team 参数 / 缓存键带 team；`_build_sprite_frames` +team 帧选择（frames 字典形式）；+`is_team_colored()`；头部注释文档化团队色机制
- `scripts/components/SpriteAnimator.gd`：`setup` 调用传 `entity.team`；团队色单位跳过 modulate 色调微调
- `scripts/battle/DeployPreview.gd`：`show_preview` 调用传 `"player"`
- `scripts/entities/MortarShell.gd`：+`_shell_texture` 加载 + `draw_texture_rect` 贴图绘制（替换圆形石块）
- `scripts/autoload/DataRegistry.gd`：mortar +`animation` 团队色配置；king_tower `trajectory` ballistic→homing
- `assets/sprites/mortar/`：+`mortar_idle_blue.png` / `mortar_fire_blue.png` / `mortar_idle_red.png` / `mortar_fire_red.png` / `mortar_shell.png`

## [0.18.3] - 2026-07-11 — 修复点击单位/塔所在格子无法部署/施法

### 修复
- **Control 节点鼠标拦截 bug**：单位身上的 `Body`(ColorRect)、`HealthBar`(ProgressBar)、`DebugLabel`(Label) 及塔的 `HPLabel`(Label) 都是 `Control` 子类，Godot 4 默认 `mouse_filter = MOUSE_FILTER_STOP`，会吞掉落在其矩形上的鼠标点击，导致 `BattleManager._unhandled_input()` 收不到事件——表现为点击单位/塔所在格子时"没反应"（部署或施法失败），挪到空格子才正常。
- 修复后：所有合法单元格（含单位/塔所在格）均能正常点击部署与施法，唯一仍非法的是超出竞技场边界 / 超出己方可部署范围 / 贴在建筑上（走原有吸附逻辑）。

### 修改
- `scripts/entities/CombatantBase.gd`：新增 `_disable_control_mouse()`，在 `_init_combat_stats()` 末尾调用，递归把实体所有 `Control` 子孙节点设为 `MOUSE_FILTER_IGNORE`（鼠标穿透）
- `scripts/entities/TowerBase.gd`：`_create_hp_label()` 中新增 `_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE`（该 Label 在 `_init_combat_stats` 之后才创建，递归覆盖不到）

## [0.18.2] - 2026-07-11 — 王子跳河能力

### 新增
- **王子（prince）跳河能力**：`can_jump_river = true`，骑乘冲锋可跨河跳跃，与野猪骑士同款跳河机制。复用 `UnitBase._try_river_jump` + `BattlePathing.path_distance`，无需新增代码——移动时比较"走桥"与"跳河"两条路线，跳河更短才跳；桥线上正常走桥不跳；跳河期间临时切换为空中单位（地面攻击打不到、对空攻击能锁定），落地恢复地面；抛物线弧高视觉。王子的冲锋机制（持续移动距离累计触发）与跳河完全兼容，跳河后可立即进入冲锋冲塔。

### 修改
- `scripts/autoload/DataRegistry.gd`：prince 单位数据新增 `can_jump_river: true`
- `scripts/tests/test_data_registry.gd`：跳河断言由 `uid == "hog_rider"` 改为 `uid in ["hog_rider", "prince"]`

## [0.18.1] - 2026-07-11 — 文档补遗：迫击炮建筑寿命

### 说明
- **迫击炮建筑寿命已在 0.18.0 实现，本次仅补记文档**：`200dab9`（部署系统 commit）给 mortar 添加 `deploy_time: 3.5` 时一并添加了 `lifespan: 30.0`（部署完成后每秒自然掉血约 45.6 HP，30 秒后血量归零自毁，与地狱塔机制一致），但 `1f9030d` 的文档同步只更新了 deploy_time，遗漏了 lifespan 描述。本次修正各文档中"建筑寿命/自然掉血"仅写"地狱塔"的遗漏，补上迫击炮。

### 修改
- `docs/兵种数据.md`：§1.5 lifespan 字段适用范围补迫击炮；§2 横向对比表后说明补迫击炮；§3.9 迫击炮数据卡片加寿命行；§5 卡牌说明补迫击炮寿命
- `CLAUDE.md`：0.18.0 版本描述、当前局限性第1条补迫击炮建筑寿命

## [0.18.0] - 2026-07-11 — 部署虚影系统 + 部署时间激活延迟

### 新增
- **部署虚影预览**（DeployPreview）：拖动卡牌时在鼠标位置显示单位模型的半透明虚影（从 SpriteFrames 加载 walk_back 方向第一帧纹理，visual_scale/offset 一致），取代之前的纯方块预览。碰撞体边框（绿/红）始终显示。无动画配置的单位退化为半透明白色方块。
- **部署下落动画**（UnitBase）：单位部署时前 0.2 秒从 3.5 格高度 lerp 下落 + alpha 0.4→1.0 渐变（只改 modulate.a 不变暗）。部署期间 `get_visual_state()` 返回 walk（播放行进方向动画），`get_facing()` 按阵营强制朝向（player→back 向上走 / enemy→front 向下走）。
- **部署时间机制**（DataRegistry）：11 个单位添加 `deploy_time` 字段（knight/hog_rider/musketeer/mini_pekka/balloon/archers/giant/prince/mega_minion/goblins = 1.0 秒，mortar = 3.5 秒）。部署期间（`is_deployed=false`）单位不能索敌/攻击/移动，但可受伤（`take_damage` 不检查 `is_deployed`）。
- **部署虚影免碰撞**（CollisionSystem）：`_resolve_pair()` 跳过 `is_deployed=false` 且 `mass>0` 的普通单位，使释放位置中心格有兵时仍可部署。部署完成后碰撞自然恢复分离重叠。
- **SpriteAnimator 部署下落偏移**：新增 `set_deploy_offset(dy)` 方法 + `_deploy_dy` 变量，与 altitude 偏移叠加应用。

### 修改
- `scripts/battle/DeployPreview.gd`：`show_preview` 加载单位帧纹理 + `_load_unit_texture` + `_draw` 绘制半透明模型虚影
- `scripts/entities/UnitBase.gd`：+部署动画常量/变量/逻辑（`_update_deploy_anim`/`_finish_deploy_anim`/`_refresh_visual_offsets`）+ `get_visual_state` 部署返回 walk + `get_facing` 阵营强制朝向
- `scripts/components/SpriteAnimator.gd`：+`set_deploy_offset`/`_deploy_dy` + 恢复原始 `_update_animation`（无 deploy 特殊状态）
- `scripts/systems/CollisionSystem.gd`：`_resolve_pair` 跳过 `is_deployed=false` 且 `mass>0` 单位
- `scripts/autoload/DataRegistry.gd`：11 个单位 +`deploy_time`

## [0.17.0] - 2026-07-10 — 地狱塔建筑卡（递增光束 + 建筑寿命 + InfernoBeam 视觉组件）

### 新增
- **地狱塔（inferno_tower）**：稀有建筑卡，5费，对空+对地，单体锁定持续光束，伤害随锁定时间三阶段递增（43→158→847）。射程6格，攻速0.4秒，部署1秒，寿命30秒（自然掉血约58.3HP/秒），HP1748，碰撞0.6格，mass=0 自动成为寻路障碍。全卡牌循环牌库自动收录。
- **递增伤害机制**（AttackComponent）：`ramp_damage`/`ramp_thresholds` 数据字段驱动，持续锁定同一目标时累加锁定时间，按阈值切换伤害阶段；目标切换/丢失时重置。`get_ramp_stage_index()` / `get_ramp_intensity()` / `has_beam_target()` / `get_beam_target()` 供光束视觉查询。
- **建筑寿命/部署机制**（UnitBase）：`lifespan`/`deploy_time`/`deploy_decay_rate` 数据字段驱动，部署期间不索敌不攻击，寿命倒计时到期自毁，期间持续自然掉血。
- **InfernoBeam 光束视觉组件**（`scripts/components/InfernoBeam.gd`）：ADD 混合 Node2D，9 层叠加绘制忠实复刻 HTML 原型「窄束清晰版 v6」——粉红外光晕→橙色发光层→黄色核心束→白色高光芯→边缘闪烁波纹→波纹条→端点光球→沿线火花，三阶段递进（宽度/振幅/波纹密度/端点亮/火花数逐级增大）。4 频率正弦 noise 复刻热颤抖动。`beam_emit_offset_y` 数据字段配置光束发射点高度。
- **地狱塔测试套件**（`scripts/tests/test_inferno_tower.gd`）：41 断言覆盖递增伤害三阶段切换、锁定时间累加、目标切换重置、非递增单位向后兼容、数据配置校验。
- **地狱塔建筑贴图**：`assets/sprites/inferno_tower/inferno_tower.png`（1254×1254，linear 过滤）。

### 修改
- `scripts/autoload/DataRegistry.gd`：+inferno_tower unit_data/card_data；巨人 visual_offset_y/health_bar_y 下移1格
- `scripts/components/AttackComponent.gd`：+递增伤害字段/逻辑/查询方法 + 部署期间不攻击
- `scripts/entities/UnitBase.gd`：+建筑寿命/部署/掉血 + InfernoBeam 子节点驱动
- `scripts/tests/TestRunner.gd`：注册 test_inferno_tower
- `docs/兵种数据.md`：全面更新（§0.3 计数 12单位15卡、§1 字段字典 +ramp/lifespan/deploy/beam_emit_offset_y、§2 横向对比表、§3.12 地狱塔数据卡片含三阶段伤害表、§5 卡牌总表、§6 附录对比图）

## [0.16.0] - 2026-07-10 — 音效系统基础设施 + 24 个音效资源接入

### 新增
- **AudioManager Autoload 单例**（`scripts/autoload/AudioManager.gd`）：程序化创建 Master/BGM/SFX 三总线（无需手动改 AudioServer）、SFX 播放器池（16 轮转复用）、AudioStream 资源缓存、并发控制（max_polyphony 限制同事件同时播放数）、音调随机化（pitch_range）、BGM 淡入淡出（Tween）、M 键静音切换。stream 路径为空或资源缺失时静默跳过，不中断游戏。
- **音效事件数据表**（DataRegistry `sound_data`）：38 个音效事件配置（事件 ID → stream 路径 + volume_db + pitch_range + max_polyphony），其中 24 个已接入实际 MP3 资源，14 个预留待补。
- **BGM 数据表**（DataRegistry `bgm_data`）：4 个 BGM 配置（menu/battle/victory/defeat，stream 暂留空）。
- **单位音效字段**（DataRegistry `unit_data.sfx`）：10 个单位添加 sfx 配置（deploy/attack/move 按 key 引用 sound_data 事件），支持 `AudioManager.play_unit_sfx(unit_id, sfx_key)` 按单位播放专属音效，未配置时回退到通用事件。
- **24 个 MP3 音效资源**接入 `assets/audio/sfx/`：部署音 ×9（弓箭手/哥布林/小皮卡/气球/火枪手/王子/野猪/亡灵重甲/建筑）、攻击音 ×3（小皮卡/巨人/火枪手）、法术音 ×6（火球发射+命中、迫击炮发射+命中、万箭齐发、毒药）、王子冲锋音 ×2（冲锋+冲锋命中）、野猪移动音 ×1、通用音 ×3（卡牌选中/倒计时10秒/公主塔摧毁）。
- **SignalBus 自动驱动**：AudioManager 监听已有信号自动播放音效——`card_selected`（卡牌选中音）、`card_played`（troop→单位专属部署音、building→建筑部署音、spell→法术部署音）、`tower_destroyed`（公主塔/国王塔摧毁音）、`projectile_spawned`（飞行物发射音）、`projectile_hit`（飞行物命中音）、`battle_started`（战斗开始音+BGM）、`battle_ended`（胜利/失败音+BGM）。
- **音效触发点手动接入**（7 个文件）：
  - `AttackComponent`：`_play_attack_sfx()`（trajectory=ballistic→迫击炮发射音，其他→unit_data.sfx.attack）
  - `SpellManager`：cast_spell 按法术类型播放（fireball_launch / arrows_rain / poison_cast）
  - `SpellProjectile`：火球命中音（_on_impact）
  - `MortarShell`：迫击炮命中音（_on_impact）
  - `UnitBase`：王子冲锋音（_accumulate_charge 进入冲锋态）+ 野猪移动音（_move_towards_position 间歇 1.5s 蹄声）
  - `BattleManager`：倒计时10秒音（_enter_overtime 进入加时赛）
- **音频资源目录 + README**：`assets/audio/sfx/README.md`（命名约定 + 接入流程 + 事件 ID 速查表）、`assets/audio/bgm/README.md`。
- **查询方法**：`DataRegistry.get_sound_data(event_id)` / `get_bgm_data(bgm_id)` / `get_unit_sfx(unit_id)`。
- **启动校验**：DataRegistry `_validate_all_data()` 新增音效配置结构性校验（pitch_range 格式、stream 字段存在性），通过时输出音效/BGM 计数。

### 涉及文件
- 新增：`scripts/autoload/AudioManager.gd`、`assets/audio/sfx/`（24 MP3 + README.md）、`assets/audio/bgm/README.md`
- 修改：`project.godot`（注册 AudioManager autoload）、`scripts/autoload/DataRegistry.gd`（sound_data + bgm_data + get 方法 + 校验 + 10 单位 sfx 字段）、`scripts/components/AttackComponent.gd`、`scripts/battle/SpellManager.gd`、`scripts/entities/SpellProjectile.gd`、`scripts/entities/MortarShell.gd`、`scripts/entities/UnitBase.gd`、`scripts/battle/BattleManager.gd`、`docs/CHANGELOG.md`

## [0.15.1] - 2026-07-09 — 修复 building_only 索敌忽略建筑卡牌

### 修复
- **building_only 单位无法锁定建筑卡牌**：`targeting="building_only"` 的单位（如巨人）此前只能锁定公主塔/国王塔，完全无视迫击炮等 `mass=0` 的可部署建筑卡牌。
  - 根因：`TargetingSystem.find_best_target()` 的 building_only 过滤只检查 `tower_type != null`，而建筑单位（UnitBase，mass=0）没有 `tower_type` 字段，被错误跳过。
  - 修复：建筑判定从「只认塔」改为「认所有建筑」——`tower_type != null` **或** `mass == 0`。塔和建筑卡牌均为 mass=0，与 `EntityRegistry.get_static_obstacles()` 的建筑判定语义一致。
  - 同步修复 `UnitBase._find_nearest_enemy_tower()`：无攻击目标时的推进方向，building_only 单位现在会朝最近的敌方建筑（含建筑卡牌）推进、可被建筑拉扯；`any` 单位仍只认塔，不偏离主路线。

### 测试
- `test_targeting_system.gd` 新增 2 个回归测试：
  - `test_building_only_targets_building_unit`：building_only 能锁定 mass=0 建筑单位，忽略更近的普通单位
  - `test_building_only_picks_nearest_among_tower_and_building`：塔与建筑单位均纳入索敌，选最近者

### 涉及文件
- 修改：`scripts/battle/TargetingSystem.gd`、`scripts/entities/UnitBase.gd`、`scripts/tests/test_targeting_system.gd`

## [0.15.0] - 2026-07-09 — 国王塔贴图接入 + 塔占位方块移除 + 血条比例化

### 新增
- **国王塔精灵贴图接入**：king_tower 新增 `sprite` 配置（队伍差异化 PNG：king_tower_player.png / king_tower_enemy.png）。此前国王塔用 ColorRect 占位，现与公主塔统一用 Sprite2D 贴图渲染。
  - 数值：visual_scale 0.072（4格塔，按公主塔每格~20px渲染高推算）、visual_offset_y 35.0（碰撞框底部40px，留5px间距）
  - 未激活暗化：国王塔初始未激活时 sprite modulate ×0.55 暗化（此前暗化仅作用于被隐藏的 ColorRect，sprite 模式下暗化丢失），activate_king() 恢复为 Color.WHITE
- **公主塔贴图统一更新**：guard_tower_player.png / guard_tower_enemy.png 替换为新版美术资源
- **塔血条比例化定位**：`_create_tower_sprite()` 血条 Y 位置从"距精灵顶部固定像素偏移（玩家50px/敌方30px）"改为"按精灵高度比例（玩家0.63/敌方0.38）"，保证公主塔(3格)和国王塔(4格)等不同高度塔的血条视觉位置一致

### 变更
- **移除塔的 Body ColorRect 占位方块**：TowerBase.tscn 删除 Body 子节点（此前代表塔占据格子范围的彩色方块），塔彻底改为纯 sprite 渲染。
  - CombatantBase.body_rect 声明从 `$Body` 改为 `get_node_or_null("Body")`（塔为 null，单位不受影响），`_apply_altitude_offset()` 增加判空
  - TowerBase setup/activate_king/die 移除所有 body_rect 颜色操作，暗化/死亡变灰逻辑统一由 sprite modulate 承载
  - BattleConstants.COLOR_PLAYER_TOWER / COLOR_ENEMY_TOWER 常量不再被生产代码引用（保留定义）

### 测试
- `test_king_tower_activation.gd`：`test_king_tower_body_darkened` → `test_king_tower_sprite_darkened`、`test_king_tower_color_restored_on_activation` → `test_king_tower_sprite_restored_on_activation`，改为检查 `_tower_sprite.modulate`，无贴图环境自动跳过视觉检查

### 涉及文件
- 修改：`scripts/autoload/DataRegistry.gd`、`scripts/entities/CombatantBase.gd`、`scripts/entities/TowerBase.gd`、`scenes/entities/towers/TowerBase.tscn`、`scripts/tests/test_king_tower_activation.gd`
- 新增：`assets/sprites/towers/king_tower_player.png`、`assets/sprites/towers/king_tower_enemy.png`
- 替换：`assets/sprites/towers/guard_tower_player.png`、`assets/sprites/towers/guard_tower_enemy.png`

## [0.14.1] - 2026-07-09 — 修复王子冲锋首击起手延迟

### 修复
- **冲锋首击无视起手延迟**：王子处于冲锋状态接近目标、停下进入射程的那一刻，此前仍要等 `first_attack_delay`（0.5s）才出手，破坏冲锋的"冲刺爆发"手感。
  - 根因：`AttackComponent.setup()` 将 `cooldown` 初始化为 `first_attack_delay`，冲锋单位进入射程后同样走 cooldown 倒计时，未区分冲锋态。
  - 修复：`AttackComponent._process()` 在目标进入射程时优先检测 `is_charging`——冲锋态下立即执行 `_execute_attack()`（内部用 `charge_damage` 并调用 `_end_charge()`），随后 `cooldown = attack_interval` 进入正常节奏，**跳过** `first_attack_delay` 与 `damage_delay`。非冲锋态保持原 `first_attack_delay` 逻辑不变。
  - 语义明确：`first_attack_delay` 仅作为非冲锋状态下的首次攻击起手延迟；冲锋首击是零帧爆发，停下即刻触发，随后才进入正常攻击序列。
- **MockCombatant 缺失 class_name 导致 test_status_combatant 编译失败**：`test_status_combatant.gd` 以全局类型 `MockCombatant` 引用（`-> MockCombatant` / `MockCombatant.new()`），但 MockCombatant.gd 缺少 `class_name` 声明，该套件一直无法编译（因环境此前无法运行测试而未暴露）。恢复 `class_name MockCombatant` 并刷新 class 缓存后修复。

### 测试
- 新增 `test_charge_attack.gd`（13 断言）：冲锋首击零延迟 / 使用 charge_damage / 退出冲锋 / cooldown 重置为 attack_interval / 触发 firing 标记 / 非冲锋态仍受 first_attack_delay 约束 / 冲锋退出后恢复普通 damage / 冷却期间不重复出手
- MockCombatant.gd：新增 `is_charging` / `charge_damage` / `end_charge_call_count` / `_end_charge()` 支持冲锋测试模拟

### 涉及文件
- 修改：`scripts/components/AttackComponent.gd`、`scripts/tests/MockCombatant.gd`、`scripts/tests/TestRunner.gd`
- 新增：`scripts/tests/test_charge_attack.gd`

## [0.14.0] - 2026-07-09 — 哥布林新卡牌 + 骑士帧动画 + 巨人back方向 + 单位缩放微调

### 新增
- **哥布林新卡牌**：4 只快速近战地面单位，方阵部署（左前/右前/左下/右下，各 ±0.8 格）
  - 数值（11级）：HP 202 / 伤害 120 / 快速（1.5格/秒）/ 射程 0.5 近战短 / 攻击间隔 1.1s / 起手 0.6s / 只攻击地面 / 3费
  - 14 帧美术素材（walk/attack × front/back + attack_side 备用），素材统一右移 510px 校正居中
- **骑士首次接入帧动画**：knight 此前为 ColorRect 兜底，现新增 walk/attack × front/back 动画配置 + damage_delay 对齐劈砍

### 变更
- **巨人补全 back（向上）方向**：新增 walk_back/attack_back/idle_back 素材与动画配置（不覆盖现有 front 帧）
- **单位缩放微调**：弓箭手 visual_scale 0.085→0.065；骑士 visual_scale 0.045→0.028；骑士血条下移（health_bar_y -75→-65）

### 涉及文件
- 修改：`scripts/autoload/DataRegistry.gd`
- 新增：`assets/sprites/goblins/`（14帧）、`assets/sprites/knight/`（10帧）、`assets/sprites/giant/` 巨人 back 方向 4 帧

## [0.13.1] - 2026-07-09 — 修复同向友军碰撞左右震荡

### 修复
- **碰撞切向滑动对同向友军产生交叉震荡**：两个同方单位并排同向前进、略有重叠时，旧逻辑会沿连线切向把两单位一前一后错开，下一帧连线方向翻号、切向选择反转，形成画面上"左右闪"的震荡。
  - 根因：切向滑动（`TANGENTIAL_SLIDE`）对"两个同向同速移动"的友军施加了反向切向推力。同向友军只需径向分离保持间距，无需互相绕过；施加反向切向推力反而制造交叉。
  - 修复：`CollisionSystem._resolve_pair()` 新增同向判定（双方移动方向点积 > `SAME_DIRECTION_DOT=0.5`，即夹角 < 60°）时跳过切向滑动，仅做纯径向分离。一方静止 / 双方异向时保留原侧滑绕过功能。

### 测试
- test_collision_system.gd：新增同向震荡回归测试（同向不产生切向位移）+ 切向滑动对照测试（一方移动一方静止仍生效）
- MockCombatant.gd：新增 `set_move_direction()` / `get_move_direction()`，供碰撞系统切向滑动测试模拟移动方向

### 涉及文件
- 修改：`scripts/systems/CollisionSystem.gd`、`scripts/tests/MockCombatant.gd`、`scripts/tests/test_collision_system.gd`

## [0.13.0] - 2026-07-09 — 王子/迫击炮/重甲亡灵三卡完善 + 冲锋机制 + 迫击炮高抛盲区炮弹

### 新增
- **王子冲锋机制**：UnitBase 新增数据驱动的冲锋状态机
  - 持续移动累计距离达到阈值（2.5格）后进入冲锋，移速翻倍（1.0→2.0格/秒），命中伤害变为 charge_damage（783）
  - 攻击命中或受到伤害时退出冲锋并重置累计距离
  - 配置字段：unit_data.`charge` = { min_charge_distance, charge_move_speed, charge_damage }
- **迫击炮盲区（min_attack_range）**：AttackComponent 新增最小射程字段
  - TargetingSystem.find_best_target 新增 p_min_range 参数，索敌时排除盲区内目标
  - AttackComponent 索敌锁定与出手判定均检查盲区，盲区内待命不攻击
- **迫击炮高抛炮弹（MortarShell）**：新建高抛溅射飞行物
  - MortarShell.gd（继承 ProjectileBase）：圆形石块（半径8px+高光）+ sin 抛物线弧高（随距离自适应，最大射程处7格/近处~2格）+ 椭圆地面影子 + 落地尘土爆炸扩散圆
  - ProjectileManager 新增 spawn_mortar_shell()；spawn_projectile() 新增 arc_height_grids 参数
  - AttackComponent._fire_projectile 按 trajectory=ballistic 分流发射炮弹；impact_type=splash 走非锁定溅射
- **新单位/卡牌数据完善**：
  - 王子：HP1920 / 伤害391（冲锋783）/ 射程1.6格 / 中速（1.0格/秒）/ 5费
  - 迫击炮：HP1369 / 范围266 / 射程3.5-11.5格盲区 / 间隔5s / 范围2格 / 4费 / 建筑(mass=0)
  - 重甲亡灵：HP837 / 伤害312 / 射程1.6格 / 中速 / 对空对地 / 3费 / 飞行

### 变更
- AttackComponent 新增字段：min_attack_range / trajectory / impact_type / impact_radius / arc_height
- AttackComponent._execute_attack 支持冲锋伤害覆盖（读取 owner.is_charging + charge_damage，命中后调 _end_charge）
- TargetingSystem.find_best_target 签名新增可选参数 p_min_range（默认0，向后兼容）
- UnitBase 冲锋机制：攻击命中后退出冲锋（不受伤害打断，确保突进不被远程塔射停）

### 测试
- test_targeting_system.gd：新增盲区过滤测试（排除近处目标/全盲区返回null/无盲区保持默认）
- test_data_registry.gd：新增王子 charge 配置校验 + 迫击炮 min_attack_range 校验

### 涉及文件
- 修改：`DataRegistry.gd`、`AttackComponent.gd`、`TargetingSystem.gd`、`UnitBase.gd`、`ProjectileManager.gd`、`docs/兵种数据.md`、`test_targeting_system.gd`、`test_data_registry.gd`
- 新增：`scripts/entities/MortarShell.gd`、`scenes/entities/MortarShell.tscn`

## [0.12.0] - 2026-07-09 — 野猪骑士攻击动画 + 移动美术更新

### 新增
- **野猪骑士攻击动画**：hog_rider 新增 `attack_back` 状态（2 帧挥锤，`once` 模式）
  - attack 数据新增 `damage_delay: 0.12`，使伤害结算对齐第 2 帧（锤子砸下瞬间）
  - 向下攻击自动降级复用 `attack_back`（SpriteAnimator 降级链，无需额外美术）
- **攻击间隔定格优化**：攻击冷却期间 idle 定格改为跑步第 2 帧（`idle_back` 引用 `walk_back_02.png`），不再停在跑步第 1 帧

### 变更
- 移动美术资源更新（walk_back 部分帧重绘）

### 涉及文件
- 修改：`scripts/autoload/DataRegistry.gd`、`assets/sprites/hog_rider/walk_back_03.png`
- 新增：`assets/sprites/hog_rider/attack_back_01.png`、`assets/sprites/hog_rider/attack_back_02.png`

## [0.11.0] - 2026-07-09 — 公主塔精灵贴图 + 塔/单位统一 y-sort 深度排序

### 新增
- **公主塔精灵渲染**：guard_tower 新增 `sprite` 配置，按队伍加载不同 PNG 贴图（我方/敌方公主塔）
  - TowerBase `_create_tower_sprite()`：创建 Sprite2D，含 Y_COMPRESS 反向补偿、底部对齐塔逻辑位置
  - 精灵底部对齐设计：`offset_y = -tex_h * scale_y / 2`，使精灵视觉上"站"在塔的 position 上
  - 血条自动重定位到精灵顶部上方
  - 塔死亡时精灵变灰（modulate），国王塔暂无贴图保持 ColorRect

### 变更
- **TowersRoot 合并入 UnitsRoot**：塔和单位现在在同一个 `y_sort_enabled` 父节点下，按 Y 坐标统一深度排序
  - BattleScene.tscn / DebugBattle.tscn：移除 TowersRoot 节点，塔实例移入 UnitsRoot
  - BattleManager：移除 `towers_root` 引用，新增 `_towers` 缓存数组（从 UnitsRoot 筛选 TowerBase 实例）
  - DebugBattle：同步更新塔遍历路径
  - **核心效果**：大体积塔模型与单位的前后层级关系正确——单位在塔下方（y更大）时画在塔前面，在塔上方（y更小）时画在塔后面

### 涉及文件
- 修改：`BattleScene.tscn`、`DebugBattle.tscn`、`BattleManager.gd`、`DebugBattle.gd`、`TowerBase.gd`、`DataRegistry.gd`
- 新增：`assets/sprites/towers/guard_tower_player.png`、`assets/sprites/towers/guard_tower_enemy.png`

## [0.10.0] - 2026-07-09 — 投射物共享基类重构 + StatusEffect 框架增强（freeze/rage）

### 新增
- **ProjectileBase 共享飞行基础设施**：消除三个投射物子类（ProjectileBase / SpellProjectile / ArrowProjectile）之间的飞行逻辑重复
  - `_fly_toward(dest, delta) -> bool`：通用定点飞行步进（线性移动 + 弧高视觉偏移 + 到达判定）
  - `_fly_progress() -> float`：飞行进度 [0,1]，供子类 _draw() 计算弧高
  - `_apply_arc_offset()`：弧高视觉偏移，body_rect 为 null 时自动跳过（支持无 Body 子节点的子类）
  - body_rect 改为 `get_node_or_null("Body")`，ArrowProjectile 无需 Body ColorRect
- **StatusEffect 新效果类型**：freeze（冰冻）和 rage（狂暴增益）
  - `freeze`：与 stun 相同的完全瘫痪效果（不能移动和攻击），独立类型用于视觉/来源区分。merge 取最长剩余时间
  - `rage`：移动速度 + 攻击速度增益（mult > 1.0）。merge 取最强 buff + 最长剩余时间
  - StatusEffect 新增 `attack_speed_mult` 字段
- **CombatantBase 新方法**：
  - `get_attack_speed_mult()`：当前攻击速度乘数（受 rage 影响）
  - `apply_stun(duration)` / `apply_freeze(duration)` / `apply_rage(move_mult, attack_mult, duration)`：便捷封装
  - `has_status_type(type_name)`：查询是否拥有指定类型效果
  - `get_move_speed_mult()` 升级：减益（slow）取最强 × 增益（rage）取最强，两者相乘；stun/freeze 返回 0.0
  - `is_stunned()` 同时检查 stun 和 freeze
- **AttackComponent 攻速/瘫痪集成**：
  - 冷却和抬手计时受 `get_attack_speed_mult()` 影响（rage 加速攻击频率）
  - 抬手延迟期间检查 is_stunned（眩晕/冰冻中断攻击动作）

### 变更
- **ArrowProjectile 继承 ProjectileBase**：从 `extends Node2D` 改为 `extends ProjectileBase`，复用 `_fly_toward()` / `_fly_progress()` / `compute_arc_offset()`，消除 ~25 行重复飞行逻辑
- **SpellProjectile 消除字段重复**：移除 `_origin` / `_target` / `_speed` / `_flight_dist` / `_arc_height` / `_body_base_y`，改用基类 `_start_pos` / `_last_target_pos` / `speed` / `_total_dist` / `arc_height` / `_body_base_y`。`_process_flight()` 从手写飞行逻辑改为调用 `_fly_toward()`
- **ProjectileBase._process()** 简化：从手写移动+弧高代码改为调用 `_fly_toward()` + `_on_hit()`

### 测试
- 新增 `test_status_effect.gd`：slow/stun/freeze/rage/poison merge 叠加规则 + is_expired + get_remaining（11 个测试）
- 新增 `test_status_combatant.gd`：CombatantBase 状态查询 + 便捷方法 + 过期移除 + slow×rage 交互 + stun/freeze 覆盖（17 个测试）
- 新增 `test_projectile_base.gd`：_fly_toward 移动/到达/斜向 + _fly_progress + null body_rect 安全行为（8 个测试）

### 涉及文件
- 修改：`ProjectileBase.gd`、`SpellProjectile.gd`、`ArrowProjectile.gd`、`StatusEffect.gd`、`CombatantBase.gd`、`AttackComponent.gd`、`TestRunner.gd`
- 新增：`test_status_effect.gd`、`test_status_combatant.gd`、`test_projectile_base.gd`

## [0.9.0] - 2026-07-09 — 底层架构审查修复（P0-P3 全量）

### 新增
- **StatusEffect 状态效果框架**：通用状态效果系统，替代侵入式减速实现
  - `StatusEffect`（RefCounted 数据对象）：type / duration / elapsed / move_speed_mult / tick_damage 等字段，同类 merge() 叠加规则
  - 当前支持 slow（减速）、stun（眩晕）、poison（DoT）三种类型预埋，扩展只需加字段 + tick 逻辑
  - CombatantBase 新增 `apply_status_effect()` / `_process_status_effects()` / `get_move_speed_mult()` / `is_stunned()`
  - AttackComponent 眩晕检查（`is_stunned()` 时不能攻击）
- **PlayerBattleState**：封装单方战斗状态（team / energy / max_energy / energy_progress）
  - BattleManager 持有两个实例替代散装 `player_energy` / `enemy_energy` 变量
  - 通过 `_get_state(team)` 统一获取，消除 if-else 分支，为 2v2 预留结构
- **AttackComponent.compute_reach()**：统一 reach 公式（attack_range + collision_radius + hurt_radius），消除 4 处重复

### 修复
- **[P0] EntityRegistry 重开泄漏**：BattleManager.start_battle() 开头调用 `EntityRegistry.clear()`，防止重开时幽灵引用累积
- **[P1] ProjectileBase 溅射伤害统一走 DamageSystem**：`_deal_splash_damage()` 改为调用 `DamageSystem.deal_area_damage()`，消除遍历场景树的旧实现，获得塔减伤支持

### 变更
- **[P1] PoisonField 继承 BattlefieldEffect**：从直接 `extends Node2D` 改为 `extends BattlefieldEffect`，复用生命周期管理。`_process()` 调 `super._process(delta)` 后追加 tick 逻辑，setup 调 `super.setup()`。`_team` → `team`、`_duration` → `lifetime`、`_elapsed` 继承自基类
- **[P2] UnitBase 减速重构**：移除 `_slow_factor` / `_slow_timer` 散装变量，`apply_slow()` 内部创建 StatusEffect，`_get_effective_move_speed()` 改用 `get_move_speed_mult()`
- **[P3] SpellProjectile 继承 ProjectileBase**：从 `extends Node2D` 改为 `extends ProjectileBase`，共享 team 字段、body_rect 引用和 `compute_arc_offset()` 静态方法
- **[P3] ProjectileBase 新增 class_name + compute_arc_offset()**：作为所有投射物的基类类型，提取抛物线弧高计算
- **[P3] AttackComponent._fire_projectile() 走 ProjectileManager**：优先通过 ProjectileManager 统一入口，DebugBattle 回退直接创建
- **[P3] TowerBase._activate() → activate_king()**：修复私有命名被外部调用的封装问题
- TowerBase._process() 新增 `_process_status_effects(delta)` 调用

### 涉及文件
- 新增：`scripts/effects/StatusEffect.gd`、`scripts/battle/PlayerBattleState.gd`
- 修改：`CombatantBase.gd`、`UnitBase.gd`、`TowerBase.gd`、`AttackComponent.gd`、`ProjectileBase.gd`、`SpellProjectile.gd`、`PoisonField.gd`、`BattleManager.gd`、`test_king_tower_activation.gd`
- 文档：SYSTEM_DESIGN.md（索敌规则修正、出牌流程修正、PoisonField 继承、StatusEffect、PlayerBattleState）、TODO.md、CLAUDE.md

## [0.8.9] - 2026-07-08 — 通用单位影子系统 + 圣水条平滑 + 牌库全卡牌

### 新增
- **UnitBase._draw()**：所有单位（地面 + 飞行）统一绘制半透明黑色椭圆影子，替代旧版仅飞行单位的小矩形影子
  - 椭圆实现：`draw_set_transform` 将正圆 Y 轴压缩 `SHADOW_SQUASH`（0.35）变成扁平椭圆，绘制后复位 transform
  - 渲染层级保证：`_draw()` 先于子节点（Body/HealthBar/SpriteAnimator）执行，影子是单位内部最底层
  - 影子始终在地面位置（origin），不受 altitude 离地偏移影响
  - 地面单位 alpha 0.28；飞行单位（altitude>0）alpha 0.18 更淡
  - setup() 末尾新增 `queue_redraw()` 确保首次渲染
- **DataRegistry unit_data**：所有 7 个单位新增 `shadow_size` 字段（格）
  - knight 0.5 | hog_rider 0.55 | musketeer 0.5 | mini_pekka 0.45 | balloon 0.7 | archers 0.35 | giant 0.8
  - 未配置时退化为 `collision_radius`
- **圣水条平滑过渡**：CardBar 新增 ElixirPending 半透明紫色填充条，`_process` 每帧驱动
  - SignalBus 新增公开变量 `player_energy_progress`（0.0~1.0），BattleManager 每帧写入当前圣水积累进度
  - 修复开局圣水条延迟显示的 bug（_ready 末尾初始化填充）
- **牌库改为全卡牌**：DataRegistry.get_default_player_deck/enemy_deck 改为返回 `card_data.keys()`，新增卡牌自动入库
  - test_data_registry 更新为校验卡组包含全部卡牌

### 变更
- UnitBase._draw()：从仅 `altitude > 0` 时画矩形影子，改为所有单位画椭圆影子
- UnitBase 新增常量 `SHADOW_SQUASH := 0.35` 和属性 `_shadow_radius`
- 气球兵影子从 ~10px 宽矩形升级到 28px 宽椭圆（约 3 倍）

### 设计说明
- 影子用 `_draw()` 而非子节点实现，因为 `_draw()` 天然在子节点之前绘制，保证影子在 Body/Sprite 之下
- `shadow_size` 单位是格，setup 时通过 `BattleConstants.px()` 转像素，遵循格系统规范
- 跳河期间临时 altitude>0，影子自动变淡，落地恢复，无需额外代码

## [0.8.8] - 2026-07-08 — 单位避障转向系统（steering）

### 新增
- **UnitBase._compute_obstacle_avoidance()**：前方 mass=0 静态实体（塔/建筑）垂直偏转避让，查询 `EntityRegistry.get_static_obstacles()`，自动跳过当前攻击/移动目标，空中单位不执行
- **UnitBase._compute_unit_separation()**：附近同层单位 boids 式分离，将推力投影到移动方向的切平面上（保留 20% 径向 + 100% 切向），创造低摩擦侧滑效果
- **CombatantBase.get_move_direction()**：基类方法供 CollisionSystem 切向判定
- **CollisionSystem TANGENTIAL_SLIDE**：碰撞推挤叠加 30% 切向滑动，移动单位双方推向相反方向帮助侧滑绕过
- **EntityRegistry.get_static_obstacles()**：查询所有 mass=0 活跃实体

### 变更
- UnitBase._process() 移动逻辑重构为四层架构：路径路由（BattlePathing）→ 障碍物避让转向 → 同类分离 → 碰撞分离

### 新增测试
- **test_obstacle_avoidance.gd**（6 测试）：前方障碍产生避让/目标不避让/空中不避让/范围过滤/方向正确性/多障碍叠加
- **test_unit_separation.gd**（7 测试）：基础分离/空中豁免/距离过滤/静态障碍排除/切向投影侧滑/对称抵消/同侧叠加

## [0.8.7] - 2026-07-08 — 万箭齐发法术卡

### 新增
- **ArrowsSpellController**（`scripts/battle/ArrowsSpellController.gd`）：3 波箭雨确定性编排控制器
  - 发射点横线阵型（垂直于飞行方向均匀排列），落点向日葵黄金角均匀分布（无随机）
  - 按各自飞行距离反推速度，全波同时到达（齐射落点）
  - 波间半角错位，3 波落点不重合但各自均匀，统一弧高同步升降
  - 每波 15 支箭，波次间隔 0.18s
- **ArrowProjectile**（`scripts/entities/ArrowProjectile.gd`）：单根箭矢实体
  - 抛物线飞行 + 切线朝向计算 + 白色细线 + 地面影子 + 淡色羽尾点缀
  - 落地插地倾斜停留 + 渐隐消失
- **万箭齐发卡牌数据**：3 费 / 3 波 × 122 单位伤害（总 366）/ 25 塔伤害（总 75）/ 3.5 格半径 / 18.33 格每秒

### 变更
- SpellManager.cast_spell 按 `spell_type` 分流：arrows → ArrowsSpellController / fireball → SpellProjectile / poison → PoisonField

### 新增测试
- **test_spell_system.gd** 新增 10 条万箭齐发数据校验（3 波/单波 122/塔 25/半径 3.5/速度 18.33/无击退/卡组包含）

## [0.8.6] - 2026-07-08 — 毒药法术卡

### 新增
- **PoisonField**（`scripts/effects/PoisonField.gd`）：持续伤害区域实体（8 秒 / 每秒 1 跳 / 共 8 跳），脉冲绿圈视觉 + 末期淡出
- **UnitBase.apply_slow()**：减速机制（slow_factor + slow_timer，取最强值、最长持续）
- **UnitBase._get_effective_move_speed()**：移动速度乘减速系数
- **毒药卡牌数据**：4 费 / 3.5 格半径 / 8 秒 8 跳 × 92 伤害（总 736）/ 21 塔伤害（总 168）/ 减速 15%

### 变更
- SpellManager.cast_spell 按 `spell_type` 分流：poison → 直接在目标位置创建 PoisonField（无弹道），不再走 SpellProjectile
- SpellProjectile 清理毒药相关代码，仅保留 fireball 分支

### 新增测试
- **test_poison_spell.gd**（11 测试）：数据校验（DOT 字段/总伤害/减速/无击退）+ 单跳塔减伤 + 单跳单位伤害 + 塔与单位减伤对比

## [0.8.5] - 2026-07-08 — 法术系统（火球法术卡）

### 新增
- **SpellManager**（`scripts/battle/SpellManager.gd`）：法术部署入口，从施法方国王塔位置发射
- **SpellProjectile**（`scripts/entities/SpellProjectile.gd`）：法术飞行物，2.5D 抛物线弹道（红球 + 地面影子 + 弧高随距离自适应 + 爆炸扩散圆）
  - 落地 `_on_impact()`：范围伤害 + 击退 → 爆炸视觉（0.3s）→ `queue_free()`
- **DamageSystem.deal_area_damage()**：新增 `tower_damage` 参数（塔减伤），不填则与 spell_damage 相同
- **CombatantBase.knockback()**：击退方法（mass=0 免疫）
- **DeployPreview**：法术卡显示半径圆预览
- **Arena.is_spell_deploy_position()**：法术卡全图可施放
- **SimpleEnemyAI**：法术卡瞄准玩家半场
- **BattleManager.try_play_card()**：按 `card_type` 分流（troop → SpawnManager / spell → SpellManager）
- **火球卡牌数据**：4 费 / 688 范围伤害 / 172 塔伤害 / 2.5 格半径 / 击退 1 格 / 10 格每秒

### 新增测试
- **test_spell_system.gd**（18 断言）：火球数据校验 + 塔减伤（deal_area_damage tower_damage）+ 击退（CombatantBase.knockback）

## [0.8.4] - 2026-07-08 — 卡牌卡面图片系统 + 帧动画 P2（朝向翻转 + 攻击动画）

### 新增
- **卡牌卡面图片**：6 张手牌 + 1 张预告牌全部接入卡面素材渲染
  - `assets/ui/cards/` 目录：knight、hog_rider、musketeer、mini_pekka、balloon、archers、giant 共 7 张卡面 PNG
  - **CardSlot.tscn**：新增 `CardIcon`（TextureRect）子节点，全填充 + STRETCH_SCALE 拉伸占满卡槽，texture_filter = LINEAR
  - **CardBar.tscn**：NextCardPanel 新增 `NextCardIcon`（TextureRect），预告牌同样显示卡面
- **DataRegistry card_data**：新增 `icon` 字段（`res://assets/ui/cards/xxx.png`），数据驱动卡面路径
- **CardSlot.gd**：`setup()` 末尾调用 `_load_icon()` 加载卡面纹理，内部 `_icon_cache` 字典缓存避免重复 load
- **CardBar.gd**：`_on_hand_updated()` 中根据 next_card 的 `icon` 字段加载预告牌卡面
- **帧动画 P2 — 朝向翻转 + 攻击动画**：
  - **SpriteAnimator**：新增朝向系统（front/back + flip_h），攻击动画状态（is_firing 标记）
  - **AttackComponent**：新增 `is_firing` 标记供 SpriteAnimator 轮询切换攻击动画
  - **CombatantBase**：新增 `get_visual_state()` 支持 attack 状态返回
  - **DataRegistry**：knight / hog_rider / giant 接入帧动画（walk_front / walk_back 朝向帧 + 攻击帧）
  - 新增巨人 walk_front 序列帧、野猪骑士 walk_back 序列帧

### 设计说明
- 卡面 TextureRect 位于 NameLabel/CostLabel 之下（最先绘制 = 最底层），选中高亮和能量不足变暗通过 Button `modulate` 自动作用于卡面
- `stretch_mode = SCALE`（非 KEEP_ASPECT）：不同原生分辨率的卡面统一拉伸填满卡槽，保证视觉一致

## [0.8.3] - 2026-07-08 — 碰撞分离系统 + 射程公式修正 + 气球兵帧动画

### 新增

#### 碰撞分离系统
- **CollisionSystem**（`scripts/systems/CollisionSystem.gd`）：单位碰撞分离，解决"单位可重叠"问题。`class_name` 全局类型，在 `BattleManager._process()` 末尾每帧调用
  - **同层分离**：ground 单位只与 ground 单位碰撞，air 单位只与 air 单位碰撞（跳河期间临时 air 的单位也参与空中层）
  - **质量反比推挤**：overlap 位移按 `1/mass` 反比分配，重单位推得少、轻单位推得多
  - **不可移动实体**（mass=0 的塔）：碰撞时承担零修正，可移动单位承担全部分离位移
  - **迭代分离**：每帧最多 3 次遍历，消除多体堆叠的残留重叠
  - **河道回弹**：碰撞将地面单位推入非桥河道时，后处理拉回最近岸（留白 1px）
  - **边界钳制**：所有实体位置钳制在 `[collision_radius, ARENA_WIDTH/HEIGHT - collision_radius]` 范围内
- **CombatantBase 新增属性**：`collision_radius`（碰撞体半径）、`hurt_radius`（受击半径，默认=collision_radius）、`mass`（碰撞质量，塔=0 不可移动）
- **DataRegistry**：所有 6 单位 + 2 塔配置 `collision_radius` / `hurt_radius` / `mass`，配置校验自动检查
- **UnitBase.setup()**：从 unit_data 读取碰撞字段，格→像素转换

#### 射程公式修正
- **AttackComponent**：射程判定从纯 `attack_range` 改为 `attack_range + collision_radius + target.hurt_radius`（有效触及距离 = 攻击范围 + 自身碰撞半径 + 目标受击半径）
- **UnitBase._get_primary_attack_range()**：推塔停步距离同样加入 `collision_radius + target.hurt_radius`
- **TargetingSystem**：索敌距离排序考虑双方碰撞半径
- **DamageSystem**：范围伤害命中判定考虑目标 `hurt_radius`（法术半径 + 目标受击半径 >= 距离 才命中）

#### 气球兵帧动画
- **balloon animation 字段**：单帧静态图（idle/walk 共用 balloon.png），1254×1254px，visual_scale 0.0792

### 变更
- AttackComponent `_update_targeting()` 和 `_can_fire()` 的 reach 计算统一改为 `attack_range + collision_radius + target_hurt_radius`
- UnitBase `_check_attack_reach()` 和 `_move_toward_tower()` 停步距离加入碰撞半径修正
- DamageSystem `deal_area_damage()` 空间查询考虑 `hurt_radius`
- DataRegistry `_validate_all_data()` 新增 collision_radius / hurt_radius / mass 校验（单位和塔）

### 新增测试
- **test_collision_system.gd**（8 测试）：两体分离、无重叠不变、质量反比、不可移动塔、跨层不碰、同位置回退、河道回弹、边界钳制
- **test_attack_targeting.gd** 新增 `test_reach_includes_collision_radius` / `test_large_hurt_radius_extends_reach`：射程含碰撞半径回归测试
- **test_damage_system.gd** 新增 `test_area_damage_uses_hurt_radius`：范围伤害含受击半径
- **test_targeting_system.gd** 新增 `test_collision_radius_extends_effective_sight`：索敌距离含碰撞半径
- **test_data_registry.gd** 新增 collision_radius / hurt_radius / mass 配置校验（单位+塔）

## [0.8.2] - 2026-07-07 — 帧动画系统 + 弓箭手单位 + 血条样式重做

### 新增

#### 帧动画基础设施
- **SpriteAnimator**（`scripts/components/SpriteAnimator.gd`）：帧动画驱动器，纯观察者模式。每帧轮询实体的 `get_visual_state()` 切换动画，**永远不写回游戏逻辑**。支持 idle/walk 状态、Y 压缩反向补偿（sprite scale.y 除以 Y_COMPRESS）、阵营色调微调（玩家方偏暖、敌方偏冷）、高清图 linear / 像素风 nearest 双纹理过滤模式。无 `animation` 字段时自动退化为 ColorRect 模式
- **SpriteRegistry**（`scripts/autoload/SpriteRegistry.gd`）：全局 Autoload 单例。按需从 `assets/sprites/{unit_id}/` 加载 PNG 构建 SpriteFrames 资源并缓存。支持逐帧 duration、loop/once/pingpong 三种播放模式
- **CombatantBase 新增**：`sprite_animator` 引用、`get_visual_state()` 虚方法（默认返回 "idle"）、`_create_sprite_animator()` 在 `_init_combat_stats()` 末尾自动调用、`_style_health_bar()` 统一血条样式方法
- **UnitBase 新增**：`_is_moving` 标记（在 `_process` 各移动分支中设置）、`get_visual_state()` 覆写（返回 "walk" / "idle"）、altitude 偏移传递给 sprite animator、血条位置支持 `health_bar_y` 配置
- **assets/sprites/** 目录 + README 规范文档（美术端约定 + 命名规则 + 数据配置模板）
- project.godot 注册 SpriteRegistry autoload

#### 弓箭手单位
- **弓箭手（archers）单位**：地面远程单位，中速，可对空对地。射程 5 格，攻击间隔 0.9 秒，单次伤害 112，血量 304。projectile + linear 弹道（箭矢飞行）
- **弓箭手卡牌（card_archers）**：cost 3，一次部署 2 只弓箭手。`spawn_offsets: [Vector2(-1, 0), Vector2(1, 0)]`，两只分居中心格左右各一格
- 弓箭手移动帧动画已接入（2 帧 pingpong，1254×1254px 高清图）
- 玩家牌库和敌方 AI 牌库均已加入弓箭手卡牌

#### 血条样式重做
- **CombatantBase `_style_health_bar()`**：替换原默认 ProgressBar 样式。玩家方浅蓝半透明底 + 正蓝填充 + 深色描边（1px border + 1px content margin 让 fill 不盖住 border）；敌方浅红半透明底 + 正红填充。微圆角。所有单位 + 塔统一生效
- 血条位置支持逐单位配置：DataRegistry `animation.health_bar_y`（像素，负=上移），无动画配置时保持原位置（body 上方 8px）

### 设计决策
- **动画与逻辑彻底解绑**：SpriteAnimator 是纯只读观察者，轮询实体状态但不改变任何游戏逻辑。AttackComponent / UnitBase 核心流程不改
- **数据驱动 + 向后兼容**：无 `animation` 字段的单位继续使用 ColorRect，新旧模式无缝共存
- **开发阶段保留 ColorRect**：有动画的单位同时显示 ColorRect 站位格 + sprite 贴图，方便位置校准
- **散装 PNG 而非精灵图集**：美术帧数不统一时增删帧不改图集布局，Godot 自动导入每张 PNG 为独立纹理

## [0.8.1] - 2026-07-07 — 部署位置预览 + 国王塔激活机制

### 新增

#### 部署位置预览
- **DeployPreview**（`scripts/battle/DeployPreview.gd`）：卡牌选中后鼠标位置跟随半透明预览圆。绿色 = 可部署，红色 = 不可部署。支持多单位（`spawn_count > 1`）时显示每个单位的精确落点
- **SpawnManager**：偏移计算改为**确定性**（去除 `randf_range` 随机因子）。新增 `get_spawn_offsets()` 静态方法，DeployPreview 与 SpawnManager 共用同一套偏移逻辑
- **spawn_offsets 字段**：card_data 新增可选 `spawn_offsets` 字段（Array of Vector2，格单位），支持显式指定每个单位的相对位置（如一排、前后站、间距可控）。未指定时回退到确定性圆形分布
- **BattleManager**：选牌时显示预览，取消/部署/战斗结束时隐藏预览

#### 国王塔激活机制
- **TowerBase**：新增 `king_activated` 属性。国王塔初始未激活（外观暗化至 55% + AttackComponent `set_process(false)`）。受击时自动激活；激活后恢复外观亮度 + 启用攻击组件
- **BattleManager**：公主塔被毁时自动激活同阵营国王塔（`_activate_king_tower()`）
- **DataRegistry**：国王塔 `first_attack_delay` 从 4.0（近似前摇）改为 0.5（正常前摇，激活逻辑由 TowerBase 控制）

### 变更
- SpawnManager 新增 `class_name SpawnManager`（供 DeployPreview 调用静态方法）
- SpawnManager._calc_spawn_offset → _calc_one_offset（重命名 + 支持显式偏移）
- TowerBase._draw()：未激活国王塔不绘制射程圆
- BattleScene.tscn：新增 DeployPreview 节点（z_index=100）

### 新增测试
- **test_king_tower_activation.gd**（8 测试 14 断言）：初始未激活、外观暗化、受击激活、颜色恢复、冷却保持、幂等性、死亡不激活、公主塔始终激活
- 修复 test_tower_attack.gd 的 `test_tower_sight_range_fallback`（MockCombatant 有 sight_range=120，断言修正）

## [0.8.0] - 2026-07-07 — 死亡炸弹 + 时间/加时赛 + 圣水条 UI

### 新增

#### 死亡延迟伤害系统（气球兵死亡掉落炸弹）
- **CombatantBase**：新增 `death_damage`、`death_radius`、`death_fuse_time` 属性。`die()` 不再直接调用 DamageSystem，改为发出 `death_damage_triggered` 信号（含位置/伤害/半径/引信/阵营）
- **SignalBus**：新增 `death_damage_triggered(pos, damage, radius, fuse, team)` 和 `impact_resolved(position, impact_type, radius, team)` 信号
- **BattlefieldEffect**：战场临时效果基类（`scripts/effects/BattlefieldEffect.gd`），有生命周期管理 + `_on_expire()` 到期回调
- **DelayedDamageEffect**：延迟范围伤害效果（`scripts/effects/DelayedDamageEffect.gd`）。引信期间显示脉冲爆炸半径指示圈，到期对范围内敌方造成全额伤害。视觉：渐亮脉冲 + 临近爆炸变红
- **EffectManager**：统一战场效果生成入口（`scripts/battle/EffectManager.gd`）。监听 `death_damage_triggered` 信号，自动生成 DelayedDamageEffect。架构风格与 SpawnManager / ProjectileManager 一致
- **EffectsRoot**：BattleScene.tscn 新增效果父容器节点
- **DataRegistry**：气球兵配置 `death_fuse_time: 3.0`（3 秒引信）

#### 时间限制与加时赛
- **BattleManager**：完整时间机制
  - 常规时间 180 秒（3 分钟）→ 加时赛 60 秒（1 分钟），加时赛圣水恢复 2x 加速
  - 三级胜负判定：塔数对比 → 总血量百分比 → 平局
  - `_check_time_limit()`、`_enter_overtime()`、`_count_alive_towers()`、`_get_total_hp_percent()`、`_determine_result_by_stats()`
- **SignalBus**：新增 `battle_phase_changed(phase, time_remaining)` 信号

#### 圣水条 UI（EnergyBar）
- **CardBar.gd**：集成圣水条（ElixirBar / ElixirFill / ElixirLabel）。监听 `energy_changed` 信号实时更新填充比例和数字显示
- 圣水条布局常量集中定义在 CardBar.gd 顶部（ELIXIR_X / ELIXIR_Y / ELIXIR_W / ELIXIR_H）

### 变更
- CombatantBase.die()：从直接调用 `DamageSystem.deal_area_damage` 改为发出 `death_damage_triggered` 信号（解耦：伤害由 EffectManager → DelayedDamageEffect 延迟执行）
- UnitBase.setup()：读取 `death_fuse_time` 配置
- BattleScene.tscn：新增 EffectManager 节点和 EffectsRoot 节点
- BattleHUD.gd：结束面板支持 "draw"（平局）显示

### 新增测试
- **test_death_damage.gd**（3 层 12 断言）：
  - Layer 1：die() 正确发出 death_damage_triggered 信号（参数校验、无配置不触发、take_damage 链路）
  - Layer 2：DelayedDamageEffect._on_expire() 范围伤害结算（范围命中、友方免疫、边界、生命周期进度）
  - Layer 3：DataRegistry 气球兵配置完整性（death_damage / death_radius / death_fuse_time）
- **test_tower_attack.gd**（10 断言）：塔 AttackComponent 接入验证（射程格→像素、地面/空中索敌、最近优先、instant 伤害结算、冷却判定、视野兜底）
- TestRunner SUITES 数组新增上述两个测试套件

## [0.7.0] - 2026-07-07 — 2.5D 渲染系统（Y 压缩 + 高度 + 弹道弧线）

### 新增

- **Y_COMPRESS 透视压缩**：BattleConstants 新增 `Y_COMPRESS = 0.7863` 常量。BattleScene.tscn 中 `World`（Node2D）施加 `scale = Vector2(1, 0.7863)`，实现 Y 轴透视压缩
- **双坐标空间**：游戏空间（360×640，逻辑坐标）与屏幕空间（360×480，渲染坐标）分离。鼠标输入通过 `world.get_local_mouse_position()` 自动逆变换回游戏空间
- **altitude 离地高度系统**：CombatantBase 新增 `altitude` 属性 + `_apply_altitude_offset()` 方法。飞行单位（movement_type = "air"）设 altitude = 2.5，Body/HealthBar/DebugLabel 视觉上移
- **飞行单位影子**：UnitBase.\_draw() 在地面位置绘制半透明椭圆影子（不受 altitude 偏移）
- **弹道弧线**：ProjectileBase 新增 `arc_height` 属性，sin 抛物线偏移 body\_rect 视觉位置（不影响命中判定）
- **y\_sort 深度排序**：UnitsRoot 开启 `y_sort_enabled = true`
- **地图底板脱离压缩**：Arena 的 MapBackground 设 `top_level = true`，保持原始比例不变形

### 变更
- BattleConstants：新增 `Y_COMPRESS`、`ARENA_SCREEN_HEIGHT`、`VIEWPORT_WIDTH`、`ARENA_TOP_OFFSET_Y`、`VIEWPORT_BORDER_CELLS` 等常量，适配 2.5D 双空间布局
- project.godot：viewport 从 360×720 改为 440×720（左右各留 40px 边距显示地图底板边框）
- Arena.gd：地图底板改用 `top_level = true` + 手动缩放定位，脱离 World 的 Y 压缩
- BattleManager.gd：左键部署改用 `world.get_local_mouse_position()` 获取游戏空间坐标（自动逆变换 Y 压缩）
- CombatantBase.gd：新增 `altitude` 属性和 `_apply_altitude_offset()` 方法
- UnitBase.gd：setup() 中根据 movement\_type 设置 altitude 并应用偏移；\_draw() 绘制影子

### 设计决策
- **altitude 纯视觉**：不影响索敌距离、移动、部署判定。所有逻辑在 2D 游戏空间进行
- **Y\_COMPRESS 是唯一透视控制器**：改一个常量即可调整透视强弱
- **地图底板特殊处理**：地图美术资源保持原始宽高比，只有游戏元素受 Y 压缩

## [0.6.1] - 2026-07-07 — Bug 修复（索敌/追击）+ 测试体系

### 修复
- **AttackComponent._update_targeting()**：锁定条件从 `_get_sight_range()`（视野范围，骑士120px）改为 `attack_range`（攻击范围，骑士30px）。修复前：视野内发现敌人就死锁不放、不切换目标；修复后：目标在攻击范围内保持锁定原地攻击，目标离开攻击范围后每帧重新搜索最近敌人，追击中可自由切换
- **UnitBase._get_primary_attack_range()**：返回值从裸格值（如 knight 的 1.2）改为 `BattleConstants.px()` 转换后的像素值（24px）。修复前：单位推塔时因 `dist(像素) > 1.2(格)` 恒为 true，永远不会在射程处停下
- **TowerBase._draw()**：射程圆 radius 从裸格值（7.5）改为 `BattleConstants.px(7.5)`（150px）。修复前：射程圆半径仅 7.5px 几乎不可见

### 新增 — 测试体系
- `TestBase.gd`：测试基类，自动发现 `test_` 方法，提供 7 种断言（eq/ne/true/false/null/not_null/approx）
- `TestRunner.gd` + `TestRunner.tscn`：测试运行器场景，F6 运行，Output 面板查看结果
- `MockCombatant.gd`：继承 CombatantBase 的轻量模拟实体（不放入场景树，直接用于索敌/伤害测试）
- 6 个测试套件（共 50+ 断言）：
  - `test_battle_constants.gd`：格→像素转换、坐标常量
  - `test_targeting_system.gd`：三重过滤索敌（阵营→ground/air→distance→building_only→死亡）
  - `test_damage_system.gd`：单体伤害、护盾吸收（不溢出）、范围伤害
  - `test_deck_manager.gd`：8牌循环轮转、手牌副本隔离
  - `test_data_registry.gd`：单位/卡牌/塔配置完整性校验
  - `test_attack_targeting.gd`：**索敌锁定/切换核心逻辑回归测试**（攻击范围内锁定不切换、离开后重新搜索、追击中切换最近目标）

## [0.6.0] - 2026-07-06 — D5 卡牌 UI（CardBar + CardSlot）

### 新增
- **CardSlot.gd/tscn**：单个卡牌槽位（Button），显示名称+费用，点击发 `card_selected` 信号。三态外观：正常 / 选中高亮（暖色 tint） / 能量不足暗化（disabled + dim）。运行时生成 StyleBoxFlat 扁平像素风样式
- **CardBar.gd/tscn**：底部卡牌栏，4 张手牌 + 1 张预告牌。监听 `hand_updated` / `energy_changed` / `selection_changed` 三个信号纯驱动，不引用任何 Manager
- SignalBus 新增 `hand_updated(hand, next_card)` 和 `selection_changed(hand_index)` 信号
- SignalBus `card_selected` 签名改为 `(card_id, hand_index)`，附带手牌索引（卡组含重复卡牌时仍可唯一定位）

### 变更
- BattleManager：
  - `_input` → `_unhandled_input`：CardSlot（STOP mouse_filter）消费点击后不再误触部署；点击战场区域穿透到此处
  - `start_battle()` 末尾 `call_deferred("_broadcast_hand_state")`：确保 CardBar `_ready` 已连接信号后才广播初始手牌
  - `_select_hand_card` / `_try_deploy` / `_cancel_selection` 均在状态变更后发 `selection_changed`
  - 连接 `card_selected` → `_on_card_selected` → `_select_hand_card`，与键盘 1-4 走同一逻辑
- BattleHUD.gd：mouse_filter 策略从「递归全量 IGNORE」改为选择性——TopBar / BottomInfo 穿透，CardBar 保持可交互
- BattleHUD.tscn：添加 CardBar 子节点；提示文字改为「点击卡牌选中 | 左键部署 | 右键取消」

## [0.5.0] - 2026-07-06 — D4 圣水+卡组+出牌全链路

### 新增
- **DeckManager**：8牌循环系统（4手牌+1预告+3队列），打出后自动轮转
- DataRegistry.get_default_player_deck()：玩家默认8张牌
- BattleManager 集成 DeckManager，出牌后自动轮转手牌

### 变更
- BattleManager 全面重写：
  - 能量恢复间隔改为 2.8s（更接近原版节奏）
  - 键盘 1-4 选手牌，左键部署，右键取消
  - 移除所有 F 键（F2/F3/F4 → G/H/无）
  - 移除 card_selected 信号依赖（D5 UI 再接入）
- 主场景 DebugBattle.tscn → BattleScene.tscn
- BattleHUD 提示文字更新为新快捷键

### 修复
- ProjectileBase._on_hit()：目标已死时不再传给 DamageSystem，飞行物自然消失（修复 Invalid type 报错）
- BattleManager 输入：`_unhandled_input` → `_input`，避免 CanvasLayer 上 Control 吞掉鼠标事件
- BattleHUD：`_ready()` 中递归设置所有子控件 `MOUSE_FILTER_IGNORE`，结束面板按钮在显示时恢复

## [0.4.0] - 2026-07-06 — 格系统重构

### 变更
- BattleConstants: TILE_SIZE → CELL_SIZE 改名，所有分区坐标从 CELL_SIZE 推导（无硬编码像素）
- DataRegistry: 所有距离/速度/范围从像素改为格值（move_speed 55→2.75, attack_range 24→1.2 等）
- setup 层（UnitBase/AttackComponent/SpawnManager）: 读格值后调 BattleConstants.px() 转为像素
- Arena.gd: TILE_SIZE→CELL_SIZE, 部署区 x 边界从硬编码改为 CELL_SIZE 推导
- project.godot: viewport 360x640→360x720（底部加4格卡牌区）, 窗口 720x1280→720x1440
- BattleConstants 新增 px() 静态函数 + VIEW_EXTRA_ROWS / ARENA_WIDTH / ARENA_HEIGHT

### 设计决策
- 格是唯一度量单位，像素是渲染细节。改 CELL_SIZE 即可整体缩放
- 数据层（DataRegistry）用格，运行时变量用像素，setup 层负责转换

## [0.3.1] - 2026-07-06 — 角色数值录入

### 变更
- knight 数值更新为正式数据（HP 1766 / DMG 202 / 间隔1.2s / 射程1.2格）
- 公主塔数值更新（HP 3052 / DMG 109 / 射程7.5格 / 前摇0.8s）
- 国王塔数值更新（HP 4824 / DMG 109 / 射程7格 / trajectory改ballistic）

### 新增
- 4 个单位：hog_rider（building_only, 极快）、musketeer（远程对空）、mini_pekka（高伤快速）、balloon（空中building_only）
- 4 张卡牌：card_hog_rider(4费)、card_musketeer(4费)、card_mini_pekka(4费)、card_balloon(5费)
- DebugBattle 数字键 1-5：在鼠标位置生成对应单位（玩家方）
- 敌方默认牌组扩展为 4 张（knight + hog_rider + musketeer + mini_pekka）

### 已知限制
- 国王塔激活机制用 first_attack_delay=4 近似（真正机制：受击/公主塔被毁后激活）
- 气球兵死亡范围伤害 240 暂未实现
- 气球兵射程 0.1 格 → 放大为 4px（0.2格）增加容错

## [0.3.0] - 2026-07-06 — D3 索敌系统完善

### 新增
- `TargetingSystem.find_best_target()`：统一索敌入口，三重过滤（阵营 → targeting 规则 → ground/air → distance）
- DebugBattle 新增 **J 键**：在鼠标位置生成敌方骑士

### 变更
- `AttackComponent._find_nearest_target()`：内联索敌逻辑删除，改为委托 `TargetingSystem.find_best_target()`
- 塔没有 `movement_type`，在索敌过滤中默认视为 ground 目标

### 当前可运行验证（DebugBattle 场景）
1. K 生成玩家骑士 → 走向敌方塔，攻击掉血
2. J 生成敌方骑士 → 两个不同阵营骑士互相索敌、追击、攻击
3. D 打印所有实体状态

## [0.2.0] - 2026-07-06 — D2 攻击系统 + 断裂修复

### 新增

#### 攻击系统（components/ + systems/）
- `AttackComponent.gd`：独立攻击组件，挂在 CombatantBase 下。负责索敌（锁定/重评）、冷却判定、按 delivery 分支执行（instant 调 DamageSystem / projectile 发射 ProjectileBase）。持有 `current_target` 供 UnitBase 读取决定走/停
- `DamageSystem.gd`：统一伤害结算入口。`resolve_impact(target, damage)` 单体结算 + `deal_area_damage(center, radius, damage, team)` 范围结算（通过 EntityRegistry 查询）

### 改进

- `CombatantBase.gd`：`_init_combat_stats()` 末尾自动为 attacks 数组每项创建 AttackComponent 子节点；提供 `get_primary_attack()` 返回主攻击组件
- `UnitBase.gd`：`_process()` 改为读 primary AttackComponent 的 `current_target` 决定追击/停步；无攻击目标时向最近敌方塔推进
- `TowerBase.gd`：AttackComponent 自动索敌+攻击（塔不移动，组件独立工作）
- `ProjectileBase.gd`：`_on_hit()` 单体伤害改走 `DamageSystem.resolve_impact()` 统一结算

### 断裂修复

- `SignalBus.gd`：补 `card_selected` 信号（BattleManager._ready 引用但原不存在）
- `BattleManager.gd`：`spawn_unit_from_card()` → `spawn_unit()`、出牌 `card_melee` → `card_knight`、`_setup_towers()` 补 `EntityRegistry.register(tower)`
- `DataRegistry.gd`：补 `get_default_enemy_deck()` 方法（SimpleEnemyAI 引用但原不存在）

### 当前可运行验证（DebugBattle 场景）

1. K 生成骑士 → 骑士走向敌方塔
2. 进入射程后停下 → 骑士攻击塔（instant），塔掉血
3. 塔会发射飞行物攻击骑士（projectile delivery）
4. D 打印所有实体状态

## [0.1.0] - 2026-07-06 — 初始可运行版本

### 新增

#### 项目配置
- 更新 `project.godot`：设置主场景为 MainMenu，注册 4 个 Autoload
- 设置逻辑分辨率 640x360，窗口大小 1280x720，像素风拉伸模式
- 设置纹理过滤为 Nearest（像素风清晰显示）

#### Autoload 脚本（全局单例）
- `SignalBus.gd`：全局信号总线，定义了 battle_started/ended、card_selected/played、energy_changed、unit_spawned/died、tower_destroyed 等信号
- `Game.gd`：游戏状态管理，提供 start_battle/return_to_menu/restart_battle 入口
- `SceneLoader.gd`：统一场景切换，封装 change_scene_to_file
- `DataRegistry.gd`：数据中心，保存 3 种单位、3 张卡牌、2 种塔的属性数据

#### 战斗脚本
- `BattleConstants.gd`：常量定义（坐标、颜色、部署区域范围）
- `Arena.gd`：战场逻辑，提供部署位置判定方法
- `BattleManager.gd`：战斗总指挥，管理能量/出牌/胜负/输入处理
- `SpawnManager.gd`：单位生成器，根据卡牌数据实例化单位
- `TargetingSystem.gd`：静态目标选择工具（最近敌方单位/塔）
- `SimpleEnemyAI.gd`：敌方 AI，每 2-4 秒随机出牌

#### 实体脚本
- `UnitBase.gd`：单位行为（移动/寻敌/攻击/受伤/死亡），3 种单位共用
- `TowerBase.gd`：塔行为（范围寻敌/攻击/受伤/死亡）

#### UI 脚本
- `MainMenu.gd`：主菜单按钮处理
- `BattleHUD.gd`：战斗 HUD（时间/能量/单位数量/胜负显示/结束面板按钮）

#### 场景文件
- `MainMenu.tscn`：主菜单界面
- `Arena.tscn`：战场背景（深色背景 + 红蓝部署区 + 中央线 + 路线标记）
- `BattleScene.tscn`：战斗主场景（Arena + 6 座塔 + 管理器 + HUD）
- `TowerBase.tscn`：塔基础场景（ColorRect 方块 + ProgressBar 血条 + Label 名称）
- `KingTower.tscn`：主塔（继承 TowerBase）
- `GuardTower.tscn`：防御塔（继承 TowerBase）
- `UnitBase.tscn`：单位基础场景
- `MeleeUnit.tscn`：近战兵（继承 UnitBase）
- `RangedUnit.tscn`：远程兵（继承 UnitBase）
- `TankUnit.tscn`：重甲兵（继承 UnitBase）
- `BattleHUD.tscn`：战斗 UI（顶栏 + 底栏 + 中央消息 + 结束面板）

#### 文档
- `PROJECT_OVERVIEW.md`：项目总览
- `GODOT_LEARNING_NOTES.md`：Godot 初学者笔记
- `ARCHITECTURE.md`：架构说明
- `TWO_WEEK_PLAN.md`：两周开发计划
- `TODO.md`：待办事项
- `CHANGELOG.md`：变更记录

### 当前可运行流程

1. 运行项目 → 显示主菜单
2. 点击"开始战斗" → 进入战斗场景
3. 看到 6 座塔（蓝/红）+ 战场背景 + HUD
4. 等待几秒 → 敌方 AI 自动生成红色单位向下移动
5. 按 K → 在鼠标位置生成蓝色玩家单位，自动向上移动攻击敌方
6. 单位相遇后互相攻击
7. 塔会自动攻击范围内的敌方单位
8. 主塔被摧毁 → 显示胜利/失败 + 重开/返回菜单按钮
9. 按 R 可重开
