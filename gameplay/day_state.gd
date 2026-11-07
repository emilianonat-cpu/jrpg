class_name DayState
extends RefCounted
## Everything that happens during one day. Slayme forgets it all at night;
## only GameState (the mentor's memory) survives.
##
## Tasks (data/tasks.json): absorb an item at the task's source, release it at
## the task's sink, `amount` times. Slayme carries one thing at a time.

signal task_progress(task_id: String, progress: int, amount: int)
signal task_completed(task_id: String)
signal carried_changed(item_id: String)

var day := 1
var variation: Dictionary = {}
var tasks: Dictionary = {}      # id -> {def, progress, start, amount}
var carried := ""               # item id inside Slayme
var carried_from := ""          # task id the item belongs to
var incidents := 0
var awarded: Dictionary = {}    # trust reasons already awarded today
var flags: Dictionary = {}      # free per-day flags for future mechanics
var taken: Dictionary = {}      # pickup object id -> true (screens mode)
var filled: Dictionary = {}     # one-item sink object id -> true (screens mode)
var carried_pickup := ""        # the pickup object Slayme is carrying


func setup(day_no: int, task_defs: Array, day_variation: Dictionary) -> void:
	day = day_no
	variation = day_variation
	tasks.clear()
	var leftover: Dictionary = variation.get("leftover", {})
	for def in task_defs:
		var id := str(def.id)
		var is_leftover := bool(def.get("leftover", false))
		if is_leftover and str(leftover.get("task", "")) != id:
			continue  # only today's leftover job exists
		var start := int(leftover.get("progress", 0)) if is_leftover else 0
		tasks[id] = {"def": def, "progress": start, "start": start, "amount": int(def.get("amount", 1))}


func task(id: String) -> Dictionary:
	return tasks.get(id, {})


func is_done(id: String) -> bool:
	var t := task(id)
	return not t.is_empty() and t.progress >= t.amount


func core_tasks() -> Array:
	return tasks.keys().filter(func(id): return not bool(tasks[id].def.get("leftover", false)))


func leftover_task() -> String:
	for id in tasks.keys():
		if bool(tasks[id].def.get("leftover", false)):
			return id
	return ""


func all_core_done() -> bool:
	for id in core_tasks():
		if not is_done(id):
			return false
	return true


## Absorb the task's item from its source. Returns {ok, msg} (msg is a text key).
func absorb(task_id: String) -> Dictionary:
	var t := task(task_id)
	if t.is_empty():
		return {"ok": false, "msg": "msg.nothing_here"}
	if carried != "":
		return {"ok": false, "msg": "msg.already_full"}
	if is_done(task_id):
		return {"ok": false, "msg": "msg.task_already_done"}
	set_carried(str(t.def.item), task_id)
	return {"ok": true, "msg": "msg.absorbed"}


## Release the carried item at the task's sink.
func release(task_id: String) -> Dictionary:
	var t := task(task_id)
	if t.is_empty():
		return {"ok": false, "msg": "msg.nothing_here"}
	if is_done(task_id):
		return {"ok": false, "msg": "msg.task_already_done"}
	if carried == "":
		return {"ok": false, "msg": "msg.nothing_to_release"}
	if carried != str(t.def.item):
		return {"ok": false, "msg": "msg.wrong_item"}
	set_carried("", "")
	t.progress += 1
	task_progress.emit(task_id, t.progress, t.amount)
	if t.progress >= t.amount:
		task_completed.emit(task_id)
		Hooks.emit("task.completed", {"task": task_id, "leftover": bool(t.def.get("leftover", false))})
		return {"ok": true, "msg": "msg.task_completed", "completed": true}
	return {"ok": true, "msg": "msg.released"}


func set_carried(item_id: String, from_task: String = "") -> void:
	carried = item_id
	carried_from = from_task
	carried_pickup = ""
	carried_changed.emit(item_id)


## Absorb a specific object lying on the ground.
func take_pickup(object_id: String, task_id: String) -> Dictionary:
	var r := absorb(task_id)
	if r.ok:
		taken[object_id] = true
		carried_pickup = object_id
	return r


## Spit out what Slayme carries: a pickup goes back on the ground.
func put_back() -> void:
	if carried_pickup != "":
		taken.erase(carried_pickup)
	set_carried("", "")


## Release into a one-item sink (e.g. one patch of grass).
func fill_slot(object_id: String, task_id: String) -> Dictionary:
	if filled.has(object_id):
		return {"ok": false, "msg": "msg.task_already_done"}
	var r := release(task_id)
	if r.ok:
		filled[object_id] = true
	return r


## Undo a finished job (heroes passing by), with its pickups back on the ground.
func reset_task(task_id: String, pickup_ids: Array) -> void:
	var t := task(task_id)
	if t.is_empty():
		return
	t.progress = 0
	for id in pickup_ids:
		taken.erase(id)
	task_progress.emit(task_id, 0, t.amount)


## An incident: what Slayme carried is lost and (rule) the task goes back.
func on_incident() -> void:
	incidents += 1
	if carried_pickup != "":
		taken.erase(carried_pickup)  # the shard is back where it was
	if carried_from != "" and Rules.flag("incident.reset_task_progress", true) and tasks.has(carried_from):
		var t: Dictionary = tasks[carried_from]
		if t.progress < t.amount:
			t.progress = t.start
			task_progress.emit(carried_from, t.progress, t.amount)
	set_carried("", "")
