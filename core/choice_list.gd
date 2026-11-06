class_name ChoiceList
extends GridContainer
## Keyboard/gamepad menu made of Labels (no mouse, no focus system).
## set_items([{ "label": "Look around", "id": "look", "enabled": true }, ...])
## then active = true; emits chosen(id, index) or cancelled.

signal chosen(id: String, index: int)
signal cancelled
signal moved(index: int)

var items: Array = []
var index := 0
var active := false:
	set(v):
		active = v
		_refresh()
var allow_cancel := false
## Text colour for the entries (alpha 0 = theme default).
@export var text_color := Color(0, 0, 0, 0)
var _labels: Array[Label] = []


func set_items(new_items: Array, start_index: int = 0) -> void:
	items = new_items
	for l in _labels:
		l.queue_free()
	_labels.clear()
	for it in items:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.gui_input.connect(_on_label_input.bind(_labels.size()))
		if text_color.a > 0.0:
			l.add_theme_color_override("font_color", text_color)
		add_child(l)
		_labels.append(l)
	index = clampi(start_index, 0, maxi(0, items.size() - 1))
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not active or items.is_empty() or not is_visible_in_tree():
		return
	var cols := maxi(1, columns)
	if event.is_action_pressed("move_down"):
		_move(cols)
	elif event.is_action_pressed("move_up"):
		_move(-cols)
	elif event.is_action_pressed("move_right") and cols > 1:
		_move(1)
	elif event.is_action_pressed("move_left") and cols > 1:
		_move(-1)
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if bool(items[index].get("enabled", true)):
			chosen.emit(str(items[index].get("id", str(index))), index)
		return
	elif event.is_action_pressed("cancel") and allow_cancel:
		get_viewport().set_input_as_handled()
		cancelled.emit()
		return
	else:
		return
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	var n := items.size()
	index = (index + step + n) % n
	_refresh()
	moved.emit(index)


func _refresh() -> void:
	var cursor := Content.text("ui.cursor")
	var blank := Content.text("ui.cursor_blank")
	for i in _labels.size():
		var it: Dictionary = items[i]
		var on := active and i == index
		_labels[i].text = (cursor if on else blank) + str(it.get("label", ""))
		_labels[i].modulate.a = 1.0 if bool(it.get("enabled", true)) else 0.45


func _on_label_input(event: InputEvent, i: int) -> void:
	if not active or i >= items.size() or not Controls.mouse_enabled():
		return
	if event is InputEventMouseMotion and index != i:
		index = i
		_refresh()
		moved.emit(index)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		index = i
		_refresh()
		accept_event()
		if bool(items[i].get("enabled", true)):
			chosen.emit(str(items[i].get("id", str(i))), i)
