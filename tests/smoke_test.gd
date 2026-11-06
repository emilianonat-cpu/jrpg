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
	d.absorb("pot")
	d.on_incident()
	check(d.carried == "" and d.task("pot").progress == 0, "incident: item lost, job back as before")
	d.absorb("leftover_pot")
	check(d.release("leftover_pot").get("completed", false), "leftover finished")


func _test_battle() -> void:
	print("battle")
	var party := ["hero_sword", "hero_mage", "hero_thief"]
	# Doing nothing useful: incident on the first round.
	var m := BattleModel.new()
	m.setup(party, [], "")
	m.plan_round()
	m.resolve("look")
	check(m.outcome == "incident", "looking around on round 1 = incident")
	# Brace, then run while the sword hero prepares.
	m = BattleModel.new()
	m.setup(party, [], "shard")
	m.plan_round()
	check(m.plans["hero_thief"] == "pickpocket", "thief plans to steal what Slayme carries")
	m.resolve("defend")
	check(m.outcome == "" and int(m.slime.hp) > 0, "bracing survives round 1")
	check(str(m.slime.item) == "", "item stolen")
	m.plan_round()
	check(m.plans["hero_sword"] == "prepare_brave", "sword hero prepares on round 2")
	m.resolve("flee")
	check(m.outcome == "fled", "flee works during the preparation")
	# Flee outside a window fails.
	m = BattleModel.new()
	m.setup(party, ["bush"], "")
	m.plan_round()
	m.resolve("flee")
	check(m.outcome == "incident", "flee on round 1 fails")
	# Hiding until they get bored.
	m = BattleModel.new()
	m.setup(party, ["bush"], "")
	var rounds := 0
	while m.outcome == "" and rounds < 20:
		m.plan_round()
		m.resolve("hide", "bush")
		rounds += 1
	check(m.outcome == "bored", "hiding until the heroes get bored (%d rounds)" % rounds)
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
	check(m.forecast("hero_mage", 2) == ["fire", "thunder"], "forecast of the mage")
	# Mage runs out of MP after 4 spells.
	var mage := {"id": "hero_mage", "mp": 12, "turn": 4, "asleep": false}
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
	print("full day")
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
	main.first_screen = "meadow"
	add_child(main)
	var frames := 0
	while frames < 6000:
		frames += 1
		await get_tree().process_frame
		seen[main.current_id] = true
		_autopilot(main)
		if main.get_node_or_null("Screens/Meadow/BattleLayer/Battle") != null:
			battle_seen = true
		if seen.has("night") and main.current_id == "meadow":
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
			var want := "defend" if battle.model.round_no == 1 else "flee"
			for i in verbs.items.size():
				if verbs.items[i].id == want:
					verbs.chosen.emit(want, i)
					return
		return
	if main.current_id == "meadow" and screen.day.flags.get("shift_over", false) and not screen.busy:
		# Evening: walk to the sign and go home.
		Rules.set_override("clock.minutes_per_second", 1.0)
		var sign: Node2D = screen.objects.get_node("home_sign")
		screen.player.position = screen.player.position.move_toward(sign.position, 8.0)
		if screen.focus == sign:
			walked_home = true
			screen.interact(sign)
		return
	if main.current_id == "meadow" and screen.party != null and not screen.busy:
		# Walk Slayme onto the path, into the heroes.
		var target: Vector2 = screen.party.positions()[0]
		screen.player.position = screen.player.position.move_toward(target, 6.0)
