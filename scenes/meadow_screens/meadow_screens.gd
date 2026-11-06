extends Screen
## The Meadow as fixed screens (rule world.mode = "screens").
##
## Every screen comes from data/locations.json. No free movement: the player
## points at something (mouse, or arrows + Z), Slayme slides there and does
## the obvious thing: absorb, carry, put back, hide, talk, leave.
## The heroes cross some screens at fixed times (heroes.json "route").
## The day's incidents are planned (days.json "incidents"): the board's number
## is their count, and the bell rings everywhere when one happens.

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

var day: DayState
var data: Dictionary = {}
var location_id := ""
var location: Dictionary = {}
var player: Player
var focus: WorldObject = null
var busy := false
var cover_id := ""                     # the cover Slayme is hiding in, if any
var walker: HeroParty = null           # the party on this screen
var passes: Array = []                 # active hero passes: {start, warned: {}, entered: {}}
var talked: Dictionary = {}            # npc id -> talks today
var event_handlers: Dictionary = {}
var interact_handlers: Dictionary = {}
var _pending: Array = []
var _incidents: Array = []             # today's planned incidents: {time, who, done, cancelled}
var _in_battle_flow := false
var _mouse_pos := Vector2(-100, -100)

var _clock_session := -1

@onready var world: Node2D = $World
@onready var background: ArtSprite = $World/Background
@onready var objects: Node2D = $World/Objects
@onready var cursor: ArtSprite = $World/Cursor
@onready var hud = $Hud
@onready var dialogue = $Dialogue
@onready var battle_layer: CanvasLayer = $BattleLayer


func enter(_payload: Dictionary) -> void:
	event_handlers = {
		"bell_morning": _ev_bell_morning,
		"hero_pass": _ev_hero_pass,
		"bell_evening": _ev_bell_evening,
		"day_end": _ev_day_end,
	}
	interact_handlers = {
		"pickup": _use_pickup, "source": _use_source, "sink": _use_sink,
		"cover": _use_cover, "board": _use_board, "npc": _use_npc,
		"exit": _use_exit, "exit_home": _use_exit_home,
	}
	data = Content.dict("locations")
	GameState.start_day()
	day = GameState.today
	_prepare_day()
	cursor.set_art("cursor_focus")
	cursor.visible = false
	hud.setup(day)
	day.carried_changed.connect(_on_carried_changed)
	Clock.ticked.connect(_on_tick)
	show_location(str(data.get("start", "pool")))
	Hooks.emit("meadow.ready", {"screen": self})
	Clock.start_day()
	_clock_session = Clock.session


func _exit_tree() -> void:
	if Clock.ticked.is_connected(_on_tick):
		Clock.ticked.disconnect(_on_tick)
	Clock.stop(_clock_session)


## Leftover progress: some shards are already on the pedestal this morning.
func _prepare_day() -> void:
	for task_id in day.tasks.keys():
		var start := int(day.tasks[task_id].start)
		for o in _all_objects_of_task(task_id, "pickup").slice(0, start):
			day.taken[o.id] = true
		for o in _all_objects_of_task(task_id, "sink").filter(func(x): return x.get("slot", false)).slice(0, start):
			day.filled[o.id] = true
	for inc in day.variation.get("incidents", []):
		_incidents.append({"time": DataFile.to_minutes(inc.get("time", "12:00")), "who": str(inc.get("who", "")),
			"done": false, "cancelled": false})


func _all_objects_of_task(task_id: String, kind: String) -> Array:
	var out := []
	for loc in data.get("locations", {}).values():
		for o in loc.get("objects", []):
			if str(o.get("task", "")) == task_id and str(o.get("kind", "")) == kind:
				out.append(o)
	return out


func planned_incidents() -> int:
	return _incidents.size()


# ---- screens -------------------------------------------------------------------

func show_location(id: String, from: String = "") -> void:
	location_id = id
	location = data.get("locations", {}).get(id, {})
	for c in objects.get_children():
		c.queue_free()
	walker = null
	cover_id = ""
	focus = null
	background.set_art(str(location.get("background", "")))
	hud.set_place(Content.name_of(str(location.get("name", id))))
	for d in location.get("objects", []):
		if not _object_visible(d):
			continue
		var o := WorldObject.new()
		o.setup(d)
		objects.add_child(o)
		_refresh_object(o)
	_build_pool_mates()
	player = Player.new()
	player.setup(str(data.get("player_art", "slime")), Rect2(0, 0, 320, 180))
	player.frozen = true
	player.position = _entry_point(from)
	objects.add_child(player)
	player.show_item(_carried_art_item())
	_update_focus()
	# The party may already be crossing this screen.
	for p in passes:
		var seg := _segment_now(p)
		if not seg.is_empty() and str(seg.location) == location_id:
			_spawn_walker(p, seg)
	Hooks.emit("location.entered", {"id": id, "screen": self})


