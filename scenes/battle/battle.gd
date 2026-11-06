extends Control
## Battle screen. The view is reversed: the Heroes are in front, big and
## detailed, as if *they* were the monsters, with their menu visible.
## Slayme is small, at the bottom, with a few verbs and no menu.
## All logic is in BattleModel; this script only shows it.

signal battle_finished(result: Dictionary)

var model: BattleModel
var _columns: Dictionary = {}   # hero id -> {sprite, menu_label, slot}
var _skip := false
var _choosing := false
var _slime_sprite: ArtSprite
var _ally_sprite: ArtSprite
var _battle: Dictionary = {}

@onready var background: TextureRect = $Background
@onready var hero_row: HBoxContainer = %HeroRow
@onready var log_panel: PanelContainer = %LogPanel
@onready var log_label: Label = %Log
@onready var slime_panel: PanelContainer = %SlimePanel
@onready var slime_slot: Control = %SlimeSlot
@onready var hp_label: Label = %Hp
@onready var status_label: Label = %Status
@onready var verbs: ChoiceList = %Verbs
@onready var sub_choices: ChoiceList = %SubChoices


func start(party: Array, terrain_ids: Array, carried_item: String) -> void:
	_battle = Content.dict("battle")
	model = BattleModel.new()
	model.setup(party, terrain_ids, carried_item)
	background.texture = Art.texture(str(_battle.get("background", "bg_battle_meadow")))
	UiTheme.panel(log_panel, "panel_dialogue")
	UiTheme.panel(slime_panel, "panel_slime")
	var ink := Color(Rules.text("ui.slime_panel_text_color", "#2a2420"))
	for l in [hp_label, status_label]:
		l.add_theme_color_override("font_color", ink)
	verbs.text_color = ink
	sub_choices.text_color = ink
	_build_heroes()
	_slime_sprite = ArtSprite.new()
	_slime_sprite.position = Vector2(10, 8)
	slime_slot.add_child(_slime_sprite)
	_slime_sprite.set_art(str(_battle.get("slime_art", "slime_battle")))
	_ally_sprite = ArtSprite.new()
	_ally_sprite.position = Vector2(28, 8)
	slime_slot.add_child(_ally_sprite)
	_ally_sprite.set_art(str(_battle.get("ally_art", "slime_battle_ally")))
	_ally_sprite.visible = false
	_refresh_slime()
	Art.play_sound(str(_battle.get("music_intro", "")))
	_run.call_deferred()


func _build_heroes() -> void:
	var defs: Dictionary = Content.dict("heroes").get("heroes", {})
	for id in model.hero_ids():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		hero_row.add_child(col)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(96, 64)
		col.add_child(slot)
		var s := ArtSprite.new()
		s.position = Vector2(48, 32)
		slot.add_child(s)
		s.set_art(str(defs.get(id, {}).get("art_battle", "missing")))
		var panel := PanelContainer.new()
		UiTheme.panel(panel, "panel_hero_menu")
		col.add_child(panel)
		var label := Label.new()
		label.custom_minimum_size = Vector2(88, 22)
		panel.add_child(label)
		_columns[id] = {"sprite": s, "label": label}
		label.text = Content.name_of(id)


# ---- main loop -------------------------------------------------------------

func _run() -> void:
	await _say(Content.text("battle.log.intro"))
	while model.outcome == "":
		model.plan_round()
		await _show_hero_menus()
		var choice: Array = await _choose_verb()
		var events := model.resolve(choice[0], choice[1])
		await _play(events)
	await _wait(Rules.num("ui.battle_log_delay", 0.9))
	battle_finished.emit(model.result())


## The Heroes' cursors move on their menu: the player sees what is coming.
func _show_hero_menus() -> void:
	var menu: Array = _battle.get("hero_menu", [])
	for id in model.hero_ids():
		var action: String = model.plans.get(id, "")
		var def := model.action_def(action)
		var label: Label = _columns[id].label
		var sprite: ArtSprite = _columns[id].sprite
		sprite.modulate = Color(0.6, 0.6, 0.7) if action == "sleeping" else Color.WHITE
		var target_menu := str(def.get("menu", ""))
		if target_menu == "":
			label.text = "%s\n%s" % [Content.name_of(id), Content.text(str(def.get("label", "")))]
			continue
		for m in menu:
			label.text = "%s\n%s%s" % [Content.name_of(id), Content.text("ui.cursor"), Content.text(str(m.label))]
			await _wait(Rules.num("ui.hero_cursor_step", 0.12), false)
			if str(m.id) == target_menu:
				break
		label.text = "%s\n%s%s %s" % [Content.name_of(id), Content.text("ui.cursor"),
			Content.text(str(def.get("label", ""))), _target_hint()]


func _target_hint() -> String:
	var t := model._pick_target()
	return Content.text("battle.target_arrow", {"target": model._target_name(t)}) if t != "" else ""


func _choose_verb() -> Array:
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


func _refresh_slime() -> void:
	hp_label.text = Content.text("battle.hp", {"hp": maxi(0, int(model.slime.hp)), "max": model.slime.max_hp})
	var item := str(model.slime.get("item", ""))
	if item == "":
		status_label.text = ""
	else:
		var it: Dictionary = Content.dict("items").get(item, {})
		status_label.text = Content.name_of(str(it.get("name", item)))


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
