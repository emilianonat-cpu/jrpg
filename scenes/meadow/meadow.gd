extends Screen
## The Meadow: one working day, from the morning bell to the evening bell.
##
## Everything placed here comes from data/maps/meadow.json; the timetable from
## data/schedule.json; today's differences from data/days.json.
## Extend through hooks: "meadow.ready", "meadow.interact" (filter, return true
## to take over an interaction), "schedule.<event>" for new timetable events.

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

var map: Dictionary = {}
var day: DayState
var player: Player
var party: HeroParty = null
var focus: WorldObject = null
var busy := false
var talked_today: Dictionary = {}
var event_handlers: Dictionary = {}
var interact_handlers: Dictionary = {}
var _pending_events: Array = []
var _spawn := Vector2.ZERO
var _in_battle_flow := false

@onready var world: Node2D = $World
@onready var background: ArtSprite = $World/Background
@onready var objects: Node2D = $World/Objects
@onready var camera: Camera2D = $World/Camera
@onready var hud = $Hud
@onready var dialogue = $Dialogue
@onready var battle_layer: CanvasLayer = $BattleLayer


func enter(_payload: Dictionary) -> void:
	event_handlers = {
		"bell_morning": _ev_bell_morning,
		"hero_pass": _ev_hero_pass,
		"bell_evening": _ev_bell_evening,
	}
	interact_handlers = {
		"board": _use_board,
		"npc": _use_npc,
		"task_source": _use_source,
		"task_sink": _use_sink,
	}
	map = Content.dict("maps/meadow")
	GameState.start_day()
	day = GameState.today
	_build_world()
	hud.setup(day)
	day.task_progress.connect(func(_id, _p, _a): hud.refresh())
	day.carried_changed.connect(_on_carried_changed)
	Clock.ticked.connect(_on_tick)
	Hooks.emit("meadow.ready", {"screen": self})
	Clock.start_day()


func _exit_tree() -> void:
	if Clock.ticked.is_connected(_on_tick):
		Clock.ticked.disconnect(_on_tick)
	Clock.stop()


# ---- building the map from data -------------------------------------------

func _build_world() -> void:
	background.set_art(str(map.get("background", "")))
	var size := DataFile.vec2(map.get("size"), Vector2(320, 180))
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)
	for d in map.get("objects", []):
		if d.has("task") and not day.tasks.has(str(d.task)):
			continue  # e.g. a leftover job that is not today's
		var o := WorldObject.new()
		o.setup(d)
		objects.add_child(o)
	_build_pool_mates()
	_spawn = DataFile.vec2(map.get("spawn"), size / 2)
	player = Player.new()
	player.setup(str(map.get("player_art", "slime")), Rect2(Vector2(4, 4), size - Vector2(8, 8)))
	player.position = _spawn
	objects.add_child(player)
	camera.position = player.position


func _build_pool_mates() -> void:
	var pm: Dictionary = map.get("pool_mates", {})
	if pm.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = day.day
	var c := DataFile.vec2(pm.get("center"))
	var r := DataFile.vec2(pm.get("radius"), Vector2(20, 10))
	for i in int(pm.get("count", 0)):
		var a := rng.randf() * TAU
		var o := WorldObject.new()
		o.setup({"id": "pool_mate_%d" % i, "kind": "decor", "art": str(pm.get("art", "slime")),
			"pos": [c.x + cos(a) * r.x * rng.randf(), c.y + sin(a) * r.y * rng.randf()]})
		objects.add_child(o)


func objects_of_kind(kind: String) -> Array:
	return objects.get_children().filter(func(n): return n is WorldObject and n.kind == kind)


# ---- frame update ---------------------------------------------------------

func _process(_delta: float) -> void:
	if player == null:
		return
	camera.position = player.position
	player.frozen = busy
	if busy:
		return
	_update_hidden()
	_update_focus()
	_check_encounter()


func _update_hidden() -> void:
	var concealed := false
	for o in objects_of_kind("cover"):
		if o.position.distance_to(player.position) <= o.radius():
			concealed = true
	if concealed != player.concealed:
		player.set_hidden(concealed)


