# TODO

## 已完成

- [x] 项目配置（project.godot：主场景、Autoload、窗口、像素风）
- [x] 主菜单（MainMenu.tscn + MainMenu.gd）
- [x] 场景切换（SceneLoader.gd）
- [x] 战场背景（Arena.tscn + Arena.gd）
- [x] 塔系统（TowerBase.tscn + TowerBase.gd，6 座塔）
- [x] 单位系统（UnitBase.tscn + UnitBase.gd，3 种单位）
- [x] 目标选择和攻击（TargetingSystem.gd）
- [x] 能量系统（BattleManager.gd）
- [x] 敌方 AI（SimpleEnemyAI.gd）
- [x] 单位生成器（SpawnManager.gd）
- [x] 胜负判定（主塔死亡 → 胜利/失败）
- [x] 战斗 HUD（时间、能量、单位数量显示）
- [x] 调试快捷键（K/D）
- [x] 数据中心（DataRegistry.gd）
- [x] 信号总线（SignalBus.gd）
- [x] 常量定义（BattleConstants.gd）
- [x] **D1 架构重构**：DataRegistry 新 schema（数据驱动 + 配置校验）、EntityRegistry（注册/注销/查询）、CombatantBase/UnitBase/TowerBase 改造（initialized 标记、护盾机制）、SpawnManager 重构、DebugBattle 场景
- [x] **D2 攻击系统**：AttackComponent（独立索敌+冷却+delivery 分支 instant/projectile）、DamageSystem（resolve_impact + deal_area_damage 统一伤害入口）、UnitBase 移动与攻击协作、TowerBase 自动攻击、ProjectileBase 走 DamageSystem
- [x] **D4 圣水+卡组+出牌**：BattleManager 出牌分发、圣水系统、DeckManager 8牌循环、AI 出牌、胜负判定
- [x] **D5 卡牌 UI**：CardSlot.tscn/gd + CardBar.tscn/gd
  - 底部显示 4 张卡牌 + 1 张预告
  - 点击卡牌进入选中状态（高亮）
  - 再点击己方半场部署单位
  - 右键取消选中
  - 能量不足时卡牌变暗且不可点击
- [x] **索敌/追击 Bug 修复 + 测试体系**（0.6.1）
  - AttackComponent 锁定条件修正（attack_range 而非 sight_range）
  - UnitBase._get_primary_attack_range 格→像素转换修正
  - TowerBase._draw 射程圆格→像素修正
  - 6 个测试套件（50+ 断言）
- [x] **2.5D 渲染系统**（0.7.0）
  - Y_COMPRESS Y 轴透视压缩（World 容器 scale）
  - altitude 离地高度系统（飞行单位视觉上移 + 地面影子）
  - ProjectileBase 弹道弧线（arc_height sin 抛物线）
  - UnitsRoot y_sort 深度排序
  - 地图底板 top_level 脱离压缩
- [x] **过桥寻路 + 野猪骑士跳河**
  - BattlePathing 统一可达距离与桥路径移动
  - 普通地面单位跨河走桥
  - 野猪骑士 `can_jump_river = true`，跳河期间临时视为空中单位
- [x] **死亡延迟伤害系统（0.8.0）**
  - CombatantBase 死亡时发出 `death_damage_triggered` 信号
  - EffectManager → DelayedDamageEffect 延迟炸弹（引信 + 脉冲指示 + 范围伤害）
  - BattlefieldEffect 临时效果基类
  - 气球兵配置 death_damage=240 / death_radius=2.0格 / death_fuse_time=3.0秒
- [x] **时间限制与加时赛（0.8.0）**
  - 3 分钟常规 + 1 分钟加时赛（圣水 2x 加速）
  - 三级胜负判定：塔数 → 总血量百分比 → 平局
- [x] **圣水条 UI（0.8.0）**
  - CardBar 集成 ElixirBar（填充条 + 数字），监听 energy_changed 实时更新
- [x] **塔攻击测试 + 死亡伤害测试（0.8.0）**
  - test_tower_attack.gd：塔 AttackComponent 射程/索敌/伤害/冷却验证
  - test_death_damage.gd：死亡信号 → 延迟炸弹伤害 → DataRegistry 配置 3 层验证
- [x] **部署位置预览（0.8.1）**
  - DeployPreview 跟随鼠标显示半透明预览圆（绿=可部署/红=不可部署）
  - 支持多单位精确落点（SpawnManager 偏移计算去随机，预览与实际一致）
  - card_data 新增 spawn_offsets 字段支持显式偏移（一排/前后站/间距可控）
- [x] **国王塔激活机制（0.8.1）**
  - 国王塔初始未激活（暗化 + 攻击禁用），受击或公主塔被毁后激活
  - first_attack_delay 从 4.0 改为 0.5（正常前摇，激活逻辑由 TowerBase 控制）
