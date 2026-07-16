# 文件名：AudioManager.gd
# 作用：全局音频管理。集中处理所有 SFX（音效）和 BGM（背景音乐）的播放、
#       音量控制、静音切换。数据驱动——所有音效配置在 DataRegistry.sound_data，
#       新增音效只需加一行配置 + 放入资源文件，无需改本脚本。
#
#       自动监听 SignalBus 通用信号驱动部署/塔摧毁/飞行物发射+命中/战斗流程音效；
#       单位专属音效（如攻击音、死亡音）由调用方通过 play_unit_sfx() 主动触发，
#       这样能携带 unit_id 选择不同音效（骑士挥剑 vs 法师施法）。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册（须在 DataRegistry / SignalBus 之后）。
# 初学者阅读建议：先看 play() 和 play_unit_sfx() 了解如何播放音效，
#       再看 _ready() 了解总线创建和信号自动绑定，最后看 _connect_signals() 了解哪些事件是自动驱动的。

extends Node

# ---- 音频总线名 ----
const BUS_MASTER := "Master"
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"

# ---- SFX 播放器池 ----
# 预创建固定数量的 AudioStreamPlayer 轮转复用，避免每次播放都 instantiate。
# 池满时复用最旧的播放器（打断其当前播放）。
const SFX_POOL_SIZE := 16
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0

# ---- BGM 播放器 ----
var _bgm_player: AudioStreamPlayer = null
var _bgm_fade_tween: Tween = null
var _current_bgm_id: String = ""

# ---- 资源缓存 ----
var _stream_cache: Dictionary = {}   ## path → AudioStream（加载成功才入缓存）
var _missing_paths: Dictionary = {}  ## path → true（已尝试加载失败，不重试，避免反复查盘）

# ---- 并发计数 ----
# 每个 event_id 当前正在播放的数量，用于 max_polyphony 限制（避免多个单位同时攻击时嘈杂）。
var _active_counts: Dictionary = {}  ## event_id → int

# ---- 音量（dB，相对总线）----
var _master_volume_db: float = 0.0
var _bgm_volume_db: float = -6.0
var _sfx_volume_db: float = 0.0
var _muted: bool = false

# ---- Web 音频解锁 ----
# 浏览器 autoplay policy 阻止页面加载时自动播放音频，
# 首次用户交互后才恢复。此标志跟踪是否已解锁。
var _web_audio_unlocked: bool = false


func _ready() -> void:
	_ensure_buses()
	_setup_sfx_pool()
	_setup_bgm_player()
	_apply_volumes()
	_connect_signals()
	print("[AudioManager] initialized | SFX pool: %d | events: %d | bgm: %d" % [
		_sfx_pool.size(),
		DataRegistry.sound_data.size(),
		DataRegistry.bgm_data.size(),
	])


func _unhandled_input(event: InputEvent) -> void:
	# Web 平台：首次用户交互后恢复被浏览器 autoplay policy 阻止的 BGM
	if not _web_audio_unlocked:
		_web_audio_unlocked = true
		_resume_bgm_if_needed()
	# M 键切换静音（避开 F 键，F 键在很多环境下被系统拦截）
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			toggle_mute()


## Web 平台音频恢复。浏览器 autoplay policy 会阻止页面加载时的自动音频播放，
## 首次用户交互（点击/触摸/按键）后音频上下文恢复。此时重播被错过的 BGM。
## 非 Web 平台上，BGM 已在正常播放则不会重播，无副作用。
func _resume_bgm_if_needed() -> void:
	if _current_bgm_id != "" and not _bgm_player.playing:
		_bgm_player.play()


# ==============================================================================
# 总线初始化
# ==============================================================================

## 程序化创建 BGM/SFX 总线（如果不存在）。无需手动在 project.godot 配置 AudioServer。
func _ensure_buses() -> void:
	# Master 总线由引擎默认创建（index 0）
	if AudioServer.get_bus_index(BUS_BGM) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, BUS_BGM)
		AudioServer.set_bus_send(idx, BUS_MASTER)
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, BUS_SFX)
		AudioServer.set_bus_send(idx, BUS_MASTER)


func _setup_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		# 自然播放结束时减少并发计数（stop() 不触发 finished，由 _next_sfx_player 手动处理）
		p.finished.connect(_on_sfx_finished.bind(i))
		_sfx_pool.append(p)


func _setup_bgm_player() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = BUS_BGM
	add_child(_bgm_player)


