# 文件名：SpriteAnimator.gd
# 作用：帧动画驱动器（纯观察者）。挂在 CombatantBase 下，每帧轮询实体的视觉状态，
#       切换 AnimatedSprite2D 动画。永远不驱动、不阻塞、不改变游戏逻辑。
#       无动画数据时不创建精灵，实体保持 ColorRect 渲染（向后兼容）。
# 挂载位置：CombatantBase 的子节点（由 _init_combat_stats 动态创建）。
# 初学者阅读建议：先看 setup() 了解动画数据怎么读取，
#       再看 _process / _update_animation 了解状态轮询怎么工作。
#
# 设计原则：
#   1. 纯只读观察者——读实体状态，永远不写回。
#   2. 无动画数据 → 不创建 AnimatedSprite2D，Body(ColorRect) 保持可见。
#   3. 缺失具体动画 → 分层降级（方向精确 → 基础名 → idle）。
#   4. 伤害/攻击逻辑完全不依赖此组件。

class_name SpriteAnimator
extends Node

# ---- 宿主引用 ----
var combatant: CombatantBase

# ---- 精灵节点 ----
var _sprite: AnimatedSprite2D = null
var _has_animation: bool = false

# ---- 视觉配置 ----
var _base_offset: Vector2 = Vector2.ZERO   ## 视觉偏移基准值（不含 altitude）
var _current_state: String = ""            ## 当前播放的动画名（调试用）
var _attack_anim_playing: bool = false     ## 攻击动画播放中（不可打断，播完自动清除）
var _jump_frame: int = 0                    ## 跳河时锁定的帧索引（0-based，从动画配置读取）
var _idle_uses_attack_facing: bool = false  ## idle 是否按攻击目标选 front/back/side 准备帧
var _side_flip_inverted: bool = false       ## side 动画是否反转默认左右镜像
var _altitude_dy: float = 0.0              ## altitude 离地视觉偏移（px，负=上移）
var _deploy_dy: float = 0.0                ## 部署下落动画偏移（px，负=上移，0=无偏移）
var _base_scale: Vector2 = Vector2.ONE     ## 精灵基础缩放（visual_scale + Y_COMPRESS 补偿）
var _deploy_scale: Vector2 = Vector2.ONE   ## 部署挤压拉伸乘数（叠乘到 _base_scale 上）
var _unit_id: String = ""
var _animation_data: Dictionary = {}


## 从单位数据初始化。由 CombatantBase._create_sprite_animator 在 add_child 后调用。
func setup(unit_data: Dictionary, entity: CombatantBase) -> void:
	combatant = entity

	var anim_data: Dictionary = unit_data.get("animation", {})
	if anim_data.is_empty():
		return  # 无动画配置，ColorRect 兜底

	# 读取视觉微调参数
	_base_offset = Vector2(
		float(anim_data.get("visual_offset_x", 0.0)),
		float(anim_data.get("visual_offset_y", 0.0))
	)
	_jump_frame = int(anim_data.get("jump_frame", 0))
	_idle_uses_attack_facing = bool(anim_data.get("idle_uses_attack_facing", false))
	_side_flip_inverted = bool(anim_data.get("side_flip_inverted", false))
	var prepared_scale := SpriteRegistry.get_render_scale(float(anim_data.get("visual_scale", 1.0)))
	_base_scale = Vector2(prepared_scale, prepared_scale / BattleConstants.Y_COMPRESS)

	# 从 SpriteRegistry 获取（或构建）SpriteFrames（团队色单位按 team 取对应贴图）
	_unit_id = unit_data.get("id", "")
	_animation_data = anim_data
	# 战斗中禁止同步解码。正常情况下加载页或后台前瞻已经准备好；极端情况下先保留占位，
	# 等后台完成后热挂接动画，避免一次部署阻塞整帧。
	var frames: SpriteFrames = SpriteRegistry.get_cached_sprite_frames(_unit_id, entity.team)
	if frames == null:
		if not SpriteRegistry.sprite_frames_ready.is_connected(_on_sprite_frames_ready):
			SpriteRegistry.sprite_frames_ready.connect(_on_sprite_frames_ready)
		SpriteRegistry.queue_sprite_frames(_unit_id, entity.team)
		return
	_attach_frames(frames)


