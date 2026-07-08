# CHANGELOG

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
