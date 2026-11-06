extends Node
## The game clock (autoload "Clock"). Minutes since midnight.
## Speed: rule clock.minutes_per_second. Anything can pause it with a reason.

signal ticked(prev: float, now: float)

var minutes: float = 360.0
var running := false
## Changes every start_day(): a screen stops the clock only if it is still its day.
var session := 0
var _pauses: Dictionary = {}


func start_day() -> void:
	session += 1
	_pauses.clear()
	minutes = DataFile.to_minutes(Rules.get_value("clock.day_start", "06:00"))
	running = true
	ticked.emit(minutes - 0.001, minutes)


func stop(only_session: int = -1) -> void:
	if only_session >= 0 and only_session != session:
		return
	running = false


func pause(reason: String) -> void:
	_pauses[reason] = true


func resume(reason: String) -> void:
	_pauses.erase(reason)


func is_paused() -> bool:
	return not running or not _pauses.is_empty()


func advance(amount: float) -> void:
	amount = Hooks.filter("clock.advance", amount, {"now": minutes})
	if amount == 0.0:
		return
	var prev := minutes
	minutes += amount
	ticked.emit(prev, minutes)


func _process(delta: float) -> void:
	if not is_paused():
		advance(delta * Rules.num("clock.minutes_per_second", 2.0))


func format(m: float = -1.0) -> String:
	if m < 0.0:
		m = minutes
	var total := int(m)
	return "%02d:%02d" % [total / 60, total % 60]


static func crossed(time: float, prev: float, now: float) -> bool:
	return prev < time and now >= time