func _update_focus() -> void:
	var best: WorldObject = null
	var best_d := INF
	for n in objects.get_children():
		if n is WorldObject and n.is_interactable():
			var d: float = n.position.distance_to(player.position)
			if d <= n.radius() and d < best_d:
				best = n
				best_d = d
	if best != focus:
		focus = best
		hud.set_prompt(focus.prompt() if focus != null else "")


func _check_encounter() -> void:
	if party == null or party.ignore_player or player.concealed:
		return
	var r := Rules.num("world.encounter_radius", 18)
	for p in party.positions():
		if p.distance_to(player.position) <= r:
			_start_battle()
			return


func _unhandled_input(event: InputEvent) -> void:
	if busy:
		return
	if event.is_action_pressed("interact") and focus != null:
		get_viewport().set_input_as_handled()
		interact(focus)
	elif event.is_action_pressed("cancel") and day.carried != "":
		get_viewport().set_input_as_handled()
		day.set_carried("", "")
		hud.toast(Content.text("msg.spat_out"))


# ---- interactions -----------------------------------------------------------

func interact(o: WorldObject) -> void:
	if Hooks.filter("meadow.interact", false, {"object": o, "screen": self}):
		return
	var handler: Callable = interact_handlers.get(o.kind, Callable())
	if handler.is_valid():
		handler.call(o)


func _use_board(_o: WorldObject) -> void:
	var v := day.variation
	await say([{"speaker": "board", "text": str(v.get("board_notice", "board.notice.default")),
		"args": {"n": v.get("adventurers", 0)}}])


func _use_source(o: WorldObject) -> void:
	var r := day.absorb(str(o.data.task))
	hud.toast(Content.text(r.msg, {"item": _item_name(day.carried)}))


func _use_sink(o: WorldObject) -> void:
	var task_id := str(o.data.task)
	var r := day.release(task_id)
	var title := Content.text(str(day.task(task_id).get("def", {}).get("title", "")))
	hud.toast(Content.text(r.msg, {"title": title}))
	if r.get("completed", false) and bool(day.task(task_id).def.get("leftover", false)):
		GameState.award("leftover_finished")


func _use_npc(o: WorldObject) -> void:
	var talk: Dictionary = o.data.get("talk", {})
	match str(talk.get("mode", "simple")):
		"trust_owner":
			await _talk_trust_owner(o, talk)
		"warn":
			await _talk_warn(o, talk)
		_:
			await say(Content.dialogue(str(talk.get("file", "")), str(talk.get("sequence", "idle"))))


func _talk_trust_owner(o: WorldObject, talk: Dictionary) -> void:
	var file := str(talk.get("file", ""))
	var step := GameState.trust_step()
	if step >= GameState.final_step():
		await say(Content.dialogue(file, "question"))
		Hooks.emit("prototype.end", {})
		go("end")
		return
	var first := not talked_today.has(o.object_id())
	talked_today[o.object_id()] = true
	await say(Content.dialogue(file, ("greeting_step_%d" if first else "idle_step_%d") % step))


func _talk_warn(o: WorldObject, talk: Dictionary) -> void:
	var file := str(talk.get("file", ""))
	var next := next_hero_pass()
	var in_window := party == null and next >= 0.0 and next - Clock.minutes <= Rules.num("world.warn_window_minutes", 60)
	if in_window and day.flags.has("warned_" + o.object_id()):
		await say(Content.dialogue(file, "warned_already"))
	elif in_window:
		day.flags["warned_" + o.object_id()] = true
		await say(Content.dialogue(file, "warn"))
		GameState.award("warned_colleague")
	else:
		await say(Content.dialogue(file, "idle"))


## Plays dialogue lines, pausing the clock and Slayme.
func say(lines: Array) -> int:
	busy = true
	hud.set_prompt("")
	if Rules.flag("clock.pause_in_dialogue", true):
		Clock.pause("dialogue")
	var choice: int = await dialogue.play(lines)
	Clock.resume("dialogue")
	busy = false
	focus = null
	if not _in_battle_flow:
		_flush_pending()
	return choice


