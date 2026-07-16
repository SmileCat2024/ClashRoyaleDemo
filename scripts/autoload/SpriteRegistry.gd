# 文件名：SpriteRegistry.gd
# 作用：全局精灵帧缓存。按 unit_id 从 DataRegistry 动画配置构建 SpriteFrames，
#       加载 assets/sprites/{unit_id}/ 下的 PNG 序列帧，构建后缓存。
#       找不到 PNG 或无动画配置时返回 null（触发 ColorRect 兜底）。
#
#       团队色区分机制（首次引入，迫击炮为首例）：
#         states 内每个 state 的 frames 字段支持两种形式：
#           1) 数组 ["a.png", "b.png"]  —— 中性贴图，所有队伍共用（默认）
#           2) 字典 {"player":[...], "enemy":[...]} —— 红蓝双套贴图，按 team 取帧
#         用字典形式时，get_sprite_frames 必须传 team，缓存键为 "unit_id:team"。
#         不是每个单位都需要团队色：仅美术提供了红/蓝两套贴图时才用字典形式。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：先看 get_sprite_frames() 了解缓存查询，
#       再看 _build_sprite_frames() 了解 PNG 怎么加载成 SpriteFrames。

extends Node

signal sprite_frames_ready(unit_id: String, team: String, frames: SpriteFrames)

# 序列帧导入缓存统一按原图 1/3 线性尺寸生成；渲染时乘回 3 倍，保持屏幕视觉尺寸不变。
# 原始 PNG 不会被修改。单帧展开内存约降为原来的 1/9。
const OPTIMIZED_IMPORT_RENDER_SCALE := 3.0
const BACKGROUND_FINALIZE_FRAME_SECONDS := 1.0 / 55.0

# 缓存："unit_id:team" → SpriteFrames（构建成功才入缓存）
var _frames_cache: Dictionary = {}

# 记录已尝试加载的 "unit_id:team"，避免重复尝试
var _load_attempted: Dictionary = {}

# 加载页通过 ResourceLoader 后台线程预取的资源。持有强引用，确保场景切换后仍命中缓存。
var _preloaded_resources: Dictionary = {}

# 战斗内低干扰续载：始终只运行一个 ResourceLoader 后台任务，且禁用会抢占主线程的子线程。
var _background_jobs: Array[Dictionary] = []
var _background_current: Dictionary = {}
var _queued_frame_sets: Dictionary = {}


func _process(delta: float) -> void:
	_process_background_loading(delta)


## 获取指定单位在指定阵营下的 SpriteFrames。
## team 默认 "player"（DeployPreview 等无明确阵营的预览场景用）。
## 返回 null 表示无动画数据或 PNG 加载失败。
func get_sprite_frames(unit_id: String, team: String = "player") -> SpriteFrames:
	var cache_key := unit_id + ":" + team
	# 已缓存 → 直接返回
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key]

	# 已尝试过且失败 → 不再重试
	if _load_attempted.has(cache_key):
		return null

	_load_attempted[cache_key] = true

	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	var anim_data: Dictionary = unit_data.get("animation", {})
	if anim_data.is_empty():
		return null

	var frames: SpriteFrames = _build_sprite_frames(unit_id, anim_data, team)
	if frames != null:
		_frames_cache[cache_key] = frames
		print("[SpriteRegistry] loaded sprite frames: %s (%s) (%d animations)" % [
			unit_id, team, frames.get_animation_names().size()
		])
	return frames


## 判断指定单位是否有动画配置字段（不代表 PNG 一定存在）。
func has_animation_config(unit_id: String) -> bool:
	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	return unit_data.has("animation") and not unit_data["animation"].is_empty()


## 判断指定单位是否使用团队色双套贴图（states 内任意 state 的 frames 为字典形式）。
## SpriteAnimator 据此跳过中性色调微调，保持红蓝贴图原色。
func is_team_colored(unit_id: String) -> bool:
	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	var anim_data: Dictionary = unit_data.get("animation", {})
	var states: Dictionary = anim_data.get("states", {})
	for state_name in states:
		var state_cfg: Dictionary = states[state_name]
		if state_cfg.get("frames", []) is Dictionary:
			return true
	return false


## 返回构建指定单位帧缓存所需的全部纹理路径（去重）。供加载页异步预取。
func get_texture_paths(unit_id: String, team: String = "player") -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	var anim_data: Dictionary = unit_data.get("animation", {})
	var sprite_dir: String = anim_data.get("sprite_dir", unit_id)
	var base_path := "res://assets/sprites/" + sprite_dir + "/"
	var states: Dictionary = anim_data.get("states", {})
	for state_name in states:
		var state_cfg: Dictionary = states[state_name]
		var frames_raw = state_cfg.get("frames", [])
		var frame_files: Array = frames_raw.get(team, []) if frames_raw is Dictionary else frames_raw
		for file_name in frame_files:
			var path := base_path + String(file_name)
			if not seen.has(path) and ResourceLoader.exists(path):
				seen[path] = true
				result.append(path)
	return result


## 接收加载页完成的异步资源并持有引用。SpriteRegistry 后续 load(path) 会直接命中资源缓存。
func retain_preloaded_resource(path: String, resource: Resource) -> void:
	if resource != null:
		_preloaded_resources[path] = resource


func has_preloaded_resource(path: String) -> bool:
	return _preloaded_resources.has(path)


## 返回已经构建完成的帧，不触发任何同步加载。战斗实体必须优先使用此接口。
func get_cached_sprite_frames(unit_id: String, team: String = "player") -> SpriteFrames:
	return _frames_cache.get(unit_id + ":" + team, null)


