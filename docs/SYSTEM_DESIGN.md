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
| 地面过桥寻路 | 所有单位直线推进（假装没有河） |
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
- 时间到判定（比塔数/血量）
- 多体召唤散开（骷髅军团）
- 近战溅射 / 远程溅射

### 明确不做

- 联网/回放/确定性同步
- 单位碰撞挤压（接受重叠）
- 动画系统（ColorRect 占位到底）
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
│  BattleManager     战斗生命周期、能量、出牌分发、胜负            │
│  DeckManager       卡组轮转（8牌循环队列）                      │
│  SpawnManager      实体生成（单位/建筑）                        │
│  SpellManager      法术执行（延迟范围伤害/状态施加）             │
│  ProjectileManager 飞行物管理                                  │
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
│  ProjectileBase      飞行物                                   │
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
| **UI** | 无 Manager 引用，只连 SignalBus | UI 永远不直接调逻辑层 |
| **Entity** | EntityRegistry（query）, DamageSystem（static） | 查敌人和造成伤害 |
| **AttackComponent** | EntityRegistry（query）, DamageSystem（static）, owner | 索敌和攻击结算 |

**禁止的**：SpawnManager 引用 BattleManager。SpellManager 引用 DeckManager。UI 直接引用任何 Manager。

---

## 四、PlayerBattleState

```gdscript
class_name PlayerBattleState
extends RefCounted

var team: String = "player"
var energy: int = 5
var max_energy: int = 10
var deck: Array = []          # 完整8张牌的id队列
var hand: Array = []          # 当前4张手牌的id
var next_card: String = ""    # 下一张预告
var towers: Array = []        # TowerBase 引用列表
var is_ai: bool = false
```

- 圣水放在 PlayerBattleState，不在 BattleManager 里放散装变量。
- BattleManager 持有两个 PlayerBattleState 实例。
- DeckManager 一个实例管双方，方法都带 team 参数。
- SimpleEnemyAI 调 `BattleManager.try_play_card()`，和玩家走完全相同路径。

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
    "spell_type": "damage",         # "damage" | "status" | "summon"
    "spell_radius": 60.0,
    "spell_damage": 300,
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
    "sight_range": 120.0,           # 视野范围（发现敌人的距离）
    "movement_targeting": "any",    # "any" | "building_only"
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

**目标锁定规则**：锁定后持续攻击，直到目标离开 `sight_range`（不是 attack_range）才重新评估。

**D1 过渡方案**：D1 没有 AttackComponent，UnitBase 直接从 `attacks_data[0]` 读 attack_range 决定何时停下，从 EntityRegistry 找最近敌方塔作为移动目标。

### 6.4 过桥寻路

```gdscript
func _get_move_direction(delta) -> Vector2:
    var dest = get_movement_destination()
    if dest == null:
        return Vector2(0, forward_y)

    if movement_type == "air" or can_cross_river:
        return (dest - global_position).normalized()

    # 地面单位：检查是否需要过河
    var same_side = is_same_side_of_river(global_position.y, dest.y)
    if not same_side:
        var bridge_x = nearest_bridge_x(global_position.x)
        if abs(global_position.x - bridge_x) > BRIDGE_ALIGN_THRESHOLD:
            return Vector2(signf(bridge_x - global_position.x), 0)  # 横移到桥口
        else:
            return Vector2(0, forward_y)  # 对齐后直行过桥
    else:
        return (dest - global_position).normalized()  # 同侧直走
```

**边界场景**：
- 左路部署但目标在右路 → 走最近的桥过河，过河后直线走向目标
- 目标在河对岸但不在桥上 → 先到桥口→过桥→直线走向目标
- 过桥后目标死亡 → 重新评估，找最近敌方单位或塔

**不用 NavigationRegion2D**：地图只有两桥，条件判断足够，更可控更省性能。

### 6.5 2.5D 渲染系统（已实现）

项目使用三层手段实现 2.5D 透视效果。**所有手段仅影响视觉，不影响逻辑**——索敌、移动、部署区域判定全部在 2D 游戏空间中进行。

#### 6.5.1 Y_COMPRESS — Y 轴透视压缩

```gdscript
const Y_COMPRESS := 0.7863  # BattleConstants
```

BattleScene.tscn 中的 `World`（Node2D）施加 `scale = Vector2(1, 0.7863)`：
- X 方向不压缩，Y 方向压扁为 78.63%
- 模拟从斜上方俯视的透视感（竞技场变"矮"了）
- 调整此常量即可改变透视强弱，无需改任何其他代码

**双坐标空间**：

| | 宽度 | 高度 | 说明 |
|---|---|---|---|
| 游戏空间（逻辑） | 360px | 640px | 所有实体的 `position` 在此空间，所有逻辑计算用此坐标 |
| 屏幕空间（渲染） | 360px | 480px（= 640 × 0.7863）| 玩家实际看到的 World 内区域 |

