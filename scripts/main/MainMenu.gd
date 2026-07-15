## 菜单保持参考图的原始版式；只有热区和卡组卡面覆盖在素材之上。
extends Control

const LOBBY_TEXTURE := preload("res://assets/ui/menu/lobby_reference.png")
const DECK_TEXTURE := preload("res://assets/ui/menu/deck_reference.png")
const LOADING_TEXTURE := preload("res://assets/ui/menu/battle_loading.jpg")

enum Page { LOBBY, DECK }
enum OnlineChoice { SOLO, HOST, JOIN }

var _page: Page = Page.LOBBY
var _selected_preset := 0
var _loading := false
var _room_mode: OnlineChoice = OnlineChoice.SOLO
var _found_hosts: Array[String] = []

var _background: TextureRect
var _lobby_layer: Control
var _deck_layer: Control
var _selected_marker: Button
var _card_layer: Control
var _settings: Control
var _room_overlay: Control
var _room_status: Label
var _host_picker: OptionButton
var _ip_input: LineEdit
var _room_action: Button
var _loading_overlay: Control
var _mode_select: OptionButton
var _online_select: OptionButton


func _ready() -> void:
	_selected_preset = Game.selected_deck_index
	_build_base()
	_build_lobby_layer()
	_build_deck_layer()
	_build_settings()
	_build_room_overlay()
	_build_loading_overlay()
	_show_page(Page.LOBBY)
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.host_discovered.connect(_on_host_discovered)


func _build_base() -> void:
	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)


func _build_lobby_layer() -> void:
	_lobby_layer = _full_layer()
	add_child(_lobby_layer)
	# 与原图齿轮、Battle、Deck、Battle 底栏严格重合的透明热区。
	_add_hotspot(_lobby_layer, Rect2(0.83, 0.025, 0.14, 0.075), _open_settings, "设置")
	_add_hotspot(_lobby_layer, Rect2(0.25, 0.655, 0.51, 0.145), _on_battle_pressed, "开始对战")
	_add_hotspot(_lobby_layer, Rect2(0.03, 0.855, 0.45, 0.145), _show_page.bind(Page.DECK), "卡组")
	_add_hotspot(_lobby_layer, Rect2(0.48, 0.855, 0.49, 0.145), _on_battle_pressed, "对战")


func _build_deck_layer() -> void:
	_deck_layer = _full_layer()
	add_child(_deck_layer)
	for index in range(5):
		_add_hotspot(_deck_layer, Rect2(0.185 + index * 0.132, 0.257, 0.108, 0.056), _select_preset.bind(index), "预设 %d" % (index + 1))
	_card_layer = _full_layer()
	_deck_layer.add_child(_card_layer)
	_add_hotspot(_deck_layer, Rect2(0.04, 0.855, 0.45, 0.145), _show_page.bind(Page.DECK), "卡组")
	_add_hotspot(_deck_layer, Rect2(0.50, 0.855, 0.46, 0.145), _show_page.bind(Page.LOBBY), "大厅")


