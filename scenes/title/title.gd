extends Screen

@onready var background: ArtSprite = $Background
@onready var title_label: Label = %TitleLabel
@onready var subtitle: Label = %Subtitle
@onready var menu: ChoiceList = %Menu


func enter(_payload: Dictionary) -> void:
	background.set_art("bg_title")
	title_label.text = Content.name_of("game_title")
	subtitle.text = Content.text("title.subtitle")
	var items := []
	if GameState.has_memory():
		items.append({"id": "continue", "label": Content.text("title.continue")})
	items.append({"id": "new", "label": Content.text("title.new")})
	items.append({"id": "quit", "label": Content.text("title.quit")})
	menu.set_items(items)
	menu.active = true
	menu.chosen.connect(_on_chosen)


func _on_chosen(id: String, _index: int) -> void:
	menu.active = false
	match id:
		"continue":
			GameState.read_memory()
			go("meadow")
		"new":
			GameState.new_game()
			go("meadow")
		"quit":
			get_tree().quit()
