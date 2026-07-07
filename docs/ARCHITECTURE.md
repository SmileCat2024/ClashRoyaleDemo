# 架构说明

## 整体架构图

```
┌──────────────────────────────────────────────────────────┐
│                    Autoload（全局单例）                     │
│  ┌──────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │  Game    │  │ SceneLoader  │  │   DataRegistry      │ │
│  │ (状态)   │  │ (场景切换)    │  │ (单位/卡牌/塔数据)   │ │
│  └──────────┘  └──────────────┘  └─────────────────────┘ │
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
│  │  │(总指挥)       │ │(生成单位)    │ │(敌方AI) ││     │
│  │  └───────────────┘ └──────────────┘ └─────────┘│     │
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
塔受到伤害 take_damage()
  ↓
current_hp <= 0 ?
  ├─ 否 → 继续
  └─ 是 → die()
            ↓
          SignalBus.tower_destroyed.emit(tower_id, team, tower_type)
            ↓
          BattleManager._on_tower_destroyed()
            ↓
          tower_type == "king" ?
            ├─ team == "enemy" → end_battle("victory")
            └─ team == "player" → end_battle("defeat")
                                      ↓
                            SignalBus.battle_ended.emit(result)
                                      ↓
                            BattleHUD 显示结果面板
```

## 设计原则

### 为什么有 World 容器和 Y 压缩？— 2.5D 双坐标空间

项目使用一个 `World`（Node2D）容器包裹所有游戏节点，施加 `scale = Vector2(1, 0.7863)` 的 Y 轴压缩，实现 2.5D 透视效果。

| | 游戏空间（逻辑） | 屏幕空间（渲染） |
|---|---|---|
| **谁用** | 所有实体的 position、索敌、移动、部署判定 | 玩家眼睛看到的 |
| **尺寸** | 360 × 640px（18格 × 32格） | 360 × 480px（= 640 × 0.7863） |
| **压缩** | 不压缩 | World 施加 Y_COMPRESS |

关键点：
- **逻辑代码永远只碰游戏空间坐标**。`global_position.distance_to()` 等距离计算在游戏空间中进行，不受压缩影响。
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