func _on_sprite_frames_ready(unit_id: String, team: String, frames: SpriteFrames) -> void:
	if unit_id != _unit_id or combatant == null or team != combatant.team:
		return
	if SpriteRegistry.sprite_frames_ready.is_connected(_on_sprite_frames_ready):
		SpriteRegistry.sprite_frames_ready.disconnect(_on_sprite_frames_ready)
	if frames != null and is_instance_valid(combatant):
		_attach_frames(frames)


func _attach_frames(frames: SpriteFrames) -> void:
	if _sprite != null:
		return
	var anim_data := _animation_data

	# 创建 AnimatedSprite2D 并挂到实体下
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = frames
	_sprite.centered = true
	# visual_offset 通过 position 设置（父坐标系，不受 sprite scale 影响）
	_sprite.position = _base_offset
	# 反向补偿 World 的 Y_COMPRESS：角色贴图不应被透视压扁，保持原始宽高比
	_sprite.scale = _base_scale
	# 纹理过滤：高分辨率图用 linear（平滑缩放），像素风用 nearest
	# 默认 linear，因为大多数素材是高清图缩放显示
	var filter: String = anim_data.get("texture_filter", "linear")
	if filter == "nearest":
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	combatant.add_child(_sprite)

	# 阵营色调（美术只画一套中性色，代码微调）
	# 团队色单位（红蓝双套贴图，如迫击炮）保持原色，不做色调微调避免偏色
	if SpriteRegistry.is_team_colored(_unit_id):
		_sprite.modulate = Color.WHITE
	elif combatant.team == "player":
		_sprite.modulate = Color(1.0, 1.0, 0.95)
	else:
		_sprite.modulate = Color(0.95, 1.0, 1.0)

	# 有动画数据且单位标记 hide_placeholder 时，隐藏 ColorRect 占位方块
	# （已校准好的单位开启，未校准的保留占位格用于位置调试）
	if anim_data.get("hide_placeholder", false) and combatant.body_rect:
		combatant.body_rect.visible = false

	_has_animation = true

	# 信号钩子（P2/P3 扩展用）
	_sprite.frame_changed.connect(_on_frame_changed)

	# 播放初始动画
	_update_animation()
	print("[SpriteAnimator] setup:", _unit_id, "team:", combatant.team)


func _process(_delta: float) -> void:
	if not _has_animation:
		return
	if combatant == null or not is_instance_valid(combatant):
		return
	_update_animation()


## 轮询实体视觉状态，按需切换动画。分层降级查找。
func _update_animation() -> void:
	var state := combatant.get_visual_state()

	# 跳河状态：锁定到 walk 动画的指定帧，不更新翻转
	if state == "jump":
		if _current_state != "jump":
			_enter_jump_state()
		return

	# 正常状态：每帧更新水平翻转；个别素材可仅对 side 动画反转默认方向。
	_sprite.flip_h = _get_flip_h_for_animation(_current_state)

	# 从跳河退出时重置状态标记
	if _current_state == "jump":
		_current_state = ""

	# 攻击动画播放中 → 不打断，等播完再恢复轮询
	if _attack_anim_playing:
		if _sprite.is_playing():
			return
		_attack_anim_playing = false
		# 攻击动画播完：清除宿主一次性攻击标记，避免下一帧重复触发
		if combatant.has_method("_clear_attack_flag"):
			combatant._clear_attack_flag()

	# 检查攻击触发（只有存在攻击动画时才进入不可打断模式）
	# 联机 client 端：优先从 combatant.is_attacking() 读取网络同步值
	var firing := false
	if combatant.has_method("is_attacking"):
		firing = combatant.is_attacking()
	else:
		var attack := combatant.get_primary_attack()
		firing = attack != null and attack.is_firing()
	if firing:
		# 优先用三态攻击朝向（front/back/side），命中即播放
		if combatant.has_method("get_attack_facing"):
			if _play_if_exists("attack_" + combatant.get_attack_facing()):
				_attack_anim_playing = true
				return
		# 降级：无 get_attack_facing 或 side 未配置 → front/back 双向降级 → 无方向 attack
		var facing := combatant.get_facing()
		var other := "back" if facing == "front" else "front"
		if _play_if_exists("attack_" + facing) \
				or _play_if_exists("attack_" + other) \
				or _play_if_exists("attack"):
			_attack_anim_playing = true
			return
		# 无攻击动画 → 正常走 walk/idle（伤害照算，只是没动画表现）

	# 常规状态：walk / idle / death（带方向 + 跨方向降级）
	_play_with_fallback(state)


