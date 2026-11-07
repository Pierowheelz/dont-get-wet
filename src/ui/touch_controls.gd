extends Control
## On-screen touch controls: hold right pad = umbrella (drag up/down within it to tilt),
## hold left pad = hurry (higher = faster), stop button.

var _umb_touch := -1
var _hur_touch := -1
var _umb_rect: Rect2
var _hur_rect: Rect2
var _stop_rect: Rect2
var _umb_start := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout() -> void:
	var s := get_viewport_rect().size
	var r := minf(s.y * 0.2, 220.0)
	_umb_rect = Rect2(s.x - r * 2.2, s.y - r * 2.2, r * 2.0, r * 2.0)
	_hur_rect = Rect2(r * 0.2, s.y - r * 2.2, r * 1.6, r * 2.0)
	_stop_rect = Rect2(r * 2.0, s.y - r * 0.9, r * 0.8, r * 0.7)


func _input(event: InputEvent) -> void:
	_layout()
	if event is InputEventScreenTouch:
		if event.pressed:
			if _umb_rect.has_point(event.position):
				_umb_touch = event.index
				_umb_start = event.position
				Inputs.touch_umbrella = 1.0
			elif _hur_rect.has_point(event.position):
				_hur_touch = event.index
				_set_hurry(event.position)
			elif _stop_rect.has_point(event.position):
				Inputs.touch_stop = true
		else:
			if event.index == _umb_touch:
				_umb_touch = -1
				Inputs.touch_umbrella = 0.0
				Inputs.touch_tilt = 0.0
			elif event.index == _hur_touch:
				_hur_touch = -1
				Inputs.touch_hurry = 0.0
	elif event is InputEventScreenDrag:
		if event.index == _umb_touch:
			Inputs.touch_tilt = clampf((event.position.x - _umb_start.x) / (_umb_rect.size.x * 0.4), -1.0, 1.0)
		elif event.index == _hur_touch:
			_set_hurry(event.position)
	queue_redraw()


func _set_hurry(p: Vector2) -> void:
	Inputs.touch_hurry = clampf(1.0 - (p.y - _hur_rect.position.y) / _hur_rect.size.y, 0.2, 1.0)


func _draw() -> void:
	_layout()
	var c := Color(1, 1, 1, 0.12)
	var on := Color(1, 1, 1, 0.28)
	draw_circle(_umb_rect.get_center(), _umb_rect.size.x * 0.5, on if _umb_touch >= 0 else c)
	draw_rect(_hur_rect, on if _hur_touch >= 0 else c)
	draw_rect(_stop_rect, c)
	var f := ThemeDB.fallback_font
	draw_string(f, _umb_rect.get_center() + Vector2(-60, 8), "UMBRELLA", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_string(f, _hur_rect.get_center() + Vector2(-40, 8), "HURRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_string(f, _stop_rect.get_center() + Vector2(-26, 8), "STOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
