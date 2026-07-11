# 文件名：TowerBase.gd
# 作用：控制塔的行为——受伤、死亡、攻击。
#       塔不会移动。主塔（king）死亡时战斗结束。
#       攻击逻辑由子节点 AttackComponent 自动驱动（_init_combat_stats 时创建）。
# 挂载位置：TowerBase.tscn 的根节点
# 初学者阅读建议：先看 setup() 了解塔怎么初始化，攻击配置怎么传递给 AttackComponent。

class_name TowerBase
extends CombatantBase

# ---- 身份信息（塔独有）----
var tower_id: String = ""
var tower_type: String = "guard"  ## "king" 或 "guard"
var king_activated: bool = true:
	set(value):
		var was := king_activated
		king_activated = value
		# 从 false → true 时恢复精灵亮度（client 端由 Synchronizer 同步触发）
		if value and not was and _tower_sprite:
			_tower_sprite.modulate = Color.WHITE

# ---- 精灵节点（有 sprite 配置时创建，替代 ColorRect 渲染）----
var _tower_sprite: Sprite2D = null
# ---- 血条数值标签（精灵塔专用）----
var _hp_label: Label = null


## 初始化塔属性。由 DebugBattle / BattleManager 在场景启动时调用。
func setup(tower_data: Dictionary, team_name: String, tower_name: String) -> void:
	tower_id = tower_name
	team = team_name
	tower_type = tower_data.get("tower_type", "guard")

	# 初始化战斗属性（基类方法）
	_init_combat_stats(tower_data)

	# 碰撞几何参数（格 → 像素）
	collision_radius = BattleConstants.px(float(tower_data.get("collision_radius", 1.5)))
	hurt_radius = BattleConstants.px(float(tower_data.get("hurt_radius", 1.5)))
	mass = int(tower_data.get("mass", 0))

	# 塔尺寸：主塔 4x4 格(80x80px)，公主塔 3x3 格(60x60px)
	var body_size: Vector2
	if tower_type == "king":
		body_size = BattleConstants.KING_TOWER_SIZE
	else:
		body_size = BattleConstants.GUARD_TOWER_SIZE

	# 国王塔初始未激活（禁用攻击组件，外观暗化由 _create_tower_sprite 处理）
	if tower_type == "king":
		king_activated = false

	health_bar.max_value = max_hp
	health_bar.value = current_hp
	health_bar.size = Vector2(body_size.x + 10, 6)
	health_bar.position = Vector2(-(body_size.x + 10) / 2.0, -body_size.y / 2.0 - 12)

	debug_label.text = ""
	debug_label.visible = false

	# 国王塔未激活时禁用攻击组件（受击或公主塔被毁后由 activate_king 启用）
	if tower_type == "king":
		for comp in attack_components:
			comp.set_process(false)

	# 精灵渲染（公主塔有 sprite 配置 → 创建 Sprite2D 替代 ColorRect）
	var sprite_data = tower_data.get("sprite", {})
	if not sprite_data.is_empty():
		_create_tower_sprite(sprite_data)

	initialized = true
	queue_redraw()
	print("[TowerBase] setup:", tower_id, team, tower_type, "hp:", max_hp)


## 从 sprite 配置创建精灵节点。按队伍加载不同纹理，底部对齐塔的逻辑位置。
## 精灵底部对齐设计：offset_y = -tex_h * scale_y / 2，使精灵视觉上"站"在塔的位置上。
## 这样 UnitsRoot 的 y-sort 以塔的 position.y（≈ 塔底）为基准，单位低于塔底时画在前面，高于时画在后面。
func _create_tower_sprite(sprite_data: Dictionary) -> void:
	var tex_path: String
	if team == "player":
		tex_path = sprite_data.get("player_texture", "")
	else:
		tex_path = sprite_data.get("enemy_texture", "")
	if tex_path.is_empty() or not ResourceLoader.exists(tex_path):
		return

	var tex = load(tex_path)
	if not tex is Texture2D:
		push_error("[TowerBase] 塔贴图加载失败: " + tex_path)
		return

	var vs: float = float(sprite_data.get("visual_scale", 1.0))
	_tower_sprite = Sprite2D.new()
	_tower_sprite.name = "TowerSprite"
	_tower_sprite.texture = tex
	_tower_sprite.centered = true
	# 反向补偿 World 的 Y_COMPRESS，保持原始宽高比
	_tower_sprite.scale = Vector2(vs, vs / BattleConstants.Y_COMPRESS)
	_tower_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# 计算偏移：让精灵底部对齐塔的逻辑位置（y=0）
	var tex_h: float = float(tex.get_height())
	var scale_y: float = vs / BattleConstants.Y_COMPRESS
	var base_offset_y: float = -tex_h * scale_y / 2.0
	var fine_tune: float = float(sprite_data.get("visual_offset_y", 0.0))
	_tower_sprite.position = Vector2(
		float(sprite_data.get("visual_offset_x", 0.0)),
		base_offset_y + fine_tune
	)
	add_child(_tower_sprite)

	# 血条：宽度缩减30% + 厚度增加（8→12px）+ 按精灵高度比例定位 Y
	# 距精灵顶部固定比例（玩家0.63 / 敌方0.38），保证公主塔/国王塔等不同高度塔的血条视觉位置一致
	var bar_w: float = health_bar.size.x * 0.7
	var bar_h: float = 12.0
	health_bar.size = Vector2(bar_w, bar_h)
	var sprite_render_h: float = tex_h * scale_y
	var top_ratio: float = 0.63 if team == "player" else 0.38
	health_bar.position = Vector2(-bar_w / 2.0, -sprite_render_h + sprite_render_h * top_ratio)

	# 血条数值标签
	_create_hp_label()

	# 血条和数值层级置顶（精灵盖不住）
	health_bar.z_index = 10

	# 国王塔未激活时暗化精灵（塔无 ColorRect 占位，暗化状态由 sprite modulate 承载）
	if tower_type == "king" and not king_activated:
		_tower_sprite.modulate = Color(0.55, 0.55, 0.55, 1.0)

	print("[TowerBase] sprite loaded:", tex_path, "scale:", vs)


