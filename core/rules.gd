extends Node
## The central rules registry (autoload "Rules").
##
## Every number of the game (HP, damage, hero timetable, MP costs, boredom
## threshold, trust thresholds...) lives in res://data/rules.json and is read
## from here. Nothing else in the code should contain gameplay numbers.
##
## Three layers, from weakest to strongest:
##   1. res://data/rules.json            (the base rules)
##   2. user://rules_override.json        (optional, edit without touching res://)
##   3. set_override() at runtime         (the future Tool, debug, the sick-out)
## and finally every read goes through the filter hook "rule:<key>".
##
## Keys are dotted paths: Rules.num("battle.slime.max_hp").

signal changed(key: String, value: Variant)

const BASE_PATH := "res://data/rules.json"
const USER_PATH := "user://rules_override.json"

var _base: Dictionary = {}
var _overrides: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_base.clear()
	_flatten(DataFile.load_json(BASE_PATH), "", _base)
	var user: Variant = DataFile.load_json(USER_PATH, true)
	if user is Dictionary:
		_flatten(user, "", _base)


func get_value(key: String, default: Variant = null) -> Variant:
	var v: Variant = _overrides.get(key, _base.get(key, default))
	if v == null and default == null and not _base.has(key) and not _overrides.has(key):
		push_warning("Rule not defined: %s" % key)
	return Hooks.filter("rule:" + key, v, {"key": key})


func num(key: String, default: float = 0.0) -> float:
	return float(get_value(key, default))


func integer(key: String, default: int = 0) -> int:
	return int(get_value(key, default))


func flag(key: String, default: bool = false) -> bool:
	return bool(get_value(key, default))


func text(key: String, default: String = "") -> String:
	return str(get_value(key, default))


func list(key: String) -> Array:
	var v: Variant = get_value(key, [])
	return v if v is Array else []


func has(key: String) -> bool:
	return _base.has(key) or _overrides.has(key)


func set_override(key: String, value: Variant) -> void:
	_overrides[key] = value
	changed.emit(key, value)
	Hooks.emit("rules.changed", {"key": key, "value": value})


func clear_override(key: String) -> void:
	_overrides.erase(key)
	changed.emit(key, get_value(key))


func clear_all_overrides() -> void:
	for key in _overrides.keys():
		clear_override(key)


func keys() -> Array:
	var all := _base.keys()
	for k in _overrides.keys():
		if not all.has(k):
			all.append(k)
	all.sort()
	return all


func _flatten(src: Variant, prefix: String, into: Dictionary) -> void:
	if not src is Dictionary:
		return
	for k in src.keys():
		if str(k).begins_with("_"):
			continue  # "_comment" keys are documentation
		var full: String = (prefix + "." + str(k)) if prefix != "" else str(k)
		if src[k] is Dictionary:
			_flatten(src[k], full, into)
		else:
			into[full] = src[k]
