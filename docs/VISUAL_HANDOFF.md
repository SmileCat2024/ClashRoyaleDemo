# 卡槽底板对齐交接文档

> 本文档供视觉模型使用。所有布局参数已在代码中就位，只需微调数字即可对齐。

## 背景

已将皇室战争原版卡槽底板图 `卡槽.png`（1916×821px）接入项目，作为底部卡牌栏背景。4 张卡牌槽位、预告牌、圣水条均已在代码中创建并定位，当前为**估算位置**，需要视觉模型根据实际图片内容微调。

## 已完成的工作

1. 图片已复制到 `res://assets/ui/卡槽.png`
2. CardBar.tscn 已重构：BgTexture（底板图）+ 4 个 CardSlot + NextCardPanel + ElixirBar
3. CardSlot 已改为透明背景（StyleBoxEmpty），底板图直接可见
4. 圣水条结构已搭建（背景条 + 填充条 + 数字标签），功能已通
5. **所有位置/尺寸参数集中在 `scripts/ui/CardBar.gd` 文件顶部常量区**

## 坐标系说明

- **逻辑视口**：440 × 780px
- **窗口**：880 × 1560px（2 倍缩放）
- **CanvasLayer 偏移**：(40, 0) —— 整个 UI 右移 40px 对齐竞技场
- **HUD 实际可用宽度**：400px（视口 440 - 右侧40px 被裁剪）
- **CardBar 覆盖区域**：(-40, 590) → (400, 780)，共 440×190px（占满视口全宽）
- **CardBar 本地坐标系**：左上角 = (0, 0)，向右 +x，向下 +y
- 所有卡槽/预告牌/圣水条的位置都是 **CardBar 本地坐标**

## 底板图显示方式

- BgTexture 是 TextureRect，`expand_mode = 1`（IGNORE_SIZE，自动拉伸填充 CardBar）
- `texture_filter = 1`（LINEAR，高清图片用线性过滤不锯齿）
- 图片会自动缩放到 CardBar 的 440×180px 区域

## 需要调整的参数（全在 CardBar.gd 顶部）

打开 `scripts/ui/CardBar.gd`，文件头部有一块标注了 `视觉模型交接区` 的常量：

### 1. CardBar 覆盖区域

```gdscript
const BAR_LEFT   := -40   # 延伸到 viewport 左边缘
const BAR_TOP    := 590   # 卡槽区上边界（国王塔下方）
const BAR_RIGHT  := 400   # viewport 右边缘
const BAR_BOTTOM := 780   # 视口底部
```

### 2. 卡牌槽位（4 张手牌）

```gdscript
const SLOT_W   := 77      # 单个卡槽宽度
const SLOT_H   := 113     # 单个卡槽高度
const SLOT_GAP := 6       # 卡槽间距
const SLOT_ROW_Y := 21    # 卡槽行顶部 y（CardBar 本地坐标）
const SLOT_START_X := 73  # 最左边卡槽的 x
```

**调整建议**：对照底板图中的卡槽边框，让透明卡牌按钮刚好覆盖在图片的卡槽孔位上。卡槽是可点击的交互区域，NameLabel 和 CostLabel 显示在其上方。

### 3. 预告牌（下一张）

```gdscript
const NEXT_W := 65
const NEXT_H := 100
const NEXT_X  := 10
const NEXT_Y  := 65
```

### 4. 圣水条

```gdscript
const ELIXIR_X := 73
const ELIXIR_Y := 147
const ELIXIR_W := 327
const ELIXIR_H := 23
```

圣水条当前用 ColorRect 简易实现：紫色背景 + 填充条 + 居中数字。如果底板图自带圣水条外观，可以把 ElixirBarBg 和 ElixirFill 设为透明（或删除），只保留 ElixirLabel 数字。

## 节点树结构（CardBar.tscn）

```
CardBar (Control)
├── BgTexture (TextureRect)     ← 底板背景图，填满 CardBar
├── CardSlot0 (Button)          ← 卡槽1（透明背景）
├── CardSlot1 (Button)
├── CardSlot2 (Button)
├── CardSlot3 (Button)
├── NextCardPanel (Panel)       ← 预告牌
│   ├── NextTitleLabel          ← "下一张"
│   └── NextNameLabel           ← 卡牌名称
└── ElixirBar (Control)         ← 圣水条
    ├── ElixirBarBg (ColorRect) ← 背景
    ├── ElixirFill (ColorRect)  ← 填充条（随能量缩放）
    └── ElixirLabel (Label)     ← "5/10" 数字
```

## 操作步骤

1. 在 Godot 编辑器中打开项目，运行 BattleScene
2. 观察底板图显示效果
3. 打开 `scripts/ui/CardBar.gd`，对照底板图调整常量
4. 保存 → 运行查看效果 → 反复微调直到对齐

## 注意事项

- CardSlot 内的 NameLabel（底部卡牌名）和 CostLabel（左上角费用）位置在 `CardSlot.tscn` 中定义，如需微调可编辑该文件
- CardSlot 选中时整体变亮（modulate tint），变暗时整体暗化——这些是纯 modulate 效果，不影响底板图
- 底板图的纹理过滤已设为 LINEAR，不会出现像素锯齿
- **不要改 CardBar.tscn 中节点的 offset/position**——全部由 CardBar.gd 常量控制，改 .tscn 无效（会被 _ready() 覆盖）
