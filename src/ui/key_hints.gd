class_name KeyHints
extends HBoxContainer
## Footer of input prompts ("[A] Select   [B] Back") that follows the last-used device.
## hints: Array of [gamepad_key, keyboard_key, action_text].

var _hints: Array = []
var _device := &""


func _init(hints: Array = []) -> void:
	_hints = hints
	add_theme_constant_override("separation", 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_hints(hints: Array) -> void:
	_hints = hints
	_device = &""


func _process(_delta: float) -> void:
	var dev: StringName = Inputs.last_device
	if dev == &"touch":
		dev = &"keyboard"
	if dev != _device:
		_device = dev
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	for h: Array in _hints:
		var key: String = h[0] if _device == &"gamepad" else h[1]
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 10)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := PanelContainer.new()
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06)
		sb.border_color = Color(UIStyle.CREAM, 0.45)
		sb.set_border_width_all(2)
		sb.border_width_bottom = 3
		sb.set_corner_radius_all(14 if _device == &"gamepad" and key.length() == 1 else 5)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		cap.add_theme_stylebox_override("panel", sb)
		var kl := UIStyle.label(key, &"CaptionLabel", 18, UIStyle.CREAM)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_child(kl)
		item.add_child(cap)
		item.add_child(UIStyle.label(String(h[2]).to_upper(), &"CaptionLabel", 20))
		add_child(item)