## 应用当前音量设置到三条总线
func _apply_volumes() -> void:
	var master_idx := AudioServer.get_bus_index(BUS_MASTER)
	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	var sfx_idx := AudioServer.get_bus_index(BUS_SFX)
	# 静音时把 Master 拉到 -80dB（而非 mute 总线，保留信号通路方便恢复）
	if master_idx != -1:
		AudioServer.set_bus_volume_db(master_idx, _master_volume_db if not _muted else -80.0)
	if bgm_idx != -1:
		AudioServer.set_bus_volume_db(bgm_idx, _bgm_volume_db)
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, _sfx_volume_db)


# ==============================================================================
# 信号自动驱动
# ==============================================================================

## 连接 SignalBus 通用信号，自动驱动对应音效事件。
## 单位专属音效（攻击/死亡）不在此绑定——由调用方通过 play_unit_sfx() 主动触发，
## 这样能根据 unit_id 选择不同音效。
func _connect_signals() -> void:
	SignalBus.battle_started.connect(_on_battle_started)
	SignalBus.battle_ended.connect(_on_battle_ended)
	SignalBus.card_played.connect(_on_card_played)
	SignalBus.tower_destroyed.connect(_on_tower_destroyed)
	SignalBus.projectile_spawned.connect(_on_projectile_spawned)
	SignalBus.projectile_hit.connect(_on_projectile_hit)
	SignalBus.elixir_generated.connect(_on_elixir_generated)
	SignalBus.card_selected.connect(_on_card_selected)


func _on_battle_started() -> void:
	play("battle_start")
	play_bgm("battle")


func _on_battle_ended(result: String) -> void:
	# result: "victory" / "defeat" / "draw"
	if result == "victory" or result == "defeat":
		play(result)
		play_bgm(result)
	else:
		stop_bgm()


func _on_card_selected(_card_id: String, _hand_index: int) -> void:
	play("card_select")


func _on_card_played(card_id: String, _team: String, _pos: Vector2, is_awakened: bool = false) -> void:
	var card := DataRegistry.get_card_data(card_id)
	var card_type: String = card.get("card_type", "")
	if card_type == "spell":
		play("deploy_spell", _pos)
		return
	# 觉醒部署音效属于卡牌变体，不应覆盖普通版单位的部署音效。
	if is_awakened:
		var awakened_deploy_sfx: String = card.get("awakening_deploy_sfx", "")
		if awakened_deploy_sfx != "":
			play(awakened_deploy_sfx, _pos)
			return
	# troop / building：尝试单位专属部署音，未配置时回退到通用 deploy
	var unit_id: String = card.get("unit_id", "")
	if unit_id != "":
		var sfx_map := DataRegistry.get_unit_sfx(unit_id)
		if sfx_map.has("deploy"):
			play(sfx_map["deploy"], _pos)
			_schedule_unit_deploy_end(unit_id, _pos)
			# 角色语音与部署 Foley 分层播放；未配置时不产生额外声音。
			if sfx_map.has("deploy_voice"):
				play_unit_sfx(unit_id, "deploy_voice", _pos)
			return
	play("deploy", _pos)


## 部署结束音紧随其对应起手 Foley 的实际时长播放。
## 不写死秒数，因此替换部署资源后仍能保持自然衔接；未配置 deploy_end 时静默跳过。
func _schedule_unit_deploy_end(unit_id: String, world_pos: Vector2) -> void:
	var sfx_map := DataRegistry.get_unit_sfx(unit_id)
	var end_value = sfx_map.get("deploy_end", "")
	var start_value = sfx_map.get("deploy", "")
	if end_value == "" or not (start_value is String):
		return
	var start_cfg := DataRegistry.get_sound_data(start_value)
	var start_path: String = start_cfg.get("stream", "")
	if start_path == "":
		return
	var stream := _load_stream(start_path)
	if stream == null:
		return
	var delay := stream.get_length()
	if delay <= 0.0:
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(delay).timeout.connect(func():
		play_unit_sfx(unit_id, "deploy_end", world_pos)
	)


func _on_tower_destroyed(_tower_id: String, _team: String, tower_type: String) -> void:
	if tower_type == "king":
		play("king_tower_destroyed")
	else:
		play("tower_destroyed")


func _on_projectile_spawned(_projectile: Node2D, _team: String) -> void:
	play("projectile_launch")


func _on_projectile_hit(_pos: Vector2, _team: String) -> void:
	play("projectile_hit")


## 圣水收集器每次产出（含死亡返还）播放其专属收集反馈。
func _on_elixir_generated(pos: Vector2, _team: String, _amount: int, _is_death: bool) -> void:
	play_unit_sfx("elixir_collector", "collect", pos)


# ==============================================================================
# SFX 播放 API
# ==============================================================================

