extends Node
## Global hook registry (autoload "Hooks").
##
## Every mechanic passes its values through Hooks before using them, so any
## script can change the game's behaviour at runtime without editing the
## mechanic itself. This is the foundation for the future "Tool" (rules that
## change) and for the sick-out (rules that stop working).
##
## Two kinds of hooks:
##   filters: transform a value.  Hooks.add_filter("rule:battle.slime.max_hp", func(v, ctx): return 1)
##   events:  notify listeners.   Hooks.on("day.started", func(ctx): print(ctx.day))
##
## Hook names used by the skeleton are listed in README.md.

var _filters: Dictionary = {}    # hook name -> Array[{fn, priority}]
var _listeners: Dictionary = {}  # event name -> Array[Callable]


func add_filter(hook: String, fn: Callable, priority: int = 0) -> void:
	var list: Array = _filters.get(hook, [])
	list.append({"fn": fn, "priority": priority})
	list.sort_custom(func(a, b): return a.priority < b.priority)
	_filters[hook] = list


func remove_filter(hook: String, fn: Callable) -> void:
	if _filters.has(hook):
		_filters[hook] = _filters[hook].filter(func(e): return e.fn != fn)


## Runs [param value] through every filter registered for [param hook].
func filter(hook: String, value: Variant, ctx: Dictionary = {}) -> Variant:
	if not _filters.has(hook):
		return value
	for e in _filters[hook]:
		if e.fn.is_valid():
			value = e.fn.call(value, ctx)
	return value


func on(event: String, fn: Callable) -> void:
	var list: Array = _listeners.get(event, [])
	if not list.has(fn):
		list.append(fn)
	_listeners[event] = list


func off(event: String, fn: Callable) -> void:
	if _listeners.has(event):
		_listeners[event].erase(fn)


func emit(event: String, ctx: Dictionary = {}) -> void:
	for fn in _listeners.get(event, []).duplicate():
		if fn.is_valid():
			fn.call(ctx)


func clear() -> void:
	_filters.clear()
	_listeners.clear()
