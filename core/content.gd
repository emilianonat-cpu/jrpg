extends Node
## Content loader (autoload "Content").
##
## Names, texts and every content table come from res://data. The code never
## contains a character name or a line of dialogue: it asks for an id.
##
##   Content.name_of("mentor")              -> "Novecento" (data/names.json)
##   Content.text("board.notice", {"n": 6})  -> line from data/text/<lang>.json
##   Content.table("heroes")                 -> parsed data/heroes.json
##
## Inside texts you can write:
##   {name:mentor}   the display name of a character/place/item id
##   {text:some.key} another text
##   {n}             an argument passed by the code

const DATA_DIR := "res://data/"

var language := "en"
var _strings: Dictionary = {}
var _names: Dictionary = {}
var _tables: Dictionary = {}
var _token := RegEx.new()
var _missing_reported: Dictionary = {}


func _ready() -> void:
	_token.compile("\\{([a-z_]+)(?::([A-Za-z0-9_.]+))?\\}")
	reload()


func reload() -> void:
	_tables.clear()
	language = Rules.text("text.language", "en")
	_strings = _dict(DataFile.load_json(DATA_DIR + "text/%s.json" % language))
	_names = _dict(DataFile.load_json(DATA_DIR + "names.json"))
	# Optional per-language name overrides: data/text/<lang>_names.json
	var local_names: Variant = DataFile.load_json(DATA_DIR + "text/%s_names.json" % language, true)
	if local_names is Dictionary:
		_names.merge(local_names, true)


func name_of(id: String) -> String:
	var n: String = str(_names.get(id, id))
	return Hooks.filter("name", n, {"id": id})


func has_text(key: String) -> bool:
	return _strings.has(key)


func text(key: String, args: Dictionary = {}) -> String:
	if key == "":
		return ""
	var s: String
	if _strings.has(key):
		s = str(_strings[key])
	else:
		if not _missing_reported.has(key):
			_missing_reported[key] = true
			push_warning("Missing text key: %s" % key)
		s = "[%s]" % key
	s = _substitute(s, args)
	return Hooks.filter("text", s, {"key": key, "args": args})


## Parsed data file, cached. table("dialogue/mentor") -> data/dialogue/mentor.json
func table(table_name: String) -> Variant:
	if not _tables.has(table_name):
		_tables[table_name] = DataFile.load_json(DATA_DIR + table_name + ".json")
	return Hooks.filter("table:" + table_name, _tables[table_name], {"name": table_name})


func dict(table_name: String) -> Dictionary:
	return _dict(table(table_name))


## A dialogue sequence: Array of line dictionaries (see data/dialogue/README in README.md).
func dialogue(file: String, sequence: String) -> Array:
	var seqs := dict("dialogue/" + file)
	var lines: Variant = seqs.get(sequence, [])
	if not lines is Array or lines.is_empty():
		push_warning("Missing dialogue %s/%s" % [file, sequence])
		return [{"speaker": "", "text": "dlg.missing"}]
	return lines


func _substitute(s: String, args: Dictionary) -> String:
	if not "{" in s:
		return s
	var out := ""
	var last := 0
	for m in _token.search_all(s):
		out += s.substr(last, m.get_start() - last)
		var kind := m.get_string(1)
		var ref := m.get_string(2)
		if kind == "name" and ref != "":
			out += name_of(ref)
		elif kind == "text" and ref != "":
			out += text(ref, args)
		elif args.has(kind):
			out += str(args[kind])
		else:
			out += m.get_string()
		last = m.get_end()
	out += s.substr(last)
	return out


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