## 播放一个音效事件。
## event_id: DataRegistry.sound_data 中的事件 key（如 "deploy"、"projectile_hit"）
## world_pos: 可选，事件发生位置（World 本地游戏空间）。
##            当前版本暂未实现 2D 距离衰减，参数保留供未来扩展近大远小效果。
##            传 Vector2.ZERO 或省略表示全局音效。
## opts: 可选覆盖项 { "volume_db": float, "pitch_scale": float }，临时调整不影响数据表配置
func play(event_id: String, world_pos: Vector2 = Vector2.ZERO, opts: Dictionary = {}) -> void:
	var cfg := DataRegistry.get_sound_data(event_id)
	if cfg.is_empty():
		return  # 未知事件 id，静默跳过（可能是资源尚未配置）
	# 可选概率门控：角色语音等装饰性音效可避免每次动作都重复播放。
	if randf() > float(cfg.get("chance", 1.0)):
		return
	var stream_path: String = cfg.get("stream", "")
	if stream_path == "":
		return  # 资源未上线，静默跳过
	var stream := _load_stream(stream_path)
	if stream == null:
		return
	# 并发控制：超过 max_polyphony 时丢弃新的（避免多个单位同时攻击时嘈杂）
	var max_poly: int = int(cfg.get("max_polyphony", 4))
	var active: int = int(_active_counts.get(event_id, 0))
	if active >= max_poly:
		return
	# 优先级（数字越大越优先）。池子满时低优先级新音效不会抢占正在播放的高优先级音效。
	var priority: int = int(cfg.get("priority", 5))
	# 获取播放器（优先空闲，否则按 priority 抢占；找不到可用则丢弃此次播放）
	var player := _next_sfx_player(priority)
	if player == null:
		return
	player.set_meta("sfx_event_id", event_id)
	player.set_meta("sfx_priority", priority)
	# 配置
	player.stream = stream
	player.volume_db = float(cfg.get("volume_db", 0.0)) + float(opts.get("volume_db", 0.0))
	# 音调随机化（让重复音效不单调）
	var pitch_range: Array = cfg.get("pitch_range", [1.0, 1.0])
	var pitch_min: float = float(pitch_range[0])
	var pitch_max: float = float(pitch_range[1])
	var pitch: float = randf_range(pitch_min, pitch_max) if pitch_max > pitch_min else pitch_min
	player.pitch_scale = pitch * float(opts.get("pitch_scale", 1.0))
	# 计数 + 播放
	_active_counts[event_id] = active + 1
	player.play()


## 播放单位专属音效。
## unit_id: 单位 id（查 DataRegistry.unit_data[unit_id].sfx）
## sfx_key: 单位 sfx 字典中的 key（如 "attack" / "death"），值为 sound_data 中的事件 id
## world_pos: 可选，事件发生位置
## 单位未配置 sfx 字段或 sfx_key 不存在时静默跳过。
## 用法示例（在 AttackComponent._execute_attack 中）：
##   AudioManager.play_unit_sfx(combatant.unit_id, "attack", BattlePathing.game_position_of(combatant))
func play_unit_sfx(unit_id: String, sfx_key: String, world_pos: Vector2 = Vector2.ZERO) -> void:
	var sfx_map := DataRegistry.get_unit_sfx(unit_id)
	if sfx_map.is_empty():
		return
	var event_value = sfx_map.get(sfx_key, "")
	var event_id := ""
	# 同一动作可配置多个等价 Foley 变体，随机选择一个而不是叠加播放。
	if event_value is Array:
		if event_value.is_empty():
			return
		event_id = str(event_value.pick_random())
	else:
		event_id = str(event_value)
	if event_id == "":
		return
	play(event_id, world_pos)


## SFX 自然播放结束回调：减少对应 event_id 的并发计数
func _on_sfx_finished(pool_index: int) -> void:
	_decrement_count(_sfx_pool[pool_index])


## 减少播放器对应事件的并发计数并清除元数据
func _decrement_count(player: AudioStreamPlayer) -> void:
	var event_id = player.get_meta("sfx_event_id", "")
	if event_id == "":
		return
	var active: int = int(_active_counts.get(event_id, 0))
	if active > 0:
		active -= 1
		if active == 0:
			_active_counts.erase(event_id)
		else:
			_active_counts[event_id] = active
	player.remove_meta("sfx_event_id")


