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
		"shadow_size": 0.5,
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
		"shadow_size": 0.55,
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
		"shadow_size": 0.5,
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
		"shadow_size": 0.45,
		"attacks": [{
			"name": "blade_slash",
			"targeting": "any",
			"attack_ground": true,
			"attack_air": false,
			"attack_range": 0.8,
			"attack_interval": 1.6,
			"first_attack_delay": 0.5,
			"delivery": "instant",
			"trajectory": "",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 755,
		}],
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
		"shadow_size": 0.35,
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
			"visual_offset_x": 0.0,
			"visual_offset_y": -24.0,
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
			"visual_offset_y": -35.0,
			"visual_scale": 0.0768,
			"health_bar_y": -100,
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
		"sight_range": 5.5,  # 原版5.5
		"movement_targeting": "any",
		"collision_radius": 0.65,  # 原版0.65
		"hurt_radius": 0.65,
		"mass": 7,
		"shadow_size": 0.6,
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
		"shadow_size": 0.8,
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
		"shadow_size": 0.4,
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
		"sfx": {
			"deploy": "deploy_mega_minion",
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
		"shadow_size": 0.3,
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
		"description": "远程射手，可对空对地。",
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
		"sprite": {
			"player_texture": "res://assets/sprites/towers/guard_tower_player.png",
			"enemy_texture": "res://assets/sprites/towers/guard_tower_enemy.png",
			"visual_scale": 0.06375,    # 统一缩放（基于原始大图，缩小25%）
			"visual_offset_y": 25.0,    # 精细微调（正=下移，负=上移），底部对齐由代码自动计算
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
			"trajectory": "ballistic",
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
	return card_data.keys()


## 返回敌方 AI 的默认卡组（卡牌 id 列表）。开发阶段包含全部卡牌。
func get_default_enemy_deck() -> Array:
	return card_data.keys()


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

	# ---- 校验单位 ----
	for uid in unit_data:
		var u: Dictionary = unit_data[uid]
		if not u.has("id"):
			errors.append("单位 '%s' 缺少 id" % uid)
		if int(u.get("max_hp", 0)) <= 0:
			errors.append("单位 '%s' max_hp <= 0" % uid)
		if not u.has("attacks"):
			errors.append("单位 '%s' 缺少 attacks 数组" % uid)
		elif u["attacks"].is_empty():
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
