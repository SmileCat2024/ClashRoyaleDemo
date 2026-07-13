# 文件名：MainMenu.gd
# 作用：主菜单 + 联机大厅。三个模式入口：
#       ① 单机 vs AI（传统 PVE）
#       ② 创建房间（作为 Host 等待对手）
#       ③ 加入房间（自动扫描 + 手动 IP 输入）
# 挂载位置：MainMenu.tscn 的根节点
# 初学者阅读建议：先看 _ready() 了解 UI 结构，再看各 _on_*_pressed 了解模式分流。

extends Control

# ---- UI 模式 ----
enum UIMode { MAIN, HOST_WAIT, JOIN }
var _ui_mode: UIMode = UIMode.MAIN

# ---- 扫描到的主机列表（IP 数组）----
var _found_hosts: Array[String] = []


func _ready() -> void:
	_show_main_mode()
	# 连接按钮
	$VBoxContainer/StartButton.pressed.connect(_on_start_ai_pressed)
	$VBoxContainer/HostButton.pressed.connect(_on_host_pressed)
	$VBoxContainer/JoinButton.pressed.connect(_on_join_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	# 联机事件
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.host_discovered.connect(_on_host_discovered)
	print("[MainMenu] ready")


# ==============================================================================
# UI 模式切换
# ==============================================================================

## 主界面（三个模式 + 退出）
func _show_main_mode() -> void:
	_ui_mode = UIMode.MAIN
	_found_hosts.clear()
	$VBoxContainer/StartButton.visible = true
	$VBoxContainer/HostButton.visible = true
	$VBoxContainer/JoinButton.visible = true
	$VBoxContainer/ModeLabel.visible = true
	$VBoxContainer/ModeSelect.visible = true
	$StatusLabel.text = ""
	$StatusLabel.visible = false
	$HostList.visible = false
	$IPInput.visible = false
	$ConnectButton.visible = false
	$BackButton.visible = false
	$VBoxContainer/QuitButton.visible = true


## Host 等待界面
func _show_host_wait_mode() -> void:
	_ui_mode = UIMode.HOST_WAIT
	$VBoxContainer/StartButton.visible = false
	$VBoxContainer/HostButton.visible = false
	$VBoxContainer/JoinButton.visible = false
	$VBoxContainer/ModeLabel.visible = false
	$VBoxContainer/ModeSelect.visible = false
	$VBoxContainer/QuitButton.visible = false
	# 显示本机 IP
	var addrs := NetworkManager.get_local_addresses()
	var ip_text := "你的 IP: "
	if addrs.is_empty():
		ip_text += "未检测到"
	else:
		ip_text += "\n".join(addrs)
	$StatusLabel.text = "等待对手加入...\n" + ip_text + "\n\n(端口 %d)" % NetworkManager.DEFAULT_PORT
	$StatusLabel.visible = true
	$BackButton.visible = true


## Join 加入界面（扫描列表 + 手动输入）
func _show_join_mode() -> void:
	_ui_mode = UIMode.JOIN
	$VBoxContainer/StartButton.visible = false
	$VBoxContainer/HostButton.visible = false
	$VBoxContainer/JoinButton.visible = false
	$VBoxContainer/ModeLabel.visible = false
	$VBoxContainer/ModeSelect.visible = false
	$VBoxContainer/QuitButton.visible = false
	$StatusLabel.text = "正在扫描局域网..."
	$StatusLabel.visible = true
	$HostList.visible = true
	$HostList.clear()
	$HostList.add_item("（扫描中...）")
	$IPInput.visible = true
	$IPInput.placeholder_text = "或手动输入 IP（如 192.168.1.100）"
	$IPInput.text = ""
	$ConnectButton.visible = true
	$BackButton.visible = true
	# 启动扫描
	_found_hosts.clear()
	NetworkManager.start_scanning()


# ==============================================================================
# 按钮回调
# ==============================================================================

## 单机 vs AI
func _on_start_ai_pressed() -> void:
	print("[MainMenu] 单机模式")
	NetworkManager.leave()
	Game.set_match_mode($VBoxContainer/ModeSelect.selected)
	Game.set_network_mode(false)
	Game.start_battle()


## 创建房间（Host）
func _on_host_pressed() -> void:
	print("[MainMenu] 创建房间")
	Game.set_match_mode($VBoxContainer/ModeSelect.selected)
	var err = NetworkManager.host_game()
	if err != OK:
		$StatusLabel.text = "创建房间失败！\n可能是端口被占用或防火墙拦截。"
		$StatusLabel.visible = true
		return
	Game.set_network_mode(true)
	_show_host_wait_mode()


## 加入房间
func _on_join_pressed() -> void:
	print("[MainMenu] 加入房间")
	# 加入方可预选模式，但进入战斗后以主机同步的规则为准。
	Game.set_match_mode($VBoxContainer/ModeSelect.selected)
	Game.set_network_mode(true)
	_show_join_mode()


## 手动连接按钮
func _on_connect_pressed() -> void:
	var ip: String = $IPInput.text.strip_edges()
	if ip.is_empty():
		# 如果扫描列表里有，用第一个
		if not _found_hosts.is_empty():
			ip = _found_hosts[0]
		else:
			return
	$StatusLabel.text = "正在连接 %s ..." % ip
	NetworkManager.stop_scanning()
	NetworkManager.join_game(ip)


## 返回主界面
func _on_back_pressed() -> void:
	NetworkManager.stop_scanning()
	NetworkManager.leave()
	Game.set_network_mode(false)
	_show_main_mode()


func _on_quit_pressed() -> void:
	get_tree().quit()


## Host 列表双击连接
func _on_host_list_item_activated(index: int) -> void:
	if index < _found_hosts.size():
		var ip := _found_hosts[index]
		$StatusLabel.text = "正在连接 %s ..." % ip
		NetworkManager.stop_scanning()
		NetworkManager.join_game(ip)


# ==============================================================================
# 联机事件
# ==============================================================================

## 连接成功 → 进入战斗
func _on_connected() -> void:
	print("[MainMenu] 连接成功，进入战斗")
	NetworkManager.stop_scanning()
	Game.start_battle()


## 连接失败
func _on_connection_failed() -> void:
	$StatusLabel.text = "连接失败！\n请检查 IP 或网络。"
	if _ui_mode == UIMode.JOIN:
		# 重新开始扫描
		NetworkManager.start_scanning()


## 服务器断开
func _on_server_disconnected() -> void:
	print("[MainMenu] 服务器断开")
	# 回到主菜单
	Game.set_network_mode(false)
	_show_main_mode()
	$StatusLabel.text = "连接已断开"
	$StatusLabel.visible = true


## 扫描到新主机
func _on_host_discovered(ip: String) -> void:
	if _ui_mode != UIMode.JOIN:
		return
	if ip in _found_hosts:
		return
	_found_hosts.append(ip)
	# 刷新列表
	$HostList.clear()
	$StatusLabel.text = "发现 %d 个房间：" % _found_hosts.size()
	for host_ip in _found_hosts:
		$HostList.add_item(host_ip)


## 处理返回键
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _ui_mode != UIMode.MAIN:
			_on_back_pressed()
