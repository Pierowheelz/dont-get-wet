extends Control
## On-screen touch controls: hold right pad = umbrella (drag up/down within it to tilt),
## hold left pad = hurry (higher = faster), stop button.

var _umb_touch := -1
var _hur_touch := -1
var _umb_rect: Rect2
var _hur_rect: Rect2
var _stop_rect: Rect2
var _umb_start := Vector2.ZERO
var _stop_flash := 0.0


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
				_stop_flash = 1.0
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


func _process(delta: float) -> void:
	if _stop_flash > 0.0:
		_stop_flash = maxf(0.0, _stop_flash - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	_layout()
	var base := Color(0.03, 0.035, 0.05, 0.38)
	var edge := Color(UIStyle.CREAM, 0.28)
	var on_edge := Color(UIStyle.AMBER, 0.9)
	var f := UIStyle.F_COND

	# Umbrella pad: a ring with the umbrella glyph; tilts with the drag.
	var uc := _umb_rect.get_center()
	var ur := _umb_rect.size.x * 0.5
	var u_on := _umb_touch >= 0
	draw_circle(uc, ur, Color(UIStyle.AMBER, 0.16) if u_on else base)
	draw_arc(uc, ur, 0.0, TAU, 64, on_edge if u_on else edge, 4.0 if u_on else 2.5, true)
	draw_arc(uc, ur - 10.0, PI * 1.15, PI * 1.85, 24, Color(1, 1, 1, 0.08), 2.0, true)
	draw_set_transform(uc + Vector2(0, -ur * 0.08), Inputs.touch_tilt * 0.35, Vector2.ONE)
	UIStyle.draw_umbrella(self, Vector2.ZERO, ur * 0.8, Color(UIStyle.AMBER if u_on else UIStyle.CREAM, 0.85), 1.0 if u_on else 0.55)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_label(f, uc + Vector2(0, ur * 0.72), "UMBRELLA", Color(UIStyle.CREAM, 0.7))
	# tilt hints
	for sgn: float in [-1.0, 1.0]:
		var ax := uc + Vector2(sgn * ur * 0.78, -ur * 0.1)
		draw_colored_polygon(PackedVector2Array([ax + Vector2(sgn * 10, 0), ax + Vector2(-sgn * 4, -9), ax + Vector2(-sgn * 4, 9)]),
			Color(UIStyle.CREAM, 0.35 if not u_on else 0.6))

	# Hurry pad: a vertical gauge, filled to the current hurry amount.
	var h_on := _hur_touch >= 0
	_rounded(_hur_rect, Color(UIStyle.AMBER, 0.12) if h_on else base, on_edge if h_on else edge, 4.0 if h_on else 2.5)
	if h_on:
		var fh := _hur_rect.size.y * Inputs.touch_hurry
		_rounded(Rect2(_hur_rect.position.x + 8, _hur_rect.end.y - fh + 8, _hur_rect.size.x - 16, fh - 16),
			Color(UIStyle.AMBER, 0.35), Color(0, 0, 0, 0), 0.0)
	for i in 3:
		var y := _hur_rect.position.y + _hur_rect.size.y * (0.22 + i * 0.12)
		var cx := _hur_rect.get_center().x
		draw_polyline(PackedVector2Array([Vector2(cx - 16, y + 8), Vector2(cx, y - 4), Vector2(cx + 16, y + 8)]),
			Color(UIStyle.CREAM, 0.25 + 0.15 * (2 - i)), 3.0, true)
	_label(f, _hur_rect.get_center() + Vector2(0, _hur_rect.size.y * 0.32), "HURRY", Color(UIStyle.CREAM, 0.7))

	# Stop button.
	var s_col := Color(UIStyle.DANGER, 0.25 + 0.5 * _stop_flash)
	_rounded(_stop_rect, s_col if _stop_flash > 0.0 else base, Color(UIStyle.CREAM, 0.28 + 0.5 * _stop_flash), 2.5)
	_label(f, _stop_rect.get_center() + Vector2(0, 8), "STOP", Color(UIStyle.CREAM, 0.8))


func _rounded(r: Rect2, fill: Color, border: Color, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.18))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _label(f: Font, c: Vector2, text: String, col: Color) -> void:
	var fs := 24
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, c + Vector2(-w * 0.5, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
	draw_string(f, c + Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
