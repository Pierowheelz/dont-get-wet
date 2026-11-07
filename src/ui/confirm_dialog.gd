class_name ConfirmDialog
extends ColorRect
## Modal confirmation card. Traps focus on Cancel / OK, closes on Esc / B, and hands focus back
## to whatever held it when it opened. Add it to a full-screen parent with `ConfirmDialog.open`.

signal closed

var _prev: Control
var _sound: UISound


## `extra` (optional) sits between the text and the buttons. `accent` colours the title and the OK button.
static func open(parent: Control, title: String, text: String, ok_text: String, on_ok: Callable,
		accent := UIStyle.DANGER, extra: Control = null) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d._build(parent, title, text, ok_text, on_ok, accent, extra)
	return d


func _build(parent: Control, title: String, text: String, ok_text: String, on_ok: Callable, accent: Color, extra: Control) -> void:
	_prev = parent.get_viewport().gui_get_focus_owner()
	_sound = UISound.new()
	add_child(_sound)
	color = Color(0, 0, 0, 0.0)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(self)
	create_tween().tween_property(self, "color:a", 0.7, 0.25)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(700, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	v.add_child(UIStyle.label(title, &"HeaderLabel", 0, accent))
	if text != "":
		var body := UIStyle.label(text, &"BodyLabel")
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(640, 0)
		v.add_child(body)
	if extra:
		v.add_child(extra)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(220, 64)
	cancel.pressed.connect(dismiss)
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = ok_text
	ok.custom_minimum_size = Vector2(220, 64)
	for c in [&"font_color", &"font_focus_color", &"font_hover_color"]:
		ok.add_theme_color_override(c, accent)
	ok.pressed.connect(func() -> void:
		_sound.play(&"ui_confirm")
		_close()
		on_ok.call())
	row.add_child(ok)
	for b: Button in [cancel, ok]:
		var other: Button = ok if b == cancel else cancel
		b.focus_neighbor_top = b.get_path()
		b.focus_neighbor_bottom = b.get_path()
		b.focus_neighbor_left = other.get_path()
		b.focus_neighbor_right = other.get_path()
		b.focus_next = other.get_path()
		b.focus_previous = other.get_path()
		b.mouse_entered.connect(b.grab_focus)
	cancel.grab_focus.call_deferred()
	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.2)


func dismiss() -> void:
	_sound.play(&"ui_back")
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
	if is_instance_valid(_prev):
		_prev.grab_focus()


## The dialog sits deepest in the tree, so it sees Esc / B before the screen under it does.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		dismiss()
