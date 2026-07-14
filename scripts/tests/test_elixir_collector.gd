# 文件名：test_elixir_collector.gd
# 作用：验证圣水收集器的数据、13 秒生产节点与死亡返还。

extends TestBase

var _collector: UnitBase
var _events: Array = []


func setup() -> void:
	_collector = UnitBase.new()
	_collector.unit_id = "elixir_collector"
	_collector.team = "player"
	var data := DataRegistry.get_unit_data("elixir_collector")
	_collector._elixir_generation_interval = float(data.get("elixir_generation_interval", 0.0))
	_collector._elixir_generation_amount = int(data.get("elixir_generation_amount", 0))
	_collector._elixir_generation_timer = _collector._elixir_generation_interval
	_collector._elixir_on_death = int(data.get("elixir_on_death", 0))
	_events.clear()
	SignalBus.elixir_generated.connect(_on_elixir_generated)


func teardown() -> void:
	if SignalBus.elixir_generated.is_connected(_on_elixir_generated):
		SignalBus.elixir_generated.disconnect(_on_elixir_generated)
	if _collector and is_instance_valid(_collector):
		_collector.free()


func _on_elixir_generated(_pos: Vector2, _team: String, amount: int, is_death: bool) -> void:
	_events.append({"amount": amount, "is_death": is_death})


func test_collector_data_config() -> void:
	var data := DataRegistry.get_unit_data("elixir_collector")
	assert_eq(data.get("id"), "elixir_collector", "单位 id 应存在")
	assert_eq(int(data.get("max_hp")), 1070, "11级生命值应为1070")
	assert_eq(int(data.get("mass")), 0, "收集器应是不可移动建筑")
	assert_approx(float(data.get("collision_radius")), 0.6, 0.01, "碰撞半径应与现有建筑一致")
	assert_approx(float(data.get("hurt_radius")), 0.6, 0.01, "受击半径应与现有建筑一致")
	assert_true(bool(data.get("knockback_immune")), "静态建筑应显式免疫击退")
	assert_approx(float(data.get("deploy_time")), 1.0, 0.01, "部署时间应为1秒")
	assert_approx(float(data.get("lifespan")), 93.0, 0.01, "寿命应为93秒")
	assert_approx(float(data.get("elixir_generation_interval")), 13.0, 0.01, "生产间隔应为13秒")
	assert_eq(int(data.get("elixir_generation_amount")), 1, "每次应生产1点")
	assert_eq(int(data.get("elixir_on_death")), 1, "死亡应返还1点")
	assert_true(bool(data.get("is_passive")), "收集器应为无攻击的被动建筑")


func test_first_elixir_at_13_seconds() -> void:
	_collector._process_elixir_generation(12.99)
	assert_eq(_events.size(), 0, "13秒前不应产出")
	_collector._process_elixir_generation(0.01)
	assert_eq(_events.size(), 1, "满13秒应产出第一滴")
	assert_eq(_events[0]["amount"], 1, "首滴应为1点")
	assert_false(_events[0]["is_death"], "正常生产不应标记为死亡返还")


func test_seven_regular_productions_by_91_seconds() -> void:
	for _i in range(7):
		_collector._process_elixir_generation(13.0)
	assert_eq(_events.size(), 7, "91秒内应正常生产7滴")
	for event in _events:
		assert_false(event["is_death"], "普通生产不应标记为死亡返还")


func test_freeze_pauses_production_timer() -> void:
	_collector.apply_status_effect(StatusEffect.new("freeze", 10.0))
	_collector._process_elixir_generation(20.0)
	assert_eq(_events.size(), 0, "冰冻期间不应生产")
	_collector._status_effects.clear()
	_collector._process_elixir_generation(13.0)
	assert_eq(_events.size(), 1, "冰冻结束后应从原计时继续生产")


func test_slow_delays_production_timer() -> void:
	var slow := StatusEffect.new("slow", 30.0)
	slow.move_speed_mult = 0.5
	_collector.apply_status_effect(slow)
	_collector._process_elixir_generation(13.0)
	assert_eq(_events.size(), 0, "50%减速下13秒不应完成生产")
	_collector._process_elixir_generation(13.0)
	assert_eq(_events.size(), 1, "50%减速下26秒应完成一滴生产")


func test_death_elixir_only_once() -> void:
	_collector.die()
	_collector.die()
	assert_eq(_events.size(), 1, "重复死亡调用只能返还一次")
	assert_eq(_events[0]["amount"], 1, "死亡返还应为1点")
	assert_true(_events[0]["is_death"], "死亡返还应带死亡标记")


func test_collector_card_config() -> void:
	var card := DataRegistry.get_card_data("card_elixir_collector")
	assert_eq(int(card.get("cost")), 6, "圣水收集器应为6费")
	assert_eq(card.get("unit_id"), "elixir_collector", "卡牌应关联收集器实体")
	assert_true(bool(card.get("exclude_from_initial_hand")), "收集器不能进入开局四张手牌")