func _build_settings() -> void:
	_settings = _full_layer()
	_settings.visible = false
	add_child(_settings)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#071426dc")
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings.add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(31, 150)
	panel.size = Vector2(378, 450)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#173a68"), 20, Color("#80d7ff"), 3))
	_settings.add_child(panel)
	var title := _label("对局设置", 27, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(20, 20)
	title.size = Vector2(338, 42)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color("#15253e"))
	panel.add_child(title)
	panel.add_child(_positioned_label("对局模式", Vector2(30, 79), Vector2(300, 25)))
	_mode_select = OptionButton.new()
	_mode_select.position = Vector2(30, 105)
	_mode_select.size = Vector2(318, 43)
	_mode_select.add_item("7× 圣水模式（极速）", Game.MatchMode.FAST_7X)
	_mode_select.add_item("经典 1v1（官方倍率）", Game.MatchMode.CLASSIC_1V1)
	_mode_select.selected = Game.match_mode
	_style_option(_mode_select)
	panel.add_child(_mode_select)
	panel.add_child(_positioned_label("对手与联机方式", Vector2(30, 170), Vector2(300, 25)))
	_online_select = OptionButton.new()
	_online_select.position = Vector2(30, 196)
	_online_select.size = Vector2(318, 43)
	_online_select.add_item("单机 · 对战 AI", OnlineChoice.SOLO)
	_online_select.add_item("局域网 · 创建房间", OnlineChoice.HOST)
	_online_select.add_item("局域网 · 加入房间", OnlineChoice.JOIN)
	_style_option(_online_select)
	panel.add_child(_online_select)
	var hint := _label("双方会在进入对局前锁定各自选中的预设卡组。", 13, Color("#d0ecff"), HORIZONTAL_ALIGNMENT_CENTER)
	hint.position = Vector2(25, 263)
	hint.size = Vector2(328, 44)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)
	var save := _styled_button("保存并返回大厅", Vector2(318, 50), Color("#b97208"), Color("#f7bf32"))
	save.position = Vector2(30, 337)
	save.pressed.connect(_apply_settings)
	panel.add_child(save)
	var close := _styled_button("取消", Vector2(318, 35), Color("#305c8e"), Color("#39a8f2"))
	close.position = Vector2(30, 397)
	close.pressed.connect(func(): _settings.visible = false)
	panel.add_child(close)


func _build_room_overlay() -> void:
	_room_overlay = _full_layer()
	_room_overlay.visible = false
	add_child(_room_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#071426df")
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_room_overlay.add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(25, 171)
	panel.size = Vector2(390, 390)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#173a68"), 20, Color("#80d7ff"), 3))
	_room_overlay.add_child(panel)
	var title := _label("局域网对战", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(24, 20)
	title.size = Vector2(342, 38)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color("#15253e"))
	panel.add_child(title)
	_room_status = _label("", 14, Color("#d5efff"), HORIZONTAL_ALIGNMENT_CENTER)
	_room_status.position = Vector2(28, 68)
	_room_status.size = Vector2(334, 86)
	_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_room_status)
	_host_picker = OptionButton.new()
	_host_picker.position = Vector2(32, 164)
	_host_picker.size = Vector2(326, 40)
	_host_picker.visible = false
	_style_option(_host_picker)
	_host_picker.item_selected.connect(_pick_host)
	panel.add_child(_host_picker)
	_ip_input = LineEdit.new()
	_ip_input.position = Vector2(32, 214)
	_ip_input.size = Vector2(326, 39)
	_ip_input.placeholder_text = "或输入主机 IP，例如 192.168.1.100"
	_ip_input.visible = false
	_ip_input.add_theme_stylebox_override("normal", _panel_style(Color("#0c2343"), 10, Color("#77cef8"), 2))
	panel.add_child(_ip_input)
	_room_action = _styled_button("", Vector2(326, 50), Color("#b97208"), Color("#f7bf32"))
	_room_action.position = Vector2(32, 276)
	_room_action.pressed.connect(_on_room_action)
	panel.add_child(_room_action)
	var back := _styled_button("返回大厅", Vector2(326, 35), Color("#305c8e"), Color("#39a8f2"))
	back.position = Vector2(32, 335)
	back.pressed.connect(_close_room_overlay)
	panel.add_child(back)


