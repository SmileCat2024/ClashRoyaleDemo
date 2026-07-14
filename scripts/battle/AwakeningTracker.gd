# 文件名：AwakeningTracker.gd
# 作用：追踪觉醒牌的打出次数，实现"循环觉醒"机制（皇室战争原版规则）。
#       每张觉醒牌有自己的 trigger_count（触发阈值），按 team + card_id 独立计数。
#       打出 trigger_count 次普通版后，下一次打出为觉醒版（附加 effects 效果）。
#       觉醒版打完后重置计数，从 0 重新累计——整局可多次觉醒。
# 挂载位置：BattleManager 动态创建并 add_child（与 DeckManager 平级）。
# 初学者阅读建议：先看 peek_next_effects() 和 record_play() 理解"预览-提交"两步流程。
#
# 状态机说明（以 trigger_count=2 为例）：
#   初始     count=0, next=false → 打出普通版，count→1
#   第 2 次  count=1, next=false → 打出普通版，count→2 达阈值，next=true，count→0
#   第 3 次  next=true           → 打出觉醒版（附加 effects），next=false
#   第 4 次  count=0, next=false → 打出普通版，count→1 ... 循环
#
# 两步流程（避免出牌失败时错误计数）：
#   1. peek_next_effects(team, card_id) → 只读预览效果，传给 SpawnManager 生成实体
#   2. record_play(team, card_id)       → 出牌成功后提交计数变更

class_name AwakeningTracker
extends Node

## 每张觉醒牌的运行时状态，按 "team:card_id" 组合 key 存储。
## key: String, value: { "count": int, "next_awakened": bool }
var _states: Dictionary = {}


## 内部：生成组合 key
static func _key(team: String, card_id: String) -> String:
	return "%s:%s" % [team, card_id]


## 预览下一次打出该牌的觉醒效果配置（只读，不改变状态）。
## 返回非空字典 = 下次为觉醒版，字典内容 = card_data.awakening.effects。
## 返回空字典 = 非觉醒牌，或下次不是觉醒版。
## BattleManager 在生成实体前调用此方法获取效果，传给 SpawnManager / SpellManager。
func peek_next_effects(team: String, card_id: String) -> Dictionary:
	var card := DataRegistry.get_card_data(card_id)
	if not card.has("awakening"):
		return {}
	if is_next_awakened(team, card_id):
		return card["awakening"].get("effects", {})
	return {}


## 记录一次出牌，更新觉醒计数状态。在出牌成功后调用（实体已生成、能量已扣）。
## 注意：不返回效果——效果应在出牌前通过 peek_next_effects 获取。
func record_play(team: String, card_id: String) -> void:
	var card := DataRegistry.get_card_data(card_id)
	if not card.has("awakening"):
		return  # 非觉醒牌

	var awakening: Dictionary = card["awakening"]
	var trigger_count: int = int(awakening.get("trigger_count", 1))
	# trigger_count=0 → 永久觉醒，无需计数
	if trigger_count <= 0:
		return
	var k := _key(team, card_id)

	# 懒初始化状态
	if not _states.has(k):
		_states[k] = {"count": 0, "next_awakened": false}
	var state: Dictionary = _states[k]

	# 判断本次是否为觉醒版
	if bool(state["next_awakened"]):
		# 觉醒版打出：重置计数（循环模式）
		state["count"] = 0
		state["next_awakened"] = false
		_emit_progress(team, card_id, trigger_count, state)
		return

	# 普通版打出：累加计数
	state["count"] = int(state["count"]) + 1
	# 达到阈值：标记下一次为觉醒版，重置计数器
	if int(state["count"]) >= trigger_count:
		state["next_awakened"] = true
		state["count"] = 0

	_emit_progress(team, card_id, trigger_count, state)


## 查询某张觉醒牌的当前进度（只读，不改变状态）。
## 返回 { count, trigger_count, next_awakened }。非觉醒牌返回空字典。
func get_progress(team: String, card_id: String) -> Dictionary:
	var card := DataRegistry.get_card_data(card_id)
	if not card.has("awakening"):
		return {}
	var awakening: Dictionary = card["awakening"]
	var trigger_count: int = int(awakening.get("trigger_count", 1))
	var k := _key(team, card_id)
	if not _states.has(k):
		return {"count": 0, "trigger_count": trigger_count, "next_awakened": false}
	var state: Dictionary = _states[k]
	return {
		"count": int(state["count"]),
		"trigger_count": trigger_count,
		"next_awakened": bool(state["next_awakened"]),
	}


## 下一次打出该牌是否为觉醒版（用于 UI 高亮 / 部署预览区分）
func is_next_awakened(team: String, card_id: String) -> bool:
	var card := DataRegistry.get_card_data(card_id)
	if not card.has("awakening"):
		return false
	var trigger_count := int(card["awakening"].get("trigger_count", 1))
	# trigger_count=0 → 每次打出都是觉醒版
	if trigger_count <= 0:
		return true
	var progress := get_progress(team, card_id)
	return bool(progress.get("next_awakened", false))


## 重置所有觉醒状态（重开战斗时调用）
func reset() -> void:
	_states.clear()


## 战斗开始时广播所有觉醒牌的初始进度（供 UI 初始化显示）。
## 由 BattleManager.start_battle 延迟调用，确保 CardBar 已连接信号。
func broadcast_initial_progress() -> void:
	for card_id in DataRegistry.card_data:
		var card: Dictionary = DataRegistry.card_data[card_id]
		if card.has("awakening"):
			var awakening: Dictionary = card["awakening"]
			var trigger_count: int = int(awakening.get("trigger_count", 1))
			# trigger_count=0 → 每次都是觉醒版
			var next_aw := trigger_count <= 0
			_emit_progress("player", card_id, trigger_count, {"count": 0, "next_awakened": next_aw})


## 内部：广播某张牌的觉醒进度变化
func _emit_progress(team: String, card_id: String, trigger_count: int, state: Dictionary) -> void:
	SignalBus.awakening_progress_changed.emit(
		team, card_id,
		int(state["count"]), trigger_count, bool(state["next_awakened"])
	)
