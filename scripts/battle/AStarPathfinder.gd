# 文件名：AStarPathfinder.gd
# 作用：基于格系统的 A* 网格寻路。将塔/建筑/河道标记为障碍物，
#       为地面单位规划绕行路径。空中单位不需要寻路（直线飞行）。
#       替代旧版 steering 避让（_compute_obstacle_avoidance），解决塔群密集区域卡死问题。
# 挂载位置：不需要挂载。通过 class_name 注册为全局类型。
# 初学者阅读建议：先看 find_path() 了解入口，再看 _astar() 了解搜索算法。

class_name AStarPathfinder

const GRID_W := BattleConstants.MAP_TILES_W  ## 网格宽度（格）= 18
const GRID_H := BattleConstants.MAP_TILES_H  ## 网格高度（格）= 32

## 障碍物膨胀安全余量（格）。路径不紧贴塔边缘，留出缓冲。
const SAFETY_MARGIN := 0.25

## 对角线移动代价（√2）。
const DIAG_COST := 1.41421

## line-of-sight 采样步长（格），用于路径平滑检查。
const LOS_SAMPLE_STEP := 0.3

## 河道格 y 范围（含两端）。推导：RIVER_Y_MIN=300, RIVER_Y_MAX=340, CELL_SIZE=20 → 格 15~16
const RIVER_CELL_Y_MIN := 15
const RIVER_CELL_Y_MAX := 16

## 4 方向直行偏移。
const DIRS_4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## 4 方向对角线偏移。
const DIRS_DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## 为地面单位计算从 from_pos 到 to_pos 的路径。
## mover_radius_cells: 单位碰撞半径（格），用于障碍物膨胀。
## 返回路径点数组（像素坐标），不含起点，含终点。
## 无需绕行时返回 [to_pos]；完全无路径时也返回 [to_pos]（兜底直线走）。
static func find_path(from_pos: Vector2, to_pos: Vector2, mover_radius_cells: float) -> Array:
	var grid := _build_blocked_grid(mover_radius_cells)

	var start_cell := _pos_to_cell(from_pos)
	var goal_cell := _pos_to_cell(to_pos)
	start_cell = _clamp_cell(start_cell)
	goal_cell = _clamp_cell(goal_cell)

	# 起点在障碍物内（如单位被卡在塔旁）→ 找最近可通行格
	if _is_blocked(start_cell, grid):
		start_cell = _find_nearest_free_cell(start_cell, grid)
		if start_cell == Vector2i(-1, -1):
			return [to_pos]

	# 目标在障碍物内（如目标是塔）→ 沿接近方向退到边缘外
	if _is_blocked(goal_cell, grid):
		goal_cell = _find_approach_cell(start_cell, goal_cell, grid)
		if goal_cell == Vector2i(-1, -1):
			goal_cell = _find_nearest_free_cell(_pos_to_cell(to_pos), grid)
			if goal_cell == Vector2i(-1, -1):
				return [to_pos]

	# A* 搜索
	var raw_path := _astar(start_cell, goal_cell, grid)
	if raw_path.is_empty():
		return [to_pos]

	# 格中心 → 像素坐标
	var pixel_points: Array = []
	for cell in raw_path:
		pixel_points.append(_cell_to_pos(cell))

	# 路径平滑：从精确起点做 line-of-sight 简化
	var smoothed := _smooth_path(from_pos, pixel_points, grid)

	# 最后一个点替换为精确目标位置
	if not smoothed.is_empty():
		smoothed[-1] = to_pos

	return smoothed


# ============================================================
#  网格构建
# ============================================================

