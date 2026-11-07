extends Screen
## Home: one room. Same question every evening, same answer.

@onready var background: ArtSprite = $Background
@onready var objects: Node2D = $Objects
@onready var dialogue = $Dialogue


func enter(_payload: Dictionary) -> void:
	var map := Content.dict("maps/home")
	background.set_art(str(map.get("background", "")))
	for d in map.get("objects", []):
		var o := WorldObject.new()
		o.setup(d)
		objects.add_child(o)
	Hooks.emit("home.ready", {"screen": self})
	_evening.call_deferred(map.get("dialogue", {}))


func _evening(dlg: Dictionary) -> void:
	var bit_line := str(GameState.variation_for(GameState.day).get("bit_line", "dlg.kid.play_1"))
	var lines: Array = Content.dialogue(str(dlg.get("file", "home")), str(dlg.get("sequence", "evening"))).duplicate(true)
	for l in lines:
		if str(l.get("text", "")) == "{bit_line}":
			l["text"] = bit_line
	await dialogue.play(lines)
	go("night")
