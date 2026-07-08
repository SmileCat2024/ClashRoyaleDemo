# Pixel Lane Battle — 项目总览

## 项目简介

**Pixel Lane Battle**（像素双线对战）是一个 2.5D 像素风卡牌塔防对战游戏（类皇室战争），用于课程作业。

核心玩法：玩家和敌人分别位于战场两端，各有 3 座塔（2 公主塔 + 1 国王塔）。通过消耗圣水召唤单位，单位自动行进、索敌、攻击。摧毁对方国王塔即获胜。

## 如何运行

### 用 Godot 编辑器运行（推荐）

1. 打开 **Godot 4.7**
2. 选择"导入"，找到项目根目录下的 `project.godot` 文件
3. 导入后，点击右上角的 **▶ 运行** 按钮

### 运行测试

```bash
# 命令行 headless 模式
cd clash-royale
"<Godot路径>/Godot_v4.7-stable_win64_console.exe" --headless res://scenes/test/TestRunner.tscn
```

退出码 0 = 全部通过，1 = 有失败。当前有 16 个测试套件覆盖格系统、寻路、索敌、伤害、卡组、数据配置、攻击锁定、跳河、塔攻击、死亡炸弹、国王塔激活、碰撞分离、法术系统、毒药法术、障碍物避让和单位分离。

### 运行后应该看到什么

1. **主菜单**：标题 "Pixel Lane Battle"，"开始战斗" 和 "退出游戏" 按钮
2. 点击"开始战斗" → 进入 **战斗场景**（BattleScene）
3. 战斗场景中可以看到：
   - 地图底板 + Y 轴透视压缩的 2.5D 战场
   - 河道分隔上下两方，左右各一座桥
   - **6 座塔**（蓝色=玩家方，红色=敌方方），各有血条
   - 底部 **4 张手牌 + 1 张预告牌**（圣水条在左侧）
   - 顶部显示战斗时间
4. **敌方 AI 自动出牌**，双方单位自动行进、过桥、索敌、攻击
5. **玩家操作**：点击卡牌选中 | 左键点击战场部署 | 右键取消 | 1-4 键也可选牌 | G/H 加玩家/敌方能量（调试）| R 重开
6. 摧毁对方国王塔即获胜，或时间到按塔数/血量判定

## 目录结构

```
res://
  scenes/
    main/             MainMenu.tscn
    battle/           Arena.tscn, BattleScene.tscn
    debug/            DebugBattle.tscn
    ui/               BattleHUD.tscn, CardBar.tscn, CardSlot.tscn
    entities/
      units/          UnitBase.tscn（唯一通用单位场景）
      towers/         TowerBase.tscn → KingTower / GuardTower (场景继承)
      Projectile.tscn, SpellProjectile.tscn, PoisonField.tscn
    test/             TestRunner.tscn
  scripts/
    autoload/         Game, SceneLoader, DataRegistry, SignalBus, EntityRegistry, SpriteRegistry
    battle/           BattleManager, SpawnManager, SpellManager, ProjectileManager, EffectManager,
                      SimpleEnemyAI, DeployPreview, Arena, BattleConstants, TargetingSystem,
                      BattlePathing, ArrowsSpellController
    entities/         CombatantBase, UnitBase, TowerBase, ProjectileBase, SpellProjectile, ArrowProjectile
    effects/          BattlefieldEffect, DelayedDamageEffect, PoisonField
    components/       AttackComponent, SpriteAnimator
    systems/          DamageSystem, CollisionSystem
    debug/            DebugBattle
    main/             MainMenu
    ui/               BattleHUD, CardBar, CardSlot
    tests/            TestBase, TestRunner, MockCombatant, test_*.gd（16 个测试套件）
  assets/
    sprites/          序列帧 PNG（按单位 ID 分目录，如 archers/、balloon/）
  docs/               SYSTEM_DESIGN, ARCHITECTURE, PROJECT_OVERVIEW, TODO, CHANGELOG
  project.godot
```

## 当前已完成的功能

