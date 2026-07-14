# 皇室战争还原 — 系统架构设计（修订版）

> 本文档经过多轮反思修订，反映了实际的优先级取舍和工程约束。
> 所有设计决策都是**最终版**，不含模糊选项。

---

## 一、优先级划分

### P0 — 不可砍（没有就不叫游戏）

| 功能 | 实现成本 | 风险 | 砍掉的影响 |
|------|---------|------|-----------|
| 双方塔（血量 + 存在） | 低 | 低 | 没有目标，游戏不成立 |
| 圣水增长 | 低 | 低 | 无法限制出牌 |
| 出牌→生成单位 | 中 | 中 | 核心玩法缺失 |
| 单位移动（直线推进） | 低 | 低 | 单位不动 |
| 索敌+攻击（单 AttackComponent） | 中 | 中 | 单位不攻击 |
| 护盾机制 | 低 | 低 | 缺一类兵种特性 |
| EntityRegistry + 配置校验 | 低 | 低 | 索敌效率差、配置错误难发现 |
| 推国王塔→胜负 | 低 | 低 | 无法结束游戏 |

### P1 — 最好有（砍了也能玩）

| 功能 | 砍掉的兜底方案 |
|------|---------------|
| 拖拽出牌 | 用点击选中→点击部署替代 |
| 8张牌轮转+4手牌+预告 | 固定4张牌，打完不消失 |
| ~~地面过桥寻路~~ | ✅ 已实现（BattlePathing 可达距离 + 走桥移动） |
| ~~高度系统 + z_index 排序~~ | ✅ 已实现（Y_COMPRESS 透视 + altitude 视觉偏移 + y_sort） |
| 空中单位 | 没有空军兵种 |
| 法术卡（延迟范围伤害） | 没有范围伤害玩法 |
| 建筑卡 | 少一类卡牌 |
| 国王塔激活机制 | 三塔一开始就攻击 |
| 部署预览圆圈 | 不知道能不能放，试错 |
| 公主塔死亡后扩展部署区 | 部署区域固定不变 |

### P2 — 时间多才做

- 多攻击（AttackComponent×N，哥布林巨人）
- 状态效果系统（减速/加速/回血）
- 弹道弧线（抛物线 ballistic）
- ~~时间到判定（比塔数/血量）~~ ✅ 已实现（0.8.0：3min 常规 + 1min 加时赛，三级判定）
- 多体召唤散开（骷髅军团）
- 近战溅射 / 远程溅射

### 明确不做

