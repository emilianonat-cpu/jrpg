extends Control
## Battle: the meadow seen by the Heroes. The place where Slayme was caught,
## zoomed in; the Heroes big, asymmetric, each with their own menu; their
## narration on top. Slayme stays his size, bottom, with a small handwritten
## card of verbs. All logic is in BattleModel; this script only shows it.
## Placement comes from battle.json "stage", timings from rules.json.

signal battle_finished(result: Dictionary)

var model: BattleModel
var _columns: Dictionary = {}   # hero id -> {sprite, label, panel, home}
var _skip := false
var _choosing := false
var _slime_sprite: ArtSprite
var _ally_sprite: ArtSprite
var _hp_label: Label
var _status_label: Label
var _battle: Dictionary = {}
var _stage: Dictionary = {}

@onready var background: TextureRect = $Background
@onready var stage: Control = %Stage
@onready var log_panel: PanelContainer = %LogPanel
@onready var log_label: Label = %Log
@onready var slime_panel: PanelContainer = %SlimePanel
@onready var verbs: ChoiceList = %Verbs
@onready var sub_choices: ChoiceList = %SubChoices


## [param bg_id]: the place where it happened (zoomed); empty = battle.json "background".
## [param focus_y]: where the Heroes' lane is on that picture.
func start(party: Array, terrain_ids: Array, carried_item: String, bg_id: String = "", focus_y: float = 108.0) -> void:
	_battle = Content.dict("battle")
	_stage = _battle.get("stage", {})
	model = BattleModel.new()
	model.setup(party, terrain_ids, carried_item)
	_set_background(bg_id, focus_y)
	UiTheme.panel(log_panel, "panel_hero_menu")
	UiTheme.panel(slime_panel, "panel_slime")
	UiTheme.font(log_panel, "font_heroes", "ui.font_size_heroes")
	UiTheme.font(slime_panel, "font_slime", "ui.font_size_slime")
	var ink := Color(Rules.text("ui.slime_panel_text_color", "#2a2420"))
	verbs.text_color = ink
	sub_choices.text_color = ink
	_build_heroes()
	_build_slime()
	_refresh_slime()
	slime_panel.visible = false   # Slayme's little card only shows when it's his turn
	Art.play_sound(str(_battle.get("music_intro", "")))
	_run.call_deferred()


## The same place, closer: a crop of the location picture around the Heroes' lane.
func _set_background(bg_id: String, focus_y: float) -> void:
	if bg_id == "" or not Art.has(bg_id):
		bg_id = str(_battle.get("background", "bg_battle_meadow"))
		focus_y = 90.0
	var tex := Art.texture(bg_id)
	if tex == null:
		return
	var k := tex.get_width() / 320.0
	var zoom := maxf(1.0, float(_stage.get("zoom", 1.0)))
	var w := 320.0 * k / zoom
	var h := 180.0 * k / zoom
	var cy := clampf(focus_y * k - h * float(_stage.get("focus_at", 0.6)), 0.0, tex.get_height() - h)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2((tex.get_width() - w) / 2.0, cy, w, h)
	background.texture = at
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if str(Art.entry(bg_id).get("filter", "")) == "linear" else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	var shade := float(_stage.get("background_shade", 1.0))
	background.modulate = Color(shade, shade, shade)


func _build_heroes() -> void:
	var defs: Dictionary = Content.dict("heroes").get("heroes", {})
	var places: Dictionary = _stage.get("heroes", {})
	var i := 0
	for id in model.hero_ids():
		var place: Dictionary = places.get(id, {})
		var home := DataFile.vec2(place.get("pos"), Vector2(70 + i * 90, 110))
		var s := ArtSprite.new()
		stage.add_child(s)
		s.set_art(str(defs.get(id, {}).get("art_battle", "missing")))
		s.scale *= float(place.get("scale", 1.0))
		s.position = home + DataFile.vec2(place.get("enter_from"), Vector2.ZERO)
		var panel := PanelContainer.new()
		UiTheme.panel(panel, "panel_hero_menu")
		UiTheme.font(panel, "font_heroes", "ui.font_size_heroes")
		var label := Label.new()
		panel.add_child(label)
		stage.add_child(panel)
		panel.position = home + DataFile.vec2(place.get("menu"), Vector2(-20, -60))
		label.text = Content.name_of(id)
		_columns[id] = {"sprite": s, "label": label, "panel": panel, "home": home}
		i += 1


