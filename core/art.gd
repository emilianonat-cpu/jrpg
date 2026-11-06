extends Node
## Art packs (autoload "Art").
##
## The code never draws anything. Every sprite, background, UI frame, font and
## sound is an id resolved through the active art pack:
##   art/packs/<pack>/manifest.json   (inside the project)
##   user://art_packs/<pack>/manifest.json   (outside, no re-import needed)
##
## The "placeholder" pack is always loaded first, so a new pack only needs to
## contain the images it wants to replace. Missing ids fall back to "missing".

signal pack_changed(pack: String)

const PACKS_DIR := "res://art/packs/"
const USER_PACKS_DIR := "user://art_packs/"
const FALLBACK_PACK := "placeholder"
const SECTIONS := ["sprites", "backgrounds", "ui", "fonts", "sounds"]

var active_pack := ""
var _entries: Dictionary = {}
var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	use_pack(Rules.text("art.pack", FALLBACK_PACK))


func use_pack(pack: String) -> void:
	_entries.clear()
	_cache.clear()
	_merge_pack(FALLBACK_PACK)
	if pack != FALLBACK_PACK:
		_merge_pack(pack)
	active_pack = pack
	pack_changed.emit(pack)
	Hooks.emit("art.pack_changed", {"pack": pack})


func has(id: String) -> bool:
	return _entries.has(_resolve(id))


func entry(id: String) -> Dictionary:
	return _entries.get(_resolve(id), {})


func texture(id: String) -> Texture2D:
	id = _resolve(id)
	if _cache.has(id):
		return _cache[id]
	var e: Dictionary = _entries.get(id, {})
	if e.is_empty():
		_warn(id)
		e = _entries.get("missing", {})
	var tex: Texture2D = null
	if e.has("path"):
		tex = _load_texture(e.path)
	_cache[id] = tex
	return tex


## A UI frame (9-slice) built from a ui entry: {"file", "margin", "padding"}.
func stylebox(id: String) -> StyleBox:
	var e := entry(id)
	var tex := texture(id)
	if tex == null:
		return StyleBoxEmpty.new()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var m := float(e.get("margin", 4))
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	var p := float(e.get("padding", m))
	sb.content_margin_left = p
	sb.content_margin_right = p
	sb.content_margin_top = p
	sb.content_margin_bottom = p
	return sb


func font(id: String) -> Font:
	var e := entry(id)
	if e.is_empty() or not e.has("path"):
		return null
	if _cache.has("font:" + id):
		return _cache["font:" + id]
	var f: Font = null
	if ResourceLoader.exists(e.path):
		f = load(e.path)
	else:
		var ff := FontFile.new()
		if ff.load_dynamic_font(e.path) == OK:
			f = ff
	_cache["font:" + id] = f
	return f


func sound(id: String) -> AudioStream:
	var e := entry(id)
	if e.is_empty() or not e.has("path"):
		return null
	if _cache.has("snd:" + id):
		return _cache["snd:" + id]
	var s: AudioStream = null
	if ResourceLoader.exists(e.path):
		s = load(e.path)
	elif e.path.ends_with(".ogg"):
		s = AudioStreamOggVorbis.load_from_file(e.path)
	_cache["snd:" + id] = s
	return s


func play_sound(id: String) -> void:
	var s := sound(id)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = float(entry(id).get("volume_db", 0.0))
			p.play()
			return


func _resolve(id: String) -> String:
	return Hooks.filter("art.id", id, {})


func _merge_pack(pack: String) -> void:
	var dir := USER_PACKS_DIR + pack + "/"
	if not FileAccess.file_exists(dir + "manifest.json"):
		dir = PACKS_DIR + pack + "/"
	var manifest: Variant = DataFile.load_json(dir + "manifest.json")
	if not manifest is Dictionary:
		push_error("Art pack '%s' has no valid manifest.json" % pack)
		return
	for section in SECTIONS:
		var items: Variant = manifest.get(section, {})
		if not items is Dictionary:
			continue
		for id in items.keys():
			var e: Dictionary = items[id].duplicate() if items[id] is Dictionary else {"file": str(items[id])}
			e["section"] = section
			e["pack"] = pack
			if e.has("file"):
				e["path"] = dir + str(e.file)
			_entries[id] = e


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_error("Cannot load image %s" % path)
		return null
	return ImageTexture.create_from_image(img)


func _warn(id: String) -> void:
	if not _warned.has(id):
		_warned[id] = true
		push_warning("Art id not in pack: %s" % id)
