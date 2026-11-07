extends Node
## The Heroes' music. Slayme's world has no soundtrack: only the Heroes do.
## One track, heard through distance: a level from rules.json "music.levels"
## ([volume_db, lowpass_hz]) is reached with a short ramp. Silent if the art
## pack has no such sound.

const BUS := "Heroes"

var level := "off"
var _player: AudioStreamPlayer
var _filter: AudioEffectLowPassFilter
var _tween: Tween
var _track := ""


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
		_filter = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(i, _filter)
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.volume_db = -80.0
	add_child(_player)


## Moves the theme to a level ("off", "far", "near", "screen", "full") over [param seconds].
func set_level(new_level: String, seconds: float = -1.0) -> void:
	if new_level == level:
		return
	level = new_level
	if seconds < 0.0:
		seconds = Rules.num("music.ramp_seconds", 1.5)
	var track := Rules.text("music.heroes_track", "hero_theme")
	if new_level != "off" and (not _player.playing or _track != track):
		var s := Art.sound(track)
		if s == null:
			return
		if s is AudioStreamWAV and bool(Art.entry(track).get("loop", false)):
			var w: AudioStreamWAV = s
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = int(w.get_length() * w.mix_rate)
		_track = track
		_player.stream = s
		_player.volume_db = -80.0
		_player.play()
	var target: Array = Rules.get_value("music.levels.%s" % new_level, [-80.0, 400.0])
	var db := float(target[0])
	var hz := float(target[1])
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_player, "volume_db", db, seconds)
	if _filter != null:
		_tween.tween_property(_filter, "cutoff_hz", hz, seconds)
	if new_level == "off":
		_tween.chain().tween_callback(_player.stop)
