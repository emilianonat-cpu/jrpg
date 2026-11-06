extends CanvasLayer
## Dialogue box. await play(lines) -> index of the last choice made (or -1).
## A line: {"speaker": "<names.json id or empty>", "text": "<text key>",
##          "args": {...}, "choices": ["<text key>", ...]}

signal _advanced

var playing := false
var _waiting := false

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = %Speaker
@onready var text_label: Label = %Text
@onready var choices: ChoiceList = %Choices


func _ready() -> void:
	panel.visible = false
	UiTheme.panel(panel, "panel_dialogue")


func play(lines: Array) -> int:
	var last_choice := -1
	playing = true
	panel.visible = true
	for line in lines:
		line = Hooks.filter("dialogue.line", line, {})
		if not line is Dictionary or line.is_empty():
			continue
		var spk := str(line.get("speaker", ""))
		speaker_label.visible = spk != ""
		speaker_label.text = Content.name_of(spk) if spk != "" else ""
		text_label.text = Content.text(str(line.get("text", "")), line.get("args", {}))
		var options: Array = line.get("choices", [])
		if options.is_empty():
			choices.visible = false
			await _wait_advance()
		else:
			choices.visible = true
			choices.set_items(options.map(func(k): return {"id": str(k), "label": Content.text(str(k))}))
			choices.active = true
			var picked: Array = await choices.chosen
			last_choice = int(picked[1])
			choices.active = false
			choices.visible = false
	panel.visible = false
	playing = false
	return last_choice


## Skip the current line (used by tests).
func advance() -> void:
	if _waiting:
		_waiting = false
		_advanced.emit()
	elif choices.active:
		choices.chosen.emit(str(choices.items[choices.index].id), choices.index)


func _wait_advance() -> void:
	_waiting = true
	await _advanced


func _unhandled_input(event: InputEvent) -> void:
	if _waiting and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		advance()


func _input(event: InputEvent) -> void:
	if _waiting and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		advance()
