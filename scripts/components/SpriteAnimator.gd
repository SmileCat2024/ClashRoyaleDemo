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
var _current_state: String = ""            ## 当前播放的视觉状态名


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
	_sprite.offset = _base_offset
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
	var target_state: String = combatant.get_visual_state()
	if target_state == _current_state:
		return
	_current_state = target_state

	var sf: SpriteFrames = _sprite.sprite_frames

	# 1. 精确匹配（如 "walk_front"）
	if sf.has_animation(target_state):
		_sprite.play(target_state)
		return

	# 2. 去掉方向后缀再试（如 "walk_front" → "walk"）
	var base_name: String = target_state.split("_")[0]
	if sf.has_animation(base_name):
		_sprite.play(base_name)
		return

	# 3. idle 兜底
	if target_state != "idle" and sf.has_animation("idle"):
		_sprite.play("idle")
	# 4. 什么都没有 → 静止（不应发生，SpriteRegistry 已保证至少有内容）


## 传递 altitude 离地偏移。由宿主实体的 altitude 系统调用。
func apply_altitude_offset(dy: float) -> void:
	if _sprite:
		_sprite.offset = _base_offset + Vector2(0, dy)


## 帧变化回调（P2 扩展：帧事件 / hit frame 通知）。
func _on_frame_changed() -> void:
	pass