func _build_slime() -> void:
	var at := DataFile.vec2(_stage.get("slime_pos"), Vector2(160, 164))
	_slime_sprite = ArtSprite.new()
	_slime_sprite.position = at
	stage.add_child(_slime_sprite)
	_slime_sprite.set_art(str(_battle.get("slime_art", "slime_battle")))
	_ally_sprite = ArtSprite.new()
	_ally_sprite.position = at + DataFile.vec2(_stage.get("ally_offset"), Vector2(16, 0))
	stage.add_child(_ally_sprite)
	_ally_sprite.set_art(str(_battle.get("ally_art", "slime_battle_ally")))
	_ally_sprite.visible = false
	_hp_label = _small_label(at + Vector2(0, -14))
	_status_label = _small_label(at + Vector2(0, 6))


## A few outlined words in the scene (Slayme's HP, what he carries).
func _small_label(center: Vector2) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", Rules.integer("ui.world_text_outline", 4))
	l.add_theme_color_override("font_outline_color", Color(Rules.text("ui.world_text_outline_color", "#1c1814")))
	UiTheme.font(l, "font_main", "ui.font_size_world")
	stage.add_child(l)
	l.set_meta("center", center)
	return l


func _place_small(l: Label) -> void:
	l.reset_size()
	var c: Vector2 = l.get_meta("center")
	l.position = c - Vector2(l.size.x / 2.0, l.size.y / 2.0)


