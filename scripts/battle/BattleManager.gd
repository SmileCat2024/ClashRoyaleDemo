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
var max_battle_time: float = 180.0       ## 常规时间（秒）
var battle_phase: String = "regular"      ## "regular" | "overtime"
var overtime_duration: float = 60.0       ## 极速 1 分钟 / 经典 2 分钟
var match_mode: int = Game.MatchMode.FAST_7X
var current_elixir_multiplier: int = 7

# ---- 能量系统 ----
var _player_state: PlayerBattleState = null
var _enemy_state: PlayerBattleState = null
var max_energy: int = 10
var energy_timer: float = 0.0
const CLASSIC_ENERGY_INTERVAL: float = 2.8
var base_energy_interval: float = CLASSIC_ENERGY_INTERVAL
var energy_interval: float = CLASSIC_ENERGY_INTERVAL / 7.0

# ---- 卡组管理 ----
var deck_manager: DeckManager = null
var selected_hand_index: int = -1  ## 当前选中的手牌索引（-1 = 未选中）

# ---- 联机状态 ----
var is_network_mode: bool = false  ## 是否联机模式
var is_host: bool = false          ## 是否是 host
var local_team: String = "player"  ## 本地玩家阵营
var _remote_deck: DeckManager = null  ## 远程玩家的卡组（仅 host 维护，跟踪 client 手牌轮转）
var _client_ready: bool = false    ## client 是否已加载完战斗场景
var _sync_timer: float = 0.0       ## 状态同步累计计时器
const SYNC_INTERVAL: float = 0.033  ## 状态同步间隔（秒，30Hz）
var _synced_unit_names: Dictionary = {}  ## 上次同步的单位名集合（client 端检测消失的单位用）
var _sync_node_cache: Dictionary = {}  ## Client 端 name→node 缓存，避免每次 RPC 重复 get_node_or_null

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
	# 读取联机状态
	is_network_mode = Game.network_mode
	is_host = (not is_network_mode) or NetworkManager.is_server()
	local_team = NetworkManager.local_team() if is_network_mode else "player"
	_configure_match_mode(Game.match_mode)
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
	# 联机断线处理
	if is_network_mode:
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
	# 初始化所有塔的属性
	_setup_towers()
	# 开始战斗
	start_battle()
	# Client 端：通知 host 已准备好
	if is_network_mode and not is_host:
		_rpc_client_ready.rpc_id(1)


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
				var tower_pos: Vector2 = BattleConstants.TOWER_PIXEL_POSITIONS[child.name]
				# Client 端塔位置镜像 + team 翻转（自己的塔在下方且为蓝方）
				if is_network_mode and not is_host:
					tower_pos = BattleConstants.mirror(tower_pos)
					team_name = "enemy" if team_name == "player" else "player"
				child.position = tower_pos
			child.setup(data, team_name, child.name)
			EntityRegistry.register(child)


## 开始一局战斗
func start_battle() -> void:
	battle_running = true
	battle_time = 0.0
	battle_phase = "regular"
	_set_elixir_multiplier(7 if match_mode == Game.MatchMode.FAST_7X else 1, false)
	_player_state.reset()
	_enemy_state.reset()
	energy_timer = 0.0
	selected_hand_index = -1

	if is_network_mode and is_host:
		# Host 联机：初始化自己 + 远程玩家的卡组
		deck_manager.setup(DataRegistry.get_default_player_deck())
		_remote_deck = DeckManager.new()
		_remote_deck.name = "RemoteDeck"
		add_child(_remote_deck)
		_remote_deck.setup(DataRegistry.get_default_enemy_deck())
		# 不启动 AI（远程玩家是真人）
	elif not is_network_mode:
		# 单机模式：初始化玩家卡组 + AI
		deck_manager.setup(DataRegistry.get_default_player_deck())
	else:
		# Client：手牌由 host 通过 RPC 同步，此处不初始化
		pass

	SignalBus.battle_started.emit()
	SignalBus.battle_phase_changed.emit("regular", max_battle_time)
	SignalBus.energy_changed.emit("player", _player_state.energy, max_energy)
	SignalBus.energy_changed.emit("enemy", _enemy_state.energy, max_energy)

	# 单机模式才 setup AI
	if not is_network_mode and enemy_ai and enemy_ai.has_method("setup"):
		enemy_ai.setup()

	# 延迟广播手牌状态，确保 CardBar 的 _ready 已连接信号
	# Client 联机：手牌由 host 通过 RPC 同步，此处不广播（避免闪烁空手牌）
	if not (is_network_mode and not is_host):
		call_deferred("_broadcast_hand_state")
	print("[BattleManager] battle started (network=%s host=%s mode=%s)" % [is_network_mode, is_host, match_mode])


