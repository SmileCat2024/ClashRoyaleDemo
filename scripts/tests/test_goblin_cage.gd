# 文件名：test_goblin_cage.gd
# 作用：验证哥布林牢笼的 11 级数据、卡牌关联及死亡召唤事件。
# 挂载位置：由 TestRunner 实例化。
# 初学者阅读建议：先看 test_cage_death_requests_one_brawler，了解数据驱动死亡召唤的链路。

extends TestBase

var _cage: UnitBase
var _spawn_events: Array[Dictionary] = []


func setup() -> void:
	var data: Dictionary = DataRegistry.get_unit_data("goblin_cage")
	_cage = UnitBase.new()
	_cage.unit_id = "goblin_cage"
	_cage.team = "player"
	_cage.position = Vector2(120.0, 360.0)
	_cage._death_spawn_unit_id = str(data.get("death_spawn_unit_id", ""))
	_cage._death_spawn_count = int(data.get("death_spawn_count", 0))
	_spawn_events.clear()
	SignalBus.unit_death_spawn_requested.connect(_on_death_spawn_requested)


func teardown() -> void:
	if SignalBus.unit_death_spawn_requested.is_connected(_on_death_spawn_requested):
		SignalBus.unit_death_spawn_requested.disconnect(_on_death_spawn_requested)
	if _cage and is_instance_valid(_cage):
		_cage.free()


func _on_death_spawn_requested(pos: Vector2, unit_id: String, team: String, count: int) -> void:
	_spawn_events.append({"position": pos, "unit_id": unit_id, "team": team, "count": count})


func test_goblin_cage_data_config() -> void:
	var cage: Dictionary = DataRegistry.get_unit_data("goblin_cage")
	assert_eq(int(cage.get("max_hp", 0)), 780, "牢笼应使用 11 级 780 生命")
	assert_true(bool(cage.get("is_passive", false)), "牢笼应为无攻击的被动建筑")
	assert_eq(int(cage.get("mass", -1)), 0, "牢笼应为不可移动的寻路障碍")
	assert_true(bool(cage.get("knockback_immune", false)), "静态牢笼应免疫击退")
	assert_approx(float(cage.get("deploy_time", 0.0)), 1.0, 0.01, "牢笼部署时间应为 1 秒")
	assert_approx(float(cage.get("lifespan", 0.0)), 20.0, 0.01, "牢笼寿命应为 20 秒")
	assert_eq(cage.get("death_spawn_unit_id", ""), "goblin_brawler", "牢笼死亡应放出斗士")
	assert_eq(int(cage.get("death_spawn_count", 0)), 1, "牢笼死亡应只放出 1 名斗士")


func test_goblin_brawler_data_config() -> void:
	var brawler: Dictionary = DataRegistry.get_unit_data("goblin_brawler")
	var attack: Dictionary = brawler.get("attacks", [])[0]
	assert_eq(int(brawler.get("max_hp", 0)), 1080, "斗士应使用 11 级 1080 生命")
	assert_approx(float(brawler.get("move_speed", 0.0)), 1.5, 0.01, "斗士应为快速移速")
	assert_eq(int(attack.get("damage", 0)), 337, "斗士应使用 11 级 337 伤害")
	assert_approx(float(attack.get("attack_range", 0.0)), 0.8, 0.01, "斗士应为 0.8 格短近战")
	assert_approx(float(attack.get("attack_interval", 0.0)), 1.1, 0.01, "斗士攻击间隔应为 1.1 秒")
	assert_approx(float(attack.get("first_attack_delay", 0.0)), 0.2, 0.01, "斗士首击延迟应为 0.2 秒")
	assert_false(bool(attack.get("attack_air", true)), "斗士只能攻击地面")


func test_goblin_cage_art_resources_exist() -> void:
	var cage_frames: Array = [
		"res://assets/sprites/goblin_cage/cage_front.png",
		"res://assets/sprites/goblin_cage/cage_back.png",
	]
	var brawler_frames: Array = [
		"res://assets/sprites/goblin_brawler/walk_front_01.png",
		"res://assets/sprites/goblin_brawler/walk_front_02.png",
		"res://assets/sprites/goblin_brawler/walk_back_01.png",
		"res://assets/sprites/goblin_brawler/walk_back_02.png",
		"res://assets/sprites/goblin_brawler/attack_front_01.png",
		"res://assets/sprites/goblin_brawler/attack_front_02.png",
		"res://assets/sprites/goblin_brawler/attack_back_01.png",
		"res://assets/sprites/goblin_brawler/attack_back_02.png",
	]
	for frame_path in cage_frames + brawler_frames:
		assert_true(FileAccess.file_exists(frame_path), "哥布林牢笼素材缺失: %s" % frame_path)


func test_cage_death_requests_one_brawler() -> void:
	_cage.die()
	_cage.die()
	assert_eq(_spawn_events.size(), 1, "重复死亡调用只能请求一次后续召唤")
	assert_eq(_spawn_events[0]["unit_id"], "goblin_brawler", "死亡召唤应指定哥布林斗士")
	assert_eq(_spawn_events[0]["team"], "player", "斗士应继承牢笼所属阵营")
	assert_eq(_spawn_events[0]["count"], 1, "死亡召唤数量应为 1")
	assert_eq(_spawn_events[0]["position"], Vector2(120.0, 360.0), "斗士应在牢笼死亡位置生成")


func test_goblin_cage_card_config() -> void:
	var card: Dictionary = DataRegistry.get_card_data("card_goblin_cage")
	assert_eq(int(card.get("cost", 0)), 4, "哥布林牢笼应为 4 费")
	assert_eq(card.get("card_type", ""), "troop", "建筑卡应走 troop + unit_id 兼容路径")
	assert_eq(card.get("unit_id", ""), "goblin_cage", "卡牌应关联牢笼单位")
	assert_true(FileAccess.file_exists(card.get("icon", "")), "哥布林牢笼卡面应存在")
