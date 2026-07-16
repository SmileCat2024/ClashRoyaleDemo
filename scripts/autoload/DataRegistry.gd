# 文件名：DataRegistry.gd
# 作用：集中保存所有游戏数据（单位、卡牌、塔、建筑属性）。
#       所有数据以字典形式硬编码，其他脚本通过 get_xxx_data() 查询。
#       _ready() 时自动运行配置校验，在控制台一次性输出所有错误。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：先看 unit_data 字典了解每种单位有哪些属性，
#       再看 _validate_all_data() 了解配置校验怎么工作。

extends Node

# ==============================================================================
# 单位数据表
# 每种单位用一个字典保存属性。key 是单位 id（如 "knight"）。
# 注意：spawn_count / spawn_spread 不在这里——它们属于卡牌，不属于单位。
#       一个"骷髅"被墓碑生成时只有1个，被骷髅军团卡生成时才有多个。
# ==============================================================================

var unit_data := {
	"knight": {
		"id": "knight",
		"display_name": "骑士",
		"max_hp": 1766,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "ground",
		"sight_range": 5.5,  # 原版5.5
		"movement_targeting": "any",
		"collision_radius": 0.5,
		"hurt_radius": 0.5,
		"mass": 6,
		"shadow_size": 0.75,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [
			{
				"name": "sword",
				"targeting": "any",
				"attack_ground": true,
				"attack_air": false,
				"attack_range": 1.2,
		"attack_interval": 1.2,
		"first_attack_delay": 0.5,
		"damage_delay": 0.2,  # 对齐攻击动画第3帧（劈下）瞬间
		"delivery": "instant",
		"trajectory": "",
		"impact_type": "single",
		"impact_radius": 0.0,
		"damage": 202,
	}],
		# ---- 帧动画配置（首次接入）----
		# 素材为高清调色板图：walk 1501×1460 / attack 1755×1579
		# visual_scale 0.028（再缩小约22%）：walk帧视觉约51px
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -25.0,
			"visual_scale": 0.028,
			"health_bar_y": -65.0,
			"texture_filter": "linear",
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],  # 暂用移动第1帧做待机
					"duration": [1.0],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],  # 暂用移动第1帧做待机
					"duration": [1.0],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png", "attack_front_03.png"],
					"duration": [0.1, 0.1, 0.15],  # 举剑→挥→劈下，第3帧对齐 damage_delay
					"mode": "once",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png"],
					"duration": [0.1, 0.1, 0.15],
					"mode": "once",
				},
			},
		},
	},
	"hog_rider": {
		"id": "hog_rider",
		"display_name": "野猪骑士",
		"max_hp": 1697,
		"shield": 0,
		"move_speed": 2.0,  # 极快
		"movement_type": "ground",
		"can_jump_river": true,
		"sight_range": 9.5,  # 原版9.5（极远视野，快速冲塔型）
		"movement_targeting": "any",
		"collision_radius": 0.6,
		"hurt_radius": 0.6,
		"mass": 4,
		"shadow_size": 0.8,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [{
			"name": "hammer_smash",
			"targeting": "building_only",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 0.8,
			"attack_interval": 1.6,
			"first_attack_delay": 0.6,
			"damage_delay": 0.12,  # 伤害对齐攻击动画第2帧（砸下瞬间）
			"delivery": "instant",
			"trajectory": "",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 317,
		}],
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_scale": 0.135,
			"visual_offset_y": -15.0,
			"health_bar_y": -90,
			"jump_frame": 0,  # 跳河期间锁定显示第1帧（front/back 各动画首帧均合法）
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png"],
					"duration": [0.15, 0.15],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png", "walk_back_03.png", "walk_back_04.png"],
					"duration": [0.15, 0.15, 0.15, 0.15],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],  # 待机/攻击间隔定格在移动第1帧
					"duration": [1.0],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_02.png"],  # 待机/攻击间隔定格在移动第2帧
					"duration": [1.0],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png"],
					"duration": [0.12, 0.18],  # 挥锤：举起快，砸下有停顿，对齐 damage_delay
					"mode": "once",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png"],
					"duration": [0.12, 0.18],  # 挥锤：举起快，砸下有停顿
					"mode": "once",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_hog_rider",
			"move": "hog_rider_move",
		},
	},
	"musketeer": {
		"id": "musketeer",
		"display_name": "火枪手",
		"max_hp": 721,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "ground",
		"sight_range": 6.0,  # 原版6.0
		"movement_targeting": "any",
		"collision_radius": 0.5,
		"hurt_radius": 0.5,
		"mass": 5,
		"shadow_size": 0.75,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [{
			"name": "musket_shot",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 6.0,
			"attack_interval": 1.0,
			"first_attack_delay": 0.7,
			"delivery": "projectile",
			"trajectory": "linear",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 217,
			"projectile_speed": 17.5,
		}],
		# ---- 帧动画配置 ----
		# 素材为高清图：walk ~710-858px宽 / attack ~747-1121px宽，高度 ~1400-1850px
		# visual_scale 0.028（与 knight 一致，按角色高度对齐）
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -25.0,
			"visual_scale": 0.028,
			"health_bar_y": -65.0,
			"texture_filter": "linear",
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png"],
					"duration": [0.2, 0.2],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.2, 0.2],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],  # 暂用移动第1帧做待机
					"duration": [1.0],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],  # 暂用移动第1帧做待机
					"duration": [1.0],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png"],
					"duration": [0.12, 0.18],  # 举枪快，射击有停顿
					"mode": "once",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png", "attack_back_04.png"],
					"duration": [0.08, 0.08, 0.1, 0.14],  # 举枪→瞄准→射击→收枪，4帧展开
					"mode": "once",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_musketeer",
			"attack": "attack_musketeer",
			"sniper_attack": "attack_awakened_musketeer",
		},
	},
	"mini_pekka": {
		"id": "mini_pekka",
		"display_name": "小皮卡",
		"max_hp": 1433,
		"shield": 0,
		"move_speed": 1.5,  # 快速
		"movement_type": "ground",
		"sight_range": 5.0,
		"movement_targeting": "any",
		"collision_radius": 0.45,
		"hurt_radius": 0.45,
		"mass": 4,
		"shadow_size": 0.2,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [{
			"name": "blade_slash",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 0.8,
			"attack_interval": 1.6,
			"first_attack_delay": 0.5,
			"damage_delay": 0.2,  # 对齐攻击动画第3帧（劈下）瞬间
			"delivery": "instant",
			"trajectory": "",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 755,
		}],
		# ---- 帧动画配置 ----
		# 素材 2048×1920，原角色整体偏左，已统一右移 345px 校正居中（alpha 质心对齐）
		# content 高约 940px，visual_scale 0.036 → 屏幕高约 43px；脚底对齐地面
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -33.0,  # 缩小后同步下移，保持脚底对齐
			"visual_scale": 0.036,  # 轻微缩小 10%
			"health_bar_y": -60.0,
			"texture_filter": "linear",
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png", "walk_front_03.png"],
					"duration": [0.2, 0.2, 0.2],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png", "walk_back_03.png"],
					"duration": [0.2, 0.2, 0.2],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],  # 暂用移动第1帧做待机
					"duration": [0.4],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],  # 暂用移动第1帧做待机
					"duration": [0.4],
					"mode": "loop",
				},
				# 攻击动画三态：根据目标相对方向选择（UnitBase.get_attack_facing 判定）
				# - 目标偏水平(|dx|>|dy|, 45°内) → side；正下 → front；正上 → back
				# side 素材默认朝左，目标在右侧时 get_flip_h()=true 自动镜像成朝右
				# 三态"劈下"帧均在 0.2s = damage_delay，视觉对齐一致
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png", "attack_front_03.png"],
					"duration": [0.1, 0.1, 0.15],  # 举刀→挥→劈下，第3帧(0.2s)对齐 damage_delay
					"mode": "once",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png"],
					"duration": [0.1, 0.1, 0.15],
					"mode": "once",
				},
				"attack_side": {
					"frames": ["attack_side_01.png", "attack_side_02.png"],
					"duration": [0.2, 0.15],  # 起手→劈下，第2帧(0.2s)对齐 damage_delay
					"mode": "once",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_mini_pekka",
			"attack": "attack_mini_pekka",
		},
	},
	"balloon": {
		"id": "balloon",
		"display_name": "气球兵",
		"max_hp": 1679,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "air",
		"sight_range": 7.7,  # 原版7.7
		"movement_targeting": "any",
		"collision_radius": 0.3,
		"hurt_radius": 0.3,
		"mass": 6,
		"shadow_size": 0.7,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"death_damage": 240,    # 死亡时范围伤害
		"death_radius": 2.0,    # 死亡伤害半径（格）
		"death_fuse_time": 3.0, # 死亡炸弹引信时间（秒）
		"attacks": [{
			"name": "bomb_drop",
			"targeting": "building_only",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 0.2,
			"attack_interval": 2.0,
			"first_attack_delay": 0.2,
			"delivery": "instant",
			"trajectory": "",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 640,
		}],
		# ---- 帧动画配置 ----
		# 单帧静态图（无序列帧动画），idle / walk 共用同一帧
		# 原始 PNG 1254×1254px，scale 0.0792 ≈ 99px（0.066 × 1.2）
		# 气球兵为飞行单位，altitude 系统自动上移 2.5 格（50px），无需额外 visual_offset_y
		"animation": {
			"hide_placeholder": true,  # 使用正式气球兵贴图，不显示测试占位格
			"visual_offset_x": 0.0,
			"visual_offset_y": -40.0,
			"visual_scale": 0.0792,
			"health_bar_y": -95.0,
			"states": {
				"idle": {
					"frames": ["balloon.png"],
					"duration": [1.0],
					"mode": "loop",
				},
			"walk": {
				"frames": ["balloon.png"],
				"duration": [1.0],
				"mode": "loop",
			},
			},
		},
		"sfx": {
			"deploy": "deploy_balloon",
		},
	},
	"archers": {
		"id": "archers",
		"display_name": "弓箭手",
		"max_hp": 304,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "ground",
		"sight_range": 5.5,  # 原版5.5
		"movement_targeting": "any",
		"collision_radius": 0.5,  # 原版0.5/个
		"hurt_radius": 0.5,
		"mass": 3,
		"shadow_size": 0.55,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [{
			"name": "bow_shot",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 5.0,
			"attack_interval": 0.9,
			"first_attack_delay": 0.5,
			"delivery": "projectile",
			"trajectory": "linear",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 112,
			"projectile_speed": 15.0,
		}],
		# ---- 帧动画配置 ----
		# 新素材 move_down/up（2帧行走）+ attack_down/up（4帧攻击拉弓→释放）
		# 素材默认面朝左，向右移动时 flip_h 自动翻转
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -20.0,  # 轻微下移 0.2 格（4px）
			"visual_scale": 0.065,
			"health_bar_y": -60.0,
			"texture_filter": "linear",
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],  # 暂用移动第1帧做待机
					"duration": [0.3],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],  # 暂用移动第1帧做待机
					"duration": [0.3],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png",
							   "attack_front_03.png", "attack_front_04.png"],
					"duration": [0.08, 0.08, 0.08, 0.16],
					"mode": "once",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png",
							   "attack_back_03.png", "attack_back_04.png"],
					"duration": [0.08, 0.08, 0.08, 0.16],
					"mode": "once",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_archers",
		},
	},
	"giant": {
		"id": "giant",
		"display_name": "巨人",
		"max_hp": 4090,
		"shield": 0,
		"move_speed": 0.75,  # 慢速（内部数值45 → 0.75格/秒）
		"movement_type": "ground",
		"sight_range": 7.5,  # 原版7.5
		"movement_targeting": "building_only",
		"collision_radius": 0.75,  # 原版0.75
		"hurt_radius": 0.75,
		"mass": 10,
		"shadow_size": 0.8,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [{
			"name": "fist_smash",
			"targeting": "building_only",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 1.2,
			"attack_interval": 1.5,
			"first_attack_delay": 0.5,
			"damage_delay": 0.15,
			"delivery": "instant",
			"trajectory": "",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 253,
		}],
		"animation": {
			"hide_placeholder": true,  # 使用正式巨人贴图，不显示测试占位格
			"visual_offset_y": -35.0,
			"visual_scale": 0.0768,
			"health_bar_y": -85,
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png"],
					"duration": [0.5, 0.5],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png"],
					"duration": [0.15, 0.25],
					"mode": "once",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],
					"duration": [1.0],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.5, 0.5],
					"mode": "loop",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png"],
					"duration": [0.15, 0.25],
					"mode": "once",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],
					"duration": [1.0],
					"mode": "loop",
				},
			},
		},
		"sfx": {
			"attack": "attack_giant",
		},
	},
	"prince": {
		"id": "prince",
		"display_name": "王子",
		"max_hp": 1920,
		"shield": 0,
		"move_speed": 1.0,  # 中速（Medium 60）
		"movement_type": "ground",
		"can_jump_river": true,   # 骑乘冲锋可跳河，与野猪骑士同款跳河能力
		"sight_range": 5.5,  # 原版5.5
		"movement_targeting": "any",
		"collision_radius": 0.65,  # 原版0.65
		"hurt_radius": 0.65,
		"mass": 6,
		"knockback_immune": true,
		"shadow_size": 0.6,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		# 冲锋机制：持续直线移动 min_charge_distance 格后进入冲锋，
		# 移速提升至 charge_move_speed，命中伤害变为 charge_damage。
		# 攻击出手或受到伤害时退出冲锋并重置累计距离。
		"charge": {
			"min_charge_distance": 2.5,  # 进入冲锋所需持续移动距离（格）
			"charge_move_speed": 2.0,    # 冲锋移速（格/秒，Very Fast 120）
			"charge_damage": 783,        # 冲锋状态命中伤害
		},
		"attacks": [{
			"name": "spear_thrust",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 1.6,  # 长近战
			"attack_interval": 1.4,
			"first_attack_delay": 0.5,
			"delivery": "instant",
			"trajectory": "",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 391,
		}],
		"sfx": {
			"deploy": "deploy_prince",
			"charge": "prince_charge",
		},
		# 帧动画：walk/attack/charge × front(back)。1024×768 高清图。
		# charge（冲刺）= 冲锋状态专属动画，get_visual_state 在 is_charging 时返回 "charge" 触发。
		# walk_01 与 attack_01 公用同一张图（移动第1帧=攻击第1帧），同源拷贝。
		"animation": {
			"hide_placeholder": true,
			"visual_offset_x": 0.0,
			"visual_offset_y": -24.0,   # 待校准
			"visual_scale": 0.12,       # 扩大一倍（用户反馈）
			"health_bar_y": -75.0,      # 血条上移 15px
			"texture_filter": "linear",
			"states": {
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png"],
					"duration": [0.12, 0.12],
					"mode": "once",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png"],
					"duration": [0.12, 0.12],
					"mode": "once",
				},
				"charge_back": {
					"frames": ["charge_back_01.png", "charge_back_02.png"],
					"duration": [0.1, 0.1],
					"mode": "loop",
				},
				"charge_front": {
					"frames": ["charge_front_01.png", "charge_front_02.png"],
					"duration": [0.1, 0.1],
					"mode": "loop",
				},
			},
		},
	},
	"mortar": {
		"id": "mortar",
		"display_name": "迫击炮",
		"max_hp": 1369,
		"shield": 0,
		"move_speed": 0.0,  # 不可移动（建筑）
		"movement_type": "ground",
		"sight_range": 11.5,  # 视野覆盖最大射程（原版11.5）
		"movement_targeting": "any",
		"collision_radius": 0.6,  # 原版0.6
		"hurt_radius": 0.6,
		"mass": 0,  # 不可移动，自动成为寻路障碍
		"knockback_immune": true,
		"shadow_size": 0.8,
		"deploy_time": 3.5,   # 部署时间（秒），建筑部署较慢，期间虚影状态不行动但可受伤
		"lifespan": 30.0,     # 寿命（秒），建筑存在期间持续掉血，到期自毁（原版最大持续时间30秒）
		"attacks": [{
			"name": "mortar_shell",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 11.5,        # 最大射程（格）
			"min_attack_range": 3.5,     # 最小射程（近距离盲区，格）
			"attack_interval": 5.0,
			"first_attack_delay": 1.0,
			"delivery": "projectile",
			"trajectory": "ballistic",   # 高抛弹道
			"impact_type": "splash",
			"impact_radius": 2.0,        # 范围伤害半径（格）
			"damage": 266,
			"projectile_speed": 6.0,     # 飞行速度（格/秒）
			"arc_height": 7.0,           # 最大射程处弧高（格），近处按距离比例自动降低
		}],
		"sfx": {
			"deploy": "deploy_building",
		},
		# 迫击炮建筑贴图（314×464）。首次使用团队色双套贴图：
		# player 用蓝方贴图，enemy 用红方贴图（联机下 team flip 后两端各看己方蓝/敌方红）。
		# attack 状态 = 发射时亮一帧（括号2），mode=once 播放后自动切回 idle（括号1）。
		"animation": {
			"visual_offset_x": 0.0,
			"visual_offset_y": -24.0,
			"visual_scale": 0.14,
			"health_bar_y": -62.0,
			"texture_filter": "linear",
			"states": {
				"idle": {
					"frames": {
						"player": ["mortar_idle_blue.png"],
						"enemy": ["mortar_idle_red.png"],
					},
					"duration": [1.0],
					"mode": "loop",
				},
				"walk": {
					"frames": {
						"player": ["mortar_idle_blue.png"],
						"enemy": ["mortar_idle_red.png"],
					},
					"duration": [1.0],
					"mode": "loop",
				},
				"attack": {
					"frames": {
						"player": ["mortar_fire_blue.png"],
						"enemy": ["mortar_fire_red.png"],
					},
					"duration": [0.15],
					"mode": "once",
				},
			},
		},
	},
	"mega_minion": {
		"id": "mega_minion",
		"display_name": "重甲亡灵",
		"max_hp": 837,
		"shield": 0,
		"move_speed": 1.0,  # 中速（Medium 60）
		"movement_type": "air",
		"sight_range": 5.5,  # 原版5.5
		"movement_targeting": "any",
		"collision_radius": 0.6,  # 原版0.6
		"hurt_radius": 0.6,
		"mass": 3,
		"shadow_size": 0.7,
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [{
			"name": "claw_strike",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 1.6,  # 长近战
			"attack_interval": 1.5,
			"first_attack_delay": 0.4,
			"delivery": "projectile",
			"trajectory": "linear",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 312,
			"projectile_speed": 14.0,
		}],
		# ---- 帧动画配置 ----
		# 重甲亡灵：飞行单位，中性单套贴图（2200×2240，linear 过滤）
		# 行走仅 front/back 各 1 帧（侧面移动回退 front/back）；攻击三方向 front/back/side
		# 注：projectile 单位不加 damage_delay（伤害由投射物命中结算，同 archers/musketeer）
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -25.0,  # 校准：放大后同步下移保持底部对齐
			"visual_scale": 0.0225,  # 校准：放大 0.5 格（显示高度 40px→50px）
			"health_bar_y": -50.0,  # 校准完成
			"texture_filter": "linear",
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],  # 暂用移动第 1 帧做待机
					"duration": [0.3],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],  # 暂用移动第 1 帧做待机
					"duration": [0.3],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png", "attack_front_03.png"],
					"duration": [0.08, 0.13, 0.09],  # 放慢约 30%，让出爪与收势更清晰
					"mode": "once",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png"],
					"duration": [0.09, 0.14],  # 放慢约 30%，保持与 front/side 相同节奏
					"mode": "once",
				},
				"attack_side": {
					"frames": ["attack_side_01.png", "attack_side_02.png", "attack_side_03.png"],
					"duration": [0.08, 0.13, 0.09],  # 放慢约 30%，让出爪与收势更清晰
					"mode": "once",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_mega_minion",
		},
	},
	"flyer": {
		"id": "flyer",
		"display_name": "飞行器",
		"max_hp": 614,
		"shield": 0,
		"move_speed": 1.5,  # 快（Fast）
		"movement_type": "air",
		"sight_range": 7.0,
		"movement_targeting": "any",
		"collision_radius": 0.6,
		"hurt_radius": 0.6,
		"mass": 3,
		"shadow_size": 1.0,
		"altitude": 3.0,  # 飞行器专属离地高度（格），比默认空中单位高 0.5 格
		"deploy_time": 1.0,
		"attacks": [{
			"name": "cannon_shot",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 6.0,
			"attack_interval": 1.1,
			"first_attack_delay": 0.7,
			"delivery": "projectile",
			"trajectory": "linear",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 171,
			"projectile_speed": 17.5,
		}],
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -25.0,
			"visual_scale": 0.05,  # 校准：模型显著增大（相对原始尺寸约 +67%）
			"health_bar_y": -85.0,  # 随模型增大同步上移
			"texture_filter": "linear",
			"states": {
				"walk_front": { "frames": ["walk_front_01.png"], "duration": [0.4], "mode": "loop" },
				"walk_back": { "frames": ["walk_back_01.png"], "duration": [0.4], "mode": "loop" },
				"idle_front": { "frames": ["walk_front_01.png"], "duration": [0.4], "mode": "loop" },
				"idle_back": { "frames": ["walk_back_01.png"], "duration": [0.4], "mode": "loop" },
				"attack_front": { "frames": ["walk_front_01.png", "attack_front_01.png"], "duration": [0.15, 0.3], "mode": "once" },
				"attack_back": { "frames": ["walk_back_01.png", "attack_back_01.png"], "duration": [0.15, 0.3], "mode": "once" },
				"attack_side": { "frames": ["attack_side_01.png"], "duration": [0.35], "mode": "once" },
			},
		},
	},
	"pekka": {
		"id": "pekka",
		"display_name": "大皮卡",
		"max_hp": 3760,
		"shield": 0,
		"move_speed": 0.6,  # 慢速（Slow）
		"movement_type": "ground",
		"sight_range": 5.0,
		"movement_targeting": "any",
		"collision_radius": 1.0,  # 比骑士(0.5)大0.5格
		"hurt_radius": 1.0,
		"mass": 18,
		"knockback_immune": true,
		"shadow_size": 1.0,
		"deploy_time": 1.0,
		"attacks": [{
			"name": "heavy_slash",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 1.2,
			"attack_interval": 1.8,
			"first_attack_delay": 0.6,
			"damage_delay": 0.05,  # 命中前段第1帧
			"delivery": "instant",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 816,
		}],
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -32.0,  # 校准：模型略微上移 0.2 格
			"visual_scale": 0.0374,  # 校准：模型增大 10%
			"health_bar_y": -85.0,  # 暂不随模型调整
			"texture_filter": "linear",
			"idle_uses_attack_facing": true,  # 攻击间隔按目标方向保持准备动作
			"side_flip_inverted": true,  # side 素材左右朝向与默认镜像规则相反
			"states": {
				"walk_front": { "frames": ["walk_front_01.png", "walk_front_02.png", "walk_front_03.png"], "duration": [0.2, 0.2, 0.2], "mode": "loop" },
				"walk_back": { "frames": ["walk_back_01.png", "walk_back_02.png", "walk_back_03.png"], "duration": [0.2, 0.2, 0.2], "mode": "loop" },
				"idle_front": { "frames": ["attack_front_03.png"], "duration": [1.0], "mode": "loop" },
				"idle_back": { "frames": ["walk_back_03.png"], "duration": [1.0], "mode": "loop" },
				"idle_side": { "frames": ["attack_side_03.png"], "duration": [1.0], "mode": "loop" },
				"attack_front": { "frames": ["attack_front_01.png", "attack_front_02.png", "attack_front_03.png"], "duration": [0.14, 0.14, 0.14], "mode": "once" },
				"attack_back": { "frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png"], "duration": [0.14, 0.14, 0.14], "mode": "once" },
				"attack_side": { "frames": ["attack_side_01.png", "attack_side_02.png", "attack_side_03.png"], "duration": [0.14, 0.14, 0.14], "mode": "once" },
			},
		},
		"sfx": {
			"deploy": "deploy_pekka",
			"attack": "attack_pekka",
		},
	},
	"valkyrie": {
		"id": "valkyrie",
		"display_name": "瓦基里武神",
		"max_hp": 1500,  # 用户要求加2倍（750→1500）
		"shield": 0,
		"move_speed": 1.0,  # 中速（Medium 60）
		"movement_type": "ground",
		"sight_range": 5.0,
		"movement_targeting": "any",
		"collision_radius": 0.5,
		"hurt_radius": 0.5,
		"mass": 5,
		"knockback_immune": false,
		"shadow_size": 0.5,
		"deploy_time": 1.0,
		"attacks": [{
			"name": "axe_spin",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 1.0,  # 用户要求：0.5→1.0 格
			"attack_interval": 1.8,
			"first_attack_delay": 0.6,
			"delivery": "instant",
			"impact_type": "splash",
			"impact_radius": 2.0,  # 用户要求：2格半径（以自身为中心）
			"damage": 169,
			"damage_delay": 0.08,  # 对齐转斧命中帧（前段出手即命中，第 2 帧）
		}],
		# ---- 帧动画配置 ----
		# 瓦基里武神：地面近战，中性单套贴图（2335×1856 横向，linear 过滤）
		# walk/attack × front/back 两方向（无 side，侧面回退 front/back）；down=front/up=back
		# 转斧命中在前段（第 2 帧），damage_delay=0.08 对齐
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -30.0,  # 校准：模型下移 9px，修正视觉偏上
			"visual_scale": 0.038,  # 校准：再缩小1格（0.049→0.038）
			"health_bar_y": -82.0,  # 继续下移 9px
			"texture_filter": "linear",
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],  # 暂用移动第 1 帧做待机
					"duration": [0.3],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png", "attack_front_03.png", "attack_front_04.png"],
					"duration": [0.08, 0.08, 0.08, 0.08],
					"mode": "once",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png"],
					"duration": [0.08, 0.08, 0.08],
					"mode": "once",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_valkyrie",
			"attack": "attack_valkyrie",
		},
	},
	"goblins": {
		"id": "goblins",
		"display_name": "哥布林",
		"max_hp": 202,
		"shield": 0,
		"move_speed": 1.5,  # 快速（Fast 120）
		"movement_type": "ground",
		"sight_range": 5.5,
		"movement_targeting": "any",
		"collision_radius": 0.5,  # 原版0.5/个
		"hurt_radius": 0.5,
		"mass": 3,
		"shadow_size": 0.5,
		"shadow_offset_y": 0.5,  # 影子下移0.5格（贴图脚部偏上，下移对齐视觉脚底）
		"deploy_time": 1.0,   # 部署时间（秒），期间虚影状态不行动但可受伤
		"attacks": [{
			"name": "stab",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": false,  # 只攻击地面
			"attack_range": 0.5,  # 近战短
			"attack_interval": 1.1,
			"first_attack_delay": 0.6,
			"damage_delay": 0.15,  # 对齐第2帧挥砍
			"delivery": "instant",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 120,
		}],
		# ---- 帧动画配置 ----
		# 素材 3000x2500，已右移510px校正居中
		"animation": {
			"hide_placeholder": true,  # 已校准，隐藏 ColorRect 占位方块
			"visual_offset_x": 0.0,
			"visual_offset_y": -8.0,
			"visual_scale": 0.016,
			"health_bar_y": -34.0,
			"texture_filter": "linear",
			"states": {
				"walk_front": {
					"frames": ["walk_front_01.png", "walk_front_02.png", "walk_front_03.png"],
					"duration": [0.2, 0.2, 0.2],
					"mode": "loop",
				},
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png", "walk_back_03.png"],
					"duration": [0.2, 0.2, 0.2],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_front_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"attack_front": {
					"frames": ["attack_front_01.png", "attack_front_02.png"],
					"duration": [0.12, 0.12],
					"mode": "once",
				},
			"attack_back": {
				"frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png"],
				"duration": [0.1, 0.1, 0.12],
				"mode": "once",
			},
			},
		},
		"sfx": {
			"deploy": "deploy_goblins",
		},
	},
	"inferno_tower": {
		"id": "inferno_tower",
		"display_name": "地狱塔",
		"max_hp": 1748,
		"shield": 0,
		"move_speed": 0.0,  # 不可移动（建筑）
		"movement_type": "ground",
		"sight_range": 6.0,  # 索敌范围 = 射程
		"movement_targeting": "any",
		"collision_radius": 0.6,
		"hurt_radius": 0.6,
		"mass": 0,  # 不可移动，自动成为寻路障碍
		"knockback_immune": true,
		"shadow_size": 0.8,
		"deploy_time": 1.0,   # 部署时间（秒），期间不能索敌/攻击
		"lifespan": 30.0,     # 寿命（秒），到期自毁
		"beam_emit_offset_y": -66.0,  # 光束发射点 Y（像素，塔顶喷口附近）
		"attacks": [{
			"name": "inferno_beam",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 6.0,
			"attack_interval": 0.4,
			"first_attack_delay": 0.0,  # 部署时间已模拟首次延迟
			"delivery": "instant",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 43,  # 基础伤害（第1阶段），实际由 ramp_damage 覆盖
			# 递增伤害：持续锁定同一目标，伤害按阶段递增（地狱塔光束核心机制）
			# 锁定时间达到阈值后切换到对应阶段伤害；目标切换/丢失时重置锁定时间
			"ramp_damage": [43, 158, 847],
			"ramp_thresholds": [0.0, 2.0, 4.0],
		}],
		# 单帧建筑贴图（1254×1254，scale 0.0792 ≈ 99px），底部对齐地面
		"animation": {
			"visual_offset_x": 0.0,
			"visual_offset_y": -26.0,
			"visual_scale": 0.0792,
			"health_bar_y": -105.0,
			"texture_filter": "linear",
			"states": {
				"idle": {
					"frames": ["inferno_tower.png"],
					"duration": [1.0],
					"mode": "loop",
				},
				"walk": {
					"frames": ["inferno_tower.png"],
					"duration": [1.0],
					"mode": "loop",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_building",
		},
	},
	"elixir_collector": {
		"id": "elixir_collector",
		"display_name": "圣水收集器",
		"max_hp": 1070,
		"shield": 0,
		"move_speed": 0.0,
		"movement_type": "ground",
		"sight_range": 0.0,
		"movement_targeting": "any",
		"collision_radius": 0.6,
		"hurt_radius": 0.6,
		"mass": 0,
		"knockback_immune": true,
		"shadow_size": 0.6,
		"deploy_time": 1.0,
		"lifespan": 93.0,
		# 被动建筑：部署完成后每 13 秒产 1 点；寿命结束或被摧毁时额外返还 1 点。
		"is_passive": true,
		"elixir_generation_interval": 13.0,
		"elixir_generation_amount": 1,
		"elixir_on_death": 1,
		"attacks": [],
		"animation": {
			"hide_placeholder": true,
			"visual_offset_x": 0.0,
			"visual_offset_y": -18.0,
			"visual_scale": 0.060,
			"health_bar_y": -58.0,
			"texture_filter": "linear",
			"states": {
				"idle": {
					"frames": ["elixir_collector.png"],
					"duration": [1.0],
					"mode": "loop",
				},
				"walk": {
					"frames": ["elixir_collector.png"],
					"duration": [1.0],
					"mode": "loop",
				},
			},
		},
		"sfx": {
			"deploy": "deploy_building",
		},
	},
	"princess": {
		"id": "princess",
		"display_name": "公主",
		"max_hp": 261,
		"shield": 0,
		"move_speed": 1.0,
		"movement_type": "ground",
		"sight_range": 10.5,
		"movement_targeting": "any",
		"collision_radius": 0.5,
		"hurt_radius": 0.5,
		"mass": 3,
		"shadow_size": 0.5,
		"deploy_time": 1.0,
		"attacks": [{
			"name": "arrow_shot",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 9.5,
			"attack_interval": 2.5,
			"first_attack_delay": 0.5,
			"damage_delay": 0.2,        # 背身/正面拉弓至第 3 帧后再放箭，确保攻击姿势完整呈现
			"delivery": "projectile",
			"trajectory": "ballistic",   # 高抛弹道（抄迫击炮：MortarShell 弧线飞行+落地爆炸范围圈）
			"arc_height": 7.0,           # 弧高峰值（格），随距离自适应（近处低远处高）
			"projectile_appearance": "arrow",  # 箭矢外观（抄箭雨白线+羽尾），落地爆炸圈
			"impact_type": "splash",
			"impact_radius": 2.0,
			"damage": 168,
			"projectile_speed": 10.0,
		}],
		"animation": {
			"hide_placeholder": true,
			"visual_offset_x": 0.0,
			"visual_offset_y": -14.0,
			"visual_scale": 0.05,
			"health_bar_y": -60.0,
			"texture_filter": "linear",
			"states": {
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"walk_front": {
					"frames": ["walk_back_01.png", "walk_back_02.png"],
					"duration": [0.25, 0.25],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"idle_front": {
					"frames": ["walk_back_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
				"attack_back": {
					"frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png"],
					"duration": [0.1, 0.1, 0.15],
					"mode": "once",
				},
			"attack_front": {
				"frames": ["attack_back_01.png", "attack_back_02.png", "attack_back_03.png"],
				"duration": [0.1, 0.1, 0.15],
				"mode": "once",
			},
		},
	},
	},
	"ranger": {
		"id": "ranger",
		"display_name": "神箭游侠",
		"max_hp": 532,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "ground",
		"sight_range": 7.0,
		"movement_targeting": "any",
		"collision_radius": 1.0,
		"hurt_radius": 1.0,
		"mass": 5,
		"shadow_size": 0.5,
		"deploy_time": 1.0,
		"attacks": [{
			"name": "piercing_arrow",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 7.0,
			"attack_interval": 1.1,
			"first_attack_delay": 0.5,
			"damage_delay": 0.2,
			"delivery": "projectile",
			"trajectory": "linear",
			"impact_type": "piercing",
			"impact_radius": 0.0,
			"max_range": 11.0,  # 弹道最大射程（格），箭矢飞到此距离消失
			"pierce_radius": 0.8,  # 穿透判定半径（格），敌人离飞行线 ≤ 此值则命中
			"damage": 147,
			"projectile_speed": 20.0,
		}],
		"animation": {
			"hide_placeholder": true,   # 使用正式帧动画，移除底部 ColorRect 调试占位
			"visual_offset_x": 0.0,
			"visual_offset_y": -19.0,
			"visual_scale": 0.025,      # 小幅放大约 9%
			"health_bar_y": -70.0,      # 随模型放大上移，保持在头顶
			"texture_filter": "linear",
			"states": {
				"walk_front": { "frames": ["walk_front_01.png", "walk_front_02.png"], "duration": [0.24, 0.24], "mode": "loop" },
				"walk_back": { "frames": ["walk_back_01.png", "walk_back_02.png"], "duration": [0.24, 0.24], "mode": "loop" },
				"idle_front": { "frames": ["walk_front_01.png"], "duration": [0.4], "mode": "loop" },
				"idle_back": { "frames": ["walk_back_01.png"], "duration": [0.4], "mode": "loop" },
				"attack_front": { "frames": ["attack_front_01.png", "attack_front_02.png", "attack_front_03.png", "attack_front_04.png"], "duration": [0.08, 0.08, 0.08, 0.55], "mode": "once" },
				"attack_back": { "frames": ["attack_back_01.png", "attack_back_02.png"], "duration": [0.1, 0.65], "mode": "once" },
			},
		},
	},
}

# ==============================================================================
# 卡牌数据表
# card_type: "troop" | "building" | "spell"
# troop/building 卡通过 unit_id/building_id 关联实体数据。
# spell 卡直接包含法术参数（spell_type, spell_radius, spell_damage）。
# spawn_count / spawn_spread 控制一张卡召唤几个单位。
# ==============================================================================

var card_data := {
	"card_knight": {
		"id": "card_knight",
		"display_name": "骑士",
		"cost": 3,
		"card_type": "troop",
		"unit_id": "knight",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/knight.png",
		"description": "一个坚韧的近战战士。",
		# ---- 觉醒配置（打出 2 次普通版后，下一次为觉醒版）----
		# 觉醒效果在 UnitBase.apply_awakening() 中数据驱动应用，动作素材不变。
		# effects 内的 key 对应已支持的觉醒效果类型，详见 UnitBase.apply_awakening。
		"awakening": {
			"trigger_count": 2,       # 打出 2 次后下一次觉醒
			"name_suffix": "·觉醒",    # 觉醒版显示后缀
			"effects": {
				"shield": 500,           # 出生自带 500 护盾
				"max_hp_bonus": 300,     # 最大血量 +300（current_hp 同步增加）
			},
		},
	},
	"card_hog_rider": {
		"id": "card_hog_rider",
		"display_name": "野猪骑士",
		"cost": 4,
		"card_type": "troop",
		"unit_id": "hog_rider",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/hog_rider.png",
		"description": "极快的建筑杀手，只攻击建筑。",
	},
	"card_musketeer": {
		"id": "card_musketeer",
		"display_name": "火枪手",
		"cost": 4,
		"card_type": "troop",
		"unit_id": "musketeer",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/musketeer.png",
		"awakening_icon": "res://assets/ui/cards/musketeer_evolution.png",
		"awakening_deploy_sfx": "deploy_awakened_musketeer",
		"description": "远程射手，可对空对地。",
		# ---- 觉醒配置（打出 1 次普通版后，下一次为觉醒版）----
		# 普通火枪手仍然保留在牌库中；轮转后由 AwakeningTracker 决定下一次是否使用觉醒版。
		# 觉醒效果在 UnitBase.apply_awakening() 中数据驱动应用。
		# effects 内的 key 对应已支持的觉醒效果类型，详见 UnitBase.apply_awakening。
		"awakening": {
			"trigger_count": 1,       # 打出 1 次普通版后，下一次为觉醒版
			"name_suffix": "·觉醒",    # 觉醒版显示后缀
			"effects": {
				"sniper_shots": {
					"count": 3,             # 狙击弹数量
					"damage_mult": 2.0,     # 伤害倍率（× 主攻击伤害 217 = 434）
					"scan_half_width": 1.0, # 扫描宽度（格，左右各 1 格）
				},
			},
		},
	},
	"card_mini_pekka": {
		"id": "card_mini_pekka",
		"display_name": "小皮卡",
		"cost": 4,
		"card_type": "troop",
		"unit_id": "mini_pekka",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/mini_pekka.png",
		"description": "高伤害近战，快速移动。",
	},
	"card_balloon": {
		"id": "card_balloon",
		"display_name": "气球兵",
		"cost": 5,
		"card_type": "troop",
		"unit_id": "balloon",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/balloon.png",
		"description": "空中单位，只攻击建筑，伤害极高。",
	},
	"card_archers": {
		"id": "card_archers",
		"display_name": "弓箭手",
		"cost": 3,
		"card_type": "troop",
		"unit_id": "archers",
		"spawn_count": 2,
		"spawn_spread": 0.0,
		"spawn_offsets": [Vector2(-1, 0), Vector2(1, 0)],  # 两只分居中心格左右各一格
		"icon": "res://assets/ui/cards/archers.png",
		"description": "两个远程射手，可对空对地。",
	},
	"card_giant": {
		"id": "card_giant",
		"display_name": "巨人",
		"cost": 5,
		"card_type": "troop",
		"unit_id": "giant",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/giant.png",
		"description": "高血量的地面肉盾，只攻击建筑。",
	},
	"card_fireball": {
		"id": "card_fireball",
		"display_name": "火球",
		"cost": 4,
		"card_type": "spell",
		"spell_type": "fireball",
		"spell_radius": 2.5,       # 作用半径（格）
		"spell_damage": 688,       # 对单位的范围伤害
		"tower_damage": 172,       # 对皇家塔的伤害（约 25%）
		"projectile_speed": 10.0,  # 飞行速度（格/秒，600格/分钟）
		"knockback": true,         # 击退
		"knockback_distance": 1.0, # 击退距离（格）
		"icon": "res://assets/ui/cards/fireball.png",
		"description": "范围伤害法术，可对空对地。击退被命中的单位。",
	},
	"card_poison": {
		"id": "card_poison",
		"display_name": "毒药",
		"cost": 4,
		"card_type": "spell",
		"spell_type": "poison",
		"spell_radius": 3.5,       # 作用半径（格）
		"spell_damage": 92,        # 单跳范围伤害（兼容即时伤害校验）
		"tower_damage": 21,        # 兼容塔减伤校验
		# DOT 专属
		"duration": 8.0,           # 持续时间（秒）
		"tick_interval": 1.0,      # 伤害间隔（秒），共 8 跳
		"tick_damage": 92,         # 每跳对单位的伤害
		"tick_tower_damage": 21,   # 每跳对皇家塔的伤害（总 168）
		"slow_factor": 0.85,       # 减速 15%
		"projectile_speed": 10.0,  # 飞行速度（格/秒）
		"knockback": false,
		"icon": "res://assets/ui/cards/poison.png",
		"description": "持续伤害法术，减速区域内敌方部队。8秒内每秒造成92伤害。",
	},
	"card_arrows": {
		"id": "card_arrows",
		"display_name": "万箭齐发",
		"cost": 3,
		"card_type": "spell",
		"spell_type": "arrows",
		"spell_radius": 3.5,       # 作用半径（格）
		"spell_damage": 122,       # 单波对单位的范围伤害
		"spell_waves": 3,          # 3波伤害（总 366）
		"tower_damage": 25,        # 单波对皇家塔的伤害（总 75）
		"projectile_speed": 18.33, # 飞行速度（格/秒，1100格/分钟）
		"knockback": false,
		"icon": "res://assets/ui/cards/arrows.png",
		"description": "3波箭雨从天而降，覆盖目标区域。对空对地，无击退。",
	},
	"card_prince": {
		"id": "card_prince",
		"display_name": "王子",
		"cost": 5,
		"card_type": "troop",
		"unit_id": "prince",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/prince.png",
		"description": "持续移动进入冲锋状态，移速翻倍且命中伤害大幅提升。中速近战，只打地面。",
	},
	"card_mortar": {
		"id": "card_mortar",
		"display_name": "迫击炮",
		"cost": 4,
		"card_type": "troop",
		"unit_id": "mortar",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/mortar.png",
		"description": "远程建筑，发射范围伤害炮弹。不可移动，自动成为障碍。",
		"awakening_icon": "res://assets/ui/cards/mortar_evolution.png",
		# ---- 觉醒配置（打出 1 次普通版后，下一次为觉醒版）----
		# 觉醒迫击炮：炮弹落地先结算范围伤害，随后在同一落点召唤一只哥布林。
		# 卡牌轮转仍使用普通 card_mortar。
		"awakening": {
			"trigger_count": 1,
			"name_suffix": "·觉醒",
			"effects": {
				"max_hp_bonus": 300,
				"projectile_impact_summon_unit_id": "goblins",
			},
		},
	},
	"card_flyer": {
		"id": "card_flyer",
		"display_name": "飞行器",
		"cost": 4,
		"card_type": "troop",
		"unit_id": "flyer",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/flyer.png",
		"description": "空中远程，对空对地，快移速高射程。",
	},
	"card_pekka": {
		"id": "card_pekka",
		"display_name": "大皮卡",
		"cost": 7,
		"card_type": "troop",
		"unit_id": "pekka",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/pekka.png",
		"description": "地面重型近战，高血量高伤害，缓慢但致命。",
	},
	"card_mega_minion": {
		"id": "card_mega_minion",
		"display_name": "重甲亡灵",
		"cost": 3,
		"card_type": "troop",
		"unit_id": "mega_minion",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/mega_minion.png",
		"description": "飞行单位，对空对地，中等射程。",
	},
	"card_valkyrie": {
		"id": "card_valkyrie",
		"display_name": "瓦基里武神",
		"cost": 4,
		"card_type": "troop",
		"unit_id": "valkyrie",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/valkyrie.png",
		"description": "地面近战，转斧范围伤害，清兵利器。",
	},
	"card_goblins": {
		"id": "card_goblins",
		"display_name": "哥布林",
		"cost": 3,
		"card_type": "troop",
		"unit_id": "goblins",
		"spawn_count": 4,
		"spawn_spread": 0.0,
		"spawn_offsets": [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(-0.8, 0.8), Vector2(0.8, 0.8)],  # 左前/右前/左下/右下 2x2方阵
		"icon": "res://assets/ui/cards/goblins.png",
		"description": "四只快速近战哥布林，围成方阵部署。",
	},
	"card_inferno_tower": {
		"id": "card_inferno_tower",
		"display_name": "地狱塔",
		"cost": 5,
		"card_type": "troop",  # 建筑卡，通过 unit_id 关联（mass=0 不可移动）
		"unit_id": "inferno_tower",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/inferno_tower.png",
		"description": "防御建筑，发射持续光束。锁定同一目标越久伤害越高，最高可秒杀肉盾。有寿命限制。",
	},
	"card_elixir_collector": {
		"id": "card_elixir_collector",
		"display_name": "圣水收集器",
		"cost": 6,
		"card_type": "troop",  # 建筑卡，通过 unit_id 关联（mass=0 不可移动）
		"unit_id": "elixir_collector",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"exclude_from_initial_hand": true,
		"icon": "res://assets/ui/cards/elixir_collector.png",
		"description": "被动建筑。部署完成后每 13 秒产出 1 点圣水，93 秒寿命内产出 7 点，死亡时额外返还 1 点。",
	},
	"card_princess": {
		"id": "card_princess",
		"display_name": "公主",
		"cost": 3,
		"card_type": "troop",
		"unit_id": "princess",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"description": "超远程弓箭手，能从己方河岸狙击对方公主塔。箭矢带范围溅射，血量极低。",
	},
	"card_ranger": {
		"id": "card_ranger",
		"display_name": "神箭游侠",
		"cost": 4,
		"card_type": "troop",
		"unit_id": "ranger",
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/ranger.png",
		"description": "远程穿透射手，箭矢沿直线飞行，穿透路径上所有敌人。",
	},
	"card_knight_elite": {
		"id": "card_knight_elite",
		"display_name": "精英骑士",
		"cost": 3,
		"card_type": "troop",
		"unit_id": "knight",   # 复用骑士单位数据（模型/动作不变，仅附加主动技能）
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/knight_elite.png",
		"description": "骑士的精英变种，拥有主动技能「集结号角」。",
		# ---- 精英技能配置 ----
		# 打出后单位存活期间，屏幕右侧出现技能按钮。花圣水释放，单位死亡按钮消失。
		# targeting: "instant"=瞬发（按下立即生效）| "targeted"=指向型（需点击战场选位置）
		"elite_skill": {
			"id": "knight_rally",
			"display_name": "集结号角",
			"cost": 2,                    # 圣水花费（独立于卡牌费用）
			"targeting": "instant",
			"cooldown": 8.0,               # 冷却时间（秒）
			"icon": "",                    # 技能图标路径（空=用文字显示技能名）
			"effect": {
				"type": "self_rage",       # 效果类型 id（UnitBase.trigger_skill 按 type 分流）
				"duration": 5.0,           # 狂暴持续时间（秒）
				"move_mult": 1.35,         # 移速倍率
				"attack_mult": 1.35,       # 攻速倍率
			},
		},
	},
	"card_mega_minion_elite": {
		"id": "card_mega_minion_elite",
		"display_name": "精英重甲亡灵",
		"cost": 3,
		"card_type": "troop",
		"unit_id": "mega_minion",   # 复用重甲亡灵单位数据（模型/动作不变，仅附加主动技能）
		"spawn_count": 1,
		"spawn_spread": 0.0,
		"icon": "res://assets/ui/cards/mega_minion_elite.png",
		"description": "重甲亡灵的精英变种，拥有主动技能「死亡俯冲」。锁定场上血量最低的敌方单位，在其脚下留下黑色标志后高速俯冲。",
		# 仅精英变种的视觉微调；不影响普通重甲亡灵。
		"visual_overrides": {
			"animation": {
				"visual_scale": 0.027,  # 相比普通版放大 20%
				"health_bar_y": -60.0,  # 随模型放大上移血条
			},
		},
		# ---- 精英技能配置 ----
		# 「死亡俯冲」：自动锁敌（instant），2 圣水释放。无需瞄准，按下即生效。
		# 冲刺期间单位免疫普通 AI（不索敌/攻击/走 A*），直线飞向目标脚下，到达后造成范围伤害。
		"elite_skill": {
			"id": "mega_minion_death_dive",
			"display_name": "死亡俯冲",
			"cost": 2,
			"targeting": "instant",        # 自动锁敌，瞬发型
			"cooldown": 8.0,
			"icon": "",
			"effect": {
				"type": "dash_to_weakest", # 锁定血量最低敌方单位 + 冲刺 + 范围伤害
				"dash_speed_cells": 30.0,   # 冲刺固定速度（格/秒）
				"impact_damage": 500,      # 到达后对单位的范围伤害
				"impact_radius": 1.5,      # 冲击范围（格）
				"tower_damage_ratio": 0.4, # 对塔伤害 = impact_damage × 此比例（200）
				"mark_duration": 2.0,      # 目标脚下黑色标志显示时长（秒）
			},
		},
	},
}

# ==============================================================================
# 塔数据表
# 与单位类似，额外有 tower_type: "king" | "guard"。
# 无 move_speed、movement_type、sight_range（塔不移动）。
# ==============================================================================

var tower_data := {
	"guard_tower": {
		"id": "guard_tower",
		"display_name": "公主塔",
		"tower_type": "guard",
		"max_hp": 3052,
		"shield": 0,
		"collision_radius": 1.5,  # 内切圆半径 = 3格 / 2
		"hurt_radius": 1.5,
		"mass": 0,  # 塔不可移动
		"knockback_immune": true,
		"sprite": {
			"player_texture": "res://assets/sprites/towers/guard_tower_player.png",
			"enemy_texture": "res://assets/sprites/towers/guard_tower_enemy.png",
			"visual_scale": 0.06375,    # 统一缩放（基于原始大图，缩小25%）
			"visual_offset_y": 25.0,    # 精细微调（正=下移，负=上移），底部对齐由代码自动计算
			# 公主塔 UI：我方整体下移，敌方整体上移；血条数值会自动跟随。
			"player_hud_offset_y": 10.0,
			"enemy_hud_offset_y": -10.0,
		},
		# 仅复用 card_princess 的角色帧，固定站在塔顶中央；绝不读取其生命、射程、伤害或攻速。
		# offset_y 为角色帧中心高度；代码会以此自动同步箭矢发射高度，避免仍从塔底飞出。
		"tower_princess": {
			"unit_id": "princess",
			"offset_x": 0.0,
			# 角色需要落在塔身上半部的中央平台内，而不是站到塔顶轮廓外。
			"player_offset_y": -28.0,
			"enemy_offset_y": -42.0,
			"visual_scale": 0.05,
		},
		"attacks": [{
			"name": "arrow_shot",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 7.5,
			"attack_interval": 0.8,
			"first_attack_delay": 0.8,
			"delivery": "projectile",
			"trajectory": "homing",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 109,
			"projectile_speed": 12.5,
		}],
	},
	"king_tower": {
		"id": "king_tower",
		"display_name": "国王塔",
		"tower_type": "king",
		"max_hp": 4824,
		"shield": 0,
		"collision_radius": 2.0,  # 内切圆半径 = 4格 / 2
		"hurt_radius": 2.0,
		"mass": 0,  # 塔不可移动
		"knockback_immune": true,
		"sprite": {
			"player_texture": "res://assets/sprites/towers/king_tower_player.png",
			"enemy_texture": "res://assets/sprites/towers/king_tower_enemy.png",
			"visual_scale": 0.072,     # 4格塔 vs 公主塔3格，按每格渲染高 ~20px 推算（图高1110→80px）
			"visual_offset_y": 35.0,   # 精灵底部对齐碰撞框底部（半径2格=40px，留5px间距）
		},
		"attacks": [{
			"name": "cannon_shot",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": true,
			"attack_range": 7.0,
			"attack_interval": 1.0,
			"first_attack_delay": 0.5,
			"delivery": "projectile",
			"trajectory": "homing",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 109,
			"projectile_speed": 11.0,
		}],
	},
}

# ==============================================================================
# 建筑数据表（P1，预留结构）
# ==============================================================================

var building_data := {}


# ==============================================================================
# 音效数据表（SFX）
# 集中配置所有战斗音效事件。key 为事件 id（AudioManager.play 用此 id 查找配置）。
# stream 字段为空字符串时 AudioManager 静默跳过（资源未上线时不报错，方便分批接入）。
#
# 字段说明：
#   stream:        AudioStream 资源路径（res://assets/audio/sfx/xxx.ogg）
#   volume_db:     播放音量（dB），相对 SFX 总线音量的偏移。0=不偏移，-6= quieter
#   pitch_range:   [min, max] 音调随机区间（1.0=原调），让重复音效不单调
#   max_polyphony: 同一事件同时播放上限，超过则丢弃新的（避免嘈杂）
#   priority:      优先级（数字越大越优先）。超出 max_polyphony 时优先级低的被丢弃
# ==============================================================================

var sound_data := {
	# ---- 部署 ----
	"deploy": {
		"stream": "",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_spell": {
		"stream": "",
		"volume_db": -2.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 2,
		"priority": 5,
	},

	# ---- 攻击（通用模板，单位专属音效通过 unit_data.sfx.attack 引用此类 key）----
	"attack_melee": {  # 近战挥砍（骑士/王子/哥布林等）
		"stream": "",
		"volume_db": -6.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 4,
		"priority": 3,
	},
	"attack_ranged": {  # 远程发射（弓箭手/火枪手）
		"stream": "",
		"volume_db": -5.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 4,
		"priority": 3,
	},
	"charge_hit": {  # 王子冲锋命中
		"stream": "res://assets/audio/sfx/王子冲锋命中.MP3",
		"volume_db": -2.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 6,
	},

	# ---- 飞行物 ----
	"projectile_launch": {  # 投射物发射（弓箭/炮弹出膛）
		"stream": "",
		"volume_db": -8.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 6,
		"priority": 2,
	},
	"projectile_hit": {  # 投射物命中
		"stream": "",
		"volume_db": -6.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 6,
		"priority": 3,
	},
	"mortar_launch": {  # 迫击炮发射（可单独配置或回退到 projectile_launch）
		"stream": "res://assets/audio/sfx/迫击炮发射.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 4,
	},

	# ---- 命中 / 受击 ----
	"hit_metal": {  # 金属碰撞（骑士打到骑士/塔）
		"stream": "",
		"volume_db": -5.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 5,
		"priority": 3,
	},
	"hit_flesh": {  # 血肉命中（一般单位受击）
		"stream": "",
		"volume_db": -7.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 6,
		"priority": 2,
	},

	# ---- 法术 ----
	"fireball_launch": {  # 火球发射
		"stream": "res://assets/audio/sfx/火球发射.MP3",
		"volume_db": -2.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 2,
		"priority": 6,
	},
	"fireball_impact": {  # 火球爆炸
		"stream": "res://assets/audio/sfx/火球命中.MP3",
		"volume_db": 0.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 7,
	},
	"arrows_rain": {  # 万箭齐发箭雨
		"stream": "res://assets/audio/sfx/万箭齐发.MP3",
		"volume_db": -4.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"poison_cast": {  # 毒药施放
		"stream": "res://assets/audio/sfx/毒药.MP3",
		"volume_db": -4.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 2,
		"priority": 5,
	},

	# ---- 死亡 / 摧毁 ----
	"unit_die": {  # 单位死亡
		"stream": "",
		"volume_db": -8.0,
		"pitch_range": [0.85, 1.15],
		"max_polyphony": 5,
		"priority": 2,
	},
	"tower_destroyed": {  # 塔被摧毁
		"stream": "res://assets/audio/sfx/公主塔爆了.MP3",
		"volume_db": 2.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 1,
		"priority": 10,
	},
	"king_tower_destroyed": {  # 国王塔被摧毁（胜负判定）
		"stream": "",
		"volume_db": 3.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 1,
		"priority": 10,
	},

	# ---- 战斗流程 ----
	"battle_start": {
		"stream": "",
		"volume_db": 0.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 1,
		"priority": 8,
	},
	"victory": {
		"stream": "",
		"volume_db": 0.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 1,
		"priority": 10,
	},
	"defeat": {
		"stream": "",
		"volume_db": 0.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 1,
		"priority": 10,
	},

	# ---- 卡牌选中 ----
	"card_select": {
		"stream": "res://assets/audio/sfx/选中卡牌.MP3",
		"volume_db": -4.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},

	# ---- 倒计时 ----
	"countdown_10s": {
		"stream": "res://assets/audio/sfx/倒计时10秒.MP3",
		"volume_db": 0.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 1,
		"priority": 8,
	},

	# ---- 单位专属部署音（unit_data.sfx.deploy 引用）----
	"deploy_archers": {
		"stream": "res://assets/audio/sfx/弓箭手部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_goblins": {
		"stream": "res://assets/audio/sfx/哥布林部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_mini_pekka": {
		"stream": "res://assets/audio/sfx/小皮卡部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_balloon": {
		"stream": "res://assets/audio/sfx/气球部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_musketeer": {
		"stream": "res://assets/audio/sfx/火枪手部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_awakened_musketeer": {
		"stream": "res://assets/audio/sfx/觉醒女枪出场.MP3",
		"volume_db": -3.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_pekka": {
		"stream": "res://assets/audio/sfx/皮卡出场.MP3",
		"volume_db": -3.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_valkyrie": {
		"stream": "res://assets/audio/sfx/女武神出场.MP3",
		"volume_db": -3.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_prince": {
		"stream": "res://assets/audio/sfx/王子部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_hog_rider": {
		"stream": "res://assets/audio/sfx/野猪部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_mega_minion": {
		"stream": "res://assets/audio/sfx/亡灵重甲部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 5,
	},
	"deploy_building": {
		"stream": "res://assets/audio/sfx/建筑部署.MP3",
		"volume_db": -3.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 2,
		"priority": 5,
	},

	# ---- 单位专属攻击音（unit_data.sfx.attack 引用）----
	"attack_mini_pekka": {
		"stream": "res://assets/audio/sfx/小皮卡攻击.MP3",
		"volume_db": -5.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 3,
		"priority": 4,
	},
	"attack_giant": {
		"stream": "res://assets/audio/sfx/巨人攻击.MP3",
		"volume_db": -5.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 3,
		"priority": 4,
	},
	"attack_musketeer": {
		"stream": "res://assets/audio/sfx/火枪手攻击.MP3",
		"volume_db": -5.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 3,
		"priority": 4,
	},
	"attack_awakened_musketeer": {
		"stream": "res://assets/audio/sfx/觉醒女枪射击.MP3",
		"volume_db": -5.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 3,
		"priority": 4,
	},
	"attack_pekka": {
		"stream": "res://assets/audio/sfx/皮卡攻击.MP3",
		"volume_db": -5.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 3,
		"priority": 4,
	},
	"attack_valkyrie": {
		"stream": "res://assets/audio/sfx/女武神攻击.MP3",
		"volume_db": -5.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 3,
		"priority": 4,
	},

	# ---- 迫击炮命中 ----
	"mortar_impact": {
		"stream": "res://assets/audio/sfx/迫击炮命中.MP3",
		"volume_db": -2.0,
		"pitch_range": [0.9, 1.1],
		"max_polyphony": 2,
		"priority": 5,
	},

	# ---- 王子冲锋 ----
	"prince_charge": {
		"stream": "res://assets/audio/sfx/王子冲锋.MP3",
		"volume_db": -1.0,
		"pitch_range": [1.0, 1.0],
		"max_polyphony": 1,
		"priority": 6,
	},

	# ---- 野猪移动 ----
	"hog_rider_move": {
		"stream": "res://assets/audio/sfx/野猪移动.MP3",
		"volume_db": -8.0,
		"pitch_range": [0.95, 1.05],
		"max_polyphony": 2,
		"priority": 2,
	},
}


# ==============================================================================
# 背景音乐数据表（BGM）
# key 为 bgm id，AudioManager.play_bgm(id) 用此 id 查找配置。
# stream 为空时静默跳过。
# ==============================================================================

var bgm_data := {
	"battle": {
		"stream": "",
		"volume_db": -6.0,
	},
	"menu": {
		"stream": "",
		"volume_db": -8.0,
	},
	"victory": {
		"stream": "",
		"volume_db": -4.0,
	},
	"defeat": {
		"stream": "",
		"volume_db": -4.0,
	},
}


# ==============================================================================
# 查询方法
# ==============================================================================

## 查询单位数据。找不到时返回空字典。
func get_unit_data(unit_id: String) -> Dictionary:
	if unit_data.has(unit_id):
		return unit_data[unit_id]
	push_error("[DataRegistry] Unknown unit id: " + unit_id)
	return {}


## 查询卡牌数据。找不到时返回空字典。
func get_card_data(card_id: String) -> Dictionary:
	if card_data.has(card_id):
		return card_data[card_id]
	push_error("[DataRegistry] Unknown card id: " + card_id)
	return {}


## 查询塔数据。找不到时返回空字典。
func get_tower_data(tower_id: String) -> Dictionary:
	if tower_data.has(tower_id):
		return tower_data[tower_id]
	push_error("[DataRegistry] Unknown tower id: " + tower_id)
	return {}


## 查询建筑数据。找不到时返回空字典。
func get_building_data(building_id: String) -> Dictionary:
	if building_data.has(building_id):
		return building_data[building_id]
	push_error("[DataRegistry] Unknown building id: " + building_id)
	return {}


## 查询音效事件配置。找不到时返回空字典（AudioManager 自行静默处理）。
## 注意：与 get_unit/card/tower_data 不同，此处不报错——音效缺失不应影响游戏运行。
func get_sound_data(event_id: String) -> Dictionary:
	return sound_data.get(event_id, {})


## 查询 BGM 配置。找不到时返回空字典。
func get_bgm_data(bgm_id: String) -> Dictionary:
	return bgm_data.get(bgm_id, {})


## 查询某单位的 sfx 配置（unit_data 内的 sfx 字典）。无 sfx 字段时返回空字典。
## 单位专属音效结构示例：
##   "sfx": { "attack": "attack_melee", "death": "unit_die" }
## 值为 sound_data 中的事件 id。AudioManager.play_unit_sfx() 用此映射查找最终配置。
func get_unit_sfx(unit_id: String) -> Dictionary:
	var u := get_unit_data(unit_id)
	return u.get("sfx", {})


## 返回玩家默认卡组（卡牌 id 列表）。开发阶段包含全部卡牌。
func get_default_player_deck() -> Array:
	var deck := card_data.keys()
	# 只有精英牌替代同定位的普通版；觉醒牌不另占牌库槽位，
	# card_mortar / card_musketeer 的普通版本必须保留，由轮次机制触发觉醒。
	deck.erase("card_knight")
	deck.erase("card_mega_minion")
	return deck


## 返回敌方 AI 的默认卡组（卡牌 id 列表）。开发阶段包含全部卡牌。
func get_default_enemy_deck() -> Array:
	var deck := card_data.keys()
	# 觉醒牌与普通牌使用同一个 card_id，敌方也保留普通版本并按轮次觉醒。
	deck.erase("card_knight")
	deck.erase("card_mega_minion")
	return deck


# ==============================================================================
# 配置校验
# 启动时自动运行，一次性输出所有错误，不遇错即停。
# ==============================================================================

func _ready() -> void:
	_validate_all_data()


func _validate_all_data() -> void:
	var errors: Array = []

	# ---- 校验卡牌 ----
	for card_id in card_data:
		var c: Dictionary = card_data[card_id]
		if not c.has("id"):
			errors.append("卡牌 '%s' 缺少 id" % card_id)
		if not c.has("cost"):
			errors.append("卡牌 '%s' 缺少 cost" % card_id)
		if not c.has("card_type"):
			errors.append("卡牌 '%s' 缺少 card_type" % card_id)
		if int(c.get("cost", 0)) < 0:
			errors.append("卡牌 '%s' cost 为负数" % card_id)

		match c.get("card_type", ""):
			"troop":
				var uid: String = c.get("unit_id", "")
				if uid == "":
					errors.append("卡牌 '%s' (troop) 缺少 unit_id" % card_id)
				elif not unit_data.has(uid):
					errors.append("卡牌 '%s' 引用了不存在的 unit_id: '%s'" % [card_id, uid])
				if int(c.get("spawn_count", 1)) < 1:
					errors.append("卡牌 '%s' spawn_count < 1" % card_id)
			"building":
				var bid: String = c.get("building_id", "")
				if bid == "":
					errors.append("卡牌 '%s' (building) 缺少 building_id" % card_id)
				elif not building_data.has(bid):
					errors.append("卡牌 '%s' 引用了不存在的 building_id: '%s'" % [card_id, bid])
			"spell":
				if not c.has("spell_type"):
					errors.append("卡牌 '%s' (spell) 缺少 spell_type" % card_id)
				if not c.has("spell_radius"):
					errors.append("卡牌 '%s' (spell) 缺少 spell_radius" % card_id)
				if not c.has("spell_damage"):
					errors.append("卡牌 '%s' (spell) 缺少 spell_damage" % card_id)
			"":
				errors.append("卡牌 '%s' card_type 为空" % card_id)
			_:
				errors.append("卡牌 '%s' card_type 不合法: '%s'" % [card_id, c.get("card_type")])

		# 觉醒字段校验（可选字段，存在时校验结构）
		if c.has("awakening"):
			var aw: Dictionary = c["awakening"]
			if int(aw.get("trigger_count", 0)) < 0:
				errors.append("卡牌 '%s' awakening.trigger_count < 0" % card_id)
			if not aw.has("effects"):
				errors.append("卡牌 '%s' awakening 缺少 effects" % card_id)
			elif aw["effects"].is_empty():
				errors.append("卡牌 '%s' awakening.effects 为空" % card_id)
			else:
				var effects: Dictionary = aw["effects"]
				if effects.has("projectile_impact_summon_unit_id"):
					var summon_unit_id := str(effects["projectile_impact_summon_unit_id"])
					if summon_unit_id.is_empty() or not unit_data.has(summon_unit_id):
						errors.append("卡牌 '%s' 的 projectile_impact_summon_unit_id 无效: '%s'" % [card_id, summon_unit_id])

		# 精英技能字段校验（可选字段，存在时校验结构）
		if c.has("elite_skill"):
			var es: Dictionary = c["elite_skill"]
			if not es.has("id"):
				errors.append("卡牌 '%s' elite_skill 缺少 id" % card_id)
			if not es.has("display_name"):
				errors.append("卡牌 '%s' elite_skill 缺少 display_name" % card_id)
			if int(es.get("cost", 0)) < 0:
				errors.append("卡牌 '%s' elite_skill.cost < 0" % card_id)
			var es_tgt: String = es.get("targeting", "")
			if es_tgt != "instant" and es_tgt != "targeted":
				errors.append("卡牌 '%s' elite_skill.targeting 不合法: '%s'" % [card_id, es_tgt])
			if not es.has("effect"):
				errors.append("卡牌 '%s' elite_skill 缺少 effect" % card_id)
			if float(es.get("cooldown", 0)) < 0:
				errors.append("卡牌 '%s' elite_skill.cooldown < 0" % card_id)

	# ---- 校验单位 ----
	for uid in unit_data:
		var u: Dictionary = unit_data[uid]
		if not u.has("id"):
			errors.append("单位 '%s' 缺少 id" % uid)
		if int(u.get("max_hp", 0)) <= 0:
			errors.append("单位 '%s' max_hp <= 0" % uid)
		if not u.has("attacks"):
			errors.append("单位 '%s' 缺少 attacks 数组" % uid)
		elif u["attacks"].is_empty() and not bool(u.get("is_passive", false)):
			errors.append("单位 '%s' attacks 为空" % uid)
		else:
			for i in range(u["attacks"].size()):
				var a: Dictionary = u["attacks"][i]
				var prefix: String = "单位 '%s' attacks[%d]" % [uid, i]
				if not a.has("damage"):
					errors.append("%s 缺少 damage" % prefix)
				if not a.has("attack_range"):
					errors.append("%s 缺少 attack_range" % prefix)
				if not a.has("attack_interval"):
					errors.append("%s 缺少 attack_interval" % prefix)
				if not a.has("targeting"):
					errors.append("%s 缺少 targeting" % prefix)
				if not a.has("delivery"):
					errors.append("%s 缺少 delivery" % prefix)
				if int(a.get("damage", 0)) < 0:
					errors.append("%s damage < 0" % prefix)
				if float(a.get("attack_range", 0)) <= 0:
					errors.append("%s attack_range <= 0" % prefix)
				var tgt: String = a.get("targeting", "")
				if tgt != "any" and tgt != "building_only":
					errors.append("%s targeting 不合法: '%s'" % [prefix, tgt])
				var dlvr: String = a.get("delivery", "")
				if dlvr != "instant" and dlvr != "projectile":
					errors.append("%s delivery 不合法: '%s'" % [prefix, dlvr])

		# 碰撞几何字段校验
		if float(u.get("collision_radius", 0)) <= 0:
			errors.append("单位 '%s' collision_radius <= 0" % uid)
		if float(u.get("hurt_radius", 0)) <= 0:
			errors.append("单位 '%s' hurt_radius <= 0" % uid)
		if int(u.get("mass", -1)) < 0:
			errors.append("单位 '%s' mass < 0" % uid)
		if u.has("knockback_immune") and not (u["knockback_immune"] is bool):
			errors.append("单位 '%s' knockback_immune 必须为 bool" % uid)
		if int(u.get("mass", -1)) == 0 and not bool(u.get("knockback_immune", false)):
			errors.append("静态单位 '%s' 必须显式 knockback_immune=true" % uid)

	# ---- 校验塔 ----
	for tid in tower_data:
		var tw: Dictionary = tower_data[tid]
		if not tw.has("id"):
			errors.append("塔 '%s' 缺少 id" % tid)
		if not tw.has("tower_type"):
			errors.append("塔 '%s' 缺少 tower_type" % tid)
		if int(tw.get("max_hp", 0)) <= 0:
			errors.append("塔 '%s' max_hp <= 0" % tid)
		var tt: String = tw.get("tower_type", "")
		if tt != "king" and tt != "guard":
			errors.append("塔 '%s' tower_type 不合法: '%s'" % [tid, tt])
		# 碰撞几何字段校验（塔必须 mass=0）
		if float(tw.get("collision_radius", 0)) <= 0:
			errors.append("塔 '%s' collision_radius <= 0" % tid)
		if float(tw.get("hurt_radius", 0)) <= 0:
			errors.append("塔 '%s' hurt_radius <= 0" % tid)
		if int(tw.get("mass", -1)) != 0:
			errors.append("塔 '%s' mass 必须为 0（不可移动）" % tid)
		if not (tw.get("knockback_immune", null) is bool):
			errors.append("塔 '%s' knockback_immune 必须为 bool" % tid)
		elif not bool(tw["knockback_immune"]):
			errors.append("塔 '%s' 必须 knockback_immune=true" % tid)

	# ---- 校验音效配置（仅结构性校验，stream 允许为空字符串）----
	for sid in sound_data:
		var s: Dictionary = sound_data[sid]
		if not s.has("stream"):
			errors.append("音效 '%s' 缺少 stream 字段（可填空字符串）" % sid)
		var pr = s.get("pitch_range", null)
		if pr != null:
			if not (pr is Array) or pr.size() != 2:
				errors.append("音效 '%s' pitch_range 必须是 [min, max] 二元数组" % sid)
			elif float(pr[0]) > float(pr[1]):
				errors.append("音效 '%s' pitch_range[0] > pitch_range[1]" % sid)
	for bid in bgm_data:
		if not bgm_data[bid].has("stream"):
			errors.append("BGM '%s' 缺少 stream 字段（可填空字符串）" % bid)

	# ---- 输出结果 ----
	if errors.is_empty():
		print("[DataRegistry] 配置校验通过 | 卡牌: %d | 单位: %d | 塔: %d | 音效: %d | BGM: %d" % [
			card_data.size(), unit_data.size(), tower_data.size(),
			sound_data.size(), bgm_data.size()
		])
	else:
		push_error("[DataRegistry] 配置校验发现 %d 个错误：" % errors.size())
		for e in errors:
			push_error("  X " + e)
