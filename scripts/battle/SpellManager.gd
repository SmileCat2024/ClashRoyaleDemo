# 文件名：SpellManager.gd
# 作用：法术卡牌的统一部署入口。接收卡牌 id + 目标位置，按 spell_type 分流：
#       fireball / arrows：从施法方国王塔发射飞行物（SpellProjectile / ArrowsSpellController）
#       poison：直接在目标位置创建 PoisonField（无弹道，即时部署）
#       与 SpawnManager（生成单位）平行，BattleManager 根据 card_type 分流到对应 Manager。
# 挂载位置：BattleScene/Managers/SpellManager
# 依赖节点：ProjectilesRoot（飞行物父容器）、EffectsRoot（持续效果父容器）
# 初学者阅读建议：看 cast_spell()，了解法术从卡牌到效果的完整流程。

extends Node

const SPELL_PROJECTILE_SCENE := preload("res://scenes/entities/SpellProjectile.tscn")
const ARROWS_CONTROLLER_SCRIPT := preload("res://scripts/battle/ArrowsSpellController.gd")
const POISON_FIELD_SCENE := preload("res://scenes/effects/PoisonField.tscn")

## 飞行物 / 持续效果的父容器
@onready var projectiles_root: Node2D = $"../../World/ProjectilesRoot"
@onready var effects_root: Node2D = $"../../World/EffectsRoot"


## 施放法术。由 BattleManager.try_play_card() 在 card_type == "spell" 时调用。
## 根据 spell_type 分流：
##   fireball → SpellProjectile（国王塔抛物线飞行 → 落地爆炸）
##   arrows   → ArrowsSpellController（多波箭雨）
##   poison   → 直接在目标位置创建 PoisonField（无弹道，即时部署）
func cast_spell(card_id: String, team_name: String, target_pos: Vector2, awakening_effects: Dictionary = {}) -> void:
	var card := DataRegistry.get_card_data(card_id)
	if card.is_empty():
		push_error("[SpellManager] Unknown card id: " + card_id)
		return

	# 法术觉醒效果应用：通过 awakening_effects 覆盖 card 字段（数据驱动）。
	# 例如觉醒火球可配 {"spell_damage": 1000, "spell_radius": 3.0} 提升伤害和范围。
	# 深拷贝 card 避免修改 DataRegistry 原始数据。
	if not awakening_effects.is_empty():
		card = card.duplicate(true)
		for key in awakening_effects:
			card[key] = awakening_effects[key]
		print("[SpellManager] 觉醒法术:", card_id, awakening_effects.keys())

	var spell_type: String = card.get("spell_type", "")

	match spell_type:
		"poison":
			AudioManager.play("poison_cast", target_pos)
			_create_poison_field(target_pos, card, team_name)
		"arrows":
			var origin := _get_king_tower_position(team_name)
			AudioManager.play("arrows_rain", origin)
			var controller = ARROWS_CONTROLLER_SCRIPT.new()
			add_child(controller)
			controller.setup(origin, target_pos, card, team_name, projectiles_root)
		_:
			# fireball / 其他 → 单体飞行物（抛物线弹道）
			var origin2 := _get_king_tower_position(team_name)
			AudioManager.play("fireball_launch", origin2)
			var projectile = SPELL_PROJECTILE_SCENE.instantiate()
			projectiles_root.add_child(projectile)
			projectile.setup_spell(origin2, target_pos, card, team_name)

	print("[SpellManager] cast %s (%s) → %s" % [card_id, team_name, target_pos])
	# Host 端：通知 client 也创建法术视觉效果（client 端效果实体 _process early return，不造成伤害）
	if NetworkManager.is_server():
		_rpc_cast_spell.rpc(card_id, team_name, target_pos)


## 联机 RPC：Host → Client，让 client 端也创建法术视觉效果
@rpc("authority", "call_remote", "reliable")
func _rpc_cast_spell(card_id: String, team_name: String, target_pos: Vector2) -> void:
	if NetworkManager.is_server():
		return  # Host 已本地执行
	# Client 端 team 翻转 + 180 度镜像落地位置
	# （发射点 origin 由 _get_king_tower_position 内部按 local_team 镜像）
	var local_team := "enemy" if team_name == "player" else "player"
	cast_spell(card_id, local_team, BattleConstants.mirror(target_pos))


## 毒药法术落地：直接在目标位置创建持续伤害区域（无弹道）
func _create_poison_field(target_pos: Vector2, card: Dictionary, team_name: String) -> void:
	var field = POISON_FIELD_SCENE.instantiate()
	effects_root.add_child(field)
	var tick_dmg := int(card.get("tick_damage", card.get("spell_damage", 0)))
	var ttd = card.get("tick_tower_damage", null)
	var tick_tower_dmg := int(ttd) if ttd != null else -1
	field.setup_field(
		target_pos,
		BattleConstants.px(float(card.get("spell_radius", 0))),
		tick_dmg,
		tick_tower_dmg,
		team_name,
		float(card.get("duration", 0.0)),
		float(card.get("tick_interval", 0.0)),
		float(card.get("slow_factor", 1.0))
	)


## 获取指定阵营国王塔的位置（World 本地游戏空间坐标）。
## 使用常量而非查找节点——即使国王塔被摧毁，法术仍从该位置发射。
## 不做 client 镜像：_rpc_cast_spell 已翻转 team，翻转后的 team 查出的
## 国王塔位置本身就是正确的（enemy→敌方塔/屏幕上方，player→己方塔/屏幕下方）。
## 若再 mirror 会把 origin 多翻转一次，导致敌方法术从己方塔发射。
static func _get_king_tower_position(team_name: String) -> Vector2:
	var key := "PlayerKingTower" if team_name == "player" else "EnemyKingTower"
	return BattleConstants.TOWER_PIXEL_POSITIONS[key]
