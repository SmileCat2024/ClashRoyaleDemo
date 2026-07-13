# 文件名：DamageSystem.gd
# 作用：统一的伤害结算入口。AttackComponent（instant 攻击）和 ProjectileBase（飞行物命中）
#       以及未来的 SpellManager（范围法术）都通过这里结算伤害，不绕过直接调 take_damage。
#       这样护盾吸收、死亡判定等逻辑有唯一实现位置（在 CombatantBase.take_damage 里）。
# 挂载位置：不需要挂载。通过 class_name 注册为全局类型。
# 初学者阅读建议：看 resolve_impact() 了解单体伤害怎么结算，看 deal_area_damage() 了解范围伤害。

class_name DamageSystem


## 单体伤害结算。目标无效或已死亡时安全跳过，不报错。
static func resolve_impact(target: Node, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.get("is_dead") == true:
		return
	if target.has_method("take_damage"):
		target.take_damage(damage)


## 范围伤害结算。对 center 周围 radius 范围内的所有敌方实体造成全额伤害（无衰减）。
## 通过 EntityRegistry 查询，不遍历场景树。
## center 使用 World 本地游戏空间坐标。
## tower_damage >= 0 时，塔（有 tower_type 属性的实体）受 tower_damage 而非 damage（法术对塔减伤）。
static func deal_area_damage(center: Vector2, radius: float, damage: int, attacker_team: String, tower_damage: int = -1, attack_ground: bool = true, attack_air: bool = true) -> void:
	var enemies = EntityRegistry.get_enemies_of(attacker_team)
	for e in enemies:
		# ground/air 过滤：单位攻击范围限定（如瓦基里仅地面）；法术默认打所有
		var mt = e.get("movement_type")
		var is_air: bool = mt == "air"
		if is_air and not attack_air:
			continue
		if not is_air and not attack_ground:
			continue
		# 受击半径偏移：大体积目标更容易被范围伤害命中
		var hr = e.get("hurt_radius")
		var hurt_r: float = float(hr) if hr != null else 0.0
		if center.distance_to(BattlePathing.game_position_of(e)) <= radius + hurt_r:
			if e.has_method("take_damage"):
				var dmg := damage
				if tower_damage >= 0 and e.get("tower_type") != null:
					dmg = tower_damage
				e.take_damage(dmg)