- 鼠标输入通过 `world.get_local_mouse_position()` 自动逆变换回游戏空间
- 底部卡牌 UI 区（480–720px）在 CanvasLayer 上，不受 Y 压缩
- 地图底板（MapBackground）用 `top_level = true` 脱离 World 变换，保持原始比例不变形

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

- UnitBase.setup() 中 `movement_type == "air"` 时设 `altitude = 2.5`，再调 `_apply_altitude_offset()`
- 实体的 `position`（地面坐标）不变，仅视觉子节点上移
- altitude 偏移会随 World 的 Y 压缩自动收缩（因在 World 子树内）
- **不影响索敌距离计算**——`global_position.distance_to()` 用的是地面坐标

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
├── Body (ColorRect)    ← position.y 因 altitude 偏移（视觉上移）
├── HealthBar           ← 跟随 Body 偏移
├── DebugLabel          ← 跟随 Body 偏移
├── _draw() 影子        ← 画在 origin (0,0)，不受偏移
└── AttackComponent(s)  ← 纯逻辑，无视觉
```

### 6.6 法术系统（P1）

P0/P1 版本：**延迟范围伤害**，不做真实弹道。
- SpellManager.execute_spell() 调 `DamageSystem.deal_area_damage(pos, radius, damage, team)`
- 视觉：ColorRect 扩散动画表示爆炸
- 真实飞行 Projectile（弧线弹道）→ P2

### 6.7 卡组轮转（P1）

```
deck = [c1, c2, c3, c4, c5, c6, c7, c8]
hand = deck[0:4], next = deck[4]

打出 c1 → deck.erase(c1), deck.push_back(c1)
→ hand = [c2, c3, c4, c5], next = c6
```

### 6.8 建筑系统（P1）

BuildingBase 继承 CombatantBase：不移动，有 `lifetime`，到期 queue_free()。攻击逻辑复用 AttackComponent。

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
1. CardSlot._get_drag_data()
   → 返回 { "card_id": self.card_id, "cost": self.cost } + DragPreview

2. Arena._can_drop_data(pos, data)
   → return BattleManager.can_deploy(team, data.card_id, world_pos)

3. Arena._process() （拖拽中）
   → 在鼠标位置绘制预览圆圈（合法=绿，非法=红）

4. Arena._drop_data(pos, data)
   → BattleManager.try_play_card(data.card_id, "player", world_pos)

5. BattleManager.try_play_card(card_id, team, pos) → bool
   → 检查 battle_running + can_deploy
   → 扣能量（先扣，失败则回滚）
   → 按 card_type 分发：
       "troop"    → SpawnManager.spawn_unit()
       "building" → SpawnManager.spawn_building()
       "spell"    → SpellManager.execute_spell()
   → 成功: card_played 信号 + DeckManager.cycle_card()
   → 失败: 回滚能量

6. SpawnManager.spawn_unit()
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

# 卡牌
signal card_selected(card_id: String)
signal card_played(card_id: String, team: String, position: Vector2)

# 能量
signal energy_changed(team: String, current: int, max_value: int)

# 实体
signal unit_spawned(unit: Node, team: String)
signal unit_died(unit: Node, team: String)
signal tower_destroyed(tower_id: String, team: String, tower_type: String)

# 战斗结算
signal shield_broken(combatant: Node)

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
- 校验所有单位（max_hp > 0、attacks 非空、每个 attack 有 damage/range/interval/targeting/delivery）
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

- **P0**：国王塔被摧毁 → 立即结束战斗。
- **P2**：时间到（180秒）→ 比剩余公主塔数量 → 比国王塔血量百分比。
- 塔注册在 PlayerBattleState.towers 里。

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
- 砍过桥寻路 → 所有单位直线推进
- 砍国王塔激活 → 三塔一开始就攻击
- 保住：出牌→走路→攻击→推塔→胜负

---

## 十五、当前版本实现局限

1. **寻路用条件判断而非 NavMesh**：地图只有两桥，航点足够
2. **状态效果用简单属性修改**（P2）：不支持状态免疫、叠加规则
3. **溅射无衰减**：范围内全额伤害
4. **数据用字典硬编码**：未用 Godot Resource (.tres)
5. **无对象池**：飞行物每次 instantiate + queue_free
6. **无物理碰撞分离**：单位可重叠
7. **法术用延迟伤害而非真实弹道**（P0/P1）：P2 才加弧线弹道
8. **多攻击 P2 才做**：P0 只读 attacks[0]，创建一个 AttackComponent
9. **altitude 离地高度仅视觉**：不影响逻辑，飞行单位和地面单位在索敌时仍按 2D 距离计算

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