## 向 UI 广播当前手牌和选中状态（延迟调用，确保 UI 已就绪）
func _broadcast_hand_state() -> void:
	SignalBus.hand_updated.emit(deck_manager.get_hand(), deck_manager.get_next())
	SignalBus.selection_changed.emit(selected_hand_index)


## 根据模式设置总时长与基础圣水恢复。联机 client 会由主机状态同步覆盖此配置。
func _configure_match_mode(mode: int) -> void:
	match_mode = mode
	if match_mode == Game.MatchMode.CLASSIC_1V1:
		max_battle_time = 180.0
		overtime_duration = 120.0
		base_energy_interval = CLASSIC_ENERGY_INTERVAL
	else:
		match_mode = Game.MatchMode.FAST_7X
		max_battle_time = 180.0
		overtime_duration = 60.0
		# 基础值始终是正常模式的 2.8 秒；x7 后才是 0.4 秒/点。
		base_energy_interval = CLASSIC_ENERGY_INTERVAL
	Game.set_match_mode(match_mode)


## 切换当前圣水倍率，并让 HUD 有机会更新右上角倍率提示。
func _set_elixir_multiplier(multiplier: int, emit_signal: bool = true) -> void:
	multiplier = max(multiplier, 1)
	var changed := current_elixir_multiplier != multiplier
	current_elixir_multiplier = multiplier
	energy_interval = base_energy_interval / float(current_elixir_multiplier)
	if emit_signal and changed:
		SignalBus.elixir_multiplier_changed.emit(current_elixir_multiplier)


## 经典 1v1：最后一分钟 x2、加时最后一分钟 x3；极速模式全程 x7。
func _update_match_timing() -> void:
	if match_mode == Game.MatchMode.FAST_7X:
		_set_elixir_multiplier(7)
		return
	var multiplier := 1
	if battle_phase == "regular" and battle_time >= max_battle_time - 60.0:
		multiplier = 2
	elif battle_phase == "overtime":
		multiplier = 3 if battle_time >= max_battle_time + overtime_duration - 60.0 else 2
	_set_elixir_multiplier(multiplier)


## 结束战斗
func end_battle(result: String) -> void:
	if not battle_running:
		return
	battle_running = false
	if deploy_preview:
		deploy_preview.hide_preview()
	SignalBus.battle_ended.emit(result)
	# 联机模式下 host 通知 client 战斗结果
	if is_network_mode and is_host:
		_rpc_battle_end.rpc(result)
	print("[BattleManager] battle ended:", result)


## 重新开始战斗（重载场景）
func restart_battle() -> void:
	SceneLoader.reload_current_scene()