## 获取下一个 SFX 播放器（兑现 priority 字段的抢占规则）。
## 1) 优先复用空闲播放器；
## 2) 全部忙碌时，按 round-robin 抢占当前播放音效 priority 不高于新音效的播放器；
## 3) 找不到可抢占目标返回 null（调用方丢弃此次播放）。
## 这样高优先级长音效（如倒计时 priority=8）不会被激战时的低优先级短音效截断。
## stop() 不触发 finished 信号，所以手动调用 _decrement_count 维持计数准确。
func _next_sfx_player(new_priority: int) -> AudioStreamPlayer:
	# 1) 优先找空闲播放器（从 round-robin 起点扫描，保持池内热度均衡）
	for i in range(_sfx_pool.size()):
		var idx := (_sfx_pool_index + i) % _sfx_pool.size()
		var p_idle := _sfx_pool[idx]
		if not p_idle.playing:
			_sfx_pool_index = (idx + 1) % _sfx_pool.size()
			return p_idle
	# 2) 全部忙碌：找一个当前 priority 不高于新音效的可抢占目标
	for i in range(_sfx_pool.size()):
		var idx := (_sfx_pool_index + i) % _sfx_pool.size()
		var p_busy := _sfx_pool[idx]
		var cur_priority := int(p_busy.get_meta("sfx_priority", 1))
		if cur_priority <= new_priority:
			_sfx_pool_index = (idx + 1) % _sfx_pool.size()
			p_busy.stop()
			_decrement_count(p_busy)
			return p_busy
	# 3) 所有播放器都在播更高优先级音效：丢弃新音效
	return null


# ==============================================================================
# BGM 控制
# ==============================================================================

## 播放背景音乐。如果已有 BGM 在播放，淡出旧的再淡入新的。
## bgm_id: DataRegistry.bgm_data 中的 key
## fade_sec: 淡入时间（秒），0 = 立即播放
func play_bgm(bgm_id: String, fade_sec: float = 0.5) -> void:
	if bgm_id == _current_bgm_id and _bgm_player.playing:
		return  # 同一首正在播放，不重启
	var cfg := DataRegistry.get_bgm_data(bgm_id)
	if cfg.is_empty():
		push_warning("[AudioManager] Unknown bgm id: " + bgm_id)
		return
	var stream_path: String = cfg.get("stream", "")
	if stream_path == "":
		# BGM 资源未配置，停掉当前 BGM
		stop_bgm(fade_sec)
		return
	var stream := _load_stream(stream_path)
	if stream == null:
		stop_bgm(fade_sec)
		return
	# 尝试开启循环（取决于资源类型）
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	# kill 旧淡入淡出
	if _bgm_fade_tween and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	var target_vol: float = float(cfg.get("volume_db", 0.0))
	_bgm_player.stream = stream
	_current_bgm_id = bgm_id
	if fade_sec > 0.0:
		_bgm_player.volume_db = -80.0
		_bgm_fade_tween = create_tween()
		_bgm_fade_tween.tween_property(_bgm_player, "volume_db", target_vol, fade_sec)
	else:
		_bgm_player.volume_db = target_vol
	_bgm_player.play()


## 停止 BGM（带淡出）
func stop_bgm(fade_sec: float = 0.5) -> void:
	if not _bgm_player.playing and _current_bgm_id == "":
		return
	if _bgm_fade_tween and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	if fade_sec > 0.0:
		_bgm_fade_tween = create_tween()
		_bgm_fade_tween.tween_property(_bgm_player, "volume_db", -80.0, fade_sec)
		_bgm_fade_tween.tween_callback(_on_bgm_fade_out_done)
	else:
		_bgm_player.stop()
		_current_bgm_id = ""


func _on_bgm_fade_out_done() -> void:
	_bgm_player.stop()
	_current_bgm_id = ""


# ==============================================================================
# 资源加载
# ==============================================================================

## 加载 AudioStream 资源（带缓存）。路径不存在或加载失败返回 null，静默处理。
func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if _missing_paths.has(path):
		return null
	if not ResourceLoader.exists(path):
		_missing_paths[path] = true
		return null
	var res = load(path)
	if res is AudioStream:
		_stream_cache[path] = res
		return res
	_missing_paths[path] = true
	push_warning("[AudioManager] 资源不是 AudioStream: " + path)
	return null


# ==============================================================================
# 音量 / 静音控制
# ==============================================================================

## 设置主音量（dB）
func set_master_volume(db: float) -> void:
	_master_volume_db = db
	_apply_volumes()


## 设置 BGM 音量（dB）
func set_bgm_volume(db: float) -> void:
	_bgm_volume_db = db
	_apply_volumes()


## 设置 SFX 音量（dB）
func set_sfx_volume(db: float) -> void:
	_sfx_volume_db = db
	_apply_volumes()


## 切换静音状态。返回切换后的静音状态。
func toggle_mute() -> bool:
	_muted = not _muted
	_apply_volumes()
	print("[AudioManager] muted: ", _muted)
	return _muted


## 当前是否静音
func is_muted() -> bool:
	return _muted


## 获取当前正在播放的某事件 SFX 数量（调试用）
func get_active_count(event_id: String) -> int:
	return int(_active_counts.get(event_id, 0))


## 当前播放的 BGM id
func get_current_bgm() -> String:
	return _current_bgm_id
