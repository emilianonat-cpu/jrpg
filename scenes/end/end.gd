extends Screen
## End of the prototype: the mentor asked his first question.


func enter(_payload: Dictionary) -> void:
	$Background.set_art("bg_title")
	%Title.text = Content.text("end.title")
	%Body.text = Content.text("end.body", {"days": GameState.day, "incidents": GameState.stats.get("incidents", 0)})
	var menu: ChoiceList = %Menu
	menu.set_items([{"id": "back", "label": Content.text("end.back")}])
	menu.active = true
	menu.chosen.connect(func(_id, _i): go("title"))
