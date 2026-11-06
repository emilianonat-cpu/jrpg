class_name WorldObject
extends Node2D
## Anything placed on a map from data (maps/*.json "objects").

var data: Dictionary = {}
var kind := ""
var sprite: ArtSprite


func setup(d: Dictionary) -> void:
	data = d
	kind = str(d.get("kind", "decor"))
	name = str(d.get("id", "object"))
	position = DataFile.vec2(d.get("pos"))
	sprite = ArtSprite.new()
	add_child(sprite)
	sprite.set_art(str(d.get("art", "")))


func object_id() -> String:
	return str(data.get("id", ""))


func radius() -> float:
	return float(data.get("radius", Rules.num("world.interact_radius", 16)))


func is_interactable() -> bool:
	return Content.has_text("prompt." + kind)


func prompt() -> String:
	return Content.text("prompt." + kind)
