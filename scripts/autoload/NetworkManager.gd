# 文件名：NetworkManager.gd
# 作用：局域网联机的统一入口。封装 ENetMultiplayerPeer 的 host/join/leave，
#       提供 is_networked()/is_server()/is_client() 便捷查询，
#       内置 LanDiscovery（UDP 广播自动发现主机）。
#
#       联机模型：Listen-Server（主机即服务器）。
#       Host 既是服务器也是玩家 1，Client 是玩家 2。
#       Host 跑完整战斗逻辑，Client 只渲染 + 转发输入。
#
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：先看 host_game()/join_game() 了解连接流程，
#       再看 LanDiscovery 内部类了解自动发现原理。

extends Node

# ---- 网络常量 ----
const DEFAULT_PORT: int = 7000          ## 联机端口（UDP，ENet 协议）
const DISCOVERY_PORT: int = 7001        ## LAN 发现广播端口（纯 UDP）
const MAX_CLIENTS: int = 2              ## 最大连接数（含 host，2 人对战）
const DISCOVERY_INTERVAL: float = 0.5   ## 广播间隔（秒）
const DISCOVERY_MAGIC: String = "PLB_HOST"  ## 广播包标识（PixelLaneBattle Host）

# ---- 连接状态 ----
enum State { OFFLINE, HOSTING, CONNECTING, CONNECTED }
var state: State = State.OFFLINE

# ---- 对外信号 ----
## Client 成功连上 Host（双方都收到）
signal connected_to_server
## Client 连接失败
signal connection_failed
## 与服务器断开（仅 client）
signal server_disconnected
## 有 peer 连接/断开
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
## LAN 发现：找到新主机
signal host_discovered(ip: String)
## LAN 发现：广播器状态变化
signal discovery_started
signal discovery_stopped
## 远端已实例化战斗场景。该握手运行在常驻 Autoload 上，避免场景切换期间 RPC 找不到 BattleManager。
signal remote_battle_scene_ready

var _local_battle_scene_ready: bool = false
var _remote_battle_scene_ready: bool = false

# ---- LAN 发现内部对象 ----
var _discovery: LanDiscovery = null


# ==============================================================================
# 连接管理
# ==============================================================================

## 作为 Host 创建房间
func host_game() -> Error:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if err != OK:
		push_error("[NetworkManager] 创建服务器失败: %d" % err)
		return err
	multiplayer.multiplayer_peer = peer
	state = State.HOSTING
	# Host 自己不需要发现广播，但可以广播自己存在（让 client 能扫到）
	_start_broadcasting()
	print("[NetworkManager] 房间已创建，端口 %d" % DEFAULT_PORT)
	return OK


## 作为 Client 连接到指定 IP
func join_game(ip: String) -> Error:
	if ip.is_empty():
		return ERR_INVALID_PARAMETER
	state = State.CONNECTING
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, DEFAULT_PORT)
	if err != OK:
		push_error("[NetworkManager] 连接失败: %d (IP=%s)" % [err, ip])
		state = State.OFFLINE
		return err
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] 正在连接 %s:%d ..." % [ip, DEFAULT_PORT])
	return OK


## 断开连接，回到离线状态
func leave() -> void:
	_stop_discovery()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	state = State.OFFLINE
	reset_battle_scene_readiness()
	print("[NetworkManager] 已断开")


# ==============================================================================
# 状态查询
# ==============================================================================

## 当前是否处于联机模式（host 或 client）
func is_networked() -> bool:
	return state == State.HOSTING or state == State.CONNECTED

## 当前是否是 Host（服务器）
func is_server() -> bool:
	return is_networked() and multiplayer.is_server()

## 当前是否是 Client
func is_client() -> bool:
	return is_networked() and not multiplayer.is_server()


## is_client() 的别名（代码中广泛使用 is_networked_client）
func is_networked_client() -> bool:
	return is_client()

## 本地玩家在游戏中的阵营。Host = "player"，Client = "enemy"
func local_team() -> String:
	return "player" if is_server() else "enemy"

## 远程玩家的阵营
func remote_team() -> String:
	return "enemy" if is_server() else "player"


