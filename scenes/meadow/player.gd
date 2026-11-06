class_name Player
extends Node2D
## Slayme in the world. Tiny. Carries one thing inside, visible through the jelly.

var bounds := Rect2(0, 0, 320, 180)
var frozen := false
var concealed := false
var body: ArtSprite
var held: ArtSprite


func _init() -> void:
	name = "Player"


func setup(art_id: String, map_bounds: Rect2) -> void:
	bounds = map_bounds
	body = ArtSprite.new()
	add_child(body)
	body.set_art(art_id)
	held = ArtSprite.new()
	held.position = Vector2(0, 1)
	add_child(held)


func show_item(item_id: String) -> void:
	if item_id == "":
		held.set_art("")
		return
	var item: Dictionary = Content.dict("items").get(item_id, {})
	held.set_art(str(item.get("art", "missing")))


func set_hidden(value: bool) -> void:
	concealed = value
	modulate.a = 0.5 if value else 1.0


func _process(delta: float) -> void:
	if frozen:
		return
	var v := Controls.move_vector()
	if v == Vector2.ZERO:
		return
	position += v * Rules.num("world.slime_speed", 50) * delta
	position = position.clamp(bounds.position, bounds.end)