## 高清原图经导入缓存缩小后，在节点缩放上补回尺寸，画面大小保持不变。
func get_render_scale(visual_scale: float) -> float:
	return visual_scale * OPTIMIZED_IMPORT_RENDER_SCALE


## 将一套单位动画加入战斗内续载队列。重复请求、已经完成的请求会自动忽略。
func queue_sprite_frames(unit_id: String, team: String = "player") -> void:
	var key := unit_id + ":" + team
	if _frames_cache.has(key) or _queued_frame_sets.has(key):
		return
	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	if unit_data.get("animation", {}).is_empty():
		return
	_queued_frame_sets[key] = true
	_background_jobs.append({
		"key": key,
		"unit_id": unit_id,
		"team": team,
		"paths": get_texture_paths(unit_id, team),
		"index": 0,
		"active_path": "",
	})


func _process_background_loading(delta: float) -> void:
	if _background_current.is_empty():
		if _background_jobs.is_empty():
			return
		_background_current = _background_jobs.pop_front()
		return

	var paths: Array = _background_current["paths"]
	var index: int = int(_background_current["index"])
	var active_path: String = _background_current["active_path"]

	if active_path.is_empty():
		if index >= paths.size():
			# SpriteFrames 组装本身很轻，但仍只在上一帧平稳时执行，避免与战斗尖峰叠加。
			if delta <= BACKGROUND_FINALIZE_FRAME_SECONDS:
				_finish_background_frame_set()
			return
		var path: String = paths[index]
		if _preloaded_resources.has(path):
			_background_current["index"] = index + 1
			return
		if ResourceLoader.has_cached(path):
			var cached := ResourceLoader.get_cached_ref(path)
			if cached is Resource:
				retain_preloaded_resource(path, cached)
			_background_current["index"] = index + 1
			return
		# false：只使用 ResourceLoader 自身的单个后台线程，避免多核解码挤占游戏主线程。
		var err := ResourceLoader.load_threaded_request(path, "", false)
		if err == OK or err == ERR_BUSY:
			_background_current["active_path"] = path
		else:
			push_warning("[SpriteRegistry] 后台预取请求失败: %s (%d)" % [path, err])
			_background_current["index"] = index + 1
		return

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(active_path, progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		# 收取资源可能触发纹理提交；卡帧时继续等待，且每帧最多收取一张。
		if delta > BACKGROUND_FINALIZE_FRAME_SECONDS:
			return
		var resource := ResourceLoader.load_threaded_get(active_path)
		if resource is Resource:
			retain_preloaded_resource(active_path, resource)
		_background_current["index"] = index + 1
		_background_current["active_path"] = ""
	elif status == ResourceLoader.THREAD_LOAD_FAILED \
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_warning("[SpriteRegistry] 后台预取失败: " + active_path)
		_background_current["index"] = index + 1
		_background_current["active_path"] = ""


func _finish_background_frame_set() -> void:
	var unit_id: String = _background_current["unit_id"]
	var team: String = _background_current["team"]
	var key: String = _background_current["key"]
	var frames := get_sprite_frames(unit_id, team)
	_queued_frame_sets.erase(key)
	_background_current = {}
	sprite_frames_ready.emit(unit_id, team, frames)


## 从动画配置和 PNG 文件构建 SpriteFrames。
## team 用于团队色帧选择（frames 为字典时取对应阵营帧）。
## 成功返回带动画的 SpriteFrames；无可用帧返回 null。
func _build_sprite_frames(unit_id: String, anim_data: Dictionary, team: String) -> SpriteFrames:
	var sprite_dir: String = anim_data.get("sprite_dir", unit_id)
	var states: Dictionary = anim_data.get("states", {})
	if states.is_empty():
		return null

	var frames := SpriteFrames.new()
	var base_path := "res://assets/sprites/" + sprite_dir + "/"
	var any_loaded := false

	for state_name in states:
		var state_cfg: Dictionary = states[state_name]
		# frames 支持两种形式：数组（中性）或字典（红蓝双套，按 team 取）
		var frames_raw = state_cfg.get("frames", [])
		var frame_files: Array
		if frames_raw is Dictionary:
			frame_files = frames_raw.get(team, [])
		else:
			frame_files = frames_raw
		if frame_files.is_empty():
			continue

		# 逐帧加载 PNG
		var textures: Array[Texture2D] = []
		for file_name in frame_files:
			var path: String = base_path + String(file_name)
			if ResourceLoader.exists(path):
				var tex = _preloaded_resources.get(path, null)
				if tex == null:
					tex = load(path)
				if tex is Texture2D:
					textures.append(tex)

		if textures.is_empty():
			continue  # 该状态无可用帧，跳过

		# 创建动画
		frames.add_animation(state_name)
		any_loaded = true

		# 循环模式
		var mode: String = state_cfg.get("mode", "loop")
		frames.set_animation_loop(state_name, mode == "loop")

		# 逐帧设置持续时间和纹理
		# animation_speed = 1.0 时，frame_duration 的单位恰好是秒
		frames.set_animation_speed(state_name, 1.0)
		var durations: Array = state_cfg.get("duration", [])
		for i in range(textures.size()):
			var dur: float = float(durations[i]) if i < durations.size() else 0.15
			frames.add_frame(state_name, textures[i], dur)

		print("[SpriteRegistry]   %s: %s (%d frames)" % [
			unit_id, state_name, textures.size()
		])

	if not any_loaded:
		return null

	return frames