## Rebuilds the current screen keeping Slayme where he is (and hidden if he was).
func _rebuild() -> void:
	if busy:
		day.flags["_rebuild"] = true
		return
	var pos := player.position if player != null else Vector2.ZERO
	var was_cover := cover_id
	show_location(location_id)
	player.position = pos
	if was_cover != "":
		cover_id = was_cover
		player.set_hidden(true)
		player.z_index = -1
	_update_focus()


func _carried_art_item() -> String:
	return day.carried


func _object_visible(d: Dictionary) -> bool:
	if d.has("task") and not day.tasks.has(str(d.task)):
		return false
	match str(d.get("kind", "")):
		"pickup":
			return not day.taken.has(str(d.id))
		"npc":
			if str(d.get("character", "")) == "colleague":
				return not day.flags.get("colleague_away", false)
	return true


func _refresh_object(o: WorldObject) -> void:
	if o.kind != "sink":
		return
	var task_id := str(o.data.get("task", ""))
	if o.data.has("stages"):
		var stages: Array = o.data.stages
		var p := clampi(int(day.task(task_id).get("progress", 0)), 0, stages.size() - 1)
		o.sprite.set_art(str(stages[p]))
	elif bool(o.data.get("slot", false)) and day.filled.has(o.object_id()):
		o.sprite.set_art(str(o.data.get("done_art", o.data.get("art", ""))))


func _entry_point(from: String) -> Vector2:
	for d in location.get("objects", []):
		if str(d.get("kind", "")) == "exit" and str(d.get("to", "")) == from and from != "":
			var p := DataFile.vec2(d.pos)
			return p + (Vector2(160, 135) - p).normalized() * 26.0
	return DataFile.vec2(location.get("slime_start"), Vector2(160, 140))


func _build_pool_mates() -> void:
	var pm: Dictionary = location.get("pool_mates", {})
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
			"pos": [c.x + cos(a) * r.x * rng.randf_range(0.3, 1.0), c.y + sin(a) * r.y * rng.randf_range(0.3, 1.0)]})
		objects.add_child(o)
	if day.flags.get("colleague_away", false):
		var g := WorldObject.new()
		g.setup({"id": "colleague_at_pool", "kind": "npc", "character": "colleague", "art": "colleague",
			"pos": [c.x + r.x + 14, c.y + 6], "talk": {"mode": "pool", "file": "colleague"}})
		objects.add_child(g)


# ---- focus: keyboard or mouse ---------------------------------------------------

func hotspots() -> Array:
	var out := objects.get_children().filter(func(n): return n is WorldObject and n.is_interactable() and n.visible)
	out.sort_custom(func(a, b): return a.position.x < b.position.x)
	return out


func _update_focus() -> void:
	var list := hotspots()
	if focus != null and (not is_instance_valid(focus) or not list.has(focus)):
		focus = null
	if focus == null and not list.is_empty():
		focus = _nearest(list, player.position)
	_show_focus()


func _nearest(list: Array, p: Vector2) -> WorldObject:
	var best: WorldObject = null
	var best_d := INF
	for o in list:
		var d: float = o.position.distance_to(p)
		if d < best_d:
			best = o
			best_d = d
	return best


func _show_focus() -> void:
	if focus == null or busy:
		cursor.visible = false
		hud.set_prompt("")
		return
	cursor.visible = true
	var h := focus.sprite.size().y
	cursor.position = focus.position + focus.sprite.offset + Vector2(0, -h / 2.0 - 5)
	hud.set_prompt(_prompt_for(focus))


func _prompt_for(o: WorldObject) -> String:
	if o.kind == "cover" and cover_id == o.object_id():
		return Content.text("prompt.cover_leave")
	if o.kind == "exit":
		var to: Dictionary = data.get("locations", {}).get(str(o.data.get("to", "")), {})
		return "%s: %s" % [Content.text("prompt.exit"), Content.name_of(str(to.get("name", "")))]
	if o.kind == "npc":
		return "%s: %s" % [Content.text("prompt.npc"), Content.name_of(str(o.data.get("character", "")))]
	return o.prompt()


