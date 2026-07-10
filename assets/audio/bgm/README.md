# 背景音乐目录（BGM）

放置所有背景音乐文件。推荐 `.ogg` 格式（支持无缝循环）。

## 命名约定

按场景/状态命名，与 `DataRegistry.bgm_data` 的 key 对应：

```
battle.ogg    ← "battle" BGM（战斗中循环播放）
menu.ogg      ← "menu" BGM（主菜单）
victory.ogg   ← "victory" BGM（胜利结算）
defeat.ogg    ← "defeat" BGM（失败结算）
```

## 接入流程

1. 把 `.ogg` 文件放入本目录
2. 打开 `scripts/autoload/DataRegistry.gd`，找到 `bgm_data` 字典
3. 在对应 BGM 的 `"stream"` 字段填入路径：

```gdscript
"battle": {
    "stream": "res://assets/audio/bgm/battle.ogg",  # ← 填这里
    "volume_db": -6.0,
},
```

4. 战斗开始时会自动播放 `battle` BGM（AudioManager 监听 `battle_started` 信号）。

## 循环设置

AudioManager 会自动为 `AudioStreamOggVorbis` 和 `AudioStreamMP3` 开启 `loop = true`。
如果使用 `.wav` 格式，需要在 Godot 导入设置中手动勾选 Loop。

## 编程接口

```gdscript
AudioManager.play_bgm("battle")       # 播放（默认 0.5s 淡入）
AudioManager.play_bgm("victory", 1.0) # 播放（1s 淡入）
AudioManager.stop_bgm()               # 停止（默认 0.5s 淡出）
AudioManager.stop_bgm(2.0)            # 停止（2s 淡出）
```
