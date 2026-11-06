class_name HeroParty
extends Node2D
## The party walking along the Path. They never stop for long.

signal left_meadow

var members: Array = []
var sprites: Array[ArtSprite] = []
var paused := false
var ignore_player := false
var _curve := Curve2D.new()
var _dist := 0.0
var _hold := 0.0


func setup(path_points: Array, party: Array) -> void:
	name = "HeroParty"
	for p in path_points:
		_curve.add_point(DataFile.vec2(p))
	var defs: Dictionary = Content.dict("heroes").get("heroes", {})
	members = party
	for id in party:
		var s := ArtSprite.new()
		add_child(s)
		s.set_art(str(defs.get(id, {}).get("art_world", "missing")))
		sprites.append(s)
	_place()


## Stops the party for a while (e.g. the thief breaking a pot).
func hold(seconds: float) -> void:
	_hold = maxf(_hold, seconds)


func sprite_of(hero_id: String) -> ArtSprite:
	var i := members.find(hero_id)
	return sprites[i] if i >= 0 else null


func positions() -> Array:
	return sprites.map(func(s): return s.global_position)


func _process(delta: float) -> void:
	if paused:
		return
	if _hold > 0.0:
		_hold -= delta
		return
	_dist += Rules.num("world.hero_walk_speed", 16) * delta
	_place()
	if _dist - Rules.num("world.hero_spacing", 14) * sprites.size() > _curve.get_baked_length():
		left_meadow.emit()
		queue_free()


func _place() -> void:
	var spacing := Rules.num("world.hero_spacing", 14)
	for i in sprites.size():
		var d := clampf(_dist - spacing * i, 0.0, _curve.get_baked_length())
		sprites[i].position = _curve.sample_baked(d)
		sprites[i].visible = _dist - spacing * i >= 0.0
