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
		"sight_range": 6.0,
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
			"delivery": "instant",
			"trajectory": "",
			"impact_type": "single",
			"impact_radius": 0.0,
			"damage": 202,
		}],
	},
	"hog_rider": {
		"id": "hog_rider",
		"display_name": "野猪骑士",
		"max_hp": 1697,
		"shield": 0,
		"move_speed": 2.0,  # 极快
		"movement_type": "ground",
		"can_jump_river": true,
		"sight_range": 6.0,
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
			"jump_frame": 2,  # 跳河期间锁定显示第3帧（0-indexed）
			"states": {
				"walk_back": {
					"frames": ["walk_back_01.png", "walk_back_02.png", "walk_back_03.png", "walk_back_04.png"],
					"duration": [0.15, 0.15, 0.15, 0.15],
					"mode": "loop",
				},
				"idle_back": {
					"frames": ["walk_back_01.png"],
					"duration": [1.0],
					"mode": "loop",
				},
			},
		},
	},
	"musketeer": {
		"id": "musketeer",
		"display_name": "火枪手",
		"max_hp": 721,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "ground",
		"sight_range": 7.0,
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
	},
	"balloon": {
		"id": "balloon",
		"display_name": "气球兵",
		"max_hp": 1679,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "air",
		"sight_range": 6.0,
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
	},
	"archers": {
		"id": "archers",
		"display_name": "弓箭手",
		"max_hp": 304,
		"shield": 0,
		"move_speed": 1.0,  # 中速
		"movement_type": "ground",
		"sight_range": 6.0,
		"movement_targeting": "any",
		"collision_radius": 0.35,
		"hurt_radius": 0.35,
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
		# 原始 PNG 473×517px，缩放到约 83px 宽（≈4格）
		# 素材默认面朝左，向右移动时 flip_h 自动翻转
		"animation": {
			"visual_offset_x": 0.0,
			"visual_offset_y": -24.0,     # 进游戏后目测微调
			"visual_scale": 0.075,       # 473 × 0.0875 ≈ 41px
			"health_bar_y": -60.0,        # 血条在角色头顶上方
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
					"frames": ["walk_back_01.png"],
					"duration": [0.3],
					"mode": "loop",
				},
			},
		},
	},
	"giant": {
		"id": "giant",
		"display_name": "巨人",
		"max_hp": 4090,
		"shield": 0,
		"move_speed": 0.75,  # 慢速（内部数值45 → 0.75格/秒）
		"movement_type": "ground",
		"sight_range": 6.0,
		"movement_targeting": "building_only",
		"collision_radius": 0.7,
		"hurt_radius": 0.7,
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
			"visual_offset_y": -55.0,
			"visual_scale": 0.096,
			"health_bar_y": -120,
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
		"icon": "",
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
		"icon": "",
		"description": "持续伤害法术，减速区域内敌方部队。8秒内每秒造成92伤害。",
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


## 返回玩家默认卡组（8张牌 id）。
func get_default_player_deck() -> Array:
	return [
		"card_knight", "card_musketeer", "card_mini_pekka",
		"card_hog_rider", "card_balloon", "card_archers",
		"card_fireball", "card_poison",
	]


## 返回敌方 AI 的默认卡组（卡牌 id 列表）。
func get_default_enemy_deck() -> Array:
	return ["card_knight", "card_hog_rider", "card_musketeer", "card_mini_pekka", "card_archers", "card_fireball", "card_poison"]


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

	# ---- 输出结果 ----
	if errors.is_empty():
		print("[DataRegistry] 配置校验通过 | 卡牌: %d | 单位: %d | 塔: %d" % [
			card_data.size(), unit_data.size(), tower_data.size()
		])
	else:
		push_error("[DataRegistry] 配置校验发现 %d 个错误：" % errors.size())
		for e in errors:
			push_error("  X " + e)
