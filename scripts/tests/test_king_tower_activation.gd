# 文件名：test_king_tower_activation.gd
# 作用：验证国王塔激活机制——初始未激活（攻击组件禁用、外观暗化）、
#       受击后激活、公主塔始终激活、激活后冷却正确。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 _make_king_tower() 了解测试塔怎么创建，再看各 test_ 方法。

extends TestBase

const KING_TOWER_SCENE := preload("res://scenes/entities/towers/KingTower.tscn")
const GUARD_TOWER_SCENE := preload("res://scenes/entities/towers/GuardTower.tscn")

var _towers: Array = []


func setup() -> void:
	_towers.clear()


func teardown() -> void:
	for t in _towers:
		if is_instance_valid(t):
			t.queue_free()
	_towers.clear()


## 创建一个已 setup 的国王塔（加入场景树以触发 @onready）
func _make_king_tower(team: String = "player") -> TowerBase:
	var tower: TowerBase = KING_TOWER_SCENE.instantiate()
	add_child(tower)
	tower.setup(DataRegistry.get_tower_data("king_tower"), team, "TestKingTower")
	_towers.append(tower)
	return tower


## 创建一个已 setup 的公主塔
func _make_guard_tower(team: String = "player") -> TowerBase:
	var tower: TowerBase = GUARD_TOWER_SCENE.instantiate()
	add_child(tower)
	tower.setup(DataRegistry.get_tower_data("guard_tower"), team, "TestGuardTower")
	_towers.append(tower)
	return tower


# ============================================================
#  初始状态
# ============================================================

func test_king_tower_starts_deactivated() -> void:
	var tower := _make_king_tower()
	assert_false(tower.king_activated, "国王塔初始应为未激活")
	var comp := tower.get_primary_attack()
	assert_not_null(comp, "国王塔应有攻击组件")
	assert_false(comp.is_processing(), "未激活时攻击组件应被禁用")


func test_king_tower_sprite_darkened() -> void:
	var tower := _make_king_tower("player")
	# 国王塔未激活时精灵暗化至 55%；无贴图环境（sprite 为 null）则跳过视觉检查
	if tower._tower_sprite:
		assert_eq(tower._tower_sprite.modulate, Color(0.55, 0.55, 0.55, 1.0), "未激活国王塔精灵应暗化至 55%")
	else:
		assert_true(true, "无精灵贴图时跳过暗化视觉检查（逻辑状态由其他测试覆盖）")


func test_guard_tower_always_activated() -> void:
	var tower := _make_guard_tower()
	assert_true(tower.king_activated, "公主塔应始终为激活状态")
	var comp := tower.get_primary_attack()
	assert_true(comp.is_processing(), "公主塔攻击组件应始终启用")


# ============================================================
#  受击激活
# ============================================================

func test_king_tower_activates_on_damage() -> void:
	var tower := _make_king_tower()
	tower.take_damage(100)
	assert_true(tower.king_activated, "受击后国王塔应激活")
	var comp := tower.get_primary_attack()
	assert_true(comp.is_processing(), "激活后攻击组件应启用")


func test_king_tower_sprite_restored_on_activation() -> void:
	var tower := _make_king_tower("player")
	tower.take_damage(50)
	# 激活后精灵亮度恢复为白色；无贴图环境则跳过
	if tower._tower_sprite:
		assert_eq(tower._tower_sprite.modulate, Color.WHITE, "激活后精灵亮度应恢复")
	else:
		assert_true(true, "无精灵贴图时跳过恢复视觉检查")


func test_king_tower_cooldown_after_activation() -> void:
	var tower := _make_king_tower()
	var comp := tower.get_primary_attack()
	tower.activate_king()
	# first_attack_delay = 0.5（DataRegistry king_tower），未激活期间未递减
	assert_approx(comp.cooldown, 0.5, 0.01, "激活后冷却应保持 first_attack_delay=0.5")


# ============================================================
#  激活幂等性
# ============================================================

func test_activate_is_idempotent() -> void:
	var tower := _make_king_tower()
	tower.activate_king()
	tower.activate_king()
	assert_true(tower.king_activated, "多次激活不应出错")
	var comp := tower.get_primary_attack()
	assert_true(comp.is_processing(), "多次激活后攻击组件仍应启用")


func test_dead_king_tower_does_not_activate() -> void:
	var tower := _make_king_tower()
	# 直接杀死塔（大量伤害）
	tower.take_damage(99999)
	assert_true(tower.is_dead, "塔应已死亡")
	# 死后 king_activated 应保持 false（take_damage 中 is_dead 检查阻止激活）
	assert_false(tower.king_activated, "死亡的国王塔不应被激活")