## 构建障碍物网格。返回 Dictionary[Vector2i] = true 表示该格被阻塞。
## 障碍物 = 河道（非桥面）+ 所有 mass=0 实体（塔/建筑），按 mover_radius + SAFETY_MARGIN 膨胀。
static func _build_blocked_grid(mover_radius_cells: float) -> Dictionary:
	var blocked := {}

	# 1. 河道格（非桥面）标记为不可通行
	for x in range(GRID_W):
		for y in range(RIVER_CELL_Y_MIN, RIVER_CELL_Y_MAX + 1):
			var cell := Vector2i(x, y)
			if not _is_bridge_cell(cell):
				blocked[cell] = true

	# 2. 塔/建筑碰撞体膨胀
	var inflate := mover_radius_cells + SAFETY_MARGIN
	for obs in EntityRegistry.get_static_obstacles():
		if not is_instance_valid(obs):
			continue
		var obs_pos := BattlePathing.game_position_of(obs)
		var obs_r_raw = obs.get("collision_radius")
		var obs_r_cells: float = (float(obs_r_raw) / BattleConstants.CELL_SIZE) if obs_r_raw != null else 0.5
		var total_r := obs_r_cells + inflate
		# 障碍物中心在格坐标系中的浮点坐标
		var cx_f := obs_pos.x / BattleConstants.CELL_SIZE
		var cy_f := obs_pos.y / BattleConstants.CELL_SIZE
		# 遍历覆盖范围内的所有格
		var min_x := maxi(0, int(floor(cx_f - total_r)))
		var max_x := mini(GRID_W - 1, int(ceil(cx_f + total_r)))
		var min_y := maxi(0, int(floor(cy_f - total_r)))
		var max_y := mini(GRID_H - 1, int(ceil(cy_f + total_r)))
		for gx in range(min_x, max_x + 1):
			for gy in range(min_y, max_y + 1):
				# 格中心到障碍物中心的距离
				var dx := (gx + 0.5) - cx_f
				var dy := (gy + 0.5) - cy_f
				if sqrt(dx * dx + dy * dy) <= total_r:
					blocked[Vector2i(gx, gy)] = true

	return blocked


## 格中心是否在桥 x 范围内。
static func _is_bridge_cell(cell: Vector2i) -> bool:
	var center_x := (cell.x + 0.5) * BattleConstants.CELL_SIZE
	var on_left := center_x >= BattleConstants.LEFT_BRIDGE_X_MIN and center_x <= BattleConstants.LEFT_BRIDGE_X_MAX
	var on_right := center_x >= BattleConstants.RIGHT_BRIDGE_X_MIN and center_x <= BattleConstants.RIGHT_BRIDGE_X_MAX
	return on_left or on_right


# ============================================================
#  A* 搜索
# ============================================================

## A* 搜索核心。返回格路径 [start, ..., goal]，无路径返回 []。
static func _astar(start: Vector2i, goal: Vector2i, grid: Dictionary) -> Array:
	if start == goal:
		return [start]

	var open: Array[Vector2i] = [start]
	var open_set := {start: true}
	var closed := {}
	var g_score := {start: 0.0}
	var f_score := {start: _heuristic(start, goal)}
	var came_from := {}

	var max_iter := GRID_W * GRID_H * 2  # 安全阀
	var iter := 0

	while not open.is_empty() and iter < max_iter:
		iter += 1

		# 找 open 中 f_score 最小的节点（线性扫描，网格小够快）
		var best_idx := 0
		var best_f: float = f_score.get(open[0], INF)
		for i in range(1, open.size()):
			var f: float = f_score.get(open[i], INF)
			if f < best_f:
				best_f = f
				best_idx = i

		var current: Vector2i = open[best_idx]

		if current == goal:
			# 回溯路径
			var path: Array[Vector2i] = [current]
			var c: Vector2i = current
			while came_from.has(c):
				c = came_from[c]
				path.push_front(c)
			return path

		open.pop_at(best_idx)
		open_set.erase(current)
		closed[current] = true

		# 遍历邻居
		for neighbor in _get_neighbors(current, grid):
			if closed.has(neighbor):
				continue

			var move_cost := DIAG_COST if (neighbor.x != current.x and neighbor.y != current.y) else 1.0
			var tentative_g: float = g_score[current] + move_cost

			if not open_set.has(neighbor):
				open.push_back(neighbor)
				open_set[neighbor] = true
			elif tentative_g >= g_score.get(neighbor, INF):
				continue  # 不是更好的路径

			came_from[neighbor] = current
			g_score[neighbor] = tentative_g
			f_score[neighbor] = tentative_g + _heuristic(neighbor, goal)

	return []  # 无路径


## 对角线距离启发式（8 方向移动的最优启发式）。
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxf(dx, dy) + minf(dx, dy) * (DIAG_COST - 1.0)


