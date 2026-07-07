# Pixel Lane Battle — 项目总览

## 项目简介

**Pixel Lane Battle**（像素双线对战）是一个 2D 像素风卡牌塔防对战游戏原型，用于课程作业。

核心玩法：玩家和敌人分别位于战场两端，各有 3 座塔。玩家通过消耗能量在己方半场召唤单位，单位自动向敌方移动并攻击。摧毁对方主塔即获胜。

## 如何运行

### 方法一：用 Godot 编辑器运行（推荐）

1. 打开 **Godot 4.7**（或 4.x 版本）。
2. 选择"导入"，找到项目根目录下的 `project.godot` 文件。
3. 导入后，点击右上角的 **▶ 运行** 按钮。
4. 游戏将启动并显示主菜单。

### 方法二：命令行运行

```bash
# 假设 Godot 可执行文件在 PATH 中
godot --path ./
```

### 运行后应该看到什么

1. **主菜单**：标题 "Pixel Lane Battle"，"开始战斗" 和 "退出游戏" 按钮。
2. 点击"开始战斗" → 进入 **战斗场景**。
3. 战斗场景中可以看到：
   - 深色战场背景
   - 上方红色半透明区域（敌方部署区）
   - 下方蓝色半透明区域（玩家部署区）
   - 中央灰色分界线
   - **6 座塔**（蓝色=玩家方，红色=敌方方），各有血条
   - 顶部显示时间、能量、敌方能量
   - 底部显示场上单位数量
4. **敌方 AI 会自动出牌**：等待几秒后会看到红色方块（敌方单位）出现并向下移动。
5. 按 **K** 在鼠标位置生成一个玩家单位（蓝色方块），它会自动向上移动攻击敌方。
6. 按 **E** / **W** 给玩家/敌方加能量。
7. 按 **R** 重开战斗。

## 目录结构

```
res://
  scenes/                    ← 场景文件（.tscn）
    main/
      MainMenu.tscn          ← 主菜单
    battle/
      Arena.tscn             ← 战场背景
      BattleScene.tscn       ← 战斗主场景（组装所有东西）
    ui/
      BattleHUD.tscn         ← 战斗界面（HUD）
    entities/
      units/
        UnitBase.tscn        ← 单位基础场景
        MeleeUnit.tscn       ← 近战兵（继承 UnitBase）
        RangedUnit.tscn      ← 远程兵
        TankUnit.tscn        ← 重甲兵
      towers/
        TowerBase.tscn       ← 塔基础场景
        KingTower.tscn       ← 主塔（继承 TowerBase）
        GuardTower.tscn      ← 防御塔

  scripts/                   ← 脚本文件（.gd）
    autoload/                ← 全局单例（自动加载）
      Game.gd                ← 游戏状态管理
      SceneLoader.gd         ← 场景切换
      DataRegistry.gd        ← 数据中心（单位/卡牌/塔属性）
      SignalBus.gd           ← 全局信号总线
    battle/                  ← 战斗逻辑
      BattleManager.gd       ← 战斗总指挥
      Arena.gd               ← 战场/部署区域
      SpawnManager.gd        ← 单位生成器
      TargetingSystem.gd     ← 目标选择工具
      SimpleEnemyAI.gd       ← 敌方 AI
      BattleConstants.gd     ← 常量定义
    entities/                ← 实体行为
      UnitBase.gd            ← 单位行为（移动/攻击/死亡）
      TowerBase.gd           ← 塔行为（寻敌/攻击/死亡）
    main/
      MainMenu.gd            ← 主菜单逻辑
    ui/
      BattleHUD.gd           ← 战斗 HUD 逻辑

  docs/                      ← 文档
  project.godot              ← Godot 项目配置
```

## 关键概念速查

| 概念 | 说明 |
|------|------|
| **Autoload** | 全局单例脚本，在任何场景中都能直接用名字访问。本项目有 4 个：Game、SceneLoader、DataRegistry、SignalBus |
| **Scene（.tscn）** | 可复用的节点组合，类似"预制体"。可以嵌套实例化 |
| **Script（.gd）** | GDScript 脚本，挂在节点上添加行为 |
| **Signal（信号）** | 事件通知机制。发出方 `emit`，接收方 `connect` |
| **@onready** | 节点就绪时自动获取子节点引用的特殊注解 |
| **class_name** | 给脚本注册全局类型名，其他脚本可以直接用名字引用 |

## 当前已完成的功能

- [x] 主菜单（标题 + 开始/退出按钮）
- [x] 场景切换（主菜单 ↔ 战斗场景）
- [x] 战场背景（部署区域、中央线、路线标记）
- [x] 6 座塔（玩家方 3 座 + 敌方方 3 座），带血条
- [x] 塔的攻击行为（自动攻击范围内的敌方单位）
- [x] 单位系统（近战兵/远程兵/重甲兵）
- [x] 单位移动、寻敌、攻击、死亡
- [x] 能量系统（每秒自动恢复）
- [x] 敌方 AI（自动出牌）
- [x] 胜负判定（主塔被摧毁时结束）
- [x] 调试快捷键（E/W/K/R）
- [x] 战斗 HUD（时间、能量、单位数量显示）

## 当前缺少的功能

- [ ] 卡牌 UI（底部卡牌栏，点击选择卡牌部署单位）
- [ ] 投射物系统（目前攻击是直接扣血）
- [ ] 调试面板（Tab 切换的详细面板）
- [ ] 完整卡组轮换机制
- [ ] 音效和粒子特效

## 已知问题

1. **没有卡牌 UI**：目前玩家无法通过正常方式部署单位，只能用 K 在鼠标位置生成单位。
2. **攻击是瞬时扣血**：没有投射物动画，远程兵的攻击看起来和近战兵一样。
3. **单位可能重叠**：没有物理碰撞，多个单位会叠在一起。

## 下一步最重要的 5 件事

1. 添加卡牌 UI（CardBar + CardSlot），让玩家能选择卡牌部署单位
2. 添加调试面板，方便课程演示
3. 优化单位外观（区分不同单位类型）
4. 添加投射物系统
5. 添加更多卡牌和单位类型