func _item_name(item_id: String) -> String:
	var item: Dictionary = Content.dict("items").get(item_id, {})
	return Content.name_of(str(item.get("name", item_id)))


func _on_carried_changed(item_id: String) -> void:
	player.show_item(item_id)
	hud.refresh()


# ---- the timetable --------------------------------------------------------------

func _event_time(e: Dictionary) -> float:
	var t := DataFile.to_minutes(e.get("time", 0))
	if str(e.get("event", "")) == "hero_pass":
		t += float(day.variation.get("hero_delay", 0))
	return t


func next_hero_pass() -> float:
	var best := -1.0
	for e in Content.dict("schedule").get("events", []):
		if str(e.get("event", "")) == "hero_pass":
			var t := _event_time(e)
			if t > Clock.minutes and (best < 0.0 or t < best):
				best = t
	return best


func _on_tick(prev: float, now: float) -> void:
	hud.set_time(now)
	for e in Content.dict("schedule").get("events", []):
		if Clock.crossed(_event_time(e), prev, now):
			_pending_events.append(str(e.get("event", "")))
	if not busy:
		_flush_pending()


func _flush_pending() -> void:
	while not busy and not _pending_events.is_empty():
		var ev: String = _pending_events.pop_front()
		var handler: Callable = event_handlers.get(ev, Callable())
		if handler.is_valid():
			handler.call()
		else:
			Hooks.emit("schedule." + ev, {"screen": self})


func _ev_bell_morning() -> void:
	Art.play_sound("bell")
	await say(Content.dialogue("world", "bell_morning"))


func _ev_hero_pass() -> void:
	if party != null:
		return
	party = HeroParty.new()
	objects.add_child(party)
	party.setup(map.get("path", []), day.variation.get("party", []))
	party.left_meadow.connect(func(): party = null)
	if player.concealed:
		GameState.award("hid_before_heroes")
	Hooks.emit("heroes.appeared", {"screen": self})


func _ev_bell_evening() -> void:
	Art.play_sound("bell")
	await say(Content.dialogue("world", "bell_evening"))
	busy = true
	go("home")


# ---- battle ----------------------------------------------------------------------

func battle_terrain_here() -> Array:
	var out := []
	var r := Rules.num("world.battle_terrain_radius", 48)
	for n in objects.get_children():
		if n is WorldObject and n.data.has("battle_terrain") and n.position.distance_to(player.position) <= r:
			var t := str(n.data.battle_terrain)
			if not out.has(t):
				out.append(t)
	return out


func _start_battle() -> void:
	busy = true
	_in_battle_flow = true
	hud.visible = false
	hud.set_prompt("")
	Clock.pause("battle")
	party.paused = true
	var b = BATTLE_SCENE.instantiate()
	battle_layer.add_child(b)
	b.start(day.variation.get("party", []), battle_terrain_here(), day.carried)
	var res: Dictionary = await b.battle_finished
	b.queue_free()
	await _after_battle(res)


func _after_battle(res: Dictionary) -> void:
	GameState.stat_add("battles")
	hud.visible = true
	if party != null:
		party.paused = false
	if str(res.get("item", "")) != day.carried:
		day.set_carried(str(res.get("item", "")), "")
	match str(res.get("outcome", "")):
		"incident":
			await _incident()
		"fled":
			if party != null:
				party.ignore_player = true
		"bored":
			if party != null:
				party.queue_free()
				party = null
	Clock.resume("battle")
	busy = false
	_in_battle_flow = false
	Clock.advance(float(res.get("rounds", 0)) * Rules.num("battle.minutes_per_round", 3))


func _incident() -> void:
	day.on_incident()
	GameState.stat_add("incidents")
	if party != null:
		party.ignore_player = true  # they got their EXP, they move on
	player.position = _spawn
	camera.position = _spawn
	Art.play_sound("bell")
	await say(Content.dialogue("world", "incident"))
	Clock.advance(Rules.num("incident.clock_penalty_minutes", 60))
	Hooks.emit("slime.incident", {"screen": self})
