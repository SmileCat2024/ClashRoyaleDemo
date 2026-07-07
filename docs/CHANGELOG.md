# CHANGELOG

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
