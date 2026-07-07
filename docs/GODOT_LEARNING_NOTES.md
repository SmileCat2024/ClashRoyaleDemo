# Godot 初学者学习笔记

本文件帮助你（Godot 初学者）理解项目中用到的核心概念。

---

## 1. Node（节点）

Godot 中所有东西都是节点。节点是构成游戏的最小单元。

常见的节点类型：
- `Node2D`：2D 空间中的节点，有 position（位置）属性
- `Control`：UI 节点的基类，用 offset/anchor 定位
- `Label`：文字标签（继承 Control）
- `Button`：按钮（继承 Control）
- `ColorRect`：纯色矩形（继承 Control）
- `ProgressBar`：进度条（继承 Control）
- `Line2D`：画线条的节点
- `CanvasLayer`：UI 专用图层，始终覆盖在游戏画面之上
- `Node`：最基础的节点，没有位置，纯粹用于组织结构

节点有**父子关系**。例如：
```
BattleScene (Node2D)        ← 父节点
  ├── Arena (Node2D)        ← 子节点
  ├── TowersRoot (Node2D)
  └── UnitsRoot (Node2D)
```

---

## 2. Scene（场景）

场景是一组节点保存成的 `.tscn` 文件。可以理解为"预制体"或"蓝图"。

例如：
- `UnitBase.tscn` 是单位的基础模板
- `BattleScene.tscn` 是整场战斗，里面包含了 Arena、塔、管理器等

**场景嵌套**：一个场景可以实例化另一个场景。
例如 `BattleScene.tscn` 中实例化了 `Arena.tscn` 和 6 个塔场景。

**场景继承**：一个场景可以继承另一个场景。
例如 `KingTower.tscn` 继承了 `TowerBase.tscn`，自动获得所有子节点和脚本。

---

## 3. Script（脚本）

脚本（`.gd` 文件）给节点添加行为。通常挂在场景的根节点上。

GDScript 关键语法：
```gdscript
extends Node2D          # 声明这个脚本继承自 Node2D

var hp: int = 100       # 变量声明
@onready var label = $Label  # 节点就绪时自动获取子节点

func _ready():          # 节点进入场景树时调用一次
    print("hello")

func _process(delta):   # 每帧调用，delta 是上一帧的时间（秒）
    position.x += 10 * delta
```

`$` 符号是获取子节点的简写：
- `$Label` 等价于 `get_node("Label")`
- `$"../../Arena"` 表示从当前节点往上两级，再找 Arena

---

## 4. Signal（信号）

信号是 Godot 的事件通知机制。

**定义信号**（在 SignalBus.gd 中）：
```gdscript
signal battle_started
signal energy_changed(team: String, current: int, max_value: int)
```

**发出信号**：
```gdscript
SignalBus.battle_started.emit()
SignalBus.energy_changed.emit("player", 5, 10)
```

**接收信号**：
```gdscript
func _ready():
    SignalBus.energy_changed.connect(_on_energy_changed)

func _on_energy_changed(team: String, current: int, max_value: int):
    print("能量变化:", team, current, "/", max_value)
```

信号的好处：发出方和接收方不需要互相认识，松散耦合。

---

## 5. Autoload（全局单例）

Autoload 是 Godot 的全局脚本。在任何地方都能直接用名字访问。

本项目在 `project.godot` 中注册了 4 个 Autoload：
```
Game        → scripts/autoload/Game.gd
SceneLoader → scripts/autoload/SceneLoader.gd
DataRegistry→ scripts/autoload/DataRegistry.gd
SignalBus   → scripts/autoload/SignalBus.gd
```

使用示例：
```gdscript
# 在任何脚本中都可以直接调用
Game.start_battle()
SceneLoader.load_main_menu()
DataRegistry.get_unit_data("melee_grunt")
SignalBus.energy_changed.emit("player", 5, 10)
```

**如何手动注册 Autoload**（如果需要）：
1. 菜单栏 → Project → Project Settings
2. 切到 **Globals** 标签页
3. 在 Path 中输入脚本路径，Name 中输入名称
4. 点击 Add

---

## 6. 如何打开和查看各种文件

### 打开 BattleScene
1. 在编辑器左下角的 **FileSystem** 面板中
2. 展开 `scenes/battle/`
3. 双击 `BattleScene.tscn`
4. 你会看到场景树：Arena、TowersRoot、Managers 等

### 查看 UnitBase.gd
1. FileSystem → `scripts/entities/` → 双击 `UnitBase.gd`
2. 重点看 `setup()` 和 `_process()`

### 查看 TowerBase.gd
1. FileSystem → `scripts/entities/` → 双击 `TowerBase.gd`

### 查看卡牌/单位数据
1. FileSystem → `scripts/autoload/` → 双击 `DataRegistry.gd`
2. 看 `unit_data`、`card_data`、`tower_data` 字典

---

## 7. 如何调试运行

1. 按 **▶ 运行** 按钮运行项目
2. 运行时，编辑器底部的 **Output** 面板会显示 `print()` 输出
3. 如果有错误，**Output** 面板会标红显示
4. 通过 **项目 → 运行当前场景** 菜单（不从头开始）

### 常见错误排查

| 错误信息 | 可能原因 | 解决方法 |
|---------|---------|---------|
| "Node not found" | @onready 路径写错 | 检查 $ 后的路径是否与场景树一致 |
| "Invalid call: method 'take_damage' not found" | 目标节点没有该方法 | 确保目标和单位都有 take_damage 方法 |
| "Cannot call function on null object" | 引用为空 | 检查 @onready 是否正确获取到节点 |

---

## 8. 快捷键速查

运行时可用：

| 按键 | 功能 |
|------|------|
| **E** | 玩家能量 +1 |
| **W** | 敌方能量 +1 |
| **K** | 在鼠标位置生成一个玩家骑士 |
| **R** | 重新开始战斗 |
| **鼠标右键** | 取消当前选中的卡牌 |

编辑器中：

| 按键 | 功能 |
|------|------|
| **▶ 按钮** | 运行项目 |
| **菜单** | 运行当前场景 |
| **Ctrl+S** | 保存场景 |