## 按降级链查找并播放动画。返回是否成功。
## 链：state_当前朝向 → state_对侧朝向 → state（无方向）→ idle_当前朝向 → idle_对侧 → idle
func _play_with_fallback(state: String) -> bool:
	# 近战单位可选择在攻击冷却/起手阶段，按目标方向定格在准备动作。
	# 只有显式开启的单位会走此分支，其他单位保持原有 front/back idle 行为。
	if state == "idle" and _idle_uses_attack_facing and combatant.has_method("get_attack_facing"):
		if _play_if_exists("idle_" + combatant.get_attack_facing()):
			return true

	var facing: String = combatant.get_facing()
	var other: String = "back" if facing == "front" else "front"

	if _play_if_exists(state + "_" + facing):
		return true
	if _play_if_exists(state + "_" + other):
		return true
	if _play_if_exists(state):
		return true
	if state != "idle":
		if _play_if_exists("idle_" + facing):
			return true
		if _play_if_exists("idle_" + other):
			return true
		if _play_if_exists("idle"):
			return true
	return false


## 尝试播放指定动画名。已播放同名动画时不重启。返回是否找到并播放。
func _play_if_exists(anim_name: String) -> bool:
	if not _sprite.sprite_frames.has_animation(anim_name):
		return false
	_sprite.flip_h = _get_flip_h_for_animation(anim_name)
	if _sprite.animation != anim_name or not _sprite.is_playing():
		_sprite.play(anim_name)
	_current_state = anim_name
	return true


## 返回指定动画应使用的水平镜像。side_flip_inverted 仅影响名字以 _side 结尾的帧组。
func _get_flip_h_for_animation(anim_name: String) -> bool:
	var flip := combatant.get_flip_h()
	return not flip if _side_flip_inverted and anim_name.ends_with("_side") else flip


## 传递 altitude 离地偏移。由宿主实体的 altitude 系统调用。
## 使用 position（父坐标系）叠加 base_offset + altitude，与 body_rect.position 同空间。
func apply_altitude_offset(dy: float) -> void:
	_altitude_dy = dy
	_refresh_sprite_position()


## 传递部署下落动画偏移（px，负=上移）。与 altitude 偏移叠加。
## 部署动画结束后传入 0.0 恢复正常位置。
func set_deploy_offset(dy: float) -> void:
	_deploy_dy = dy
	_refresh_sprite_position()


## 传递部署挤压拉伸缩放乘数（着地瞬间 Y 压扁 / X 拉宽 → 弹回 1.0）。
## 叠乘到 _base_scale 上，部署动画结束后传入 Vector2.ONE 恢复正常比例。
func set_deploy_scale(s: Vector2) -> void:
	_deploy_scale = s
	if _sprite:
		_sprite.scale = Vector2(_base_scale.x * s.x, _base_scale.y * s.y)


## 统一刷新精灵位置 = base_offset + altitude偏移 + 部署下落偏移。
func _refresh_sprite_position() -> void:
	if _sprite:
		_sprite.position = _base_offset + Vector2(0, _altitude_dy + _deploy_dy)


## 帧变化回调（P2 扩展：帧事件 / hit frame 通知）。
func _on_frame_changed() -> void:
	pass


## 进入跳河状态：切换到 walk 动画，暂停并锁定到指定帧。
func _enter_jump_state() -> void:
	_play_with_fallback("walk")
	_sprite.pause()
	_sprite.frame = _jump_frame
	_current_state = "jump"
