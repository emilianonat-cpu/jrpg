extends Node
## Input setup (autoload "Controls").
##
## Actions are defined in res://data/controls.json (keyboard + gamepad).
## In the first act the mouse does nothing (rule input.mouse_enabled = false):
## the cursor will arrive later, with the Tool, as a *mode*, not a device.

const PATH := "res://data/controls.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	register_actions()
	_apply_mouse()
	Rules.changed.connect(func(key, _v): if key == "input.mouse_enabled": _apply_mouse())


func register_actions() -> void:
	var data := Content._dict(DataFile.load_json(PATH))
	for action in data.keys():
		if str(action).begins_with("_"):
			continue
		var def: Dictionary = data[action]
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, float(def.get("deadzone", 0.4)))
		for key_name in def.get("keys", []):
			var ev := InputEventKey.new()
			ev.physical_keycode = OS.find_keycode_from_string(str(key_name))
			InputMap.action_add_event(action, ev)
		for b in def.get("joy_buttons", []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(b)
			InputMap.action_add_event(action, jb)
		for ax in def.get("joy_axes", []):
			var ja := InputEventJoypadMotion.new()
			ja.axis = int(ax[0])
			ja.axis_value = float(ax[1])
			InputMap.action_add_event(action, ja)


func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func mouse_enabled() -> bool:
	return Rules.flag("input.mouse_enabled", false)


func _apply_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mouse_enabled() else Input.MOUSE_MODE_HIDDEN


func _input(event: InputEvent) -> void:
	if not mouse_enabled() and (event is InputEventMouseButton or event is InputEventMouseMotion):
		get_viewport().set_input_as_handled()