### 核心
- [x] 主菜单 + 场景切换（主菜单 ↔ 战斗场景）
- [x] 战场背景（部署区域、河道、桥梁、中央线、路线标记）
- [x] 6 座塔（玩家方 3 + 敌方 3），带血条
- [x] 国王塔激活机制（受击/公主塔被毁后激活）
- [x] 单位系统（7 种单位共用一个场景，数据驱动）
- [x] 单位移动、过桥寻路、跳河（野猪骑士）
- [x] 单位避障转向系统（障碍物避让 + 同类分离 + 碰撞切向滑动）
- [x] 索敌+攻击系统（AttackComponent + DamageSystem）
- [x] 投射物系统（projectile + 弹道）
- [x] 圣水系统 + 圣水条 UI（含平滑过渡动画）
- [x] 卡牌 UI（点击选牌→点击部署，能量不足变暗禁用）+ 卡牌卡面图片
- [x] 卡组轮转（全卡牌循环：4 手牌 + 1 预告 + 队列）
- [x] 部署位置预览（半透明圆 + 多单位精确落点）
- [x] 敌方 AI（自动出牌）
- [x] 胜负判定（国王塔摧毁 + 时间限制 + 加时赛 + 三级判定）
- [x] 死亡延迟伤害（气球兵死亡炸弹：引信 + 脉冲指示 + 范围伤害）
- [x] 法术系统（SpellManager + 火球/毒药/万箭齐发三分支）

### 渲染与视觉
- [x] 2.5D 渲染（Y_COMPRESS 透视压缩 + altitude 离地高度 + 通用单位影子系统）
- [x] y_sort 深度排序
- [x] 弹道弧线（ProjectileBase arc_height sin 抛物线，数据未启用）
- [x] 帧动画系统（SpriteAnimator + SpriteRegistry，数据驱动序列帧动画）
- [x] 帧动画 P2（朝向翻转 front/back + flip_h + 攻击动画 + knight/hog_rider/giant 接入）
- [x] 血条样式重做（玩家方蓝/敌方红，统一 _style_health_bar）

### 物理
- [x] 碰撞分离系统（CollisionSystem：同层分离 + 质量反比推挤 + 河道回弹 + 边界钳制）
- [x] 射程/索敌/范围伤害公式接入碰撞半径

### 测试
- [x] 16 个测试套件（格系统、寻路、索敌、伤害、卡组、数据配置、攻击锁定、跳河、塔攻击、死亡炸弹、国王塔激活、碰撞分离、法术系统、毒药法术、障碍物避让、单位分离）

### 调试
- [x] 调试快捷键（G/H 加能量、K 生成骑士、D 打印状态、R 重开、1-4 选牌）

## 当前缺少的功能

- [ ] 暂停功能
- [ ] 调试面板（DebugPanel）
- [ ] 更多单位帧动画接入（死亡/受击状态，等待美术素材）
- [ ] 音效和粒子特效

## 已知问题

1. **数据有 7 单位 10 卡**：knight、hog_rider、musketeer、mini_pekka、balloon、archers、giant + 火球/毒药/万箭齐发法术卡
2. **帧动画缺死亡/受击动画**：P2 已完成朝向+攻击动画，仍缺死亡/受击状态
3. **碰撞分离非物理引擎**：每帧迭代分离，无连续碰撞检测、无冲量/弹力/摩擦
4. **无暂停**：战斗开始后无法暂停
5. **altitude 离地高度仅视觉**：不影响索敌距离计算
6. **弹道弧线 arc_height 数据未填入**：ProjectileBase 已支持，但当前数据中默认 0.0

## 技术栈

| 项目 | 值 |
|------|-----|
| 引擎 | Godot 4.7 (Forward+) |
| 脚本语言 | GDScript（无 C# / GDExtension） |
| 逻辑分辨率 | 440 × 780 |
| 窗口分辨率 | 880 × 1560 |
| 2.5D 透视 | Y_COMPRESS = 0.7863 |
| 纹理过滤 | Nearest（像素风） |
| 主场景 | `res://scenes/battle/BattleScene.tscn` |
