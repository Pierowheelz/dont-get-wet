extends Control
## Title screen.

var _box: VBoxContainer
var _sub: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "DON'T GET WET"
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-600, 140)
	title.custom_minimum_size = Vector2(1200, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.position = Vector2(-180, -40)
	_box.custom_minimum_size = Vector2(360, 0)
	_box.add_theme_constant_override("separation", 14)
	add_child(_box)
	_main_buttons()


func _clear() -> void:
	for c in _box.get_children():
		c.queue_free()


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 58)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


func _main_buttons() -> void:
	_clear()
	var first := _btn("Continue" if not Game.completed.is_empty() else "Start", Game.goto_map)
	if not Game.completed.is_empty():
		_btn("Replay a street", _replay_list)
	_btn("Settings", _settings)
	_btn("Quit", get_tree().quit)
	first.grab_focus.call_deferred()


func _replay_list() -> void:
	_clear()
	var first: Button
	for id in Game.completed:
		var n: Dictionary = Game.nodes.get(id, {})
		var b: Dictionary = Game.best.get(id, {})
		var btn := _btn("%s   %s  %d" % [n.get("name", id), b.get("grade", "-"), int(b.get("score", 0))],
			func() -> void: Game.play_level(id))
		if first == null:
			first = btn
	var back := _btn("Back", _main_buttons)
	(first if first else back).grab_focus.call_deferred()


func _settings() -> void:
	_clear()
	var p := _btn("Painterly filter: %s" % ("on" if Game.settings["painterly"] else "off"), func() -> void:
		Game.settings["painterly"] = not Game.settings["painterly"]
		Game.save_game()
		_settings())
	_btn("Touch controls: %s" % ("on" if Game.settings["touch_controls"] else "off"), func() -> void:
		Game.settings["touch_controls"] = not Game.settings["touch_controls"]
		Game.save_game()
		_settings())
	_btn("Reset progress", func() -> void:
		Game.reset_progress()
		_main_buttons())
	_btn("Back", _main_buttons)
	p.grab_focus.call_deferred()
