# 文件名：BattleManager.gd
# 作用：管理一整局战斗的完整生命周期——能量、出牌、卡组轮转、胜负判定、重开。
#       这是战斗的"总指挥"，所有关键决策都经过这里。
# 挂载位置：BattleScene/Managers/BattleManager
# 依赖节点：Arena、UnitsRoot、SpawnManager、SimpleEnemyAI
# 初学者阅读建议：先看 _ready() 和 start_battle()，理解初始化流程；
#       再看 _unhandled_input() 和 _try_deploy()，理解出牌的完整链路。

extends Node

# ---- 战斗状态 ----
var battle_running: bool = false
var battle_time: float = 0.0
var max_battle_time: float = 180.0       ## 常规时间（秒），参考皇室战争 3 分钟
var battle_phase: String = "regular"      ## "regular" | "overtime"
var overtime_duration: float = 60.0       ## 加时赛时长（秒），参考皇室战争 1 分钟
var overtime_energy_multiplier: float = 2.0  ## 加时赛圣水加速倍率

# ---- 能量系统 ----
var _player_state: PlayerBattleState = null
var _enemy_state: PlayerBattleState = null
var max_energy: int = 10
var energy_timer: float = 0.0
const BASE_ENERGY_INTERVAL: float = 0.4   ## [临时调试] 常规时间每 0.4 秒恢复 1 点能量（原值 2.8，7x 加速）
var energy_interval: float = BASE_ENERGY_INTERVAL

# ---- 卡组管理 ----
var deck_manager: DeckManager = null
var selected_hand_index: int = -1  ## 当前选中的手牌索引（-1 = 未选中）

# ---- 节点引用 ----
# World 容器（持有 Y 压缩变换，所有世界节点在其下）
@onready var world: Node2D = $"../../World"
@onready var arena: Node2D = $"../../World/Arena"
@onready var units_root: Node2D = $"../../World/UnitsRoot"
@onready var spawn_manager: Node = $"../SpawnManager"
@onready var spell_manager: Node = $"../SpellManager"
@onready var enemy_ai: Node = $"../SimpleEnemyAI"
@onready var deploy_preview: Node2D = $"../../World/DeployPreview"

# ---- 塔引用缓存（_setup_towers 时从 UnitsRoot 中筛选 TowerBase 实例）----
var _towers: Array = []


func _ready() -> void:
	print("[BattleManager] initialized")
	# 清理上一局的注册表残留（重开时旧实体已被引擎 free，但未调用 unregister）
	# 必须在 _setup_towers() 之前，否则会清掉刚注册的塔
	EntityRegistry.clear()
	# 创建双方状态
	_player_state = PlayerBattleState.new("player")
	_enemy_state = PlayerBattleState.new("enemy")
	# 创建 DeckManager（动态添加，不放在 tscn 里）
	deck_manager = DeckManager.new()
	deck_manager.name = "DeckManager"
	add_child(deck_manager)
	# 连接全局信号
	SignalBus.tower_destroyed.connect(_on_tower_destroyed)
	SignalBus.card_selected.connect(_on_card_selected)
	# 初始化所有塔的属性
	_setup_towers()
	# 开始战斗
	start_battle()


## 遍历 UnitsRoot 下的所有塔节点（TowerBase 实例），根据节点名称设置阵营和类型
func _setup_towers() -> void:
	_towers.clear()
	for child in units_root.get_children():
		if child is TowerBase:
			_towers.append(child)
			var name_lower = child.name.to_lower()
			var team_name = "player" if "player" in name_lower else "enemy"
			var type_name = "king" if "king" in name_lower else "guard"
			var data_key = type_name + "_tower"
			var data = DataRegistry.get_tower_data(data_key)
			# 从常量设置位置（.tscn 中的值仅作编辑器预览）
			if BattleConstants.TOWER_PIXEL_POSITIONS.has(child.name):
				child.position = BattleConstants.TOWER_PIXEL_POSITIONS[child.name]
			child.setup(data, team_name, child.name)
			EntityRegistry.register(child)


