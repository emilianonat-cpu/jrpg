class_name UiTheme
extends RefCounted
## Builds the global UI theme from rules + art pack (font, font size, colors).
## No drawing: frames come from the art pack via Art.stylebox().


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = Rules.integer("ui.font_size", 8)
	var f := Art.font("font_main")
	if f != null:
		t.default_font = f
	t.set_color("font_color", "Label", Color(Rules.text("ui.text_color", "#ffffff")))
	t.set_constant("line_spacing", "Label", Rules.integer("ui.line_spacing", 0))
	t.set_stylebox("panel", "PanelContainer", Art.stylebox("panel_dialogue"))
	return t


## Applies the theme to every Control (also those under CanvasLayers).
static func apply() -> void:
	var t := build()
	var default := ThemeDB.get_default_theme()
	default.merge_with(t)
	default.default_font_size = t.default_font_size
	if t.default_font != null:
		default.default_font = t.default_font
	ThemeDB.fallback_font_size = t.default_font_size


static func panel(node: PanelContainer, art_id: String) -> void:
	node.add_theme_stylebox_override("panel", Art.stylebox(art_id))
