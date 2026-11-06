extends Screen
## Night: black screen, the morning bell, a new day exactly like the last.
## This is where the day ends and the mentor's memory is written.


func enter(_payload: Dictionary) -> void:
	$Background.set_art("bg_night")
	GameState.end_day()
	_sleep.call_deferred()


func _sleep() -> void:
	await get_tree().create_timer(Rules.num("night.seconds", 2.5)).timeout
	go("meadow")