## 开始一局战斗
func start_battle() -> void:
	battle_running = true
	battle_time = 0.0
	battle_phase = "regular"
	energy_interval = BASE_ENERGY_INTERVAL
	_player_state.reset()
	_enemy_state.reset()
	energy_timer = 0.0
	selected_hand_index = -1
	# 初始化卡组
	deck_manager.setup(DataRegistry.get_default_player_deck())
	SignalBus.battle_started.emit()
	SignalBus.battle_phase_changed.emit("regular", max_battle_time)
	SignalBus.energy_changed.emit("player", _player_state.energy, max_energy)
	SignalBus.energy_changed.emit("enemy", _enemy_state.energy, max_energy)
	if enemy_ai and enemy_ai.has_method("setup"):
		enemy_ai.setup()
	# 延迟广播手牌状态，确保 CardBar 的 _ready 已连接信号
	call_deferred("_broadcast_hand_state")
	print("[BattleManager] battle started")


## 向 UI 广播当前手牌和选中状态（延迟调用，确保 UI 已就绪）
func _broadcast_hand_state() -> void:
	SignalBus.hand_updated.emit(deck_manager.get_hand(), deck_manager.get_next())
	SignalBus.selection_changed.emit(selected_hand_index)


## 结束战斗
func end_battle(result: String) -> void:
	if not battle_running:
		return
	battle_running = false
	if deploy_preview:
		deploy_preview.hide_preview()
	SignalBus.battle_ended.emit(result)
	print("[BattleManager] battle ended:", result)


## 重新开始战斗（重载场景）
func restart_battle() -> void:
	SceneLoader.reload_current_scene()


func _process(delta: float) -> void:
	if not battle_running:
		return
	battle_time += delta
	update_energy(delta)
	_check_time_limit()
	# 碰撞分离：在所有单位移动之后统一执行（场景树顺序保证单位先于 Manager 执行 _process）
	CollisionSystem.resolve_overlaps(EntityRegistry.get_all_combatants())


## 能量恢复逻辑：每 energy_interval 秒，双方各 +1 能量（不超过上限）
func update_energy(delta: float) -> void:
	energy_timer += delta
	if energy_timer >= energy_interval:
		energy_timer = 0.0
		if _player_state.gain_energy():
			SignalBus.energy_changed.emit("player", _player_state.energy, max_energy)
		if _enemy_state.gain_energy():
			SignalBus.energy_changed.emit("enemy", _enemy_state.energy, max_energy)
	# 更新当前正在积累的那一滴圣水的完成度（供 UI 平滑显示）
	var progress := (energy_timer / energy_interval) if _player_state.energy < max_energy else 0.0
	_player_state.energy_progress = progress
	SignalBus.player_energy_progress = progress


# ==============================================================================
# 出牌 / 部署
# ==============================================================================

## 选中手牌中指定索引的卡牌（再次点击同一张 = 取消选中）
func _select_hand_card(hand_index: int) -> void:
	if not battle_running:
		return
	var hand = deck_manager.get_hand()
	if hand_index >= hand.size():
		return
	var card_id = hand[hand_index]
	# 能量不足时不允许选中
	if not can_afford_card("player", card_id):
		print("[BattleManager] 能量不足:", card_id, "(需要", DataRegistry.get_card_data(card_id).get("cost", 0), "当前", _player_state.energy, ")")
		return
	# 再次点击同一张 = 取消
	if selected_hand_index == hand_index:
		selected_hand_index = -1
		if deploy_preview:
			deploy_preview.hide_preview()
		print("[BattleManager] 取消选中")
	else:
		selected_hand_index = hand_index
		if deploy_preview:
			deploy_preview.show_preview(DataRegistry.get_card_data(card_id))
		print("[BattleManager] 选手牌[%d]: %s" % [hand_index, card_id])
	# 通知 UI 更新高亮
	SignalBus.selection_changed.emit(selected_hand_index)


## 接收 CardSlot 点击信号，委托给 _select_hand_card 处理
func _on_card_selected(_card_id: String, hand_index: int) -> void:
	_select_hand_card(hand_index)


