extends Node
## Screen manager. Each screen is a scene whose root extends Screen and ends
## by emitting finished(next_screen, payload).

const SCREENS := {
	"title": "res://scenes/title/title.tscn",
	"meadow": "res://scenes/meadow_screens/meadow_screens.tscn",
	"meadow_free": "res://scenes/meadow/meadow.tscn",
	"home": "res://scenes/home/home.tscn",
	"night": "res://scenes/night/night.tscn",
	"end": "res://scenes/end/end.tscn",
}

@export var first_screen := "title"

var current: Screen = null
var current_id := ""

@onready var screens: Node = $Screens


func _ready() -> void:
	_apply_theme()
	Art.pack_changed.connect(func(_p): _apply_theme())
	show_screen(first_screen)


func show_screen(id: String, payload: Dictionary = {}) -> void:
	id = Hooks.filter("screen.next", id, {"from": current_id, "payload": payload})
	if id == "meadow" and Rules.text("world.mode", "screens") == "free":
		id = "meadow_free"
	if not SCREENS.has(id):
		push_error("Unknown screen: %s" % id)
		return
	if current != null:
		current.queue_free()
	var scene: PackedScene = load(SCREENS[id])
	current = scene.instantiate() as Screen
	current_id = id
	screens.add_child(current)
	current.finished.connect(func(next, p): show_screen.call_deferred(next, p))
	current.enter(payload)
	Hooks.emit("screen.entered", {"id": id, "node": current})


func _apply_theme() -> void:
	UiTheme.apply()
