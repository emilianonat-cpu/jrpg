class_name DataFile
extends RefCounted
## Small helpers to read the JSON data files in res://data and user://.


## Returns the parsed JSON (Dictionary or Array), or null if missing/invalid.
static func load_json(path: String, silent_if_missing: bool = false) -> Variant:
	if not FileAccess.file_exists(path):
		if not silent_if_missing:
			push_error("Data file not found: %s" % path)
		return null
	var raw := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func save_json(path: String, data: Variant) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## "09:30" -> 570. Numbers are returned as they are (already minutes).
static func to_minutes(value: Variant) -> float:
	if value is String and ":" in value:
		var parts: PackedStringArray = value.split(":")
		return float(parts[0]) * 60.0 + float(parts[1])
	return float(value)


static func vec2(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
