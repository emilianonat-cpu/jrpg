extends Node
## Persistent state (autoload "GameState").
##
## Slayme starts from zero every day, so what is saved is almost only the trust
## of the mentor and the state of the world: the memory file *is* the mentor's
## memory. File: user://memory.json

signal trust_changed(value: int, step: int)
signal step_reached(step: int)

const MEMORY_PATH := "user://memory.json"
const MEMORY_VERSION := 1

var day := 1
var trust := 0
var flags: Dictionary = {}   # world flags that survive the night
var stats: Dictionary = {}   # counters (incidents, battles, days...)
var today: DayState = null


func new_game() -> void:
	day = 1
	trust = 0
	flags = {}
	stats = {}
	today = null
	Hooks.emit("game.new", {})


# ---- memory (save) -------------------------------------------------------

func has_memory() -> bool:
	return FileAccess.file_exists(MEMORY_PATH)


func write_memory() -> void:
	var data := {"version": MEMORY_VERSION, "day": day, "trust": trust, "flags": flags, "stats": stats}
	data = Hooks.filter("memory.write", data, {})
	DataFile.save_json(MEMORY_PATH, data)


func read_memory() -> bool:
	var data: Variant = DataFile.load_json(MEMORY_PATH, true)
	if not data is Dictionary:
		return false
	data = Hooks.filter("memory.read", data, {})
	day = int(data.get("day", 1))
	trust = int(data.get("trust", 0))
	flags = data.get("flags", {})
	stats = data.get("stats", {})
	return true


func forget() -> void:
	if has_memory():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MEMORY_PATH))


# ---- trust -----------------------------------------------------------------

## Step 1 at the start; thresholds in rules trust.step_thresholds.
func trust_step() -> int:
	var step := 0
	for t in Rules.list("trust.step_thresholds"):
		if trust >= int(t):
			step += 1
	return maxi(1, step)


func final_step() -> int:
	return Rules.integer("trust.final_step", 3)


## Award trust for a reason defined in rules trust.awards.<reason>.
## Each reason counts once per day unless trust.repeatable.<reason> is true.
func award(reason: String) -> int:
	if today != null and today.awarded.has(reason) and not Rules.flag("trust.repeatable." + reason, false):
		return 0
	var amount := Rules.integer("trust.awards." + reason, 0)
	amount = int(Hooks.filter("trust.gain", amount, {"reason": reason}))
	if amount == 0:
		return 0
	if today != null:
		today.awarded[reason] = true
	var prev_step := trust_step()
	trust += amount
	stat_add("trust_" + reason)
	trust_changed.emit(trust, trust_step())
	Hooks.emit("trust.changed", {"trust": trust, "reason": reason, "amount": amount})
	if trust_step() > prev_step:
		step_reached.emit(trust_step())
	return amount


# ---- days ------------------------------------------------------------------

func start_day() -> void:
	today = DayState.new()
	var tasks: Array = Content.dict("tasks").get("tasks", [])
	today.setup(day, tasks, variation_for(day))
	Hooks.emit("day.started", {"day": day, "variation": today.variation})


## Daily variations cycle through data/days.json.
func variation_for(day_no: int) -> Dictionary:
	var data := Content.dict("days")
	var list: Array = data.get("variations", [])
	var v: Dictionary = data.get("defaults", {}).duplicate(true)
	if not list.is_empty():
		v.merge(list[(day_no - 1) % list.size()], true)
	return Hooks.filter("day.variation", v, {"day": day_no})


## Evening: end-of-day awards, then the night, then the memory is written.
func end_day() -> void:
	if today != null:
		if today.all_core_done():
			award("all_tasks_done")
		if today.incidents == 0:
			award("no_incidents")
	Hooks.emit("day.ended", {"day": day})
	stat_add("days")
	day += 1
	today = null
	write_memory()


func stat_add(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n