func _process(delta: float) -> void:
	if not battle_running:
		return
	# Client 端：不跑战斗逻辑（时间/能量/碰撞由 host 同步）
	if is_network_mode and not is_host:
		return
	battle_time += delta
	_update_match_timing()
	update_energy(delta)
	_check_time_limit()
	# 碰撞分离：在所有单位移动之后统一执行（场景树顺序保证单位先于 Manager 执行 _process）
	CollisionSystem.resolve_overlaps(EntityRegistry.get_all_combatants())
	# Host 联机：定频同步状态给 client
	if is_network_mode and is_host:
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer = 0.0
			_sync_state_to_client()


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
	# 能量不足时不允许选中（联机模式下用 local_team 判断）
	if not can_afford_card(local_team, card_id):
		print("[BattleManager] 能量不足:", card_id, "(需要", DataRegistry.get_card_data(card_id).get("cost", 0), "当前", _get_state(local_team).energy, ")")
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

	# Client 联机：发 RPC 给 host，不在本地处理
	if is_network_mode and not is_host:
		_rpc_play_card.rpc_id(1, selected_hand_index, local_team, world_position)
		# 立即清除选中（体验上不等 RPC 往返）
		selected_hand_index = -1
		if deploy_preview:
			deploy_preview.hide_preview()
		SignalBus.selection_changed.emit(-1)
		return

	# Host / 单机：本地处理
	var success = try_play_card(card_id, local_team, world_position)
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

	# 检查部署位置是否合法
	# 法术可全图施放（含河道）；单位限己方半场且不可部署在建筑/塔上
	if not arena.is_cell_deployable(world_position, card_type == "spell", team_name):
		print("[BattleManager] 无效部署位置:", world_position)
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