## The Heroes walk in from the edges of the picture.
func _enter() -> void:
	var d := Rules.num("battle.stage.enter_seconds", 0.5)
	var t := create_tween().set_parallel(true)
	for id in _columns.keys():
		t.tween_property(_columns[id].sprite, "position", _columns[id].home, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	modulate.a = 0.0
	t.tween_property(self, "modulate:a", 1.0, d * 0.6)
	await t.finished


## They leave the way they came; the picture fades back to the meadow.
func _leave() -> void:
	var d := Rules.num("battle.stage.leave_seconds", 0.6)
	var places: Dictionary = _stage.get("heroes", {})
	var t := create_tween().set_parallel(true)
	if model.outcome != "incident":
		for id in _columns.keys():
			var out := DataFile.vec2(places.get(id, {}).get("enter_from"), Vector2(0, 200))
			t.tween_property(_columns[id].sprite, "position", _columns[id].home + out, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			t.tween_property(_columns[id].panel, "modulate:a", 0.0, d * 0.5)
	t.tween_property(self, "modulate:a", 0.0, d).set_delay(d * 0.5)
	await t.finished


# ---- main loop -------------------------------------------------------------

func _run() -> void:
	await _enter()
	await _say(Content.text("battle.log.intro"))
	var bark := _battle_bark()
	if bark != "":
		await _say(bark)
	var first_time := not GameState.flags.has("verbs_known")
	for label in model.take_new_verbs():
		if not first_time:
			Art.play_sound("unlock")
			await _say(Content.text("battle.log.new_verb", {"verb": label}))
	while model.outcome == "":
		model.plan_round()
		await _show_hero_menus()
		var choice: Array = await _choose_verb()
		Art.play_sound(_verb_sfx(choice[0]))
		var events := model.resolve(choice[0], choice[1])
		await _play(events)
		_show_boredom()
	Art.play_sound("battle_" + model.outcome)
	await _wait(Rules.num("ui.battle_log_delay", 0.9))
	if model.outcome != "incident":
		Music.set_level("near", Rules.num("battle.stage.leave_seconds", 0.6) * 4.0)
	await _leave()
	battle_finished.emit(model.result())


## Boredom you can see: one by one they stop paying attention (battle.json "bored_turn").
func _show_boredom() -> void:
	var turns: Dictionary = _battle.get("bored_turn", {})
	for level in turns.keys():
		var id := str(turns[level])
		if not _columns.has(id) or model.boredom < int(level):
			continue
		var s: ArtSprite = _columns[id].sprite
		if not s.flip_h:
			s.flip_h = true
			var t := create_tween()
			t.tween_property(s, "position", _columns[id].home + DataFile.vec2(_stage.get("bored_shift"), Vector2(0, 4)), 0.4)


func _verb_sfx(verb_id: String) -> String:
	for v in _battle.get("verbs", []):
		if str(v.get("id", "")) == verb_id:
			return str(v.get("sfx", ""))
	return ""


## One hero says something as the fight starts (heroes.json barks).
func _battle_bark() -> String:
	var defs: Dictionary = Content.dict("heroes").get("heroes", {})
	var ids := model.hero_ids()
	if ids.is_empty():
		return ""
	var n := int(GameState.stats.get("battles", 0))
	var id: String = ids[n % ids.size()]
	var barks: Array = defs.get(id, {}).get("barks", [])
	if barks.is_empty():
		return ""
	return "%s: %s" % [Content.name_of(id), Content.text(str(barks[(n + 1) % barks.size()]))]


## The Heroes' cursors move on their menu: the player sees what is coming.
func _show_hero_menus() -> void:
	var menu: Array = _battle.get("hero_menu", [])
	var dim := float(_stage.get("dim", 0.6))
	for id in model.hero_ids():
		var action: String = model.plans.get(id, "")
		var def := model.action_def(action)
		var label: Label = _columns[id].label
		# Whoever is choosing gets the light; the others step back a little.
		for other in _columns.keys():
			var on: bool = other == id
			_columns[other].sprite.modulate = Color.WHITE if on else Color(dim, dim, dim)
			_columns[other].panel.modulate.a = 1.0 if on else 0.75
		if action == "sleeping":
			_columns[id].sprite.modulate = Color(0.6, 0.6, 0.7)
		var target_menu := str(def.get("menu", ""))
		if def.has("peek"):
			await _peek(id, str(def.peek))
		if target_menu == "":
			label.text = "%s\n%s" % [Content.name_of(id), Content.text(str(def.get("label", "")))]
			continue
		for m in menu:
			label.text = "%s\n%s%s" % [Content.name_of(id), Content.text("ui.cursor"), Content.text(str(m.label))]
			_fit(_columns[id].panel)
			await _wait(Rules.num("ui.hero_cursor_step", 0.12), false)
			if str(m.id) == target_menu:
				break
		label.text = "%s\n%s%s %s" % [Content.name_of(id), Content.text("ui.cursor"),
			Content.text(str(def.get("label", ""))), _target_hint()]
	for other in _columns.keys():
		_columns[other].sprite.modulate = Color.WHITE
		_columns[other].panel.modulate.a = 1.0
		_fit(_columns[other].panel)


## Keeps a panel inside the screen after its text changed.
func _fit(panel: Control) -> void:
	panel.reset_size()
	panel.position.x = clampf(panel.position.x, 2.0, 318.0 - panel.size.x)
	panel.position.y = clampf(panel.position.y, 26.0, 178.0 - panel.size.y)


## A Hero checks their own stuff: a panel opens, half-readable, and closes.
## Numbers show only if Slayme looked around this fight.
func _peek(hero_id: String, key: String) -> void:
	var h := model._hero(hero_id)
	var max_mp := Rules.integer("battle.heroes.%s.mp" % hero_id, 0)
	var k := key if model.looked or not Content.has_text(key + ".hidden") else key + ".hidden"
	var panel := PanelContainer.new()
	UiTheme.panel(panel, "panel_hero_menu")
	UiTheme.font(panel, "font_heroes", "ui.font_size_heroes")
	var l := Label.new()
	l.text = Content.text(k, {"mp": int(h.get("mp", 0)), "max": max_mp, "item": _item_name(str(model.slime.get("item", "")))})
	panel.add_child(l)
	stage.add_child(panel)
	panel.position = _columns[hero_id].panel.position + DataFile.vec2(_stage.get("peek_offset"), Vector2(0, 26))
	panel.scale = Vector2(1, 0)
	var t := create_tween()
	t.tween_property(panel, "scale", Vector2.ONE, 0.12)
	await t.finished
	await _wait(Rules.num("battle.stage.peek_seconds", 1.4))
	panel.queue_free()


func _item_name(item_id: String) -> String:
	if item_id == "":
		return Content.text("peek.nothing")
	var it: Dictionary = Content.dict("items").get(item_id, {})
	return Content.name_of(str(it.get("name", item_id)))


func _target_hint() -> String:
	var t := model._pick_target()
	return Content.text("battle.target_arrow", {"target": model._target_name(t)}) if t != "" else ""


func _choose_verb() -> Array:
	slime_panel.visible = true
	var r: Array = await _choose_verb_inner()
	slime_panel.visible = false
	return r


func _choose_verb_inner() -> Array:
	while true:
		verbs.set_items(model.verbs(), verbs.index)
		verbs.visible = true
		sub_choices.visible = false
		verbs.active = true
		_choosing = true
		var picked: Array = await verbs.chosen
		verbs.active = false
		var verb: String = picked[0]
		var options: Array = []
		if verb == "absorb":
			options = model.absorbable_terrain()
		elif verb == "hide":
			options = model.cover_terrain()
		if options.size() <= 1:
			_choosing = false
			return [verb, options[0] if options.size() == 1 else ""]
		# Several things around: choose which one.
		sub_choices.set_items(options.map(func(t): return {"id": t, "label": model.terrain_label(t)}))
		sub_choices.allow_cancel = true
		verbs.visible = false
		sub_choices.visible = true
		sub_choices.active = true
		var result: Array = await _sub_choice()
		sub_choices.active = false
		if result[0] != "":
			_choosing = false
			return [verb, result[0]]
	return ["look", ""]


func _sub_choice() -> Array:
	var state := {"done": false, "id": ""}
	var on_pick := func(id, _i):
		state.done = true
		state.id = id
	var on_cancel := func():
		state.done = true
	sub_choices.chosen.connect(on_pick)
	sub_choices.cancelled.connect(on_cancel)
	while not state.done:
		await get_tree().process_frame
	sub_choices.chosen.disconnect(on_pick)
	sub_choices.cancelled.disconnect(on_cancel)
	return [state.id]


func _play(events: Array) -> void:
	for e in events:
		match str(e.get("type", "")):
			"log":
				await _say(Content.text(str(e.key), e.get("args", {})))
			"sfx":
				Art.play_sound(str(e.id))
			"slime":
				_refresh_slime()
			"ally_in":
				_ally_sprite.visible = true
			"ally_out":
				_ally_sprite.visible = false
			"preview":
				_show_preview(e.data)
				await _wait(Rules.num("ui.battle_log_delay", 0.9) * 2.0)


func _show_preview(data: Dictionary) -> void:
	for id in data.keys():
		var names: Array = data[id].map(func(a): return Content.text(str(model.action_def(a).get("label", a))))
		_columns[id].label.text = "%s\n%s" % [Content.name_of(id), Content.text("battle.preview", {"list": ", ".join(names)})]
		_fit(_columns[id].panel)


func _refresh_slime() -> void:
	var hp := maxi(0, int(model.slime.hp))
	var dots := ""
	for i in int(model.slime.max_hp):
		dots += Content.text("battle.hp_full") if i < hp else Content.text("battle.hp_empty")
	_hp_label.text = dots
	_place_small(_hp_label)
	var item := str(model.slime.get("item", ""))
	if item == "":
		_status_label.text = ""
	else:
		var it: Dictionary = Content.dict("items").get(item, {})
		_status_label.text = Content.name_of(str(it.get("name", item)))
	_place_small(_status_label)


func _say(text: String) -> void:
	log_label.text = text
	await _wait(Rules.num("ui.battle_log_delay", 0.9))


## Waits [param seconds] or until the player presses interact (if skippable).
func _wait(seconds: float, skippable: bool = true) -> void:
	_skip = false
	var t := 0.0
	while t < seconds and not (skippable and _skip):
		await get_tree().process_frame
		t += get_process_delta_time()


func _unhandled_input(event: InputEvent) -> void:
	if not _choosing and event.is_action_pressed("interact"):
		_skip = true
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _choosing and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip = true
		get_viewport().set_input_as_handled()
