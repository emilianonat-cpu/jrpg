extends CanvasLayer
## Meadow HUD: day, clock, what Slayme is carrying, today's jobs, prompts.

var _toast_time := 0.0
var _day: DayState = null

@onready var top: PanelContainer = $Top
@onready var tasks_panel: PanelContainer = $Tasks
@onready var day_label: Label = %Day
@onready var time_label: Label = %Time
@onready var carry_label: Label = %Carry
@onready var task_list: VBoxContainer = %List
@onready var prompt_label: Label = %Prompt
@onready var toast_label: Label = %Toast


func _ready() -> void:
	UiTheme.panel(top, "panel_hud")
	UiTheme.panel(tasks_panel, "panel_hud")
	prompt_label.text = ""
	toast_label.text = ""


func setup(day: DayState) -> void:
	_day = day
	day_label.text = Content.text("hud.day", {"n": day.day})
	refresh()


func refresh() -> void:
	if _day == null:
		return
	time_label.text = Clock.format()
	if _day.carried == "":
		carry_label.text = Content.text("hud.carrying_nothing")
	else:
		var item: Dictionary = Content.dict("items").get(_day.carried, {})
		carry_label.text = Content.text("hud.carrying", {"item": Content.name_of(str(item.get("name", _day.carried)))})
	for c in task_list.get_children():
		c.queue_free()
	for id in _day.tasks.keys():
		var t: Dictionary = _day.tasks[id]
		var l := Label.new()
		var title := Content.text(str(t.def.get("title", id)))
		if _day.is_done(id):
			l.text = Content.text("hud.task_done", {"title": title})
			l.modulate.a = 0.6
		else:
			l.text = Content.text("hud.task_line", {"title": title, "p": t.progress, "a": t.amount})
		task_list.add_child(l)


func set_time(minutes: float) -> void:
	time_label.text = Clock.format(minutes)


func set_prompt(text: String) -> void:
	prompt_label.text = text


func toast(text: String) -> void:
	toast_label.text = text
	_toast_time = 2.5


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			toast_label.text = ""