## 获取格的可通行邻居（8 方向，禁止对角线穿越角落）。
static func _get_neighbors(cell: Vector2i, grid: Dictionary) -> Array:
	var neighbors: Array = []
	# 4 方向直行
	for d in DIRS_4:
		var n: Vector2i = cell + d
		if _is_valid_cell(n) and not _is_blocked(n, grid):
			neighbors.append(n)
	# 对角线：两侧不能都是障碍（防止穿角）
	for d in DIRS_DIAG:
		var n: Vector2i = cell + d
		if not _is_valid_cell(n) or _is_blocked(n, grid):
			continue
		var side1 := Vector2i(cell.x + d.x, cell.y)
		var side2 := Vector2i(cell.x, cell.y + d.y)
		if _is_blocked(side1, grid) and _is_blocked(side2, grid):
			continue
		neighbors.append(n)
	return neighbors


# ============================================================
#  路径平滑（line-of-sight 简化）
# ============================================================

## 从 from_pos 出发，沿 cell_path 做视线检查，跳过可直接到达的中间点。
## 返回简化后的路径点列表（不含 from_pos）。
static func _smooth_path(from_pos: Vector2, cell_path: Array, grid: Dictionary) -> Array:
	if cell_path.size() <= 1:
		return cell_path.duplicate()

	# 构建候选点列表：[from_pos, cell0, cell1, ..., cellN]
	var points: Array = [from_pos]
	for p in cell_path:
		points.append(p)

	var result: Array = []
	var anchor := 0
	while anchor < points.size() - 1:
		var farthest := anchor + 1
		for i in range(anchor + 2, points.size()):
			if _has_line_of_sight(points[anchor], points[i], grid):
				farthest = i
			else:
				break
		result.append(points[farthest])
		anchor = farthest

	return result


## 两点之间是否有无障碍直线视线。超采样检查路径上每个采样点。
static func _has_line_of_sight(from: Vector2, to: Vector2, grid: Dictionary) -> bool:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return true
	var steps := maxi(1, int(dist / (BattleConstants.CELL_SIZE * LOS_SAMPLE_STEP)))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		if _is_blocked(_pos_to_cell(p), grid):
			return false
	return true


# ============================================================
#  辅助方法
# ============================================================

static func _pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / BattleConstants.CELL_SIZE)), int(floor(pos.y / BattleConstants.CELL_SIZE)))


static func _cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * BattleConstants.CELL_SIZE, (cell.y + 0.5) * BattleConstants.CELL_SIZE)


static func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_W and cell.y >= 0 and cell.y < GRID_H


static func _clamp_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, 0, GRID_W - 1), clampi(cell.y, 0, GRID_H - 1))


static func _is_blocked(cell: Vector2i, grid: Dictionary) -> bool:
	return grid.has(cell)


## BFS 找离 center 最近的非障碍格。完全被包围时返回 (-1, -1)。
static func _find_nearest_free_cell(center: Vector2i, grid: Dictionary) -> Vector2i:
	if not _is_blocked(center, grid) and _is_valid_cell(center):
		return center
	# 螺旋向外搜索（BFS）
	var queue: Array[Vector2i] = [center]
	var visited := {center: true}
	var max_iter := GRID_W * GRID_H
	var iter := 0
	while not queue.is_empty() and iter < max_iter:
		iter += 1
		var cell: Vector2i = queue.pop_front()
		for d in DIRS_4:
			var n: Vector2i = cell + d
			if not _is_valid_cell(n) or visited.has(n):
				continue
			visited[n] = true
			if not _is_blocked(n, grid):
				return n
			queue.append(n)
	return Vector2i(-1, -1)


## 从 goal 沿 start→goal 反方向退，找到第一个非障碍格。
## 确保单位从正确方向接近目标（如塔），而不是绕到错误的一侧。
static func _find_approach_cell(start: Vector2i, goal: Vector2i, grid: Dictionary) -> Vector2i:
	var dir := Vector2(goal.x - start.x, goal.y - start.y)
	if dir.length() < 0.01:
		return _find_nearest_free_cell(goal, grid)
	dir = dir.normalized()
	var check_f := Vector2(goal)
	for i in range(20):
		check_f -= dir
		var check_cell := Vector2i(int(round(check_f.x)), int(round(check_f.y)))
		check_cell = _clamp_cell(check_cell)
		if not _is_blocked(check_cell, grid):
			return check_cell
	return _find_nearest_free_cell(goal, grid)
