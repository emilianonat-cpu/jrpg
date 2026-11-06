class_name BattleModel
extends RefCounted
## Battle logic, without any UI. "They have a menu, you have a body."
##
## Data:   data/heroes.json (patterns), data/hero_actions.json (what actions do),
##         data/battle.json (Slayme's verbs), data/terrain.json (the place matters).
## Numbers: rules.json under "battle.*".
##
## Flow, driven by the battle screen (or by a test):
##   setup() -> loop { plan_round(); [UI shows hero menus]; resolve(verb, arg) }
##   until outcome != "" ("fled", "bored", "incident").
## resolve() returns a list of events ({type: "log", key, args}, ...) for the UI.
##
## Extending: listen to the "battle.created" hook and add entries to
## verb_handlers (Callable(arg: String, ev: Array) -> void), or filter
## "battle.damage", "battle.flee", "battle.condition", "battle.target".

var heroes: Array = []          # [{id, mp, turn, asleep}]
var slime: Dictionary = {}
var ally: Dictionary = {}       # empty = no colleague in the fight
var terrain: Array = []         # terrain ids still usable here
var round_no := 0
var boredom := 0
var outcome := ""
var plans: Dictionary = {}      # hero id -> action id for this round
var ally_incidents := 0
var calls_left := 0
var looked := false
var verb_handlers: Dictionary = {}

var _hero_defs: Dictionary = {}
var _actions: Dictionary = {}
var _terrain_defs: Dictionary = {}
var _battle: Dictionary = {}
var _hid_this_round := false
var _sleep_next_actor := false
var _out_of_mp_this_round := false


func setup(party: Array, terrain_ids: Array, carried_item: String) -> void:
	_hero_defs = Content.dict("heroes").get("heroes", {})
	_actions = Content.dict("hero_actions")
	_terrain_defs = Content.dict("terrain")
	_battle = Content.dict("battle")
	heroes.clear()
	for id in party:
		if _hero_defs.has(id):
			heroes.append({"id": str(id), "mp": Rules.integer("battle.heroes.%s.mp" % id, 0), "turn": 0, "asleep": false})
	var hp := Rules.integer("battle.slime.max_hp", 3)
	slime = {"hp": hp, "max_hp": hp, "defense_bonus": 0, "heavy": false, "item": carried_item,
		"defending": false, "hidden": false}
	terrain = terrain_ids.filter(func(t): return _terrain_defs.has(t))
	calls_left = Rules.integer("battle.ally.max_calls", 1)
	verb_handlers = {
		"look": _verb_look, "defend": _verb_defend, "absorb": _verb_absorb,
		"hide": _verb_hide, "call_help": _verb_call_help, "flee": _verb_flee,
	}
	Hooks.emit("battle.created", {"model": self})


# ---- heroes ---------------------------------------------------------------

func plan_round() -> void:
	round_no += 1
	plans.clear()
	for h in heroes:
		plans[h.id] = _current_action(h)
	Hooks.emit("battle.planned", {"model": self, "plans": plans})


func action_def(action_id: String) -> Dictionary:
	return _actions.get(action_id, {})


func hero_ids() -> Array:
	return heroes.map(func(h): return h.id)


## The next [param n] actions of a hero after this round (what "look around" shows).
func forecast(hero_id: String, n: int) -> Array:
	var h := _hero(hero_id)
	if h.is_empty():
		return []
	var sim := h.duplicate()
	var cur: String = plans.get(hero_id, _current_action(h))
	if cur != "sleeping":
		sim.mp -= _mp_cost(cur)
		sim.turn += 1
	var out := []
	for i in n:
		var a := _pattern_action(sim)
		sim.mp -= _mp_cost(a)
		sim.turn += 1
		out.append(a)
	return out


func _current_action(h: Dictionary) -> String:
	if h.asleep:
		return "sleeping"
	var def: Dictionary = _hero_defs.get(h.id, {})
	for o in def.get("overrides", []):
		if _condition(str(o.get("when", ""))):
			return str(o.action)
	return _pattern_action(h)


func _pattern_action(h: Dictionary) -> String:
	var def: Dictionary = _hero_defs.get(h.id, {})
	var pattern: Array = def.get("pattern", ["attack"])
	var a := str(pattern[int(h.turn) % pattern.size()])
	if _mp_cost(a) > int(h.mp):
		a = str(def.get("no_mp_action", "out_of_mp"))
	return a


func _mp_cost(action_id: String) -> int:
	return Rules.integer("battle.actions.%s.mp_cost" % action_id, 0)


func _condition(cond: String) -> bool:
	var result := false
	match cond:
		"slime_has_item":
			result = str(slime.get("item", "")) != ""
		"slime_hidden":
			result = bool(slime.get("hidden", false))
		"ally_present":
			result = not ally.is_empty()
	return bool(Hooks.filter("battle.condition", result, {"name": cond, "model": self}))