func _hotspot_at(p: Vector2) -> WorldObject:
	var pad := Rules.num("screens.focus_padding", 4)
	for o in hotspots():
		var size: Vector2 = o.sprite.size() + Vector2(pad, pad) * 2.0
		var center: Vector2 = o.position + o.sprite.offset
		if Rect2(center - size / 2.0, size).has_point(p):
			return o
	return null


func _unhandled_input(event: InputEvent) -> void:
	if busy:
		return
	if event is InputEventMouseMotion and Controls.mouse_enabled():
		var o := _hotspot_at(world.get_global_mouse_position())
		if o != null and o != focus:
			focus = o
			_show_focus()
		return
	if event is InputEventMouseButton and event.pressed and Controls.mouse_enabled():
		if event.button_index == MOUSE_BUTTON_LEFT:
			var o := _hotspot_at(world.get_global_mouse_position())
			if o != null:
				get_viewport().set_input_as_handled()
				focus = o
				act(o)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_spit()
		return
	if event.is_action_pressed("move_right") or event.is_action_pressed("move_down"):
		_cycle(1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_up"):
		_cycle(-1)
	elif event.is_action_pressed("interact") and focus != null:
		get_viewport().set_input_as_handled()
		act(focus)
	elif event.is_action_pressed("cancel"):
		_spit()
	else:
		return
	get_viewport().set_input_as_handled()


func _cycle(step: int) -> void:
	var list := hotspots()
	if list.is_empty():
		return
	var i := list.find(focus)
	focus = list[posmod(i + step, list.size())] if i >= 0 else list[0]
	_show_focus()


func _spit() -> void:
	if day.carried == "":
		return
	day.put_back()
	hud.toast(Content.text("msg.put_back"))
	_rebuild()


# ---- acting -------------------------------------------------------------------------

## Slayme slides to the object, then does the obvious thing with it.
func act(o: WorldObject) -> void:
	if busy or o == null:
		return
	if Hooks.filter("meadow.interact", false, {"object": o, "screen": self}):
		return
	busy = true
	_show_focus()
	if cover_id != "" and o.object_id() != cover_id:
		_leave_cover()
	var target := o.position + Vector2(0, 8)
	if o.kind == "cover":
		target = o.position + Vector2(0, 2)
	elif o.kind in ["pickup", "exit", "exit_home"]:
		target = o.position
	var dist := player.position.distance_to(target)
	if dist > 1.0:
		var tw := create_tween()
		tw.tween_property(player, "position", target, dist / Rules.num("screens.slime_speed", 90))
		await tw.finished
	busy = false
	if not is_instance_valid(o) or not o.is_inside_tree():
		_update_focus()
		return
	var handler: Callable = interact_handlers.get(o.kind, Callable())
	if handler.is_valid():
		await handler.call(o)
	if is_instance_valid(self) and not busy:
		_update_focus()


func _use_pickup(o: WorldObject) -> void:
	var r := day.take_pickup(o.object_id(), str(o.data.task))
	hud.toast(Content.text(r.msg, {"item": _item_name(day.carried)}))
	if r.ok:
		o.visible = false
		o.queue_free()
		focus = null


func _use_source(o: WorldObject) -> void:
	var r := day.absorb(str(o.data.task))
	hud.toast(Content.text(r.msg, {"item": _item_name(day.carried)}))


func _use_sink(o: WorldObject) -> void:
	var task_id := str(o.data.task)
	var r: Dictionary
	if bool(o.data.get("slot", false)):
		r = day.fill_slot(o.object_id(), task_id)
	else:
		r = day.release(task_id)
	var title := Content.text(str(day.task(task_id).get("def", {}).get("title", "")))
	hud.toast(Content.text(r.msg, {"title": title}))
	_refresh_object(o)
	if r.get("completed", false) and bool(day.task(task_id).def.get("leftover", false)):
		GameState.award("leftover_finished")


func _use_cover(o: WorldObject) -> void:
	if cover_id == o.object_id():
		_leave_cover()
		return
	cover_id = o.object_id()
	player.set_hidden(true)
	player.z_index = -1


func _leave_cover() -> void:
	cover_id = ""
	player.set_hidden(false)
	player.z_index = 0


func _use_exit(o: WorldObject) -> void:
	var to := str(o.data.get("to", ""))
	busy = true
	Clock.advance(Rules.num("screens.travel_minutes", 15))
	busy = false
	if not is_inside_tree() or _in_battle_flow:
		return
	show_location(to, location_id)
	_flush_pending()


func _use_exit_home(_o: WorldObject) -> void:
	if day.flags.get("shift_over", false):
		go_home()
	else:
		hud.toast(Content.text("msg.shift_not_over"))


func go_home() -> void:
	busy = true
	Hooks.emit("meadow.go_home", {"screen": self})
	go("home")


func _use_board(_o: WorldObject) -> void:
	var v := day.variation
	var n := planned_incidents()
	await say([{"speaker": "board", "text": str(v.get("board_title", "board.title.1"))},
		{"speaker": "board", "text": str(v.get("board_notice", "board.notice.default")), "args": {"n": n}},
		{"speaker": "board", "text": "board.footer"}])


func _use_npc(o: WorldObject) -> void:
	var talk: Dictionary = o.data.get("talk", {})
	var file := str(talk.get("file", ""))
	var count := int(talked.get(o.object_id(), 0))
	talked[o.object_id()] = count + 1
	match str(talk.get("mode", "simple")):
		"trust_owner":
			await _talk_mentor(file, count)
		"warn":
			await _talk_colleague(o, file, count)
		"pool":
			await say(Content.dialogue(file, "after_incident" if day.flags.get("colleague_hurt", false) else "at_pool"))
		_:
			await say(Content.dialogue(file, str(talk.get("sequence", "idle")), count))


func _talk_mentor(file: String, count: int) -> void:
	var step := GameState.trust_step()
	if step >= GameState.final_step():
		await say(Content.dialogue(file, "question"))
		Hooks.emit("prototype.end", {})
		go("end", {"bells": int(GameState.stats.get("bells", 0))})
		return
	if count == 0:
		var key := "greeting_step_%d_day_%d" % [step, day.day]
		if not Content.has_dialogue(file, key):
			key = "greeting_step_%d" % step
		await say(Content.dialogue(file, key))
	else:
		await say(Content.dialogue(file, "idle_step_%d" % step, count - 1 + day.day))


func _talk_colleague(o: WorldObject, file: String, count: int) -> void:
	var next := next_hero_pass()
	var in_window := next >= 0.0 and next - Clock.minutes <= Rules.num("world.warn_window_minutes", 60)
	if in_window and day.flags.get("colleague_warned", false):
		await say(Content.dialogue(file, "warned_already"))
	elif in_window:
		day.flags["colleague_warned"] = true
		await say(Content.dialogue(file, "warn"))
		GameState.award("warned_colleague")
		day.flags["colleague_away"] = true
		o.visible = false
		o.queue_free()
		focus = null
	else:
		await say(Content.dialogue(file, "idle", count))


## Plays dialogue lines, pausing the clock and the heroes.
func say(lines: Array) -> int:
	busy = true
	_show_focus()
	if Rules.flag("clock.pause_in_dialogue", true):
		Clock.pause("dialogue")
	if walker != null:
		walker.paused = true
	var choice: int = await dialogue.play(lines)
	Clock.resume("dialogue")
	if walker != null and not _in_battle_flow:
		walker.paused = false
	busy = false
	if not _in_battle_flow:
		_flush_pending()
	if is_inside_tree():
		_update_focus()
	return choice


func _item_name(item_id: String) -> String:
	var item: Dictionary = Content.dict("items").get(item_id, {})
	return Content.name_of(str(item.get("name", item_id)))


func _on_carried_changed(item_id: String) -> void:
	if player != null and is_instance_valid(player):
		player.show_item(item_id)
	hud.refresh()


# ---- time ----------------------------------------------------------------------------

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
		var ev := str(e.get("event", ""))
		if ev == "colleague_incident":
			continue  # screens mode uses the day's planned incidents instead
		if Clock.crossed(_event_time(e), prev, now):
			_pending.append(ev)
	for inc in _incidents:
		if not inc.done and Clock.crossed(inc.time, prev, now):
			inc.done = true
			if not inc.cancelled:
				_background_incident(inc)
	_update_passes(prev, now)
	if not busy:
		_flush_pending()


func _flush_pending() -> void:
	while not busy and not _pending.is_empty():
		var ev: String = _pending.pop_front()
		var handler: Callable = event_handlers.get(ev, Callable())
		if handler.is_valid():
			handler.call()
		else:
			Hooks.emit("schedule." + ev, {"screen": self})


func _ev_bell_morning() -> void:
	_ring()
	await say(Content.dialogue("world", "bell_morning"))


func _ev_bell_evening() -> void:
	Art.play_sound("bell")
	day.flags["shift_over"] = true
	await say(Content.dialogue("world", "bell_evening"))


func _ev_day_end() -> void:
	await say(Content.dialogue("world", "day_end"))
	go_home()


## The bell: morning, incidents, evening. Always the same bell.
func _ring() -> void:
	Art.play_sound("bell")


# ---- incidents in the background (the quota) ----------------------------------------------

func _background_incident(inc: Dictionary) -> void:
	GameState.stat_add("bells")
	_ring()
	var who := str(inc.who)
	if who == "colleague" and not day.flags.get("colleague_warned", false) and not day.flags.get("colleague_hurt", false):
		day.flags["colleague_hurt"] = true
		day.flags["colleague_away"] = true
		if location_id == "path" or location_id == "pool":
			_rebuild()
	if location_id == "pool":
		var mates := objects.get_children().filter(func(n): return n is WorldObject and n.object_id().begins_with("pool_mate_"))
		if not mates.is_empty():
			var mate: WorldObject = mates[randi() % mates.size()]
			mate.visible = false
			var ref: WeakRef = weakref(mate)
			get_tree().create_timer(Rules.num("world.respawn_hidden_seconds", 2.0)).timeout.connect(
				func():
					var m = ref.get_ref()
					if m != null:
						m.visible = true)
	else:
		hud.toast(Content.text("world.bell_far"))
	Hooks.emit("colleague.incident", {"who": who, "screen": self})


## Someone's incident was "used": the next planned one doesn't happen.
## The total always matches the board.
func _consume_incident_slot() -> void:
	GameState.stat_add("bells")
	for inc in _incidents:
		if not inc.done and not inc.cancelled:
			inc.cancelled = true
			return


# ---- heroes ------------------------------------------------------------------------------

func _ev_hero_pass() -> void:
	passes.append({"start": Clock.minutes, "entered": {}, "warned": {}})
	Hooks.emit("heroes.appeared", {"screen": self})


func _route() -> Array:
	return Content.dict("heroes").get("route", [])


func _segment_now(p: Dictionary) -> Dictionary:
	var t := Clock.minutes - float(p.start)
	for seg in _route():
		if t >= float(seg.offset) and t < float(seg.offset) + float(seg.duration):
			return seg
	return {}


func _update_passes(_prev: float, now: float) -> void:
	var warn := Rules.num("screens.hero_warning_minutes", 20)
	for p in passes:
		var t := now - float(p.start)
		for seg in _route():
			var loc := str(seg.location)
			# A warning for the screen Slayme is on.
			if loc == location_id and not p.warned.has(loc) and t < float(seg.offset) and float(seg.offset) - t <= warn:
				p.warned[loc] = true
				hud.toast(Content.text("world.heroes_coming_toast"))
			if t >= float(seg.offset) and not p.entered.has(loc):
				p.entered[loc] = true
				_heroes_enter(p, seg)
	# Upcoming pass: warn on the first screen too.
	var next := next_hero_pass()
	if next >= 0.0 and next - now <= warn and not _route().is_empty():
		var first: Dictionary = _route()[0]
		var key := "pre_%d" % int(next)
		if str(first.location) == location_id and not day.flags.has(key):
			day.flags[key] = true
			hud.toast(Content.text("world.heroes_coming_toast"))
	passes = passes.filter(func(p): return now - float(p.start) < _route_length())


func _route_length() -> float:
	var total := 0.0
	for seg in _route():
		total = maxf(total, float(seg.offset) + float(seg.duration))
	return total


func _heroes_enter(p: Dictionary, seg: Dictionary) -> void:
	var loc := str(seg.location)
	# Repaired things on their way get broken again. Every time.
	for task_id in day.tasks.keys():
		for o in _all_objects_of_task(task_id, "sink"):
			if bool(o.get("heroes_break_when_done", false)) and _object_location(str(o.id)) == loc and day.is_done(task_id):
				day.reset_task(task_id, _all_objects_of_task(task_id, "pickup").map(func(x): return str(x.id)))
				GameState.stat_add("pots_broken")
				day.flags["pot_rebroken"] = true
				Hooks.emit("pot.broken", {"task": task_id, "screen": self})
				if loc == location_id:
					Art.play_sound("hit")
					hud.toast(Content.text("world.pot_broken_toast"))
					_rebuild()
	if loc == location_id:
		if cover_id != "":
			GameState.award("hid_before_heroes")
		_spawn_walker(p, seg)


func _object_location(object_id: String) -> String:
	for loc_id in data.get("locations", {}).keys():
		for o in data.locations[loc_id].get("objects", []):
			if str(o.get("id", "")) == object_id:
				return loc_id
	return ""


func _spawn_walker(p: Dictionary, seg: Dictionary) -> void:
	if walker != null:
		return
	var y := float(location.get("hero_lane_y", 108))
	walker = HeroParty.new()
	objects.add_child(walker)
	var seconds := maxf(Rules.num("screens.hero_cross_seconds_min", 6), float(seg.duration) / Rules.num("clock.minutes_per_second", 2.5))
	walker.speed_override = 400.0 / seconds
	walker.setup([[-40, y], [360, y]], day.variation.get("party", []))
	walker.left_meadow.connect(func(): walker = null)
	if bool(p.get("ignore", false)):
		walker.ignore_player = true
	walker.set_meta("pass", p)
	_bark()


func _bark() -> void:
	var defs: Dictionary = Content.dict("heroes").get("heroes", {})
	var ids: Array = day.variation.get("party", [])
	if ids.is_empty():
		return
	var n := int(GameState.stats.get("barks", 0))
	GameState.stat_add("barks")
	var id: String = ids[n % ids.size()]
	var barks: Array = defs.get(id, {}).get("barks", [])
	if not barks.is_empty():
		hud.toast("%s: %s" % [Content.name_of(id), Content.text(str(barks[(n / ids.size()) % barks.size()]))])


func _process(_delta: float) -> void:
	if not busy and day.flags.get("_rebuild", false):
		day.flags.erase("_rebuild")
		_rebuild()
	if player == null or busy or walker == null or walker.ignore_player or cover_id != "":
		return
	var r := Rules.num("screens.spot_radius", 22)
	for pos in walker.positions():
		if absf(pos.x - player.position.x) <= r:
			_start_battle()
			return


# ---- battle ----------------------------------------------------------------------------

func _start_battle() -> void:
	busy = true
	_in_battle_flow = true
	_show_focus()
	hud.visible = false
	Clock.pause("battle")
	walker.paused = true
	var b = BATTLE_SCENE.instantiate()
	battle_layer.add_child(b)
	b.start(day.variation.get("party", []), location.get("terrain", []), day.carried)
	var res: Dictionary = await b.battle_finished
	b.queue_free()
	await _after_battle(res)


func _after_battle(res: Dictionary) -> void:
	GameState.stat_add("battles")
	hud.visible = true
	if bool(res.get("looked", false)):
		GameState.award("read_heroes")
	for i in int(res.get("ally_incidents", 0)):
		GameState.award("ally_hurt")
		_consume_incident_slot()
	if str(res.get("item", "")) != day.carried:
		if str(res.get("item", "")) == "":
			day.set_carried("", "")   # stolen: gone for good today
		else:
			day.set_carried(str(res.item), "")
	var p: Dictionary = walker.get_meta("pass", {}) if walker != null else {}
	match str(res.get("outcome", "")):
		"incident":
			p["ignore"] = true
			await _incident()
		"fled":
			p["ignore"] = true
			if walker != null:
				walker.ignore_player = true
				walker.paused = false
		"bored":
			p["ignore"] = true
			if walker != null:
				walker.queue_free()
				walker = null
	Clock.resume("battle")
	busy = false
	_in_battle_flow = false
	Clock.advance(float(res.get("rounds", 0)) * Rules.num("battle.minutes_per_round", 3))
	if is_inside_tree():
		_update_focus()
		_flush_pending()


func _incident() -> void:
	day.on_incident()
	GameState.stat_add("incidents")
	_consume_incident_slot()
	_ring()
	show_location(str(data.get("start", "pool")))
	await say(Content.dialogue("world", "incident"))
	Clock.advance(Rules.num("incident.clock_penalty_minutes", 60))
	Hooks.emit("slime.incident", {"screen": self})
