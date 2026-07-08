# 架构说明

> **归档文档（截至 0.8.2）**：本文档停止维护，架构相关信息以 `CLAUDE.md` 为唯一权威。
> 本文档保留作为历史参考，其中的架构图和模块描述可能已过时（缺少法术系统、steering、影子系统等 0.8.3+ 变更）。
> 如需了解当前架构，请阅读 `CLAUDE.md` 的"架构概览"和"继承体系"章节。

## 整体架构图

```
┌──────────────────────────────────────────────────────────┐
│                    Autoload（全局单例）                     │
│  ┌──────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │  Game    │  │ SceneLoader  │  │   DataRegistry      │ │
│  │ (状态)   │  │ (场景切换)    │  │ (单位/卡牌/塔数据)   │ │
│  └──────────┘  └──────────────┘  └─────────────────────┘ │
│  ┌──────────────────┐  ┌─────────────────────┐          │
│  │  EntityRegistry   │  │   SpriteRegistry    │          │
│  │ (实体注册/索敌)    │  │ (精灵帧缓存)        │          │
│  └──────────────────┘  └─────────────────────┘          │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                    SignalBus                          │ │
│  │     (全局信号总线，连接所有系统的事件通信)              │ │
│  └──────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                            │
                    场景切换 change_scene
                            ▼
┌──────────────────────────────────────────────────────────┐
│                    MainMenu.tscn                          │
│  MainMenu.gd → 点击按钮 → Game.start_battle()             │
└──────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────┐
│                   BattleScene.tscn                        │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  World (Node2D)  scale=(1, 0.7863) ← 2.5D Y压缩  │     │
│  │  ┌─────────┐  ┌────────────┐  ┌────────────────┐ │     │
│  │  │  Arena  │  │ TowersRoot │  │   UnitsRoot    │ │     │
│  │  │ (战场)  │  │  (6座塔)   │  │  (y_sort=true) │ │     │
│  │  │         │  │            │  │  (动态单位)    │ │     │
│  │  └─────────┘  └────────────┘  └────────────────┘ │     │
│  │  ┌────────────────┐  ┌───────────┐               │     │
│  │  │ ProjectilesRoot│  │EffectsRoot│               │     │
│  │  └────────────────┘  └───────────┘               │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │                   Managers                       │     │
│  │  ┌───────────────┐ ┌──────────────┐ ┌─────────┐│     │
│  │  │BattleManager  │ │SpawnManager  │ │EnemyAI  ││     │
│  │  │(总指挥/时间)  │ │(生成单位)    │ │(敌方AI) ││     │
│  │  └───────────────┘ └──────────────┘ └─────────┘│     │
│  │  ┌───────────────┐ ┌──────────────┐            │     │
│  │  │ProjectileMgr  │ │EffectManager │            │     │
│  │  │(飞行物管理)   │ │(战场效果生成)│            │     │
│  │  └───────────────┘ └──────────────┘            │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  CanvasLayer (不受 Y 压缩)                        │     │
│  │              ┌────────────┐                      │     │
│  │              │ BattleHUD  │ CardBar / CardSlot   │     │
│  │              └────────────┘                      │     │
│  └─────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

## 核心流程

### 玩家出牌流程（当前用键盘 1-4 + 鼠标，D5 添加卡牌 UI）

```
玩家按 1-4 选中手牌，左键点击战场
  ↓
BattleManager._input()
  ↓
_try_deploy() → try_play_card(card_id, "player", pos)
  ↓
SpawnManager.spawn_unit(card_id, "player", pos)
  ↓
1. DataRegistry.get_card_data(card_id) → 获取卡牌数据
2. 从卡牌数据找到 unit_id（如 "knight"）
3. DataRegistry.get_unit_data(unit_id) → 获取单位数据
4. preload(UnitBase.tscn).instantiate() → 创建单位节点（所有单位共用一个场景）
5. units_root.add_child(unit) → 加入战场
6. unit.setup(unit_data, "player") → 初始化属性（含 AttackComponent 创建）
7. EntityRegistry.register(unit) → 注册到索敌系统
8. SignalBus.unit_spawned.emit() → 通知其他系统
9. DeckManager.play_card(hand_index) → 卡组轮转（仅玩家）
```

### 敌方 AI 出牌流程

```
SimpleEnemyAI._process(delta)
  ↓ 每隔 2~4 秒
  ↓
choose_random_card() → 从卡组随机选卡牌
choose_spawn_position() → 在敌方区域随机选位置
  ↓
BattleManager.try_play_card(card_id, "enemy", position)
  ↓
  ├─ 检查能量是否足够
  ├─ 检查位置是否在敌方区域
  ├─ SpawnManager.spawn_unit_from_card() → 生成单位
  └─ spend_energy("enemy", cost) → 扣除能量
```

### 单位攻击流程

```
UnitBase._process(delta)
  ↓ 每 0.3 秒或目标失效时
  ↓
find_target()
  ├─ 收集所有敌方单位 → 优先选最近的
  └─ 没有敌方单位时 → 选最近的敌方塔
  ↓
