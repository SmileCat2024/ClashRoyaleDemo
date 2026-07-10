# 音效资源目录（SFX）

放置所有战斗音效文件。文件格式推荐 `.ogg`（OggVorbis，体积小、质量好，Godot 原生支持循环）。

## 命名约定

按事件语义命名，全小写 + 下划线，与 `DataRegistry.sound_data` 的 key 对应：

```
deploy.ogg              ← "deploy" 事件（部署单位）
deploy_spell.ogg        ← "deploy_spell" 事件（施放法术）
attack_melee.ogg        ← "attack_melee" 事件（近战挥砍）
attack_ranged.ogg       ← "attack_ranged" 事件（远程发射）
projectile_launch.ogg   ← "projectile_launch" 事件（投射物出膛）
projectile_hit.ogg      ← "projectile_hit" 事件（投射物命中）
fireball_impact.ogg     ← "fireball_impact" 事件（火球爆炸）
tower_destroyed.ogg     ← "tower_destroyed" 事件（塔被摧毁）
...
```

## 接入流程

1. 把 `.ogg` 文件放入本目录
2. 打开 `scripts/autoload/DataRegistry.gd`，找到 `sound_data` 字典
3. 在对应事件的 `"stream"` 字段填入路径：

```gdscript
"deploy": {
    "stream": "res://assets/audio/sfx/deploy.ogg",  # ← 填这里
    "volume_db": -3.0,
    "pitch_range": [0.95, 1.05],
    "max_polyphony": 2,
    "priority": 5,
},
```

4. 运行游戏即可听到效果。无需重启编辑器（资源会在首次播放时缓存）。

## 单位专属音效

如果某个单位需要独特的音效（如骑士挥剑 vs 法师施法），在该单位的 `unit_data` 中加 `sfx` 字段：

```gdscript
"knight": {
    ...
    "sfx": {
        "attack": "attack_melee",   # 值为 sound_data 中的事件 id
        "death": "unit_die",
    },
},
```

然后在攻击/死亡的代码处调用：

```gdscript
AudioManager.play_unit_sfx(unit_id, "attack")
```

## 事件 id 速查

| 事件 id | 触发方式 | 说明 |
|---|---|---|
| `deploy` | 自动（card_played） | 部署单位 |
| `deploy_spell` | 自动（card_played） | 施放法术 |
| `attack_melee` | 手动（play_unit_sfx） | 近战攻击 |
| `attack_ranged` | 手动（play_unit_sfx） | 远程攻击 |
| `charge_hit` | 手动 | 王子冲锋命中 |
| `projectile_launch` | 自动（projectile_spawned） | 投射物发射 |
| `projectile_hit` | 自动（projectile_hit） | 投射物命中 |
| `mortar_launch` | 手动 | 迫击炮发射 |
| `hit_metal` | 手动 | 金属碰撞命中 |
| `hit_flesh` | 手动 | 血肉命中 |
| `fireball_launch` | 手动 | 火球发射 |
| `fireball_impact` | 手动 | 火球爆炸 |
| `arrows_rain` | 手动 | 万箭齐发 |
| `poison_cast` | 手动 | 毒药施放 |
| `unit_die` | 手动（play_unit_sfx） | 单位死亡 |
| `tower_destroyed` | 自动（tower_destroyed） | 塔被摧毁 |
| `king_tower_destroyed` | 自动（tower_destroyed） | 国王塔被摧毁 |
| `battle_start` | 自动（battle_started） | 战斗开始 |
| `victory` | 自动（battle_ended） | 胜利 |
| `defeat` | 自动（battle_ended） | 失败 |

"自动" = AudioManager 监听 SignalBus 信号自动播放，只需填 stream 路径。
"手动" = 需要在对应代码处调用 `AudioManager.play(event_id)` 或 `AudioManager.play_unit_sfx(...)`。