func _hero(id: String) -> Dictionary:
	for h in heroes:
		if h.id == id:
			return h
	return {}


# ---- Slayme ----------------------------------------------------------------

func verbs() -> Array:
	var out := []
	for v in _battle.get("verbs", []):
		var enabled := true
		match str(v.get("needs", "")):
			"absorbable":
				enabled = not absorbable_terrain().is_empty()
			"cover":
				enabled = not cover_terrain().is_empty()
			"ally_call":
				enabled = ally.is_empty() and calls_left > 0
		out.append({"id": str(v.id), "label": Content.text(str(v.label)), "enabled": enabled})
	return out


func absorbable_terrain() -> Array:
	return terrain.filter(func(t): return _terrain_defs[t].has("absorb"))


func cover_terrain() -> Array:
	return terrain.filter(func(t): return bool(_terrain_defs[t].get("cover", false)))


func terrain_label(id: String) -> String:
	return Content.text(str(_terrain_defs.get(id, {}).get("label", "")))


## Resolve one round: Slayme's verb first, then every hero's planned action.
func resolve(verb: String, arg: String = "") -> Array:
	var ev: Array = []
	slime.defending = false
	slime.hidden = false
	_hid_this_round = false
	_sleep_next_actor = false
	_out_of_mp_this_round = false
	var handler: Callable = verb_handlers.get(verb, Callable())
	if handler.is_valid():
		handler.call(arg, ev)
	if outcome != "":
		return ev
	var exp_gained := false
	for h in heroes:
		var action: String = plans.get(h.id, "attack")
		if action == "sleeping":
			h.asleep = false
			_log(ev, "battle.log.wakes_up", {"hero": Content.name_of(h.id)})
			continue
		if _sleep_next_actor:
			_sleep_next_actor = false
			h.asleep = true
			_log(ev, "battle.log.falls_asleep", {"hero": Content.name_of(h.id)})
			continue
		if _perform(h, action, ev):
			exp_gained = true
		h.turn += 1
		if outcome != "":
			return ev
	_update_boredom(exp_gained, ev)
	Hooks.emit("battle.round_end", {"model": self, "events": ev})
	return ev


func result() -> Dictionary:
	return {"outcome": outcome, "item": str(slime.get("item", "")), "rounds": round_no,
		"ally_incidents": ally_incidents, "boredom": boredom, "looked": looked}


func _perform(h: Dictionary, action: String, ev: Array) -> bool:
	var def := action_def(action)
	h.mp = int(h.mp) - _mp_cost(action)
	var target := _pick_target()
	var args := {"hero": Content.name_of(h.id), "target": _target_name(target)}
	_log(ev, str(def.get("log", "")), args)
	if def.has("sfx"):
		ev.append({"type": "sfx", "id": str(def.sfx)})
	match str(def.get("effect", "none")):
		"damage":
			if target == "":
				_log(ev, "battle.log.no_target", args)
				return false
			var dmg := Rules.integer("battle.actions.%s.damage" % action, 0)
			return _hit(target, dmg, h.id, ev)
		"steal":
			if str(slime.item) != "":
				_log(ev, "battle.log.stolen", {"hero": args.hero, "item": Content.name_of(str(slime.item))})
				slime.item = ""
				ev.append({"type": "slime"})
			else:
				_log(ev, "battle.log.steal_nothing", args)
		"out_of_mp":
			_out_of_mp_this_round = true
	return false


func _pick_target() -> String:
	var t := "slime"
	if bool(slime.hidden):
		t = "ally" if not ally.is_empty() else ""
	elif not ally.is_empty() and Rules.flag("battle.ally.draws_aggro", true):
		t = "ally"
	return str(Hooks.filter("battle.target", t, {"model": self}))


func _target_name(target: String) -> String:
	match target:
		"slime":
			return Content.name_of(str(_battle.get("slime_character", "protagonist")))
		"ally":
			return Content.name_of(str(_battle.get("ally_character", "pool_mate")))
	return ""


func _hit(target: String, dmg: int, hero_id: String, ev: Array) -> bool:
	if target == "slime":
		if bool(slime.defending):
			dmg = int(floor(dmg * Rules.num("battle.slime.defend_multiplier", 0.5)))
		dmg -= int(slime.defense_bonus)
		dmg = maxi(Rules.integer("battle.min_damage", 0), dmg)
		dmg = int(Hooks.filter("battle.damage", dmg, {"target": target, "hero": hero_id, "model": self}))
		slime.hp = int(slime.hp) - dmg
		_log(ev, "battle.log.slime_hit", {"n": dmg})
		ev.append({"type": "slime"})
		if int(slime.hp) <= 0:
			outcome = "incident"
			_log(ev, "battle.log.slime_incident", {})
			return true
		return false
	dmg = int(Hooks.filter("battle.damage", dmg, {"target": target, "hero": hero_id, "model": self}))
	ally.hp = int(ally.hp) - dmg
	_log(ev, "battle.log.ally_hit", {"n": dmg, "target": _target_name("ally")})
	if int(ally.hp) <= 0:
		ally = {}
		ally_incidents += 1
		_log(ev, "battle.log.ally_incident", {"target": _target_name("ally")})
		ev.append({"type": "ally_out"})
		return true
	return false


