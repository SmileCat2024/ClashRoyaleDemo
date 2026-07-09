# 文件名：DebugBattle.gd
# 作用：独立测试场景的控制器。不经过主菜单，直接进入战斗。
#       K = 生成玩家骑士 | J = 生成敌方骑士 | D = 打印所有实体状态
#       1=骑士 2=火枪手 3=小皮卡 4=野猪骑士 5=气球兵（玩家方，鼠标位置）
# 挂载位置：DebugBattle.tscn 的根节点
# 初学者阅读建议：看 _setup_towers() 了解塔怎么初始化和注册。

extends Node2D

@onready var _world: Node2D = $World
@onready var spawn_manager: Node = $Managers/SpawnManager


func _ready() -> void:
	EntityRegistry.clear()
	_setup_towers()
	print("[DebugBattle] ready | K=player knight | J=enemy knight | D=dump | 1-5=spawn units")


## 遍历 UnitsRoot 下的所有塔（TowerBase 实例），根据节点名称推断阵营和类型，初始化并注册
func _setup_towers() -> void:
	for tower in $World/UnitsRoot.get_children():
		if tower is TowerBase:
			var name_lower = tower.name.to_lower()
			var team_name = "player" if "player" in name_lower else "enemy"
			var type_name = "king" if "king" in name_lower else "guard"
			var data_key = type_name + "_tower"
			var data = DataRegistry.get_tower_data(data_key)
			if BattleConstants.TOWER_PIXEL_POSITIONS.has(tower.name):
				tower.position = BattleConstants.TOWER_PIXEL_POSITIONS[tower.name]
			tower.setup(data, team_name, tower.name)
			EntityRegistry.register(tower)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var pos = _world.get_local_mouse_position()
		match event.keycode:
			KEY_K:
				spawn_manager.spawn_unit("card_knight", "player", pos)
			KEY_J:
				spawn_manager.spawn_unit("card_knight", "enemy", pos)
			KEY_D:
				EntityRegistry.dump()
			KEY_1:
				spawn_manager.spawn_unit("card_knight", "player", pos)
			KEY_2:
				spawn_manager.spawn_unit("card_musketeer", "player", pos)
			KEY_3:
				spawn_manager.spawn_unit("card_mini_pekka", "player", pos)
			KEY_4:
				spawn_manager.spawn_unit("card_hog_rider", "player", pos)
			KEY_5:
				spawn_manager.spawn_unit("card_balloon", "player", pos)
