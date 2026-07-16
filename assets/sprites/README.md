# 精灵帧动画素材规范

## 美术端约定（只需做两件事）

### 1. 同一角色的所有帧画布尺寸一致

例如骑士的全部帧（idle / walk / attack 各方向）都使用相同的画布尺寸（如 32×36px）。
不同角色之间可以不同尺寸。

### 2. 帧内角色对齐

同一个动作的序列帧之间，角色的脚底/重心位置保持稳定，不要在帧之间上下左右跳动。
跨动作之间尽量也保持一致（idle 的脚底位置 ≈ walk 的脚底位置）。

## 高清源图的无损工作流

仓库保留原始 PNG，不要求美术缩图，也不会覆盖源文件。Godot 的派生导入缓存按原图
`1/3` 线性尺寸生成，运行时由 `SpriteRegistry.get_render_scale()` 统一补偿 3 倍显示缩放，
因此单位在屏幕上的视觉尺寸、锚点和碰撞逻辑保持不变，而序列帧展开内存约降为原来的 `1/9`。

新增或替换序列帧后，在项目根目录运行：

```powershell
./tools/OptimizeSpriteImports.ps1
```

然后启动一次 Godot Editor 触发重新导入。塔贴图、火球和迫击炮弹使用独立尺寸逻辑，
脚本会自动排除，不要手动套用统一的 3 倍渲染补偿。

## 目录结构

```
assets/sprites/
  knight/                    ← unit_id（与 DataRegistry 中的 id 一致）
    idle_front_01.png
    idle_front_02.png
    walk_front_01.png
    walk_front_02.png
    walk_front_03.png
    walk_front_04.png
    attack_front_01.png
    attack_front_02.png      ← 如果需要标记命中帧，在数据中指定索引
    ...
  hog_rider/
    ...
```

## 命名规则

```
{state}_{direction}_{序号}.png

state:     idle | walk | attack | hit | death | spawn
direction: front | back    （front = 面朝镜头，back = 背朝镜头）
序号:       01, 02, 03, ...（两位数字）
```

左右方向不需要单独画，代码用 `flip_h` 水平翻转。

## DataRegistry 动画配置

在 `DataRegistry.gd` 的 `unit_data` 字典中，给需要动画的单位添加 `animation` 字段：

```gdscript
"knight": {
    "id": "knight",
    # ... 其他现有字段 ...

    "animation": {
        # 素材目录名（默认 = unit_id，可省略）
        "sprite_dir": "knight",

        # 进游戏后微调用（像素）
        "visual_offset_x": 0,       # 水平偏移，正=右移
        "visual_offset_y": -2,      # 垂直偏移，正=下移，负=上移
        "visual_scale": 1.0,        # 整体缩放

        # 动画状态定义
        "states": {
            "idle_front": {
                "frames": ["idle_front_01.png", "idle_front_02.png"],
                "duration": [0.3, 0.3],     # 每帧停留秒数（逐帧可不同）
                "mode": "loop",             # loop | once
            },
            "walk_front": {
                "frames": ["walk_front_01.png", "walk_front_02.png",
                           "walk_front_03.png", "walk_front_04.png"],
                "duration": [0.12, 0.12, 0.12, 0.12],
                "mode": "loop",
            },
            "attack_front": {
                "frames": ["attack_front_01.png", "attack_front_02.png",
                           "attack_front_03.png"],
                "duration": [0.08, 0.05, 0.12],
                "mode": "once",
            },
            # back 方向同理
            "idle_back": { ... },
            "walk_back": { ... },
            "attack_back": { ... },
        }
    }
}
```

## 缺失动画的降级规则

SpriteAnimator 查找动画时按以下顺序降级：

1. 精确匹配：`walk_front` → 找到了就用
2. 去方向后缀：`walk_front` → 找 `walk`
3. 兜底：找 `idle`
4. 全都没有 → 保持 ColorRect 方块渲染（不 crash）

所以美术可以**分批交付**：先给 walk_front，之后再补 walk_back、attack 等。