## 新的一局开始加载时清空场景握手状态。双方各自在进入加载页前调用。
func reset_battle_scene_readiness() -> void:
	_local_battle_scene_ready = false
	_remote_battle_scene_ready = false


## 当前端已实例化 BattleScene 后调用。RPC 挂在 Autoload，远端仍在菜单/加载页也能安全接收。
func announce_battle_scene_ready() -> void:
	if _local_battle_scene_ready:
		return
	_local_battle_scene_ready = true
	if is_networked():
		_rpc_battle_scene_ready.rpc()


func is_remote_battle_scene_ready() -> bool:
	return _remote_battle_scene_ready


## 接收远端的战斗场景就绪通知。不能放在 BattleManager：其中一端加载较慢时该节点尚不存在。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_battle_scene_ready() -> void:
	if not is_networked() or _remote_battle_scene_ready:
		return
	_remote_battle_scene_ready = true
	remote_battle_scene_ready.emit()

## 获取本机所有 IPv4 地址（用于显示给对方）
func get_local_addresses() -> PackedStringArray:
	var addrs: PackedStringArray = []
	for ip in IP.get_local_addresses():
		# 过滤掉回环和 IPv6，保留局域网地址
		if ip != "127.0.0.1" and not ip.contains(":") and ip != "0.0.0.0":
			addrs.append(ip)
	return addrs


func _ready() -> void:
	# 连接 MultiplayerAPI 信号
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] peer connected: %d" % peer_id)
	# Host 收到 client 连入 → 进入 CONNECTED 状态
	if state == State.HOSTING:
		state = State.CONNECTED
		# 停止广播（已有人连入）
		_stop_broadcasting()
	connected_to_server.emit()
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] peer disconnected: %d" % peer_id)
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	# Client 端：成功连上服务器
	state = State.CONNECTED
	_stop_discovery()
	print("[NetworkManager] 已连接到服务器")
	connected_to_server.emit()


func _on_connection_failed() -> void:
	print("[NetworkManager] 连接失败")
	state = State.OFFLINE
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[NetworkManager] 服务器断开")
	state = State.OFFLINE
	server_disconnected.emit()


# ==============================================================================
# LAN 发现（UDP 广播）
# ==============================================================================

## Host 调用：开始广播自己的存在（让 client 能扫到）
func _start_broadcasting() -> void:
	_stop_discovery()
	_discovery = LanDiscovery.new()
	_discovery.start_broadcast()
	add_child(_discovery)


## Client 调用：开始扫描局域网中的主机
func start_scanning() -> void:
	_stop_discovery()
	_discovery = LanDiscovery.new()
	_discovery.host_found.connect(_on_host_found)
	_discovery.start_scan()
	add_child(_discovery)
	discovery_started.emit()
	print("[NetworkManager] 开始扫描局域网...")


## 停止扫描/广播
func stop_scanning() -> void:
	_stop_discovery()
	discovery_stopped.emit()


func _stop_broadcasting() -> void:
	# 广播和扫描共用 _discovery 对象，统一清理
	_stop_discovery()


func _stop_discovery() -> void:
	if _discovery != null and is_instance_valid(_discovery):
		_discovery.stop()
		_discovery.queue_free()
	_discovery = null


func _on_host_found(ip: String) -> void:
	host_discovered.emit(ip)


