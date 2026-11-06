class_name ArtSprite
extends Sprite2D
## A sprite whose image comes from the art pack by id.
## Manifest entry keys: file, frames (horizontal strip), fps, centered, offset [x,y],
## scale (a sharper, bigger image drawn smaller: 0.5 = made at 2x), filter ("linear" for
## painted/photo images; pixel art stays "nearest").
## Few frames and low fps on purpose for mobs: choppy animation is a style choice.

@export var art_id: String = "":
	set = set_art

var _fps := 0.0
var _art_scale := 1.0
var _t := 0.0


func _ready() -> void:
	Art.pack_changed.connect(func(_p): set_art(art_id))


func set_art(id: String) -> void:
	art_id = id
	if id == "":
		texture = null
		set_process(false)
		return
	var e := Art.entry(id)
	texture = Art.texture(id)
	hframes = maxi(1, int(e.get("frames", 1)))
	frame = 0
	_fps = float(e.get("fps", 0))
	centered = bool(e.get("centered", true))
	offset = DataFile.vec2(e.get("offset"), Vector2.ZERO)
	_art_scale = float(e.get("scale", 1.0))
	scale = Vector2(_art_scale, _art_scale)
	texture_filter = TEXTURE_FILTER_LINEAR if str(e.get("filter", "")) == "linear" else TEXTURE_FILTER_PARENT_NODE
	set_process(hframes > 1 and _fps > 0.0)


func size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(texture.get_width() / float(hframes), texture.get_height()) * _art_scale


func _process(delta: float) -> void:
	_t += delta
	var step := 1.0 / _fps
	while _t >= step:
		_t -= step
		frame = (frame + 1) % hframes
