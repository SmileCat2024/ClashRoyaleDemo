# 文件名：SpriteRegistry.gd
# 作用：全局精灵帧缓存。按 unit_id 从 DataRegistry 动画配置构建 SpriteFrames，
#       加载 assets/sprites/{unit_id}/ 下的 PNG 序列帧，构建后缓存。
#       找不到 PNG 或无动画配置时返回 null（触发 ColorRect 兜底）。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：先看 get_sprite_frames() 了解缓存查询，
#       再看 _build_sprite_frames() 了解 PNG 怎么加载成 SpriteFrames。

extends Node

# 缓存：unit_id → SpriteFrames（构建成功才入缓存）
var _frames_cache: Dictionary = {}

# 记录已尝试加载的 unit_id，避免重复尝试
var _load_attempted: Dictionary = {}


## 获取指定单位的 SpriteFrames。返回 null 表示无动画数据或 PNG 加载失败。
func get_sprite_frames(unit_id: String) -> SpriteFrames:
	# 已缓存 → 直接返回
	if _frames_cache.has(unit_id):
		return _frames_cache[unit_id]

	# 已尝试过且失败 → 不再重试
	if _load_attempted.has(unit_id):
		return null

	_load_attempted[unit_id] = true

	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	var anim_data: Dictionary = unit_data.get("animation", {})
	if anim_data.is_empty():
		return null

	var frames: SpriteFrames = _build_sprite_frames(unit_id, anim_data)
	if frames != null:
		_frames_cache[unit_id] = frames
		print("[SpriteRegistry] loaded sprite frames: %s (%d animations)" % [
			unit_id, frames.get_animation_names().size()
		])
	return frames


## 判断指定单位是否有动画配置字段（不代表 PNG 一定存在）。
func has_animation_config(unit_id: String) -> bool:
	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	return unit_data.has("animation") and not unit_data["animation"].is_empty()


## 从动画配置和 PNG 文件构建 SpriteFrames。
## 成功返回带动画的 SpriteFrames；无可用帧返回 null。
func _build_sprite_frames(unit_id: String, anim_data: Dictionary) -> SpriteFrames:
	var sprite_dir: String = anim_data.get("sprite_dir", unit_id)
	var states: Dictionary = anim_data.get("states", {})
	if states.is_empty():
		return null

	var frames := SpriteFrames.new()
	var base_path := "res://assets/sprites/" + sprite_dir + "/"
	var any_loaded := false

	for state_name in states:
		var state_cfg: Dictionary = states[state_name]
		var frame_files: Array = state_cfg.get("frames", [])
		if frame_files.is_empty():
			continue

		# 逐帧加载 PNG
		var textures: Array[Texture2D] = []
		for file_name in frame_files:
			var path: String = base_path + String(file_name)
			if ResourceLoader.exists(path):
				var tex = load(path)
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