# ==============================================================================
# LanDiscovery 内部类
# ==============================================================================
## UDP 广播自动发现。两种模式：
##   broadcast：Host 每 DISCOVERY_INTERVAL 秒向有限广播 + 各子网定向广播地址发心跳
##   scan：Client 监听 DISCOVERY_PORT，收到广播就提取 Host IP 并发信号
class LanDiscovery extends Node:
	const BROADCAST_ADDR := "255.255.255.255"

	var _udp: PacketPeerUDP = null
	var _mode: String = ""  ## "broadcast" | "scan"
	var _timer: float = 0.0
	var _found_ips: Dictionary = {}  ## 已发现的主机 IP → 上次收到时间（去重）
	var _broadcast_targets: Array[String] = []  ## 预计算的广播目标地址列表

	signal host_found(ip: String)

	## Host 模式：启动广播
	## Host 绑定随机端口（port 0），只负责向 DISCOVERY_PORT 发广播，
	## 不占用固定端口——这样同机开两个实例（Host + Client）不会冲突
	func start_broadcast() -> void:
		_mode = "broadcast"
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		var err = _udp.bind(0, "0.0.0.0")
		if err != OK:
			printerr("[LanDiscovery] bind 失败（广播模式）: %d" % err)
			return
		# 预计算广播目标：255.255.255.255 + 各本地子网的定向广播地址
		_broadcast_targets = [BROADCAST_ADDR]
		for subnet_bcast in _get_subnet_broadcasts():
			if not _broadcast_targets.has(subnet_bcast):
				_broadcast_targets.append(subnet_bcast)
		print("[LanDiscovery] 广播目标: %s" % _format_targets(_broadcast_targets))
		_send_broadcast()  # 立即发一次

	## Client 模式：启动扫描
	func start_scan() -> void:
		_mode = "scan"
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		var err = _udp.bind(DISCOVERY_PORT, "0.0.0.0")
		if err != OK:
			printerr("[LanDiscovery] bind 失败（扫描模式）: %d — 可能端口 %d 被占用" % [err, DISCOVERY_PORT])
			return
		print("[LanDiscovery] 扫描已启动，监听 UDP %d" % DISCOVERY_PORT)

	## 停止并释放
	func stop() -> void:
		if _udp and _udp.is_bound():
			_udp.close()
		_udp = null

	func _process(delta: float) -> void:
		if _udp == null or not _udp.is_bound():
			return

		if _mode == "broadcast":
			_timer += delta
			if _timer >= DISCOVERY_INTERVAL:
				_timer = 0.0
				_send_broadcast()
		elif _mode == "scan":
			_process_incoming()

	## 发送广播包：向所有预计算目标（有限广播 + 子网定向广播）各发一份
	func _send_broadcast() -> void:
		var packet := (DISCOVERY_MAGIC + "\n").to_utf8_buffer()
		for addr in _broadcast_targets:
			_udp.set_dest_address(addr, DISCOVERY_PORT)
			var err = _udp.put_packet(packet)
			if err != OK:
				printerr("[LanDiscovery] 发送到 %s 失败: %d" % [addr, err])

	## 从本机所有 IP 推算子网定向广播地址（如 192.168.1.x → 192.168.1.255）
	## 家庭网络几乎都是 /24，此处按 /24 推算。过滤回环、IPv6、虚拟网段
	func _get_subnet_broadcasts() -> PackedStringArray:
		var result: PackedStringArray = []
		for ip in IP.get_local_addresses():
			# 跳过回环、IPv6、全零
			if ip == "127.0.0.1" or ip.contains(":") or ip == "0.0.0.0":
				continue
			var parts := ip.split(".")
			if parts.size() != 4:
				continue
			# 跳过常见虚拟网段（Docker/Hyper-V/VMware 的默认网段）
			if parts[0] == "172" and int(parts[1]) >= 17 and int(parts[1]) <= 31:
				# 172.17-31 是 Docker 等容器常用网段，大概率不是物理局域网
				continue
			# 按 /24 推算广播地址：前三段不变，第四段改为 255
			var bcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not result.has(bcast):
				result.append(bcast)
		return result

	## 格式化广播目标列表为逗号分隔字符串（调试日志用）
	func _format_targets(targets: Array[String]) -> String:
		var s := ""
		for i in range(targets.size()):
			if i > 0:
				s += ", "
			s += targets[i]
		return s

	## 接收并处理广播包
	func _process_incoming() -> void:
		while _udp.get_available_packet_count() > 0:
			var packet = _udp.get_packet()
			var text := packet.get_string_from_utf8().strip_edges()
			if text == DISCOVERY_MAGIC:
				var ip := _udp.get_packet_ip()
				# 去重：同一个 IP 只通知一次
				if not _found_ips.has(ip):
					_found_ips[ip] = Time.get_ticks_msec()
					host_found.emit(ip)
					print("[LanDiscovery] 发现主机: %s" % ip)