## 进入加时赛：极速模式维持 x7；经典模式维持 x2，最后一分钟转 x3。
func _enter_overtime() -> void:
	battle_phase = "overtime"
	energy_timer = 0.0
	_update_match_timing()
	SignalBus.battle_phase_changed.emit("overtime", overtime_duration)
	print("[BattleManager] overtime started (energy x%d)" % current_elixir_multiplier)


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
				# 联机模式：只有 host 能重开，通过 RPC 让 client 也重开
				if is_network_mode:
					if is_host:
						_rpc_restart.rpc()
						restart_battle()
				else:
					restart_battle()
			KEY_G:
				# 联机 client 端：不能调试加能量（能量由 host 同步）
				if not (is_network_mode and not is_host):
					add_energy("player", 1)
			KEY_H:
				# 联机 client 端：不能调试加能量
				if not (is_network_mode and not is_host):
					add_energy("enemy", 1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if battle_running and selected_hand_index >= 0:
				# 通过 World 节点的逆变换获取游戏空间坐标（自动处理 Y 压缩 + 偏移）
				# 判断当前卡牌类型：法术全图含河道，单位限己方半场且避让建筑
				var hand = deck_manager.get_hand()
				var card_id = hand[selected_hand_index]
				var card = DataRegistry.get_card_data(card_id)
				var is_spell = (card.get("card_type") == "spell")
				# 吸附到最近合法格中心（出界/贴近建筑时自动锁定）
				# Client 端画面是 180 度镜像的：鼠标视觉坐标需逆镜像回逻辑坐标再做部署判定
				var raw_pos: Vector2 = world.get_local_mouse_position()
				if is_network_mode and not is_host:
					raw_pos = BattleConstants.mirror(raw_pos)
				var world_pos: Vector2 = arena.find_nearest_valid_deploy(
					raw_pos, is_spell, local_team)
				_try_deploy(world_pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_selection()


# ==============================================================================
# 联机 RPC（@rpc 方法）
# ==============================================================================

## Client → Host：通知已加载完战斗场景，准备好接收状态同步
@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready() -> void:
	_client_ready = true
	print("[BattleManager] client 已就绪，开始同步状态")
	# 立即同步一次完整状态
	_sync_state_to_client()
	if _remote_deck:
		var remote_hand := _remote_deck.get_hand()
		var remote_next := _remote_deck.get_next()
		_rpc_sync_hand.rpc(remote_hand, remote_next)


## Client → Host：请求出牌。hand_index 为 client 手牌索引。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_play_card(hand_index: int, team: String, world_position: Vector2) -> void:
	if not is_host:
		return
	# 远程玩家的 team 应为 enemy（与 host 的 remote_team 一致）
	if team != NetworkManager.remote_team():
		team = NetworkManager.remote_team()
	# 查找远程玩家手牌
	if _remote_deck == null:
		return
	var hand = _remote_deck.get_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_id = hand[hand_index]
	var success = try_play_card(card_id, team, world_position)
	if success:
		# 轮转远程玩家手牌
		_remote_deck.play_card(hand_index)
		# 同步新手牌给 client
		_rpc_sync_hand.rpc(_remote_deck.get_hand(), _remote_deck.get_next())
		print("[BattleManager] 远程玩家出牌:", card_id)


## Host → Client：同步手牌
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_hand(hand: Array, next_card: String) -> void:
	if is_host:
		return  # Host 自己不需要接收
	deck_manager.set_hand(hand, next_card)
	SignalBus.hand_updated.emit(hand, next_card)
	SignalBus.selection_changed.emit(-1)


## Host → Client：定频同步战斗状态（能量 + 时间 + 阶段 + 规则）。
@rpc("authority", "call_remote", "unreliable")
func _rpc_sync_state(p_energy: int, e_energy: int, p_progress: float, e_progress: float, time_val: float, phase_val: String, mode_val: int, multiplier_val: int) -> void:
	if is_host:
		return
	if match_mode != mode_val:
		_configure_match_mode(mode_val)
		SignalBus.battle_phase_changed.emit(phase_val, overtime_duration if phase_val == "overtime" else max_battle_time)
	_set_elixir_multiplier(multiplier_val)
	# Client 视角翻转：自己(player)=host 的 enemy；敌方(enemy)=host 的 player
	_player_state.energy = e_energy
	_enemy_state.energy = p_energy
	SignalBus.energy_changed.emit("player", e_energy, max_energy)
	SignalBus.energy_changed.emit("enemy", p_energy, max_energy)
	SignalBus.player_energy_progress = e_progress
	# 更新时间
	battle_time = time_val
	# 阶段切换
	if battle_phase != phase_val:
		battle_phase = phase_val
		if phase_val == "overtime":
			SignalBus.battle_phase_changed.emit("overtime", overtime_duration)
	# 更新圣水条进度（client 自己 = host 的 enemy）
	_player_state.energy_progress = e_progress


## Host → Client：战斗结束
@rpc("authority", "call_remote", "reliable")
func _rpc_battle_end(result: String) -> void:
	if is_host:
		return
	end_battle(result)


## Host 端调用：打包当前状态发送给 client
func _sync_state_to_client() -> void:
	if not is_host or not _client_ready:
		return
	var p_progress := _player_state.energy_progress
	var e_progress := _enemy_state.energy_progress
	_rpc_sync_state.rpc(
		_player_state.energy,
		_enemy_state.energy,
		p_progress,
		e_progress,
		battle_time,
		battle_phase,
		match_mode,
		current_elixir_multiplier
	)
	# 单次遍历收集单位状态 + 光束状态（合并避免双遍历）
	var unit_states: Array = []
	var beam_states: Array = []
	for child in units_root.get_children():
		if not (child is CombatantBase) or not child.initialized:
			continue
		unit_states.append([child.name, child.position.x, child.position.y,
			child.current_hp, child.current_shield, child.is_dead])
		# 地狱塔光束：beam_emit_offset_y != 0 的单位有光束能力
		if child is UnitBase and child.beam_emit_offset_y != 0.0:
			var attack = child.get_primary_attack()
			if attack != null and attack.has_method("has_beam_target"):
				var b_active: bool = attack.has_beam_target()
				var b_target := Vector2.ZERO
				var b_stage := 0
				if b_active:
					var bt = attack.get_beam_target()
					if bt and is_instance_valid(bt):
						b_target = BattlePathing.game_position_of(bt)
					b_stage = attack.get_ramp_stage_index()
				beam_states.append([child.name, b_active, b_target.x, b_target.y, b_stage])
	_rpc_sync_units.rpc(unit_states)
	if not beam_states.is_empty():
		_rpc_sync_beams.rpc(beam_states)


## Host → Client：定频同步地狱塔光束状态。
## 数据格式：Array of [name, active, target_x, target_y, stage]
@rpc("authority", "call_remote", "unreliable")
func _rpc_sync_beams(states: Array) -> void:
	if is_host:
		return
	for s in states:
		var unit_name: String = s[0]
		var active: bool = s[1]
		# 光束目标位置镜像（与单位/塔位置镜像一致）
		var target_pos := BattleConstants.mirror(Vector2(s[2], s[3]))
		var stage: int = s[4]
		var unit = units_root.get_node_or_null(unit_name)
		if unit is UnitBase:
			unit.update_beam_from_sync(active, target_pos, stage)


## Host → Client：定频同步所有单位/塔状态。替代 MultiplayerSynchronizer 的手动方案。
## 数据格式：Array of [name, x, y, hp, shield, is_dead]
@rpc("authority", "call_remote", "unreliable")
func _rpc_sync_units(states: Array) -> void:
	if is_host:
		return
	var current_names: Dictionary = {}
	for s in states:
		var unit_name: String = s[0]
		current_names[unit_name] = true
		# 缓存查节点：避免每个 RPC 包重复 get_node_or_null 字符串匹配
		var unit = _sync_node_cache.get(unit_name, null)
		if unit == null or not is_instance_valid(unit):
			unit = units_root.get_node_or_null(unit_name)
			if unit == null:
				continue
			_sync_node_cache[unit_name] = unit
		# 镜像位置（180 度旋转，让 client 看到自己的塔在下方）
		var mirrored_pos := BattleConstants.mirror(Vector2(s[1], s[2]))
		# 单位用插值目标位置（_process 里 lerp 平滑过渡，消除卡顿）；
		# 塔静止不动，直接设 position。
		if unit is UnitBase:
			# 计算外推速度（最近两个同步包的位移 / 同步间隔），供丢包时位置外推
			if unit._sync_pos_init:
				unit._sync_velocity = (mirrored_pos - unit._sync_target_pos) / SYNC_INTERVAL
			unit._last_sync_target = unit._sync_target_pos
			unit._sync_target_pos = mirrored_pos
			unit._sync_time_since_update = 0.0
			if not unit._sync_pos_init:
				unit.position = mirrored_pos
				unit._last_sync_target = mirrored_pos
				unit._sync_pos_init = true
		else:
			unit.position = mirrored_pos
		unit.current_hp = int(s[3])
		unit.current_shield = int(s[4])
		# 死亡同步（触发 _on_remote_death 播放死亡视觉）
		if s[5] and not unit.is_dead:
			unit.is_dead = true
		# 国王塔激活检测：hp 低于上限说明已受击
		if unit is TowerBase and unit.tower_type == "king" and not unit.king_activated:
			if unit.current_hp < unit.max_hp:
				unit.activate_king()
	# 检测从同步中消失的单位（host 端已死亡/释放）→ 标记死亡触发视觉 + 清理缓存
	for prev_name in _synced_unit_names:
		if not current_names.has(prev_name):
			var unit = _sync_node_cache.get(prev_name, null)
			if unit == null or not is_instance_valid(unit):
				unit = units_root.get_node_or_null(prev_name)
			if unit and not unit.is_dead:
				unit.is_dead = true
			_sync_node_cache.erase(prev_name)
	_synced_unit_names = current_names


## Host → Client：通知重开（R 键联机同步）
@rpc("authority", "call_remote", "reliable")
func _rpc_restart() -> void:
	if is_host:
		return
	restart_battle()


# =============================================================================
# 联机断线处理
# =============================================================================

## Host 端：Client 断线（掉线/退出）
func _on_peer_disconnected(_peer_id: int) -> void:
	if not is_host or not battle_running:
		return
	print("[BattleManager] 对手断线，结束战斗")
	end_battle("disconnect")

## Client 端：与 Host 的连接断开
func _on_server_disconnected() -> void:
	if is_host or not battle_running:
		return
	print("[BattleManager] 与主机断开连接")
	end_battle("disconnect")
