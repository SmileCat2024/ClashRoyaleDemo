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

## 必须完成

- [ ] **能量 UI**：EnergyBar.tscn/gd
  - 更好看的能量显示（圣水条/数字可视化）
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
- [ ] 部署位置预览
- [ ] 时间结束判定（比较双方主塔血量）
- [ ] 暂停功能
- [ ] altitude 高度影响逻辑（当前纯视觉，可考虑高度差影响索敌距离）

## 暂不实现

- 联网对战
- 真实匹配系统
- 复杂寻路（A*）
- 复杂动画系统
- 商店和养成
- 开箱和排行榜
- 账号系统
- 真实版权素材

## 已知问题

1. **数据只有 5 单位 5 卡**：knight、hog_rider、musketeer、mini_pekka、balloon。气球兵死亡伤害未实现
2. **能量显示仍为纯文字**：卡牌变暗已实现，但圣水条可视化待 EnergyBar
3. **单位可重叠**：没有物理碰撞，多个单位会叠在一起
4. **无复杂寻路/碰撞**：桥与跳河已实现，但没有 A*、障碍绕行和单位碰撞挤压
5. **无暂停**：战斗开始后无法暂停
6. **无时间结束判定**：只有主塔死亡才能结束战斗
7. **altitude 离地高度仅视觉**：不影响索敌距离计算，飞行单位和地面单位仍按 2D 平面距离判定
8. **弹道弧线 arc_height 数据未填入**：ProjectileBase 已支持 arc_height，但当前单位/塔数据中未设置此值（默认 0.0 = 直线飞行）