目标在攻击范围内？
  ├─ 是 → attack_target() → target.take_damage(damage)
  └─ 否 → 朝目标移动
```

### 胜负判断流程

```
 ┌─ 国王塔被摧毁（任意时刻）
 │    → TowerBase.die()
 │    → SignalBus.tower_destroyed.emit()
 │    → BattleManager._on_tower_destroyed()
 │    → tower_type == "king" → end_battle("victory"/"defeat")
 │
 ├─ 常规时间 180s 到 → _check_time_limit()
 │    → 比塔数 → 不等则判胜负
 │    → 塔数相等 → _enter_overtime()（圣水 2x，battle_phase_changed 信号）
 │
 └─ 加时赛 60s 到 → _determine_result_by_stats()
      → 比塔数 → 比总血量百分比 → 平局("draw")
                    ↓
          SignalBus.battle_ended.emit(result)
                    ↓
          BattleHUD 显示结果面板
```

## 设计原则

### 为什么有 World 容器和 Y 压缩？— 视口 / 游戏空间 / 底图三层

项目使用一个 `World`（Node2D）容器包裹所有游戏节点，施加 `scale = Vector2(1, 0.7863)` 的 Y 轴压缩，实现 2.5D 透视效果。

| 层 | 谁用 | 说明 |
|---|---|---|
| **视口空间** | project.godot / CanvasLayer / HUD | 当前 440 × 780，只决定窗口裁剪和 UI 可见范围 |
| **World 本地游戏空间** | 实体 position、索敌、移动、部署、桥/河/塔常量 | 360 × 640（18格 × 32格），唯一战斗逻辑空间 |
| **地图底板图** | Arena.MapBackground | `top_level = true`，只负责底图显示，不改变逻辑坐标 |

关键点：
- **逻辑代码永远只碰 World 本地游戏空间坐标**。实体自身移动用 `position`；跨父节点读取目标位置时先转成 `World.to_local(node.global_position)`，不要直接拿 `global_position` 和 `BattleConstants` 的格子坐标混算。
- **鼠标坐标自动逆变换**：`world.get_local_mouse_position()` 把屏幕点击位置转回游戏空间，部署逻辑无需关心压缩。
- **CanvasLayer（卡牌 UI）不受压缩**：底部卡牌区在独立的 CanvasLayer 上，保持正常比例。
- **地图底板脱离压缩**：Arena 的 MapBackground 设 `top_level = true`，脱离 World 变换树，保持原始比例不变形。
- **飞行单位高度也仅视觉**：`altitude` 偏移在 World 子树内，随 Y 压缩自动收缩，不影响索敌距离。

### 为什么 UI 不直接生成单位？

BattleHUD 只负责**显示**。生成单位是 SpawnManager 的职责。

如果 HUD 直接生成单位，会导致：
- 能量检查、位置验证等逻辑散落在 UI 代码中
- 敌方 AI 也需要生成单位，会重复代码
- 难以维护和扩展

通过 BattleManager 统一调度，所有出牌（玩家和敌方）走同一条路径。

### 为什么数据放 DataRegistry？

单位属性（血量、攻击力等）集中在一个地方管理，好处：
- 修改数值只改一处
- 所有脚本通过 `DataRegistry.get_unit_data()` 查询，不自己硬编码
- 后续可以方便地替换为 Godot Resource 或外部配置文件

### 为什么用 SignalBus？

没有 SignalBus 时，脚本之间需要互相引用：
```gdscript
# 不好的方式
battle_hud.energy_label.text = "能量: 5"
```

用 SignalBus 后：
```gdscript
# 好的方式：发出信号
SignalBus.energy_changed.emit("player", 5, 10)

# HUD 自己监听并更新
func _on_energy_changed(team, current, max):
    energy_label.text = "能量: %d/%d" % [current, max]
```

发出方不需要知道谁在听，接收方不需要知道谁在发。松散耦合。

### 为什么死亡伤害要发信号而不是直接造成伤害？

气球兵死亡时的范围伤害不是瞬时结算，而是延迟炸弹（引信 3 秒后才爆炸）。

如果 `CombatantBase.die()` 直接调 `DamageSystem.deal_area_damage()`：
- 实体层需要知道"炸弹效果"这个概念（违反职责分离）
- 无法延迟执行（die → queue_free 后实体已不存在）
- 其他需要监听死亡伤害的系统无法介入

通过信号解耦：
```gdscript
# CombatantBase 只负责声明"我死了，有死亡伤害参数"
SignalBus.death_damage_triggered.emit(pos, damage, radius, fuse, team)

# EffectManager 负责生成效果实例
func _on_death_damage_triggered(pos, damage, radius, fuse, team):
    spawn_delayed_damage(pos, damage, radius, fuse, team)
```

实体层不知道效果系统的存在，效果系统不知道哪个实体会触发它。新增其他死亡效果类型时，只需在 EffectManager 中添加新的监听分支。
