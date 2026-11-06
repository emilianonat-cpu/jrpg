class_name Screen
extends Node
## Base class of every screen (title, meadow, home, night, end).
## A screen ends by emitting finished(next_screen_id, payload).

signal finished(next_screen: String, payload: Dictionary)


## Called by Main right after the screen enters the tree.
func enter(_payload: Dictionary) -> void:
	pass


func go(next_screen: String, payload: Dictionary = {}) -> void:
	finished.emit(next_screen, payload)