## 在指定位置部署当前选中的手牌
func _try_deploy(world_position: Vector2) -> void:
	if selected_hand_index < 0:
		return
	var hand = deck_manager.get_hand()
	var card_id = hand[selected_hand_index]
	var success = try_play_card(card_id, "player", world_position)
	if success:
		# 卡组轮转：打出的牌回队尾，下一张填补空位
		deck_manager.play_card(selected_hand_index)
		selected_hand_index = -1
		# 隐藏部署预览
		if deploy_preview:
			deploy_preview.hide_preview()
		# 通知 UI：清除选中高亮 + 刷新手牌
		SignalBus.selection_changed.emit(-1)
		SignalBus.hand_updated.emit(deck_manager.get_hand(), deck_manager.get_next())
		print("[BattleManager] 手牌:", deck_manager.get_hand(), " 下一张:", deck_manager.get_next())


## 取消当前选中
func _cancel_selection() -> void:
	if selected_hand_index >= 0:
		selected_hand_index = -1
		if deploy_preview:
			deploy_preview.hide_preview()
		SignalBus.selection_changed.emit(-1)
		print("[BattleManager] 取消选中")


## 通用出牌方法（玩家和敌方共用）。
## 返回 true 表示出牌成功，false 表示失败。
func try_play_card(card_id: String, team_name: String, world_position: Vector2) -> bool:
	if not battle_running:
		return false

	# 检查能量
	if not can_afford_card(team_name, card_id):
		return false

	var card := DataRegistry.get_card_data(card_id)
	var card_type: String = card.get("card_type", "")

	# 检查部署位置是否合法（法术可全图施放，单位受半场限制）
	if card_type == "spell":
		if not arena.is_spell_deploy_position(world_position):
			print("[BattleManager] 无效法术位置:", world_position)
			return false
	elif team_name == "player":
		if not arena.is_player_deploy_position(world_position):
			print("[BattleManager] 无效部署位置:", world_position)
			return false
	else:
		if not arena.is_enemy_deploy_position(world_position):
			return false

	# 按卡牌类型分流
	match card_type:
		"troop":
			var unit = spawn_manager.spawn_unit(card_id, team_name, world_position)
			if unit == null:
				return false
		"spell":
			if spell_manager:
				spell_manager.cast_spell(card_id, team_name, world_position)
			else:
				push_error("[BattleManager] SpellManager not found")
				return false
		_:
			push_error("[BattleManager] Unknown card_type: " + card_type)
			return false

	# 扣除能量
	spend_energy(team_name, int(card.get("cost", 0)))

	SignalBus.card_played.emit(card_id, team_name, world_position)
	print("[BattleManager] card played:", card_id, team_name, world_position)
	return true


# ==============================================================================
# 能量操作
# ==============================================================================

## 获取指定阵营的状态对象
func _get_state(team_name: String) -> PlayerBattleState:
	return _player_state if team_name == "player" else _enemy_state

## 判断某一方是否有足够能量打出指定卡牌
func can_afford_card(team_name: String, card_id: String) -> bool:
	var card = DataRegistry.get_card_data(card_id)
	if card.is_empty():
		return false
	var cost = int(card.get("cost", 999))
	return _get_state(team_name).can_spend(cost)


## 扣除能量
func spend_energy(team_name: String, amount: int) -> void:
	var state := _get_state(team_name)
	state.spend(amount)
	SignalBus.energy_changed.emit(team_name, state.energy, max_energy)


## 增加能量（调试用）
func add_energy(team_name: String, amount: int) -> void:
	var state := _get_state(team_name)
	state.energy = mini(max_energy, state.energy + amount)
	SignalBus.energy_changed.emit(team_name, state.energy, max_energy)
	print("[Cheat] %s energy +%d -> %d" % [team_name, amount, state.energy])


# ==============================================================================
# 胜负判定
# ==============================================================================

