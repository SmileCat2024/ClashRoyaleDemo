# 文件名：SignalBus.gd
# 作用：集中声明全局信号，让不同系统之间可以松散耦合地通信。
#       发出方不需要知道谁在听，接收方不需要知道谁在发。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：这里只是声明信号（signal），不需要理解实现细节。

extends Node

# ---- 战斗生命周期 ----

## 战斗开始时发出
signal battle_started

## 战斗结束时发出，result 为本地玩家视角的 "victory" / "defeat" / "draw"。
signal battle_ended(result: String)

## 战斗阶段变化（"regular" → "overtime"），time_remaining 为当前阶段剩余秒
signal battle_phase_changed(phase: String, time_remaining: float)

## 圣水倍率变更（1 / 2 / 3 / 7）。用于战斗 HUD 的倍率与阶段播报。
signal elixir_multiplier_changed(multiplier: int)

# ---- 卡牌相关 ----

## 玩家点击了一张卡牌槽位（点击卡牌进入部署待命状态）。
## hand_index 为手牌索引 0-3，BattleManager 据此切换选中状态。
signal card_selected(card_id: String, hand_index: int)

## 一张卡牌被成功打出（实体已生成 / 法术已执行）。
## is_awakened 用于让部署音效等表现只在觉醒版本生效。
signal card_played(card_id: String, team: String, position: Vector2, is_awakened: bool)

## 手牌状态更新（初始分配 / 出牌轮转后发出）。
## hand 为当前 4 张手牌 id 数组，next_card 为下一张预告 id。
signal hand_updated(hand: Array, next_card: String)

## 选中状态变化。hand_index 为当前选中槽位（-1 = 未选中）。
signal selection_changed(hand_index: int)

## 觉醒进度变化（打出觉醒牌后发出，含初始广播）。
## team: 阵营 | card_id: 卡牌 id | count: 累计普通版次数 | trigger_count: 阈值 | next_awakened: 下次是否觉醒
signal awakening_progress_changed(team: String, card_id: String, count: int, trigger_count: int, next_awakened: bool)

# ---- 精英技能 ----

## 精英单位生成（带 elite_skill 的卡牌打出后发出）。SkillBar 据此创建技能按钮。
signal elite_skill_added(unit: Node, skill_data: Dictionary)

## 精英单位死亡/释放。SkillBar 据此移除技能按钮。
signal elite_skill_removed(unit: Node)

## UI 请求释放精英技能（玩家点击技能按钮发出）。BattleManager 据此处理能量检查和瞄准。
signal elite_skill_requested(unit: Node, skill_data: Dictionary)

## 精英技能已释放。效果执行后发出，可用于音效/视觉触发。
signal elite_skill_cast(unit: Node, skill_data: Dictionary, target_pos: Vector2)

## 精英技能冷却变化（每帧或释放时发出）。SkillBar 据此更新冷却进度条。
signal elite_skill_cooldown_changed(unit: Node, remaining: float, total: float)

# ---- 能量相关 ----

## 某一方能量发生变化
signal energy_changed(team: String, current: int, max_value: int)

## 被动建筑产出圣水。position 使用 World 本地游戏坐标；is_death 标记死亡返还。
signal elixir_generated(position: Vector2, team: String, amount: int, is_death: bool)

## 玩家圣水当前正在积累的那一滴的完成度（0.0 ~ 1.0）。
## BattleManager 每帧更新，CardBar._process() 读取用于平滑过渡动画。
var player_energy_progress: float = 0.0

# ---- 实体相关 ----

## 一个单位被生成到战场上
signal unit_spawned(unit: Node, team: String)

## 一个单位死亡
signal unit_died(unit: Node, team: String)

## 单位死亡时请求召唤后续单位（如哥布林牢笼放出哥布林硬汉）。
## position 使用 World 本地游戏坐标；仅 Host / 单机端发出，SpawnManager 是唯一实际创建实体的入口。
signal unit_death_spawn_requested(position: Vector2, unit_id: String, team: String, count: int)

## 一座塔被摧毁
signal tower_destroyed(tower_id: String, team: String, tower_type: String)

# ---- 战斗结算 ----

## 护盾被打破
signal shield_broken(combatant: Node)

## 单位死亡时触发延迟范围伤害（如气球兵死亡掉落炸弹）。
## pos: 死亡位置 | damage: 伤害值 | radius: 半径（像素）| fuse: 引信延迟（秒）| team: 伤害来源阵营
signal death_damage_triggered(pos: Vector2, damage: int, radius: float, fuse: float, team: String)

# ---- 飞行物相关（D2+）----

## 一个飞行物被发射到战场上
signal projectile_spawned(projectile: Node2D, team: String)

## 一个飞行物命中目标
signal projectile_hit(position: Vector2, team: String)

## 一个范围效果在指定位置结算（如炸弹爆炸、法术命中）。
## impact_type: "single" | "splash"
signal impact_resolved(position: Vector2, impact_type: String, radius: float, team: String)