- ~~联网/回放/确定性同步~~ ✅ 联机已实现（0.19.1：Listen-Server 手动 RPC 方案，见 [6.10](#610-联机同步系统0191已实现)）；回放/确定性同步仍不做
- ~~单位碰撞挤压（接受重叠）~~ ✅ 已实现（0.8.3：CollisionSystem 碰撞分离，非物理引擎方案）
- 卡牌养成/商店
- 精确数值复刻

---

## 二、系统分层架构

```
┌─────────────────────────────────────────────────────────────┐
│               Autoload（全局单例）                             │
│  Game │ SceneLoader │ DataRegistry │ SignalBus │ EntityRegistry │
└─────────────────────────────────────────────────────────────┘
                           │
                    BattleScene.tscn
                           │
┌─────────────────────────────────────────────────────────────┐
│               Managers（战斗系统层 / 纯逻辑）                   │
│                                                              │
│  BattleManager     战斗生命周期、能量、出牌分发、胜负、时间/加时 │
│  DeckManager       卡组轮转（8牌循环队列）                      │
│  SpawnManager      实体生成（单位/建筑）                        │
│  SpellManager      法术执行（延迟范围伤害/状态施加）             │
│  ProjectileManager 飞行物管理                                  │
│  EffectManager     战场效果生成入口（监听 death_damage_triggered）│
│  StatusSystem      状态效果管理（P2）                          │
│  SimpleEnemyAI     敌方AI                                     │
└─────────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────────┐
│               Entity（实体层 / 有场景树节点）                    │
│                                                              │
│  CombatantBase (Node2D)                                      │
│  ├── 身份、血量/护盾、initialized标记、受伤、死亡              │
│  │                                                           │
│  ├── UnitBase        可移动战斗单位                            │
│  ├── BuildingBase    可部署建筑（P1，不移动，有持续时间）       │
│  └── TowerBase       国王塔/公主塔                            │
│                                                              │
│  AttackComponent (Node)    攻击组件（D2+，独立索敌+冷却+攻击）  │
│  SpriteAnimator (Node)    帧动画驱动器（0.8.2+，纯观察者轮询状态）│
│  ProjectileBase      飞行物                                   │
│                                                              │
│  BattlefieldEffect (Node2D) 战场效果基类（生命周期+_on_expire） │
│  └── DelayedDamageEffect   延迟范围伤害炸弹（引信→爆炸）       │
│                                                              │
│  CollisionSystem     碰撞分离（0.8.3+，静态工具，BattleManager  │
│                      _process() 末尾调用）                    │
└─────────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────────┐
│               UI（表现层 / 只显示和转发输入）                    │
│                                                              │
│  BattleHUD / CardBar / CardSlot / EnergyBar                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、Manager 通信规则（混合方案）

**规则：BattleManager 作为协调者，直接持有它调度的 Manager 引用。SignalBus 用于通知 UI 和跨系统事件。**

| Manager | 直接引用谁 | 说明 |
|---------|-----------|------|
| **BattleManager** | SpawnManager, SpellManager, DeckManager, Arena | 协调者，直接调度 |
| **SpawnManager** | EntityRegistry（register） | 生成后注册 |
| **SpellManager** | DamageSystem（static）, EntityRegistry（query） | 法术查实体造成伤害 |
| **DeckManager** | 无 | 纯状态管理，被 BattleManager 调用 |
| **SimpleEnemyAI** | BattleManager（调 try_play_card） | 和玩家走同一条路径 |
| **EffectManager** | 无 Manager 引用，监听 SignalBus.death_damage_triggered | 独立工作，信号驱动生成效果 |
| **UI** | 无 Manager 引用，只连 SignalBus | UI 永远不直接调逻辑层 |
| **Entity** | EntityRegistry（query）, DamageSystem（static） | 查敌人和造成伤害 |
| **AttackComponent** | EntityRegistry（query）, DamageSystem（static）, owner | 索敌和攻击结算 |
| **BattlefieldEffect** | DamageSystem（static）, EntityRegistry（via DamageSystem） | 到期结算伤害 |

**禁止的**：SpawnManager 引用 BattleManager。SpellManager 引用 DeckManager。UI 直接引用任何 Manager。

---

## 四、PlayerBattleState（0.9.0，已实现）

```gdscript
class_name PlayerBattleState
extends RefCounted

var team: String = "player"
var energy: int = 5
var max_energy: int = 10
var energy_progress: float = 0.0  # 当前积累的圣水完成度，供 UI 平滑显示

func can_spend(cost: int) -> bool
func spend(cost: int) -> void
func gain_energy() -> bool          # +1 不超上限
func reset() -> void                # 重置到初始状态
```

- 圣水放在 PlayerBattleState，不在 BattleManager 里放散装变量。
- BattleManager 持有两个 PlayerBattleState 实例（`_player_state` / `_enemy_state`），通过 `_get_state(team)` 获取。
- DeckManager 当前只管玩家方；敌方 AI 的出牌直接调 `BattleManager.try_play_card()`，能量从 `_enemy_state` 扣除。
- 未来 2v2 / 回放 / 旁观者只需扩展 `_get_state()` 返回逻辑。

---

## 五、数据 Schema

### 5.1 card_data — 卡牌配置

```gdscript
"card_knight": {
    "id": "card_knight",
    "display_name": "骑士",
    "cost": 3,
    "card_type": "troop",           # "troop" | "building" | "spell"
    "unit_id": "knight",            # troop → 关联 unit_data
    "spawn_count": 1,               # ★ 召唤数量。属于卡牌，不属于单位
    "spawn_spread": 0.0,            # 多体召唤散开半径
    "description": "一个坚韧的近战战士。",
}

# 骷髅军团 — spawn_count = 4
"card_skeleton_army": {
    "id": "card_skeleton_army",
    "cost": 3,
    "card_type": "troop",
    "unit_id": "skeleton",
    "spawn_count": 4,
    "spawn_spread": 30.0,
}

# 火球 — 法术参数直接在卡牌里
"card_fireball": {
    "id": "card_fireball",
    "cost": 4,
    "card_type": "spell",
    "spell_type": "fireball",       # "fireball" | "poison" | "arrows"
    "spell_radius": 2.5,            # 格（setup 时转像素）
    "spell_damage": 688,            # 对单位的范围伤害
    "tower_damage": 172,            # 对皇家塔的减伤
    "projectile_speed": 10.0,       # 格/秒
    "knockback": true,
    "knockback_distance": 1.0,      # 格
}
```

**为什么 spawn_count 在卡牌不在单位**：一个"骷髅"被墓碑生成时只有1个，被骷髅军团卡生成时才有4个。召唤数量是卡牌的部署规则，不是单位本体属性。

### 5.2 unit_data — 单位配置

```gdscript
"knight": {
    "id": "knight",
    "display_name": "骑士",
    "max_hp": 700,
    "shield": 0,                    # 护盾上限。0=无护盾
    "move_speed": 45.0,
    "movement_type": "ground",      # "ground" | "air"
    "can_jump_river": false,        # 可选。true=地面单位可跳河（当前仅野猪骑士）
    "sight_range": 120.0,           # 视野范围（发现敌人的距离）
    "movement_targeting": "any",    # "any" | "building_only"
    "collision_radius": 0.5,        # 碰撞体半径（格，setup 后转像素）。碰撞分离 + 射程扩展用
    "hurt_radius": 0.5,             # 受击半径（格）。法术/溅射/投射物命中判定
    "mass": 6,                      # 碰撞质量。越大被推得越少，0=不可移动（塔）
    "attacks": [{
        "name": "sword_slash",
        "targeting": "any",         # "any" | "building_only"
        "attack_ground": true,
        "attack_air": false,
        "attack_range": 28.0,
        "attack_interval": 1.1,
        "first_attack_delay": 0.3,  # 首次出手前摇
        "delivery": "instant",      # "instant" | "projectile"
        "trajectory": "homing",     # "homing" | "ballistic" | "linear"
        "impact_type": "single",    # "single" | "splash"
        "impact_radius": 0.0,
        "damage": 80,
    }],
}
```

**注意**：`scene_path` 不存在。SpawnManager 固定 `preload(UnitBase.tscn)`，所有单位共用一个场景。
**注意**：`count` / `spawn_count` 不存在。召唤数量由卡牌控制。

### 5.3 tower_data — 塔配置

```gdscript
"guard_tower": {
    "id": "guard_tower",
    "display_name": "公主塔",
    "tower_type": "guard",
    "max_hp": 1400,
    "shield": 0,
    "collision_radius": 1.5,        # 碰撞体半径（格）。塔内切圆半径 = 占地格数 / 2
    "hurt_radius": 1.5,             # 受击半径（格）
    "mass": 0,                      # 塔不可移动，碰撞时承担零修正
    "attacks": [{
        "name": "arrow_shot",
        "targeting": "any",
        "attack_ground": true,
        "attack_air": true,
        "attack_range": 140.0,
        "attack_interval": 0.8,
        "first_attack_delay": 0.0,
        "delivery": "projectile",
        "trajectory": "homing",
        "impact_type": "single",
        "impact_radius": 0.0,
        "damage": 50,
        "projectile_speed": 250.0,
    }],
}
```

P1 追加国王塔激活字段：`"starts_active": false`。

### 5.4 多攻击（P2，数据保留）

`attacks` 始终是数组。P0 只读 `attacks[0]`，创建一个 AttackComponent。P2 支持多个。

---

## 六、核心系统设计

### 6.1 护盾机制 — take_damage()

```
take_damage(amount):
    if current_shield > 0:
        current_shield = max(0, current_shield - amount)
        if current_shield == 0:
            SignalBus.shield_broken.emit(self)
        return                    # 有盾时不掉血
    current_hp -= amount
    if current_hp <= 0: die()
```

盾存在时，不管单次伤害多高，都不会溢出到血量。多次小伤害可以逐次削弱盾。

### 6.2 攻击系统 — 三维度解耦

攻击拆为三个正交维度（Delivery × Trajectory × Impact），存在每个 AttackComponent 内部：

| | 单体 (impact_radius=0) | 溅射 (impact_radius>0) |
|---|---|---|
| **instant** | 近战单体（骑士） | 近战溅射-以自身为中心（瓦基丽） |
| **projectile** | 远程单体（弓箭手） | 远程溅射-以命中点为中心（法师） |

DamageSystem.resolve_impact() 是共享的伤害结算入口，AttackComponent 和 ProjectileBase 都调它。

### 6.3 移动与攻击的职责划分

**核心原则：UnitBase 负责移动决策，AttackComponent 负责攻击决策。两者通过 primary attack 的 target 通信。**

```gdscript
# === UnitBase._process() 简化伪代码 ===
func _process(delta):
    if not initialized or is_dead: return

    var primary = get_primary_attack()
    if primary and primary.has_valid_target():
        var dist = distance_to(primary.target)
        if dist <= primary.attack_range:
            pass  # 在射程内，停下，AttackComponent 自己攻击
        else:
            move_toward(primary.target.position, delta)  # 追击
    else:
        # 无目标，找最近敌方塔
        var tower = find_nearest_enemy_tower()
        if tower: move_toward(tower.position, delta)
        else: move_forward(delta)

# === AttackComponent._process() 简化伪代码 ===
func _process(delta):
    if not owner.initialized or owner.is_dead: return
    if attack_cooldown > 0: attack_cooldown -= delta
    update_targeting(delta)  # 独立索敌

    if has_valid_target():
        var dist = owner.distance_to(target)
        if dist <= attack_range and attack_cooldown <= 0:
            execute_attack()
            attack_cooldown = attack_interval
```

**目标锁定规则**：锁定后持续攻击，直到目标离开 `attack_range`（含双方碰撞/受击半径的 reach 判定）才重新评估。reach 公式统一走 `AttackComponent.compute_reach()`，UnitBase 和 AttackComponent 共用。

**D1 过渡方案**：D1 没有 AttackComponent，UnitBase 直接从 `attacks_data[0]` 读 attack_range 决定何时停下，从 EntityRegistry 找最近敌方塔作为移动目标。

### 6.4 过桥寻路与跳河

`BattlePathing.gd` 是统一路径工具，索敌排序和单位移动都通过它计算，避免“索敌按直线、移动按路径”两套规则打架。

- 空中单位：`path_distance()` 使用直线距离，`advance_position()` 直飞目标
- 普通地面单位：跨河时 `path_distance()` 取左右桥中更短路线，`advance_position()` 按“桥口→过桥→目标”逐段移动
- 可跳河地面单位：单位数据配置 `can_jump_river = true`，跨河时比较“走桥”和“到河岸→跳跃跨河→目标”两条路线；跳河更短才跳，平局优先走桥

跳河由 `UnitBase` 状态机处理。跳跃期间：

- `is_jumping_river = true`
- `movement_type` 临时改为 `"air"`，落地后恢复 `base_movement_type`
- `altitude = sin(t * PI) * RIVER_JUMP_ARC_HEIGHT`，Body/HealthBar/DebugLabel 按 2.5D 视觉规则上移
- 地面攻击因 `attack_air = false` 无法继续锁定它，对空攻击可以锁定
- 起跳点和落点各离河岸 1px，确保逻辑坐标不落在非桥河道内

当前只有 `hog_rider` 配置 `can_jump_river = true`。后续单位复用该能力，只需要在 `unit_data` 增加同名字段；如果单位已经在桥线上跨河，会正常走桥，不进入跳跃状态。

**不用 NavigationRegion2D**：地图只有两桥和一种跳河能力，过桥/跳河路由用条件判断足够，更可控更省性能。但**绕塔/建筑避障**已升级为 A* 网格寻路（见 6.4.2），替代早期的 steering 避让方案。

### 6.4.1 碰撞分离系统（0.8.3，已实现）

**CollisionSystem**（`scripts/systems/CollisionSystem.gd`）在 `BattleManager._process()` 末尾调用，所有单位移动完毕后统一解析碰撞。

**不是物理引擎**：无刚体、无冲量、无摩擦、无连续碰撞检测。每帧做迭代位置分离（位置修正），让重叠的实体互推开。

#### 核心流程

```
resolve_overlaps(entities)
  ├─ ×3 迭代: _resolve_one_pass()
  │    └─ 两两检查 _resolve_pair(a, b):
  │         ├─ 分层检查：ground↔ground, air↔air（跳河临时 air 的单位参与空中层）
  │         ├─ 重叠判定：dist < collision_radius_a + collision_radius_b
  │         └─ 质量反比分配：
  │              overlap × (1/mass_a) / (1/mass_a + 1/mass_b)  → a 被推
  │              overlap × (1/mass_b) / (1/mass_a + 1/mass_b)  → b 被推
  │              mass=0 的实体不移动（塔），可移动方承担全部修正
  └─ _post_process(): 河道回弹 + 边界钳制
```

#### 关键设计决策

- **同层分离**：ground 和 air 互不碰撞（飞行单位从地面单位头顶飞过）
- **质量反比**：骑士 mass=6 推得少，弓箭手 mass=3 推得多。近似皇室战争中重单位推轻单位的效果
- **不可移动实体（mass=0）**：塔不参与位移修正。单位撞塔时全部被推开，塔纹丝不动
- **迭代 3 次**：多体堆叠时单次分离可能引入新的重叠，多次迭代消除残留
- **河道回弹**：分离后处理检查是否有地面单位被推入非桥河道，拉回最近岸（留白 1px）
- **边界钳制**：所有实体 clamp 到 `[collision_radius, ARENA_WIDTH/HEIGHT - collision_radius]`
- **同位置回退**：两个实体完全重叠时 `dist≈0`，方向向量退化。用 x 坐标比较确定确定性分离方向

#### 射程公式变更

碰撞系统引入后，攻击/索敌/范围伤害的距离判定统一扩展：

```
有效触及距离 = attack_range + attacker.collision_radius + target.hurt_radius
```

- **AttackComponent**：锁定判定和开火判定用此公式
- **UnitBase**：推塔停步距离用此公式
- **TargetingSystem**：索敌距离排序考虑双方碰撞半径
- **DamageSystem**：范围伤害命中判定 = `spell_radius + target.hurt_radius >= distance`

`hurt_radius` 与 `collision_radius` 分开：可以单独调节法术蹭塔、建筑受击等细节，而不影响碰撞体大小。

### 6.4.2 A* 网格寻路系统（替代 steering 避让）

**AStarPathfinder**（`scripts/battle/AStarPathfinder.gd`）对地面单位做动态网格寻路，绕开塔和可部署建筑（mass=0 的静态障碍物）。空中单位跳过 A*，直接走 BattlePathing 给的直线/过桥路径。

**为什么从 steering 升级到 A\***：早期版本（0.8.8）用 `_compute_obstacle_avoidance`（前方障碍物垂直偏转）+ `_compute_unit_separation`（boids 式分离）做轻量避让。但在塔群密集区域（如双公主塔 + 国王塔 + 敌方建筑挤在一起）会出现单位卡死、绕不出来的问题。A* 网格寻路从全局规划路径，彻底解决。

**单位移动三层架构**（当前）：

```
路径路由（BattlePathing）          → 河道/桥/跳河的大方向路由
  ↓ 给出"下一目标点"
A* 网格寻路（AStarPathfinder）     → 地面单位绕塔/建筑规划局部路径
  ↓ 返回像素路径点数组
同类分离 + 碰撞分离                → UnitBase._compute_unit_separation + CollisionSystem
  ↓ 最终位置修正
```

**关键接口**：
- `AStarPathfinder.find_path(from: Vector2, to: Vector2, mover_radius_cells: float) -> Array[Vector2]`
  - `from` / `to`：World 本地游戏空间坐标
  - `mover_radius_cells`：单位的碰撞半径（格），用于障碍物膨胀，避免单位贴着塔边卡住
  - 返回值：像素路径点数组（包括起点和终点），空数组表示无可达路径
- `UnitBase._recompute_path()`：目标切换时调用 A* 重新规划，缓存路径逐点移动

**障碍物来源**：`EntityRegistry.get_static_obstacles()` 返回所有 `mass=0` 的实体（塔 + 可部署建筑如迫击炮/地狱塔）。新增建筑卡牌（mass=0）会自动成为寻路障碍，无需额外注册。

**不做动态重规划**：单位只在目标切换时重新算路径，不会每帧重算。这意味着如果障碍物在单位移动中途出现（如敌方在路径上部署建筑），单位会在撞到障碍时才重新规划。

### 6.5 2.5D 渲染系统（已实现）

项目使用三层互相独立的空间组织画面。**战斗逻辑只使用 World 本地游戏空间**；视口大小、World 显示偏移、地图底板位置都不能参与寻路、索敌、距离判断。

#### 6.5.1 Y_COMPRESS — Y 轴透视压缩

```gdscript
const Y_COMPRESS := 0.7863  # BattleConstants
```

BattleScene.tscn 中的 `World`（Node2D）施加 `scale = Vector2(1, 0.7863)`：
- X 方向不压缩，Y 方向压扁为 78.63%
- 模拟从斜上方俯视的透视感（竞技场变"矮"了）
- 调整此常量即可改变透视强弱，无需改任何其他代码

**三层坐标职责**：

| 层 | 尺寸 / 变换 | 职责 |
|---|---|---|
| 视口空间 | project.godot 当前 440×780 | 只决定窗口裁剪和 UI 可见区域 |
| World 本地游戏空间 | 360×640，18×32 格 | 唯一逻辑空间。实体 `position`、河道、桥、塔、部署区、寻路都在这里 |
| 地图底板图 | `MapBackground.top_level = true` | 只负责底图显示，位置/缩放不改变逻辑坐标 |

- 鼠标输入通过 `world.get_local_mouse_position()` 自动逆变换回 World 本地游戏空间
- 底部卡牌 UI 区（480–720px）在 CanvasLayer 上，不受 Y 压缩
- 逻辑代码不要直接把 `global_position` 和 `BattleConstants` 常量混算；跨父节点目标位置用 `BattlePathing.game_position_of()`
- 桥位按格定义：左桥 x=2.5–4.5，右桥 x=13.5–15.5；路线中心线 x=3.5 / 14.5

#### 6.5.2 altitude — 离地高度（纯视觉）

```gdscript
# CombatantBase
var altitude: float = 0.0  # 格。地面单位=0，飞行单位>0

func _apply_altitude_offset() -> void:
    var dy := -altitude * BattleConstants.CELL_SIZE
    body_rect.position.y += dy       # Body 向上偏移
    health_bar.position.y += dy      # 血条跟随
    debug_label.position.y += dy     # 标签跟随
```

- UnitBase.setup() 中 `movement_type == "air"` 时设 `altitude = 2.5`，再用 `_set_visual_altitude()` 根据基础子节点位置应用视觉偏移
- 实体的 `position`（地面坐标）不变，仅视觉子节点上移
- altitude 偏移会随 World 的 Y 压缩自动收缩（因在 World 子树内）
- 常驻飞行单位的 altitude 不影响索敌距离；跳河单位在跳跃期间会临时改为 `movement_type = "air"`，影响 ground/air 攻击过滤

#### 6.5.3 飞行单位影子

UnitBase.\_draw() 在实体 origin（地面位置）绘制半透明椭圆影子。影子不受 altitude 偏移影响，始终在地面。

#### 6.5.4 弹道弧线（ProjectileBase）

```gdscript
var arc_height: float = 0.0  # 弹道最大弧高（格）

# _process() 中：
var arc := arc_height * sin(progress * PI) * CELL_SIZE
body_rect.position.y = _body_base_y - arc  # sin 抛物线偏移
```

- 仅影响 body\_rect 的视觉位置，不影响逻辑命中判定
- 国王塔（ballistic trajectory）目前数据中已标注，运行时按需启用

#### 6.5.5 深度排序（y\_sort）

UnitsRoot 开启 `y_sort_enabled = true`：Godot 按 Node2D 的 y 坐标自动排序绘制顺序（y 大的画在前面 = 离镜头近）。配合 altitude 偏移，飞行单位在天上时视觉上覆盖地面单位。

#### 节点结构

```
CombatantBase (Node2D)  ← position = 地面坐标（逻辑不变）
├── Body (ColorRect)    ← position.y 因 altitude 偏移（视觉上移）。有动画时保留可见用于位置校准
├── HealthBar           ← 跟随 Body 偏移。玩家方蓝/敌方红样式（_style_health_bar）
├── DebugLabel          ← 跟随 Body 偏移
├── _draw() 影子        ← 画在 origin (0,0)，不受偏移
├── AttackComponent(s)  ← 纯逻辑，无视觉
└── SpriteAnimator      ← 有 animation 字段时自动创建。创建 AnimatedSprite2D 子节点做帧动画
```

### 6.6 法术系统（0.8.5~0.8.7，已实现）

SpellManager.cast_spell() 按 `card_data.spell_type` 三分支分流：

| spell_type | 弹道 | 效果 | 对应类 |
|---|---|---|---|
| **fireball** | SpellProjectile 2.5D 抛物线（三帧火球动画 + 地面影子 + 弧高随距离自适应；素材向下朝向自动旋转至飞行方向） | 落地即时范围伤害（塔减伤）+ 击退 + 爆炸扩散圆 | SpellProjectile |
| **poison** | 无弹道，直接在目标位置创建 PoisonField | DOT 持续伤害（每 tick_interval 一跳，共 duration/tick 跳）+ 区域内减速 | PoisonField |
| **arrows** | ArrowsSpellController 编排 3 波箭雨（每波 15 支 ArrowProjectile） | 每波落地范围伤害，确定性向日葵分布 | ArrowsSpellController + ArrowProjectile |

**fireball 流程**：SpellManager 获取施法方国王塔位置 → 在 ProjectilesRoot 下创建 SpellProjectile → setup(origin, target, card, team) → 飞行（线性移动 + sin 抛物线弧高）→ 落地 `_on_impact()`：`DamageSystem.deal_area_damage()`（tower_damage 塔减伤）+ `CombatantBase.knockback()` → 爆炸视觉 → queue_free

**poison 流程**：SpellManager 获取目标位置 → 在 EffectsRoot 下直接创建 PoisonField（继承 BattlefieldEffect）→ setup(center, radius, tick_dmg, tower_dmg, team, duration, interval, slow) → 首跳立即伤害 → 每 tick_interval 秒一跳 `deal_area_damage` → 每帧对区域内敌方 `UnitBase.apply_slow()`（通过 StatusEffect 系统施加减速）→ lifetime 到期 super._process() 自动 queue_free

**arrows 流程**：SpellManager 获取施法方国王塔位置 → 创建 ArrowsSpellController → setup(origin, target, card, team, arrows_root) → 按 flight_time 编排发射+伤害时间表 → 每波 `_spawn_wave()`：横线阵型发射点 + 向日葵黄金角落点分布 + 按距离反推速度同步到达 → 每波 `_deal_wave_damage()`：`deal_area_damage` → 全部波次完成自毁

**共同入口**：BattleManager.try_play_card() 检查 card_type == "spell" → SpellManager.cast_spell()。法术卡全图可施放（Arena.is_spell_deploy_position 始终 true）。DeployPreview 法术卡显示半径圆。SimpleEnemyAI 法术卡瞄准玩家半场。

### 6.6.1 战场效果系统（0.8.0，已实现）

战场效果是"短暂存在于地面上、有有限生命周期的非战斗实体"。典型用例：气球兵死亡掉落炸弹、法术爆炸残留区域、召唤特效。

**继承体系**：

```
Node2D
└── BattlefieldEffect         ← 生命周期管理 + _on_expire() 到期回调
    ├── DelayedDamageEffect   ← 引信期间脉冲指示 → 到期范围伤害
    └── PoisonField           ← 持续 DOT + 减速区域（super._process 管理到期，追加 tick 逻辑）
```

**核心设计**：

- **BattlefieldEffect**（`scripts/effects/BattlefieldEffect.gd`）：基类。`setup(pos, team, lifetime)` 初始化，`_process()` 累加计时器，到期调 `_on_expire()` 然后 `queue_free()`。提供 `get_progress()` / `get_remaining_time()` 供视觉和查询使用
- **DelayedDamageEffect**（`scripts/effects/DelayedDamageEffect.gd`）：延迟伤害炸弹。`setup_damage(pos, team, fuse, dmg, radius)` 配置参数，`_on_expire()` 调 `DamageSystem.deal_area_damage()` 结算 + 发 `impact_resolved` 信号。`_draw()` 绘制脉冲爆炸半径指示圈
- **EffectManager**（`scripts/battle/EffectManager.gd`）：统一生成入口。监听 `SignalBus.death_damage_triggered`，自动在 `EffectsRoot` 下生成效果实例。与 SpawnManager / ProjectileManager 保持一致的管理器风格

**数据流（死亡炸弹完整链路）**：

```
CombatantBase.die()
  → death_damage > 0 ?
  → SignalBus.death_damage_triggered.emit(pos, dmg, radius, fuse, team)
  → EffectManager._on_death_damage_triggered()
  → spawn_delayed_damage() → DelayedDamageEffect 实例加入 EffectsRoot
  → setup_damage() 配置炸弹参数
  → 引信期间 _draw() 脉冲显示爆炸半径
  → _on_expire() → DamageSystem.deal_area_damage() → impact_resolved 信号
  → queue_free()
```

**扩展规则**：新增战场效果只需继承 `BattlefieldEffect`，重写 `_on_expire()`（如需持续逻辑则在 `_process()` 中调 `super._process(delta)` 后追加），创建对应场景文件，在 EffectManager 中注册生成入口。

### 6.6.2 状态效果系统（0.9.0，已实现）

状态效果是施加在 CombatantBase 上的临时修饰（减速、眩晕、中毒DoT 等）。由 `StatusEffect`（RefCounted 数据对象）+ `CombatantBase` 上的 `_status_effects` 列表共同管理。

**核心类**：`StatusEffect`（`scripts/effects/StatusEffect.gd`）— 纯数据对象，不挂场景树。字段：`type`（"slow" / "stun" / "poison"）、`duration`、`elapsed`、`move_speed_mult`、`tick_interval` / `tick_damage`（DoT 用）。同类效果按 `merge()` 规则叠加（slow 取最强减速 + 最长持续）。

**CombatantBase 接口**：
- `apply_status_effect(effect)` — 施加效果，同类自动 merge
- `_process_status_effects(delta)` — 子类 `_process()` 调用，处理过期和 DoT tick
- `get_move_speed_mult()` — 查询当前移动速度乘数（slow / stun 影响）
- `is_stunned()` — 是否眩晕（AttackComponent 检查此标记，眩晕时不能攻击）

**扩展新效果**：在 StatusEffect 加 type 和字段 → 在 `_process_status_effects()` 加 tick 逻辑 → 在查询方法中读取效果。

### 6.7 卡组轮转（P1）

```
deck = [c1, c2, c3, c4, c5, c6, c7, c8]
hand = deck[0:4], next = deck[4]

打出 c1 → deck.erase(c1), deck.push_back(c1)
→ hand = [c2, c3, c4, c5], next = c6
```

### 6.8 建筑系统（P1）

BuildingBase 继承 CombatantBase：不移动，有 `lifetime`，到期 queue_free()。攻击逻辑复用 AttackComponent。

### 6.9 帧动画系统（0.8.2，已实现 P1 骨架）

帧动画系统采用**纯观察者模式**——动画系统只读取游戏状态，永远不改变游戏逻辑。SpriteAnimator 每帧轮询实体的 `get_visual_state()` 切换动画，与 AttackComponent / UnitBase 核心流程完全解耦。

#### 核心组件

- **SpriteAnimator**（`scripts/components/SpriteAnimator.gd`）：挂在 CombatantBase 下的 Node 组件。在 `_init_combat_stats()` 末尾检查数据中是否有 `animation` 字段，有则自动创建。创建 AnimatedSprite2D 子节点做帧动画渲染。Y 压缩反向补偿（`scale.y /= Y_COMPRESS`）确保贴图宽高比正确。开发阶段不隐藏 Body(ColorRect)，两者并存方便位置校准
- **SpriteRegistry**（`scripts/autoload/SpriteRegistry.gd`）：全局 Autoload。按需从 `assets/sprites/{unit_id}/` 加载 PNG 构建 SpriteFrames 资源并按 unit_id 缓存。支持逐帧 duration、loop/once/pingpong 三种播放模式

#### 视觉状态接口

```gdscript
# CombatantBase（虚方法，默认返回 "idle"）
func get_visual_state() -> String:
    return "idle"

# UnitBase（覆写）
func get_visual_state() -> String:
    if is_dead: return "death"
    if _is_moving: return "walk"
    return "idle"
```

SpriteAnimator `_update_animation()` 先尝试匹配完整状态名（如 `walk_front`），找不到则回退基础名（`walk`），再回退到 `idle`。缺失的动画不 crash，静默降级。

#### 数据配置

```gdscript
"archers": {
    ...
    "animation": {
        "visual_offset_x": 0.0,      # sprite 水平偏移（像素，目测微调）
        "visual_offset_y": -65.0,    # sprite 垂直偏移（负=上移）
        "visual_scale": 0.066,       # 缩放系数
        "health_bar_y": -45.0,       # 血条 Y 偏移（负=上移）
        "states": {
            "walk": {
                "frames": ["walk_01.png", "walk_02.png"],
                "duration": [0.25, 0.25],
                "mode": "loop",
            },
        },
    },
}
```

无 `animation` 字段 → ColorRect 兜底（当前行为）。有字段但 PNG 缺失 → SpriteRegistry 返回 null，同样 ColorRect 兜底。

#### 后续路线（P2-P4）

- P2：攻击动画状态（AttackComponent 加 `is_firing()` 只读标记）+ 朝向系统（front/back + flip_h 水平翻转）
- P3：死亡动画 opt-in 延迟销毁 + 受击闪白
- P4：逐单位配置完善 + 美术素材批量接入

### 6.10 联机同步系统（0.19.1，已实现）

联机采用 **Listen-Server 架构**：Host（开房方）运行完整的战斗逻辑，Client（加入方）只负责渲染 + 转发输入。Host 是唯一权威，Client 不做任何战斗判定。

#### 6.10.1 架构总览

```
┌─────────────────────────────┐                ┌─────────────────────────────┐
│         Host（权威端）        │                │        Client（影子端）       │
│                             │                │                             │
│  BattleManager.is_host=true │   RPC 下行 ▶   │  BattleManager.is_host=false│
│  ┌───────────────────────┐  │                │  ┌───────────────────────┐  │
│  │ 全部战斗逻辑            │  │  30Hz unreliable│  │ 仅渲染 + 输入转发      │  │
│  │ 索敌/攻击/伤害/移动    │  │  + 事件 reliable│  │ 位置 lerp 插值        │  │
│  │ 碰撞/寿命/胜负         │  │                │  │ 本地推断动画/朝向     │  │
│  └───────────────────────┘  │                │  └───────────────────────┘  │
│           ▲                 │                │           │                 │
│           └──── 输入转发 ◀──┼────────────────┤  点击/选牌 → reliable RPC  │
└─────────────────────────────┘                └─────────────────────────────┘
```

**职责切分**：

| 关注点 | Host | Client |
|---|---|---|
| 索敌 / 攻击 / 伤害 | ✅ 唯一计算 | ❌ 不跑 |
| 移动 / 碰撞 / 寿命 | ✅ 唯一计算 | ❌ 不跑 |
| 能量 / 时间 / 胜负 | ✅ 唯一计算 | ❌ 只接收展示 |
| 单位 `position` | ✅ 真实位置 | lerp 插值追 Host 同步目标 |
| walk/idle 动画 | ✅ 真实状态 | **本地推断**（移动方向） |
| front/back 朝向 | ✅ 真实状态 | **本地推断**（按 team） |
| flip_h 水平翻转 | ✅ 真实状态 | **本地推断**（X 位移） |
| 攻击动画 / 朝向 | ✅ 出手即发 RPC | **RPC 同步**（事件型） |
| 投射物 / 法术创建 | ✅ 创建即发 RPC | **RPC 同步**（事件型） |

**关键决策**：放弃 Godot 内置的 `MultiplayerSynchronizer`（节点命名时序导致路径不匹配，地狱塔光束等持续视觉无法同步），改为**手动 RPC**。Host 每帧打包状态字典通过 unreliable 通道广播，Client 端按节点名查表应用。

`BattleManager.is_host` 在 `_ready()` 中根据 `NetworkManager.is_server()` 设定，联机模式（`is_network_mode`）下决定哪些逻辑路径执行、哪些 RPC 接收后直接 return（防回环）。

#### 6.10.2 双轨同步通道

同步分两类：**定频状态**（每 33ms 一包，可丢包可外推）和**事件**（必须到达，reliable）。

##### A. 30Hz unreliable 定频状态同步

```gdscript
const SYNC_INTERVAL: float = 0.033  # ≈30Hz
```

Host 在 `_process()` 中累加 `_sync_timer`，到达阈值后调用 `_sync_state_to_client()` 单次遍历收集所有状态并广播。

| RPC | 传输内容 | 数据格式 | Client 处理 |
|---|---|---|---|
| `_rpc_sync_units` | 所有单位/塔位置、血量、护盾、死亡 | `[[name, x, y, hp, shield, is_dead], ...]` | 位置镜像 + lerp 插值目标 + 血量直写 + 死亡触发视觉 |
| `_rpc_sync_state` | 能量、圣水进度、战斗时间、阶段 | `(p_energy, e_energy, p_progress, e_progress, time, phase)` | team 翻转映射能量 + 阶段切换信号 |
| `_rpc_sync_beams` | 地狱塔光束（激活/目标/阶段） | `[[name, active, target_x, target_y, stage], ...]` | 目标位置镜像 + `update_beam_from_sync()` |
| `_rpc_sync_hand` | 手牌 + 预告牌 | `(hand, next_card)` | 刷新本地牌库 |

**单位位置插值 + 外推**：Client 端收到 `_sync_target_pos` 后，`_process()` 用 lerp（`SYNC_LERP_SPEED`）平滑追上目标位置，消除 30Hz 同步包之间的卡顿。同时记录最近两个包的位移作为 `_sync_velocity`，丢包时按速度外推预测位置。

**节点查找缓存**：`_sync_node_cache`（Dictionary）缓存节点名→节点引用，避免每个 RPC 包重复 `get_node_or_null` 字符串匹配。

##### B. 事件型 reliable RPC（创建/触发型）

低频但必须到达的事件用 reliable 通道，Host 创建时立即广播，Client 端独立实例化并按确定性规则运行。

| RPC | 触发时机 | Client 处理 |
|---|---|---|
| `_rpc_spawn_unit` | SpawnManager 生成单位 | team 翻转 + 位置镜像后实例化（独立确定性移动） |
| `_rpc_spawn_projectile` | ProjectileManager 发射投射物 | 坐标镜像后实例化（独立确定性飞行） |
| `_rpc_spawn_mortar_shell` | 迫击炮发射炮弹 | 同上 |
| `_rpc_cast_spell` | SpellManager 施放法术 | 坐标镜像后实例化效果 |
| `_rpc_attack_trigger` | AttackComponent 出手瞬间（0.19.1 新增） | 朝向镜像翻转 + 播放攻击动画 |
| `_rpc_battle_end` | 战斗结束 | `end_battle(result)` |

**事件型 RPC 的共性**：投射物/炮弹/单位一旦实例化，后续飞行/移动就是确定性的（速度+目标已知），不再需要逐帧同步。这正是用 reliable 而非定频的原因——一次性事件，不能漏。

#### 6.10.3 坐标镜像 — BattleConstants.mirror()

Client 端要把 Host 的逻辑坐标系翻转 180°，让每个玩家都看到自己的塔在屏幕下方。

```gdscript
# BattleConstants.gd
## 联机 client 端 180 度镜像：以竞技场中心为对称点，同时翻转 X 和 Y。
## 用途：每个玩家屏幕上都看到自己的塔在下方。
## Host 用逻辑坐标，Client 渲染/输入用镜像坐标。
## 镜像是自反的：mirror(mirror(p)) == p。
static func mirror(pos: Vector2) -> Vector2:
    return Vector2(ARENA_WIDTH - pos.x, ARENA_HEIGHT - pos.y)
```

**应用规则**：

- **所有 RPC 下行的坐标**，Client 接收时调 `BattleConstants.mirror()`（单位位置、光束目标、法术落点、投射物起止点）
- **Client 端上行输入**（点击部署位置），上行前 mirror 还原回 Host 逻辑坐标，Host 收到的是未翻转坐标
- **塔初始位置**：Host 在创建塔时若 `not is_host`，直接对塔位 mirror
- **team 翻转**：Client 视角下，自己的 `player` = Host 的 `enemy`，反之亦然。能量同步、单位生成都做此翻转

**自反性**是关键：`mirror(mirror(p)) == p`，所以 Host↔Client 双向传递坐标时各自 mirror 一次即可还原，不会累积误差。

#### 6.10.4 攻击动画镜像规则

攻击触发 RPC（`_rpc_attack_trigger`）携带 `attack_facing`（三态：front/back/side）和 `flip_h`，Client 接收时按 180° 镜像规则翻转：

| 维度 | Host 值 | Client 翻转后 | 原理 |
|---|---|---|---|
| **facing** | `front` | `back` | dy 在镜像下变号（目标从下方变上方） |
| **facing** | `back` | `front` | 同上 |
| **facing** | `side` | `side`（不变） | \|dx\| 在镜像下不变（水平偏移不翻转） |
| **flip_h** | `true` | `false` | 左右镜像，翻转取反 |

```gdscript
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
```

**为何攻击用 RPC 而非本地推断**：攻击期间单位静止（位置不变），靠"移动方向推断朝向"会失效。攻击是低频事件（间隔 0.4~1.4s），用 reliable RPC 保证不漏播，与 `_rpc_spawn_projectile` 同模式。无帧动画的单位（ColorRect 兜底）跳过——没有 attack 动画可播。

#### 6.10.5 Client 端视觉推断

> **判断标准**：能从已同步数据（position / team）数学推导的状态用本地推断；依赖 Host 独立运行时变量（如攻击锁定、冲锋）的状态必须显式 RPC。

| 视觉状态 | 推断依据 | 实现位置 |
|---|---|---|
| **walk/idle 动画** | `_sync_target_pos` 与 `_last_sync_target` 距离差 > 阈值 = 在移动 | `UnitBase.get_visual_state()` client 分支 |
| **front/back 朝向** | 按 team（player→back，enemy→front） | `UnitBase.get_facing()` client 分支 |
| **flip_h 水平翻转** | `_sync_target_pos.x - _last_sync_target.x > 0.3`（向右移动翻转） | `UnitBase.get_flip_h()` client 分支 |
| **攻击动画/朝向** | ❌ 不推断，走 `_rpc_attack_trigger`（出手期间单位静止，方向推断失效） | `UnitBase.is_attacking()` / `get_attack_facing()` |

**朝向推断的巧思**：Client 端坐标已 mirror，team 已翻转。镜像后 player 单位向上走（屏幕下方→上方），其素材朝向恰好应是 back（背身向上）；enemy 单位向下走，朝向应是 front（面朝镜头）。所以**只看 team 就能定朝向**，无需额外同步移动方向。

**flip_h 在攻击期间的例外**：攻击触发时单位位置不变，X 位移推断失效，故 `get_flip_h()` 在 `_net_is_firing` 期间改读 RPC 同步的 `_net_flip_h`。

**国王塔激活**：不显式 RPC。Client 检测到塔 `current_hp < max_hp` 即视为已激活（受击激活的副产物），恢复 sprite 亮度。

#### 6.10.6 Client 端 _process 提前 return

为防止 Client 端误跑战斗逻辑，所有实体 `_process()` 开头检查 `_is_remote()`：

```gdscript
func _process(delta):
    if not initialized or is_dead: return
    if _is_remote():
        # Client 端仅做：位置 lerp 插值 + 部署动画 + 光束视觉更新
        _process_remote(delta)
        return
    # Host 端跑完整战斗逻辑
    ...
```

`_is_remote()`（在 CombatantBase）返回 `NetworkManager.is_networked() and not NetworkManager.is_server()`。新增任何视觉效果时，若需 Client 每帧更新，必须在 `_is_remote()` 的 return 之前调用更新方法——否则 Client 端看不到该效果。

**典型教训**：地狱塔光束（InfernoBeam）最初依赖 Host 端 AttackComponent 的 `_lock_target` 状态，未同步到 Client，导致 Client 看不到光束。修复方案是新增 `_rpc_sync_beams` 定频通道，把 `has_beam_target()` / `get_beam_target()` / `get_ramp_stage_index()` 三个 Host 独有状态打包同步。

#### 6.10.7 新增视觉效果/战斗机制的同步检查清单

1. **这个效果依赖什么数据？**
   - 只依赖 position / hp → 已被 `_rpc_sync_units` 覆盖
   - 依赖 Host 独有运行时状态（攻击目标、锁定时间、冷却、冲锋） → **必须 RPC 同步**
2. **持续性还是瞬时？**
   - 持续性（光束、光环、粒子）→ 加 30Hz 定频 RPC，参考 `_rpc_sync_beams`
   - 瞬时（投射物、爆炸、一次性特效）→ 创建时发一次 reliable RPC，参考 `_rpc_spawn_projectile`
3. **Client 端 `_process` 能驱动吗？**
   - 需要每帧更新的视觉，必须在 `_is_remote()` return 之前调用更新方法
4. **坐标和 team 是否需要镜像？**
   - 所有 RPC 下行坐标，Client 接收时 `BattleConstants.mirror()`
   - 所有 RPC 下行 team，Client 接收时翻转 player↔enemy

---

## 七、实体生命周期

### EntityRegistry 规则

| 时机 | 动作 |
|------|------|
| SpawnManager 生成实体后（setup 之后） | `EntityRegistry.register(entity)` |
| 实体 die() 被调用时 | `EntityRegistry.unregister(entity)`，在 queue_free 之前 |
| EntityRegistry 查询时 | 额外过滤 `is_instance_valid(e) and not e.is_dead`（双保险） |
| Projectile 目标死亡 | homing 飞到最后位置消失，area 继续到锁定位置溅射 |

### 实体生成顺序

```
instantiate → set position → add_child → setup → register
```

- `add_child` 触发 `_ready()`，`@onready` 子节点引用解析
- `setup` 配置属性，D2 起在这里动态创建 AttackComponent
- 所有实体有 `initialized: bool = false`，setup 末尾设 true
- `_process` / `_draw` 开头检查 `if not initialized: return`

### initialized 标记

防止实体在 setup 完成前被 `_process` 访问到未初始化的数据。

---

## 八、出牌调用链（最终版，无"或者"）

```
1. CardSlot 点击 → SignalBus.card_selected.emit(card_id, hand_index)
   → BattleManager._on_card_selected → _select_hand_card(hand_index)
   → DeployPreview.show_preview(card_data)

2. BattleManager._unhandled_input (左键点击战场)
   → world.get_local_mouse_position() → BattleConstants.snap_to_cell_center()
   → _try_deploy(world_pos)

3. BattleManager._try_deploy(world_pos)
   → try_play_card(card_id, "player", world_pos)

4. BattleManager.try_play_card(card_id, team, pos) → bool
   → 检查 battle_running + 能量 + 部署位置合法性
   → 按 card_type 分发：
       "troop"    → SpawnManager.spawn_unit()
       "building" → SpawnManager.spawn_building()
       "spell"    → SpellManager.cast_spell()
   → 扣能量
   → 成功: DeckManager.play_card() + card_played 信号

5. SpawnManager.spawn_unit()
   → DataRegistry 取数据
   → 读 spawn_count / spawn_spread
   → 循环: instantiate → position → add_child → setup → register
   → SignalBus.unit_spawned.emit()
```

**约束**：UI 永远不直接生成单位、扣圣水、改手牌。

---

## 九、SignalBus 信号清单

```gdscript
# 战斗生命周期
signal battle_started
signal battle_ended(result: String)
signal battle_phase_changed(phase: String, time_remaining: float)  # 0.8.0: 常规/加时切换

# 卡牌
signal card_selected(card_id: String)
signal card_played(card_id: String, team: String, position: Vector2)

# 能量
signal energy_changed(team: String, current: int, max_value: int)
signal elixir_generated(position: Vector2, team: String, amount: int, is_death: bool)  # 圣水收集器产出 / 死亡返还

# 实体
signal unit_spawned(unit: Node, team: String)
signal unit_died(unit: Node, team: String)
signal tower_destroyed(tower_id: String, team: String, tower_type: String)

# 战斗结算
signal shield_broken(combatant: Node)
signal death_damage_triggered(pos: Vector2, damage: int, radius: float, fuse: float, team: String)  # 0.8.0: 死亡炸弹

# 飞行物（D2+）
signal projectile_spawned(projectile: Node2D, team: String)
signal projectile_hit(position: Vector2, team: String)

# P1+ 追加
signal hand_updated(hand: Array, next_card: String)
signal impact_resolved(position: Vector2, impact_type: String, radius: float, team: String)
```

---

## 十、配置校验

DataRegistry._ready() 时自动运行 `_validate_all_data()`：
- 校验所有卡牌（id、cost、card_type、unit_id 引用是否存在）
- 校验所有单位（max_hp > 0；非被动单位的 attacks 非空且每个 attack 有 damage/range/interval/targeting/delivery）
- 校验所有塔（tower_type 合法、max_hp > 0）
- **一次性输出所有错误**，不遇错即停

---

## 十一、调试基础设施

| 功能 | 触发方式 | 预期结果 |
|------|---------|---------|
| 配置校验 | 启动自动运行 | 控制台打印"配置校验通过"或列出所有错误 |
| 生成骑士 | K | 鼠标位置出现骑士，自动走向最近敌方塔 |
| 实体状态转储 | D | 控制台打印所有实体的 id/team/pos/hp/target |
| DebugBattle 场景 | 直接运行 | 跳过主菜单，直接进战场测试 |

---

## 十二、血量更新

`health_bar` 是 CombatantBase 的可选子节点。`take_damage()` 里 `if health_bar: health_bar.value = current_hp`。
不发 `health_changed` 信号——两周项目不需要这层抽象。

---

## 十三、胜负判定

### 即时胜负（P0，已实现）
- 国王塔被摧毁 → 立即结束战斗（`end_battle("victory"/"defeat")`）

### 时间限制与加时赛（0.8.0，已实现）

```
常规时间 180s
  ├─ 国王塔被摧毁 → 立即胜负
  └─ 时间到 → _check_time_limit()
      ├─ 双方存活塔数不等 → 多者胜
      └─ 塔数相等 → 进入加时赛

加时赛 60s（圣水恢复 2x 加速）
  ├─ 国王塔被摧毁 → 立即胜负
  └─ 加时结束 → _determine_result_by_stats()
      ├─ 比塔数 → 多者胜
      ├─ 塔数相同 → 比总血量百分比 → 高者胜
      └─ 都相同 → 平局（"draw"）
```

- `battle_phase` 状态：`"regular"` / `"overtime"`
- 进入加时时广播 `battle_phase_changed("overtime", remaining)` 信号，圣水间隔减半
- 塔注册在 PlayerBattleState.towers 里

---

## 十四、实施计划（Day 1-14）

| 天 | 交付物 | 可运行验证 |
|----|--------|-----------|
| **D1** | DataRegistry 新 schema、DataValidator、EntityRegistry、CombatantBase/UnitBase/TowerBase 改造（initialized 标记）、DebugBattle 场景 | 启动无报错，K 生成骑士，骑士移动到塔前 |
| **D2** | AttackComponent、DamageSystem | 骑士走到塔前攻击，塔掉血 |
| **D3** | TargetingSystem 三重过滤、双方索敌互打 | 两个骑士互相攻击 |
| **D4** | BattleManager 出牌分发、圣水系统、PlayerBattleState | 点击出牌扣圣水，能量不够不能出 |
| **D5** | 卡牌 UI：CardBar + CardSlot + 点击部署 | **点击卡牌→点击战场→出兵** |
| **D6** | 胜负判定、TowerBase AttackComponent 接入 | 推国王塔→胜负面板 |
| **D7** | DebugPanel（D）、数值调整 | D 打印实体状态，战斗平衡 |
| **D8** | 拖拽部署、部署预览 | 拖拽卡牌到战场释放 |
| **D9** | DeckManager 8张牌轮转 | 打出的牌进队尾，下一张补上 |
| **D10** | 过桥寻路、SimpleEnemyAI 适配 | 地面单位过桥到对岸 |
| **D11** | 法术卡（延迟范围伤害）、SpellManager | 火球丢到人群造成范围伤害 |
| **D12** | 建筑卡、BuildingBase | 加农炮部署后自动攻击 |
| **D13** | 联调测试、数值调整、Bug 修复 | 完整对局可玩 |
| **D14** | 打磨、文档更新、录演示 | 可提交可演示 |

### 如果第 5 天还没跑通"骑士打塔"

立刻砍：
- 砍 EntityRegistry → 退回遍历场景树
- 砍 AttackComponent → 攻击逻辑写回 CombatantBase
- 砍 TargetingSystem 三重过滤 → 只做"最近敌方"
- 保住：UnitBase 能移动 + 攻击 + 塔能掉血

### 如果第 10 天还没跑通"完整出牌+战斗+胜负"

立刻砍：
- 砍拖拽 → 点击选中+点击部署
- 砍 DeckManager 轮转 → 固定4张牌
- 砍法术卡和建筑卡 → 只保留部队卡
- 砍国王塔激活 → 三塔一开始就攻击
- 保住：出牌→走路→攻击→推塔→胜负

---

## 十五、当前版本实现局限

1. **过桥/跳河用条件判断，绕障用 A\***：地图只有两桥，过桥路由用条件判断足够；地面单位绕塔/建筑用 A* 网格寻路（AStarPathfinder），空中单位走直线。A* 不做动态重规划（目标切换才重算）
2. **状态效果用简单属性修改**（P2）：不支持状态免疫、叠加规则
3. **溅射无衰减**：范围内全额伤害
4. **数据用字典硬编码**：未用 Godot Resource (.tres)
5. **无对象池**：飞行物每次 instantiate + queue_free
6. **碰撞分离非物理引擎**：CollisionSystem 每帧迭代位置分离，无连续碰撞检测、无冲量/弹力/摩擦。大规模堆叠时可能有轻微抖动
7. **法术按 spell_type 三分支**（0.8.5+）：fireball 走 SpellProjectile 抛物线弹道；poison 无弹道直接创建 PoisonField（DOT+减速）；arrows 走 ArrowsSpellController 多波编排
8. **多攻击 P2 才做**：P0 只读 attacks[0]，创建一个 AttackComponent
9. **altitude 离地高度仅视觉**：不影响逻辑，飞行单位和地面单位在索敌时仍按 2D 距离计算
10. **死亡炸弹爆炸无独立动画**：引信期间有脉冲指示圈，但到期瞬间 queue_free，无爆炸闪帧
11. **DebugBattle.tscn 无 EffectManager**：该场景主要用于单位移动调试，死亡炸弹仅在 BattleScene 中生效
12. **帧动画系统 P2 已完成**：支持 idle/walk/attack 状态 + front/back/side 朝向 + flip_h 水平翻转。当前 knight / hog_rider / giant / archers / balloon / goblins / mortar / mini_pekka 已接入帧动画。仍缺死亡/受击动画状态

---

## 十六、并行开发分工

| 模块 | 负责内容 | 依赖 |
|------|----------|------|
| **A. 基础设施** | DataRegistry schema、EntityRegistry、CombatantBase（护盾/initialized）、AttackComponent、DamageSystem | 无 |
| **B. 战斗核心** | TargetingSystem 三重过滤、移动与攻击协作 | A |
| **C. 卡牌系统** | DeckManager、CardBar、CardSlot、拖拽部署 | A |
| **D. 法术系统** | SpellManager、延迟范围伤害 | A, B |
| **E. 建筑系统** | BuildingBase、建筑部署 | A, B |
| **F. UI/能量** | EnergyBar、部署预览、BattleHUD | A, C |

### PR 规范

```
分支命名：  feature/<模块名>-<简述>
PR 标题：   [模块名] 简述
PR 描述：   改了什么 / 改了哪些文件 / 如何测试 / 依赖
```