func _update_boredom(exp_gained: bool, ev: Array) -> void:
	if exp_gained:
		boredom = 0
		return
	var add := Rules.integer("battle.boredom.per_round", 1)
	if _hid_this_round:
		add += Rules.integer("battle.boredom.hide_bonus", 1)
	if _out_of_mp_this_round:
		add += Rules.integer("battle.boredom.out_of_mp_bonus", 1)
	boredom += int(Hooks.filter("battle.boredom", add, {"model": self}))
	var lines: Dictionary = _battle.get("boredom_lines", {})
	var best := ""
	var best_level := -1
	for level in lines.keys():
		if int(level) <= boredom and int(level) > best_level:
			best_level = int(level)
			best = str(lines[level])
	if best != "" and best_level == boredom:
		_log(ev, best, {})
	if boredom >= Rules.integer("battle.boredom.threshold", 5):
		outcome = "bored"
		_log(ev, "battle.log.heroes_leave", {})


func _log(ev: Array, key: String, args: Dictionary) -> void:
	if key != "":
		ev.append({"type": "log", "key": key, "args": args})


# ---- verbs -------------------------------------------------------------------

func _verb_look(_arg: String, ev: Array) -> void:
	looked = true
	_log(ev, "battle.log.look", {})
	var preview := {}
	var n := Rules.integer("battle.look.turns", 2)
	for h in heroes:
		preview[h.id] = forecast(h.id, n)
	ev.append({"type": "preview", "data": preview})


func _verb_defend(_arg: String, ev: Array) -> void:
	slime.defending = true
	_log(ev, "battle.log.defend", {})


func _verb_absorb(arg: String, ev: Array) -> void:
	if arg == "" and not absorbable_terrain().is_empty():
		arg = absorbable_terrain()[0]
	if not absorbable_terrain().has(arg):
		_log(ev, "battle.log.absorb_nothing", {})
		return
	var def: Dictionary = _terrain_defs[arg]
	var fx: Dictionary = def.absorb
	_log(ev, str(def.get("absorb_log", "battle.log.absorb")), {"thing": terrain_label(arg)})
	if fx.has("item"):
		slime.item = str(fx.item)
	if bool(fx.get("defense_bonus", false)):
		slime.defense_bonus = int(slime.defense_bonus) + Rules.integer("battle.terrain.%s.defense_bonus" % arg, 0)
	if bool(fx.get("heavy", false)):
		slime.heavy = true
	if bool(fx.get("sleep_next_actor", false)):
		_sleep_next_actor = true
	ev.append({"type": "slime"})
	if Rules.flag("battle.terrain.consumed_on_absorb", true):
		terrain.erase(arg)


func _verb_hide(arg: String, ev: Array) -> void:
	var covers := cover_terrain()
	if covers.is_empty():
		_log(ev, "battle.log.hide_nowhere", {})
		return
	if arg == "" or not covers.has(arg):
		arg = covers[0]
	slime.hidden = true
	_hid_this_round = true
	_log(ev, "battle.log.hide", {"thing": terrain_label(arg)})
	if Rules.flag("battle.terrain.consumed_on_hide", true):
		terrain.erase(arg)   # a cover works once per battle


func _verb_call_help(_arg: String, ev: Array) -> void:
	_log(ev, "battle.log.call_help", {})
	if not ally.is_empty() or calls_left <= 0:
		_log(ev, "battle.log.nobody_comes", {})
		return
	calls_left -= 1
	ally = {"hp": Rules.integer("battle.ally.max_hp", 3)}
	_log(ev, "battle.log.ally_arrives", {"target": _target_name("ally")})
	ev.append({"type": "ally_in"})


func _verb_flee(_arg: String, ev: Array) -> void:
	var window := false
	for id in plans.keys():
		if action_def(plans[id]).get("flags", []).has("flee_window"):
			window = true
	var ok := window and not bool(slime.heavy)
	ok = bool(Hooks.filter("battle.flee", ok, {"model": self, "window": window}))
	if ok:
		outcome = "fled"
		_log(ev, "battle.log.fled", {})
	elif bool(slime.heavy):
		_log(ev, "battle.log.too_heavy", {})
	else:
		_log(ev, "battle.log.flee_failed", {})
