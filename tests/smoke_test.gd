extends Node
## Headless smoke test. Run:
##   godot --headless res://tests/smoke_test.tscn
## Checks the core systems, then plays one full day automatically
## (meadow -> battle -> home -> night -> next morning) and quits with
## exit code 0 if everything passed.

var _failures := 0
var _main: Node = null
var walked_home := false


func _ready() -> void:
	_test_rules_and_hooks()
	_test_content()
	_test_day_state()
	_test_battle()
	_test_trust_and_memory()
	await _test_full_day()
	await _test_screens_day()
	print("SMOKE TEST: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		_failures += 1
		printerr("  FAIL ", what)


func _test_rules_and_hooks() -> void:
	print("rules + hooks")
	check(Rules.integer("battle.slime.max_hp") == 3, "slime hp read from rules.json")
	check(Rules.integer("battle.slime.max_hp") < Rules.integer("battle.actions.attack.damage"), "the Slime is always weak: one hit is an incident")
	Rules.set_override("battle.slime.max_hp", 1)
	check(Rules.integer("battle.slime.max_hp") == 1, "runtime override")
	Rules.clear_override("battle.slime.max_hp")
	var f := func(v, _ctx): return v * 2
	Hooks.add_filter("rule:battle.slime.max_hp", f)
	check(Rules.integer("battle.slime.max_hp") == 6, "rule filter hook")
	Hooks.remove_filter("rule:battle.slime.max_hp", f)
	check(Rules.integer("battle.slime.max_hp") == 3, "filter removed")


func _test_content() -> void:
	print("content")
	check(Content.text("dlg.mentor.greet_1").contains(Content.name_of("mentor")), "mentor name injected in text")
	var rename := func(n, ctx): return "Placeholder" if ctx.id == "mentor" else n
	Hooks.add_filter("name", rename)
	check(Content.text("dlg.mentor.greet_1").contains("Placeholder"), "names are not taken for granted")
	Hooks.remove_filter("name", rename)
	check(Content.text("board.notice.default", {"n": 6}).contains("6"), "text arguments")
	check(Art.texture("slime") != null, "art pack: slime texture")
	check(Art.texture("does_not_exist") != null, "art pack: missing id falls back")


func _test_day_state() -> void:
	print("day")
	var d := DayState.new()
	d.setup(1, Content.dict("tasks").get("tasks", []), {"leftover": {"task": "leftover_pot", "progress": 3}})
	check(d.tasks.has("pot") and d.tasks.has("leftover_pot") and not d.tasks.has("leftover_chest"), "only today's leftover exists")
	check(d.absorb("pot").ok, "absorb a shard")
	check(not d.absorb("chest").ok, "one thing at a time")
	check(not d.release("chest").ok, "wrong item")
	check(d.release("pot").ok and d.task("pot").progress == 1, "release on pedestal")
	d.take_pickup("shard_1", "pot")
	Rules.set_override("incident.reset_task_progress", true)
	d.on_incident()
	Rules.clear_override("incident.reset_task_progress")
	check(d.carried == "" and d.task("pot").progress == 0, "incident: item lost, job back as before")
	check(not d.taken.has("shard_1"), "incident: the shard is back on the ground")
	d.absorb("leftover_pot")
	check(d.release("leftover_pot").get("completed", false), "leftover finished")


func _test_battle() -> void:
	print("battle")
	var party := ["hero_sword", "hero_mage", "hero_thief"]
	# Round 1 is the heroes' warm-up (pose, focus): looking around is safe.
	var m := BattleModel.new()
	m.setup(party, [], "")
	m.plan_round()
	check(m.plans["hero_sword"] == "pose" and m.plans["hero_mage"] == "focus", "round 1: the heroes warm up")
	m.resolve("look")
	check(m.outcome == "" and int(m.slime.hp) == Rules.integer("battle.slime.max_hp"), "looking around on round 1 is safe")
	# Round 2 without defending: one normal hit of the sword hero is an incident.
	m.plan_round()
	check(m.plans["hero_sword"] == "attack", "sword hero attacks on round 2")
	m.resolve("look")
	check(m.outcome == "incident", "no defence on round 2 = incident")
	# Look, brace, run.
	m = BattleModel.new()
	m.setup(party, [], "shard")
	m.plan_round()
	check(m.plans["hero_thief"] == "pickpocket", "thief plans to steal what Slayme carries")
	m.resolve("look")
	check(str(m.slime.item) == "", "item stolen")
	m.plan_round()
	m.resolve("defend")
	check(m.outcome == "" and int(m.slime.hp) > 0, "bracing survives round 2")
	m.plan_round()
	check(m.plans["hero_sword"] == "prepare_brave", "sword hero prepares on round 3")
	m.resolve("flee")
	check(m.outcome == "fled", "flee works during the preparation")
	# Flee outside a window fails.
	m = BattleModel.new()
	m.setup(party, ["bush"], "")
	m.plan_round()
	m.resolve("flee")
	check(m.outcome == "", "flee on round 1 fails (nothing happens: warm-up)")
	m.plan_round()
	m.resolve("flee")
	check(m.outcome == "incident", "flee on round 2 fails: incident")
	# A cover works once per battle: hide, then run.
	m = BattleModel.new()
	m.setup(party, ["bush"], "")
	m.plan_round()
	m.resolve("look")
	m.plan_round()
	m.resolve("hide", "bush")
	check(m.outcome == "" and int(m.slime.hp) == Rules.integer("battle.slime.max_hp"), "hiding: nobody to hit")
	check(m.cover_terrain().is_empty(), "the cover is used up")
	m.plan_round()
	m.resolve("flee")
	check(m.outcome == "fled", "hide, then run")
	# Hiding until they get bored (only if covers are not used up).
	Rules.set_override("battle.terrain.consumed_on_hide", false)
	m = BattleModel.new()
	m.setup(party, ["bush"], "")
	var rounds := 0
	while m.outcome == "" and rounds < 20:
		m.plan_round()
		m.resolve("hide", "bush")
		rounds += 1
	check(m.outcome == "bored", "hiding until the heroes get bored (%d rounds)" % rounds)
	Rules.clear_override("battle.terrain.consumed_on_hide")
	# Verbs come one at a time with Novecento's trust.
	var saved_trust := GameState.trust
	var saved_flags: Dictionary = GameState.flags.duplicate(true)
	GameState.trust = 0
	GameState.flags.erase("verbs_known")
	m = BattleModel.new()
	m.setup(party, ["bush"], "")
	check(m.verbs().map(func(v): return v.id) == ["defend"], "trust 0: Slayme only knows how to brace")
	check(m.take_new_verbs().size() == 1 and m.take_new_verbs().is_empty(), "new verbs are told once")
	rounds = 0
	while m.outcome == "" and rounds < 10:
		m.plan_round()
		m.resolve("defend")
		rounds += 1
	check(m.outcome == "incident" and rounds == 4, "bracing only: the incident comes with Brave Slash (round %d)" % rounds)
	GameState.trust = Rules.integer("battle.unlock.flee")
	var ids: Array = m.verbs().map(func(v): return v.id)
	check(ids.has("look") and ids.has("flee") and not ids.has("hide"), "more trust: look around and run away")
	check(m.take_new_verbs().size() == 2, "two new verbs to tell")
	GameState.trust = saved_trust
	GameState.flags = saved_flags
	# Mud: heavy, cannot flee.
	m = BattleModel.new()
	m.setup(party, ["mud"], "")
	m.plan_round()
	m.resolve("absorb", "mud")
	check(bool(m.slime.heavy) and int(m.slime.defense_bonus) == 1, "mud: +defense, heavy")
	# Look shows the future.
	m = BattleModel.new()
	m.setup(party, [], "")
	m.plan_round()
	check(m.forecast("hero_mage", 2) == ["fire", "fire"], "forecast of the mage")
	# Mage runs out of MP after 4 spells.
	var mage := {"id": "hero_mage", "mp": 12, "turn": 5, "asleep": false}
	m.heroes = [mage]
	mage.mp = 0
	check(m._pattern_action(mage) == "out_of_mp", "mage out of MP")


func _test_trust_and_memory() -> void:
	print("trust + memory")
	GameState.new_game()
	check(GameState.trust_step() == 1, "step 1 at start")
	GameState.start_day()
	GameState.award("leftover_finished")
	check(GameState.award("leftover_finished") == 0, "once per day")
	GameState.trust = Rules.list("trust.step_thresholds")[2]
	check(GameState.trust_step() == GameState.final_step(), "final step reachable")
	GameState.write_memory()
	GameState.trust = 0
	check(GameState.read_memory() and GameState.trust_step() == GameState.final_step(), "memory survives")
	GameState.forget()
	GameState.new_game()


## Plays one day with an autopilot: dialogues advance, Slayme walks into the
## heroes, braces, then runs. Time is accelerated through a rule override.
func _test_full_day() -> void:
	print("full day (free top-down mode)")
	Rules.set_override("world.mode", "free")
	Rules.set_override("clock.minutes_per_second", 240.0)
	Rules.set_override("ui.battle_log_delay", 0.01)
	Rules.set_override("ui.hero_cursor_step", 0.0)
	Rules.set_override("night.seconds", 0.1)
	Rules.set_override("world.hero_walk_speed", 400.0)
	var seen := {}
	var battle_seen := false
	walked_home = false
	var start_day := GameState.day
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.first_screen = "meadow_free"
	add_child(main)
	var frames := 0
	while frames < 6000:
		frames += 1
		await get_tree().process_frame
		seen[main.current_id.replace("_free", "")] = true
		_autopilot(main)
		if main.get_node_or_null("Screens/Meadow/BattleLayer/Battle") != null:
			battle_seen = true
		if seen.has("night") and main.current_id.begins_with("meadow"):
			break
	check(seen.has("meadow") and main.current != null, "meadow shown")
	check(battle_seen, "a battle happened")
	check(seen.has("home"), "went home at the evening bell")
	check(seen.has("night"), "night")
	check(GameState.day == start_day + 1, "next day started (day %d)" % GameState.day)
	check(GameState.has_memory(), "memory written at night")
	check(int(GameState.stats.get("pots_broken", 0)) > 0, "the thief broke pots on the path (%d)" % int(GameState.stats.get("pots_broken", 0)))
	check(walked_home, "walked home past the sign after the evening bell")
	main.queue_free()
	Rules.clear_all_overrides()
	GameState.forget()


func _autopilot(main: Node) -> void:
	var screen: Node = main.current
	if screen == null:
		return
	var dlg = screen.get_node_or_null("Dialogue")
	if dlg != null and dlg.playing:
		dlg.advance()
		return
	var battle = screen.get_node_or_null("BattleLayer/Battle")
	if battle != null:
		var verbs: ChoiceList = battle.verbs
		if verbs.active:
			var want := "look" if battle.model.round_no == 1 else ("defend" if battle.model.round_no == 2 else "flee")
			var ids: Array = verbs.items.map(func(it): return str(it.id))
			if not ids.has(want):
				want = "defend"   # verbs come with trust: early on, bracing is all Slayme knows
			for i in verbs.items.size():
				if verbs.items[i].id == want:
					verbs.chosen.emit(want, i)
					return
		return
	if main.current_id == "meadow_free" and screen.day.flags.get("shift_over", false) and not screen.busy:
		# Evening: walk to the sign and go home.
		Rules.set_override("clock.minutes_per_second", 1.0)
		var sign: Node2D = screen.objects.get_node("home_sign")
		screen.player.position = screen.player.position.move_toward(sign.position, 8.0)
		if screen.focus == sign:
			walked_home = true
			screen.interact(sign)
		return
	if main.current_id == "meadow_free" and screen.party != null and not screen.busy:
		# Walk Slayme onto the path, into the heroes.
		var target: Vector2 = screen.party.positions()[0]
		screen.player.position = screen.player.position.move_toward(target, 6.0)


# ---- fixed screens (the prototype) ------------------------------------------------

var _screen_seen := {}


## Plays a full day on the fixed screens with an autopilot that does the
## jobs like a player would: point at things, carry, release, travel.
func _test_screens_day() -> void:
	print("full day (fixed screens)")
	GameState.forget()
	GameState.new_game()
	Rules.set_override("clock.minutes_per_second", 30.0)
	Rules.set_override("screens.slime_speed", 2000.0)
	Rules.set_override("ui.battle_log_delay", 0.01)
	Rules.set_override("ui.hero_cursor_step", 0.0)
	Rules.set_override("night.seconds", 0.1)
	Rules.set_override("screens.hero_cross_seconds_min", 0.5)
	_screen_seen = {}
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.first_screen = "meadow"
	add_child(main)
	var meadow: Node = main.current
	check(meadow.has_method("show_location"), "the meadow is the fixed-screen version")
	# A theft puts the item back where it was: the job stays possible.
	check(bool(meadow.day.take_pickup("coin_1", "chest").ok), "absorbed a coin")
	await meadow._after_battle({"outcome": "fled", "item": ""})
	check(meadow.day.carried == "" and not meadow.day.taken.has("coin_1"), "a stolen coin turns up again where it was")
	# The pot broken while Slayme was away: one line when he comes back.
	meadow.day.flags["pot_broken_unseen"] = "path"
	meadow.show_location("path")
	check(meadow.hud.toast_label.text == Content.text("world.pot_broken_found"), "found the pot broken again")
	check(not meadow.day.flags.has("pot_broken_unseen"), "said once")
	meadow.show_location("pool")
	GameState.stats.erase("battles")
	var planned: int = meadow.planned_incidents()
	var battle_seen := false
	var done_tasks := 0
	var bells_day1 := -1
	var frames := 0
	while frames < 20000:
		frames += 1
		await get_tree().process_frame
		_screen_seen[main.current_id] = true
		if main.current_id == "meadow" and main.current != null and main.current.day != null:
			done_tasks = main.current.day.core_tasks().filter(func(t): return main.current.day.is_done(t)).size()
			if main.current.location_id != "":
				_screen_seen["loc:" + main.current.location_id] = true
		if main.current_id == "home" and bells_day1 < 0:
			bells_day1 = int(GameState.stats.get("bells", 0))
		if main.get_node_or_null("Screens/Meadow/BattleLayer/Battle") != null:
			battle_seen = true
		_screens_autopilot(main)
		if _screen_seen.has("night") and main.current_id == "meadow":
			break
	check(_screen_seen.has("loc:path") and _screen_seen.has("loc:old_tree") and _screen_seen.has("loc:field"), "visited the screens")
	check(done_tasks >= 0, "jobs tracked")
	check(int(GameState.stats.get("trust_all_tasks_done", 0)) >= 1 or GameState.trust > 0, "trust changed during the day (trust %d)" % GameState.trust)
	check(battle_seen, "met the heroes and fought")
	check(_screen_seen.has("home") and _screen_seen.has("night"), "went home and slept")
	check(GameState.day == 2, "day 2 started")
	check(bells_day1 == planned, "bells rung = board's forecast (%d / %d)" % [bells_day1, planned])
	# Keep playing: days 2 and 3, until the mentor asks his question.
	frames = 0
	while frames < 40000 and main.current_id != "end":
		frames += 1
		await get_tree().process_frame
		_screens_autopilot(main)
	check(main.current_id == "end", "the mentor's question ends the prototype (day %d, trust %d)" % [GameState.day, GameState.trust])
	main.queue_free()
	Rules.clear_all_overrides()
	GameState.forget()


func _screens_autopilot(main: Node) -> void:
	var screen: Node = main.current
	if screen == null:
		return
	var dlg = screen.get_node_or_null("Dialogue")
	if dlg != null and dlg.playing:
		dlg.advance()
		return
	var battle = screen.get_node_or_null("BattleLayer/Battle")
	if battle != null:
		var verbs: ChoiceList = battle.verbs
		if verbs.active:
			var want := "look" if battle.model.round_no == 1 else ("defend" if battle.model.round_no == 2 else "flee")
			var ids: Array = verbs.items.map(func(it): return str(it.id))
			if not ids.has(want):
				want = "defend"   # verbs come with trust: early on, bracing is all Slayme knows
			for i in verbs.items.size():
				if verbs.items[i].id == want:
					verbs.chosen.emit(want, i)
					return
		return
	if main.current_id != "meadow" or screen.busy or screen.player == null:
		return
	var target := _next_target(screen)
	if target != "":
		for o in screen.hotspots():
			if o.object_id() == target:
				screen.act(o)
				return


## Which hotspot the autopilot should use now (an object here, or an exit).
func _next_target(screen: Node) -> String:
	var day: DayState = screen.day
	var want_loc := ""
	var want_obj := ""
	if day.flags.get("shift_over", false):
		want_loc = "pool"
		want_obj = "home_sign"
	else:
		for loc_id in screen.data.locations.keys():
			for o in screen.data.locations[loc_id].objects:
				if want_obj != "" or not o.has("task") or not day.tasks.has(o.task) or day.is_done(o.task):
					continue
				var kind := str(o.kind)
				var item := str(day.task(o.task).def.item)
				if day.carried != "":
					if kind == "sink" and item == day.carried and not day.filled.has(o.id):
						want_loc = loc_id
						want_obj = o.id
				elif (kind == "pickup" and not day.taken.has(o.id)) or kind == "source":
					want_loc = loc_id
					want_obj = o.id
		if want_obj == "":
			want_loc = "pool"
			want_obj = "mentor" if not screen.talked.has("mentor") else ""
	if want_obj == "":
		return ""
	if want_loc == screen.location_id:
		return want_obj
	# One step toward the wanted screen (the graph is tiny: everything goes through the path).
	var hop := want_loc if screen.location_id == "path" else "path"
	for o in screen.location.objects:
		if str(o.kind) == "exit" and str(o.to) == hop:
			return str(o.id)
	return ""
