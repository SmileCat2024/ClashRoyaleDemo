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

	# 从 SpriteRegistry 获取（或构建）SpriteFrames
	var unit_id: String = unit_data.get("id", "")
	var frames: SpriteFrames = SpriteRegistry.get_sprite_frames(unit_id)
	if frames == null:
		return  # PNG 加载失败，ColorRect 兜底

	# 创建 AnimatedSprite2D 并挂到实体下
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = frames
	_sprite.centered = true
	# visual_offset 通过 position 设置（父坐标系，不受 sprite scale 影响）
	_sprite.position = _base_offset
	var vs: float = float(anim_data.get("visual_scale", 1.0))
	# 反向补偿 World 的 Y_COMPRESS：角色贴图不应被透视压扁，保持原始宽高比
	_sprite.scale = Vector2(vs, vs / BattleConstants.Y_COMPRESS)
	# 纹理过滤：高分辨率图用 linear（平滑缩放），像素风用 nearest
	# 默认 linear，因为大多数素材是高清图缩放显示
	var filter: String = anim_data.get("texture_filter", "linear")
	if filter == "nearest":
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	entity.add_child(_sprite)

	# 阵营色调（美术只画一套中性色，代码微调）
	if entity.team == "player":
		_sprite.modulate = Color(1.0, 1.0, 0.95)
	else:
		_sprite.modulate = Color(0.95, 1.0, 1.0)

	# 开发阶段：保留 ColorRect 站位格用于校准位置，不隐藏
	# if entity.body_rect:
	# 	entity.body_rect.visible = false

	_has_animation = true

	# 信号钩子（P2/P3 扩展用）
	_sprite.frame_changed.connect(_on_frame_changed)

	# 播放初始动画
	_update_animation()
	print("[SpriteAnimator] setup:", unit_id, "team:", entity.team)


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

	# 正常状态：每帧更新水平翻转
	_sprite.flip_h = combatant.get_flip_h()

	# 从跳河退出时重置状态标记
	if _current_state == "jump":
		_current_state = ""

	# 攻击动画播放中 → 不打断，等播完再恢复轮询
	if _attack_anim_playing:
		if _sprite.is_playing():
			return
		_attack_anim_playing = false

	# 检查攻击触发（只有存在攻击动画时才进入不可打断模式）
	var attack := combatant.get_primary_attack()
	if attack and attack.is_firing():
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
	if _sprite.animation != anim_name or not _sprite.is_playing():
		_sprite.play(anim_name)
	_current_state = anim_name
	return true


## 传递 altitude 离地偏移。由宿主实体的 altitude 系统调用。
## 使用 position（父坐标系）叠加 base_offset + altitude，与 body_rect.position 同空间。
func apply_altitude_offset(dy: float) -> void:
	if _sprite:
		_sprite.position = _base_offset + Vector2(0, dy)


## 帧变化回调（P2 扩展：帧事件 / hit frame 通知）。
func _on_frame_changed() -> void:
	pass


## 进入跳河状态：切换到 walk 动画，暂停并锁定到指定帧。
func _enter_jump_state() -> void:
	_play_with_fallback("walk")
	_sprite.pause()
	_sprite.frame = _jump_frame
	_current_state = "jump"