## 创建血条数值标签。我方在血条下方（重叠），敌方在血条上方（重叠）。
## 粗体 + 队伍色描边 + 极浅队伍色填充（整体偏白）。
func _create_hp_label() -> void:
	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.text = str(current_hp)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 鼠标穿透，避免标签矩形拦截战场点击（见 CombatantBase._disable_control_mouse）
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_label)

	# 粗体：FontVariation embolden
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.8
	_hp_label.add_theme_font_override("font", fv)
	_hp_label.add_theme_font_size_override("font_size", 14)

	# 描边色 + 填充色（队伍差异化）
	var outline_c: Color
	var fill_c: Color
	if team == "player":
		outline_c = Color(0.08, 0.42, 0.92)     # 正蓝描边
		fill_c = Color(0.92, 0.96, 1.0)          # 极浅蓝白
	else:
		outline_c = Color(0.88, 0.12, 0.08)     # 正红描边
		fill_c = Color(1.0, 0.94, 0.92)          # 极浅红白
	_hp_label.add_theme_color_override("font_color", fill_c)
	_hp_label.add_theme_color_override("font_outline_color", outline_c)
	_hp_label.add_theme_constant_override("outline_size", 3)
	_hp_label.z_index = 10

	# 尺寸与定位：相对血条居中，按队伍上下偏移并重叠
	var label_w: float = health_bar.size.x + 10.0
	var label_h: float = 16.0
	_hp_label.size = Vector2(label_w, label_h)
	var label_x: float = health_bar.position.x + health_bar.size.x / 2.0 - label_w / 2.0
	if team == "player":
		# 血条下方，重叠5px
		_hp_label.position = Vector2(label_x, health_bar.position.y + health_bar.size.y - 5.0)
	else:
		# 血条上方，重叠5px
		_hp_label.position = Vector2(label_x, health_bar.position.y - label_h + 5.0)


## 更新血条数值标签文本
func _update_hp_label() -> void:
	if _hp_label:
		_hp_label.text = str(current_hp)


## 受到伤害。国王塔首次受击后激活。
func take_damage(amount: int) -> void:
	if _is_remote():
		return  # Client 端血量由 Synchronizer 同步
	super.take_damage(amount)
	if tower_type == "king" and not king_activated and not is_dead:
		activate_king()
	_update_hp_label()


## 激活国王塔：恢复外观亮度，启用攻击组件。
func activate_king() -> void:
	if king_activated:
		return
	king_activated = true
	# 恢复精灵亮度（未激活时被暗化）
	if _tower_sprite:
		_tower_sprite.modulate = Color.WHITE
	# 启用攻击组件
	for comp in attack_components:
		comp.set_process(true)
	queue_redraw()
	print("[TowerBase] king tower activated:", tower_id)


## _draw()：绘制攻击范围圆圈（调试用）
func _draw() -> void:
	if not initialized or is_dead:
		return
	# 国王塔未激活时不绘制射程圆
	if tower_type == "king" and not king_activated:
		return
	if attacks_data.is_empty():
		return
	var range_val = BattleConstants.px(float(attacks_data[0].get("attack_range", 0)))
	if range_val <= 0:
		return
	# 射程填充色（很淡）
	var fill_color: Color
	if team == "player":
		fill_color = Color(0.3, 0.6, 1.0, 0.05)
	else:
		fill_color = Color(1.0, 0.3, 0.2, 0.05)
	draw_circle(Vector2.ZERO, range_val, fill_color)
	# 射程边线
	var ring_color = Color(1, 1, 1, 0.08)
	draw_arc(Vector2.ZERO, range_val, 0, TAU, 64, ring_color, 1.0)


func _process(delta: float) -> void:
	if not initialized or is_dead:
		return
	if _is_remote():
		# Client 端：position/hp 由 BattleManager 手动 RPC 同步。仅刷新血条标签。
		_update_hp_label()
		return
	_process_status_effects(delta)
	# 塔的攻击逻辑由子节点 AttackComponent 独立处理（_init_combat_stats 时自动创建），
	# TowerBase._process 无需额外操作。


## 死亡：隐藏精灵，从注册表注销，发出信号（塔不 queue_free，保留节点避免引用失效）
func die() -> void:
	super.die()
	if _is_remote():
		# Client 端：不注销、不发信号，只隐藏视觉（由 Synchronizer 同步 is_dead 触发）
		if _tower_sprite:
			_tower_sprite.visible = false
		if health_bar:
			health_bar.visible = false
		if _hp_label:
			_hp_label.visible = false
		queue_redraw()
		return
	EntityRegistry.unregister(self)
	if _tower_sprite:
		_tower_sprite.visible = false
	if health_bar:
		health_bar.visible = false
	if _hp_label:
		_hp_label.visible = false
	queue_redraw()
	SignalBus.tower_destroyed.emit(tower_id, team, tower_type)
	print("[TowerBase] tower destroyed:", tower_id, team, tower_type)


## 联机 client 端：检测到 host 同步的 is_dead=true 后，隐藏视觉
func _on_remote_death() -> void:
	if _tower_sprite:
		_tower_sprite.visible = false
	if health_bar:
		health_bar.visible = false
	if _hp_label:
		_hp_label.visible = false
	queue_redraw()