- [x] **帧动画系统 P1 骨架（0.8.2）**
  - SpriteAnimator 纯观察者组件（轮询实体状态切换动画，不写回逻辑）
  - SpriteRegistry 全局 SpriteFrames 缓存（按需从 PNG 构建）
  - 支持 idle/walk 状态、Y 压缩反向补偿、阵营色调、高清/像素双纹理过滤
  - 无 animation 字段时 ColorRect 兜底，向后兼容
- [x] **弓箭手单位（0.8.2）**
  - 地面远程单位，射程 5 格，projectile + linear 弹道
  - 卡牌 cost 3，一次部署 2 只，spawn_offsets 左右各一格
  - 移动帧动画已接入（2 帧 1254×1254px 高清图）
- [x] **血条样式重做（0.8.2）**
  - 玩家方浅蓝底+正蓝填充，敌方浅红底+正红填充，fill 不盖住 border
  - 血条位置支持逐单位 health_bar_y 配置
- [x] **碰撞分离系统（0.8.3）**
  - CollisionSystem：同层（ground/air）圆形碰撞体分离，质量反比推挤
  - 不可移动实体（mass=0 的塔）承担零修正
  - 河道回弹 + 边界钳制
  - CombatantBase 新增 collision_radius / hurt_radius / mass 属性，所有单位和塔已配置
  - 射程公式修正：attack_range + collision_radius + target.hurt_radius
  - DamageSystem / TargetingSystem 均已接入碰撞/受击半径
- [x] **气球兵帧动画（0.8.3）**
  - 单帧静态图（idle/walk 共用 balloon.png）
- [x] **底层架构审查修复（0.9.0）**
  - [P0] EntityRegistry 重开泄漏修复
  - [P1] PoisonField 继承 BattlefieldEffect
  - [P1] ProjectileBase 溅射伤害统一走 DamageSystem
  - [P2] StatusEffect 状态效果框架（替代侵入式减速）
  - [P2] reach 公式去重（AttackComponent.compute_reach）
  - [P2] PlayerBattleState 封装双方状态
  - [P3] SpellProjectile 继承 ProjectileBase
  - [P3] AttackComponent 走 ProjectileManager
  - [P3] TowerBase._activate → activate_king 封装修复

## 必须完成

- [ ] **帧动画 P3**：死亡动画 opt-in 延迟销毁 + 受击闪白
- [ ] **更多单位帧动画接入**：knight / hog_rider / musketeer / mini_pekka 等待美术素材
- [ ] **调试面板**：DebugPanel.tscn/gd
  - Tab 切换显示
  - 显示详细信息
  - 添加测试按钮

## 可选增强

- [ ] 卡组轮换机制（已在 DeckManager 实现，可考虑视觉动画）
- [ ] 更多单位类型（范围攻击、快速单位等）
- [ ] 简单音效
- [ ] 单位死亡特效
- [ ] 塔受伤闪烁
- [ ] 暂停功能
- [ ] altitude 高度影响逻辑（当前纯视觉，可考虑高度差影响索敌距离）

## 暂不实现

- 联网对战
- 真实匹配系统
- 复杂寻路（A*）
- 商店和养成
- 开箱和排行榜
- 账号系统
- 真实版权素材

## 已知问题

1. **数据有 7 单位 10 卡**：knight、hog_rider、musketeer、mini_pekka、balloon、archers、giant + 火球/毒药/万箭齐发 3 张法术卡
2. **帧动画 P2 已完成（朝向+攻击），仍缺死亡/受击动画**：0.8.4 新增朝向系统（front/back + flip_h）+ 攻击动画状态。knight / hog_rider / giant / archers / balloon 已接入帧动画
3. **碰撞分离非物理引擎**：CollisionSystem 每帧迭代分离，无连续碰撞检测、无冲量/弹力/摩擦。大规模堆叠时可能有轻微抖动
4. **无暂停**：战斗开始后无法暂停
5. **altitude 离地高度仅视觉**：不影响索敌距离计算，飞行单位和地面单位仍按 2D 平面距离判定
6. **弹道弧线 arc_height 数据未填入**：ProjectileBase 已支持 arc_height，但当前单位/塔数据中未设置此值（默认 0.0 = 直线飞行）
7. **ArrowProjectile 未继承 ProjectileBase**：因无 $Body 子节点（纯 _draw 渲染），与 ProjectileBase 的 @onready 引用冲突。使用 ProjectileBase.compute_arc_offset() 静态方法共享弧高计算
8. **DebugBattle.tscn 无 EffectManager / SpellManager**：该场景主要用于单位移动调试，死亡炸弹和法术效果仅在 BattleScene 中生效