func _build_loading_overlay() -> void:
	_loading_overlay = _full_layer()
	_loading_overlay.visible = false
	add_child(_loading_overlay)
	var image := TextureRect.new()
	image.texture = LOADING_TEXTURE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_loading_overlay.add_child(image)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#05112670")
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.add_child(shade)
	var text := _label("正在进入竞技场…", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text.position = Vector2(20, 620)
	text.size = Vector2(400, 48)
	text.add_theme_constant_override("outline_size", 7)
	text.add_theme_color_override("font_outline_color", Color("#15253e"))
	_loading_overlay.add_child(text)


func _show_page(page: Page) -> void:
	_page = page
	_background.texture = LOBBY_TEXTURE if page == Page.LOBBY else DECK_TEXTURE
	_lobby_layer.visible = page == Page.LOBBY
	_deck_layer.visible = page == Page.DECK
	if page == Page.DECK:
		_refresh_deck_cards()


func _select_preset(index: int) -> void:
	_selected_preset = index
	Game.set_selected_deck(index)
	_refresh_deck_cards()


func _refresh_deck_cards() -> void:
	for child in _card_layer.get_children():
		child.queue_free()
	var cards: Array = Game.PRESET_DECKS[_selected_preset].get("cards", [])
	for index in range(cards.size()):
		var image := TextureRect.new()
		var x := 0.077 + (index % 4) * 0.220
		var y := 0.414 + (index / 4) * 0.174
		image.set_anchors_preset(Control.PRESET_TOP_LEFT)
		image.anchor_left = x
		image.anchor_right = x + 0.180
		image.anchor_top = y
		image.anchor_bottom = y + 0.145
		image.offset_left = 0
		image.offset_right = 0
		image.offset_top = 0
		image.offset_bottom = 0
		image.texture = _card_texture(str(cards[index]))
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_layer.add_child(image)
	# 唯一可见的控件覆盖：当前选中卡组的编号，黄色状态与需求一致。
	if _selected_marker and is_instance_valid(_selected_marker):
		_selected_marker.queue_free()
	_selected_marker = _styled_button(str(_selected_preset + 1), Vector2.ZERO, Color("#c98208e8"), Color("#ffd24b"))
	_selected_marker.flat = false
	_selected_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_marker.add_theme_font_size_override("font_size", 25)
	_selected_marker.anchor_left = 0.185 + _selected_preset * 0.132
	_selected_marker.anchor_right = _selected_marker.anchor_left + 0.108
	_selected_marker.anchor_top = 0.257
	_selected_marker.anchor_bottom = 0.313
	_deck_layer.add_child(_selected_marker)


func _on_battle_pressed() -> void:
	Game.set_selected_deck(_selected_preset)
	match _online_select.selected:
		OnlineChoice.SOLO:
			NetworkManager.leave()
			Game.set_network_mode(false)
			_begin_loading()
		OnlineChoice.HOST:
			_open_host_room()
		OnlineChoice.JOIN:
			_open_join_room()


func _open_settings() -> void:
	_settings.visible = true


func _apply_settings() -> void:
	Game.set_match_mode(_mode_select.get_selected_id())
	_settings.visible = false


func _open_host_room() -> void:
	Game.set_match_mode(_mode_select.get_selected_id())
	Game.set_network_mode(true)
	Game.set_remote_deck([])
	var err := NetworkManager.host_game()
	if err != OK:
		Game.set_network_mode(false)
		return
	_room_mode = OnlineChoice.HOST
	_room_overlay.visible = true
	_host_picker.visible = false
	_ip_input.visible = false
	_room_action.text = "等待对手加入…"
	_room_action.disabled = true
	_room_status.text = "房间已创建。把你的 IP 告诉好友：\n\n%s\n端口：%d" % [_local_ips(), NetworkManager.DEFAULT_PORT]


func _open_join_room() -> void:
	_room_mode = OnlineChoice.JOIN
	_room_overlay.visible = true
	_host_picker.visible = true
	_ip_input.visible = true
	_host_picker.clear()
	_host_picker.add_item("扫描局域网房间…")
	_ip_input.text = ""
	_room_action.text = "连接房间"
	_room_action.disabled = false
	_room_status.text = "选择扫描到的房间，或输入好友的局域网 IP。"
	_found_hosts.clear()
	NetworkManager.start_scanning()


func _on_room_action() -> void:
	if _room_mode != OnlineChoice.JOIN:
		return
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty() and not _found_hosts.is_empty():
		ip = _found_hosts[0]
	if ip.is_empty():
		_room_status.text = "尚未找到房间，请稍候扫描或输入 IP。"
		return
	Game.set_match_mode(_mode_select.get_selected_id())
	Game.set_network_mode(true)
	NetworkManager.stop_scanning()
	if NetworkManager.join_game(ip) != OK:
		Game.set_network_mode(false)
		_room_status.text = "无法连接，请检查 IP 后重试。"
		return
	_room_status.text = "正在连接 %s…" % ip
	_room_action.disabled = true


func _close_room_overlay() -> void:
	NetworkManager.stop_scanning()
	NetworkManager.leave()
	Game.set_network_mode(false)
	_room_overlay.visible = false


func _pick_host(index: int) -> void:
	if index >= 0 and index < _found_hosts.size():
		_ip_input.text = _found_hosts[index]


func _on_host_discovered(ip: String) -> void:
	if not _room_overlay.visible or _room_mode != OnlineChoice.JOIN or ip in _found_hosts:
		return
	_found_hosts.append(ip)
	_host_picker.clear()
	for host_ip in _found_hosts:
		_host_picker.add_item("发现房间：" + host_ip)


func _on_connected() -> void:
	NetworkManager.stop_scanning()
	if NetworkManager.is_client():
		_rpc_submit_lobby_deck.rpc_id(1, Game.get_selected_deck())
	_begin_loading()


func _on_connection_failed() -> void:
	Game.set_network_mode(false)
	if _room_overlay.visible:
		_room_status.text = "连接失败，请确认双方在同一局域网并检查 IP。"
		_room_action.disabled = false
		NetworkManager.start_scanning()


func _on_server_disconnected() -> void:
	Game.set_network_mode(false)
	_room_overlay.visible = false


func _begin_loading() -> void:
	if _loading:
		return
	_loading = true
	_settings.visible = false
	_room_overlay.visible = false
	_loading_overlay.visible = true
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		Game.start_battle()


## 在大厅场景完成卡组锁定，避免两端加载速度不同导致远端手牌被默认值覆盖。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_lobby_deck(cards: Array) -> void:
	if not NetworkManager.is_server():
		return
	var validated: Array = []
	for card_id in cards:
		if card_id is String and not DataRegistry.get_card_data(card_id).is_empty():
			validated.append(card_id)
	if validated.size() >= 5:
		Game.set_remote_deck(validated)


func _full_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer


func _add_hotspot(parent: Control, area: Rect2, callback: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = ""
	button.tooltip_text = tooltip
	button.anchor_left = area.position.x
	button.anchor_top = area.position.y
	button.anchor_right = area.end.x
	button.anchor_bottom = area.end.y
	button.offset_left = 0
	button.offset_top = 0
	button.offset_right = 0
	button.offset_bottom = 0
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _card_texture(card_id: String) -> Texture2D:
	var asset_id := card_id.replace("card_", "")
	if asset_id == "knight_elite":
		asset_id = "knight"
	elif asset_id == "mega_minion_elite":
		asset_id = "mega_minion"
	var path := "res://assets/ui/cards/%s.png" % asset_id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _local_ips() -> String:
	var addresses := NetworkManager.get_local_addresses()
	return " / ".join(addresses) if not addresses.is_empty() else "未检测到局域网 IP"


func _label(value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _positioned_label(value: String, position_value: Vector2, size_value: Vector2) -> Label:
	var label := _label(value, 15, Color("#c8e9ff"))
	label.position = position_value
	label.size = size_value
	return label


func _styled_button(value: String, button_size: Vector2, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.size = button_size
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(fill, 12, border, 2))
	button.add_theme_stylebox_override("hover", _panel_style(fill.lightened(0.12), 12, Color.WHITE, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(fill.darkened(0.12), 12, border.darkened(0.2), 2))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#35516d"), 12, Color("#6687a4"), 1))
	return button


func _style_option(option: OptionButton) -> void:
	option.add_theme_font_size_override("font_size", 15)
	option.add_theme_color_override("font_color", Color.WHITE)
	option.add_theme_stylebox_override("normal", _panel_style(Color("#0c2343"), 10, Color("#77cef8"), 2))
	option.add_theme_stylebox_override("hover", _panel_style(Color("#163b68"), 10, Color.WHITE, 2))


func _panel_style(fill: Color, radius: int, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	return style


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _settings.visible:
			_settings.visible = false
		elif _room_overlay.visible:
			_close_room_overlay()