## 接收 SignalBus.tower_destroyed 信号
func _on_tower_destroyed(tower_id: String, team_name: String, tower_type: String) -> void:
	print("[BattleManager] tower destroyed:", tower_id, team_name, tower_type)
	if tower_type == "king":
		if team_name == "enemy":
			end_battle("victory")
		elif team_name == "player":
			end_battle("defeat")
	elif tower_type == "guard":
		# 公主塔被毁后激活同阵营的国王塔
		_activate_king_tower(team_name)


## 激活指定阵营的国王塔（公主塔被毁时触发）
func _activate_king_tower(team_name: String) -> void:
	for tower in _towers:
		if tower.team == team_name and tower.tower_type == "king" and not tower.is_dead:
			tower.activate_king()


# =============================================================================
# 时间限制与加时赛
# =============================================================================

## 每帧检查时间是否到限，触发阶段切换或胜负判定
func _check_time_limit() -> void:
	if battle_phase == "regular":
		if battle_time >= max_battle_time:
			var player_towers := _count_alive_towers("player")
			var enemy_towers := _count_alive_towers("enemy")
			if player_towers != enemy_towers:
				var result := "victory" if player_towers > enemy_towers else "defeat"
				end_battle(result)
			else:
				_enter_overtime()
	elif battle_phase == "overtime":
		if battle_time >= max_battle_time + overtime_duration:
			end_battle(_determine_result_by_stats())


## 进入加时赛：圣水加速，广播阶段变化
func _enter_overtime() -> void:
	battle_phase = "overtime"
	energy_interval = BASE_ENERGY_INTERVAL / overtime_energy_multiplier
	energy_timer = 0.0
	AudioManager.play("countdown_10s")
	SignalBus.battle_phase_changed.emit("overtime", overtime_duration)
	print("[BattleManager] overtime started (energy x%.1f)" % overtime_energy_multiplier)


## 统计指定阵营存活的塔数量
func _count_alive_towers(team_name: String) -> int:
	var count := 0
	for tower in _towers:
		if tower.team == team_name and not tower.is_dead:
			count += 1
	return count


## 计算指定阵营所有塔的总血量百分比（含已毁塔，分母为总 max_hp）
func _get_total_hp_percent(team_name: String) -> float:
	var total_hp := 0
	var total_max := 0
	for tower in _towers:
		if tower.team == team_name:
			total_hp += tower.current_hp
			total_max += tower.max_hp
	if total_max == 0:
		return 0.0
	return float(total_hp) / float(total_max)


## 时间到时的综合判定：塔数 → 总血量百分比 → 平局
func _determine_result_by_stats() -> String:
	var player_towers := _count_alive_towers("player")
	var enemy_towers := _count_alive_towers("enemy")
	if player_towers > enemy_towers:
		return "victory"
	elif enemy_towers > player_towers:
		return "defeat"
	# 塔数相同，比总血量百分比
	var player_pct := _get_total_hp_percent("player")
	var enemy_pct := _get_total_hp_percent("enemy")
	if player_pct > enemy_pct:
		return "victory"
	elif enemy_pct > player_pct:
		return "defeat"
	return "draw"


# ==============================================================================
# 输入处理
# ==============================================================================

## 处理输入（用 _unhandled_input：CardSlot 的 STOP mouse_filter 会消费点击，
## 使点击卡牌不会误触部署；点击战场区域则穿透到此处）
## 键 1-4：选中手牌 | 左键：部署 | 右键：取消 | R：重开 | G/H：加能量（调试）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_hand_card(0)
			KEY_2:
				_select_hand_card(1)
			KEY_3:
				_select_hand_card(2)
			KEY_4:
				_select_hand_card(3)
			KEY_R:
				restart_battle()
			KEY_G:
				add_energy("player", 1)
			KEY_H:
				add_energy("enemy", 1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if battle_running and selected_hand_index >= 0:
				# 通过 World 节点的逆变换获取游戏空间坐标（自动处理 Y 压缩 + 偏移）
				# 吸附到最近的格中心
				var world_pos: Vector2 = BattleConstants.snap_to_cell_center(world.get_local_mouse_position())
				_try_deploy(world_pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_selection()
