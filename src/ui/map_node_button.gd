extends Button
## A street on the city map: a round marker (grade-coloured when walked, pulsing when it's a
## reachable new street, dim when too far), with the street name underneath.

const R := 24.0

var node_id := ""
var selectable := false
var walked := false
var current := false
var grade := ""
var neon := 0.0          # 0 = country .. 1 = city centre (tints the ring)
var _t := 0.0
var _name_lbl: Label
var _sub_lbl: Label


func setup(id: String, n: Dictionary, best: Dictionary) -> void:
	node_id = id
	selectable = Game.can_select(id)
	walked = Game.completed.has(id)
	current = id == Game.current_node
	grade = String(best.get("grade", ""))
	neon = clampf((float(n["map_pos"][0]) - 0.55) / 0.35, 0.0, 1.0)
	text = ""
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(R * 2.0 + 24.0, R * 2.0 + 24.0)
	size = custom_minimum_size
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, empty)
	_name_lbl = UIStyle.label(String(n.get("name", id)).to_upper(), &"HeaderSmall", 36)
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.custom_minimum_size = Vector2(260, 0)
	_name_lbl.position = Vector2(size.x * 0.5 - 130.0, size.y - 6.0)
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_name_lbl.add_theme_constant_override("shadow_outline_size", 10)
	add_child(_name_lbl)
	var sub := ""
	if not best.is_empty():
		sub = "BEST %d" % int(best.get("score", 0))
	elif selectable:
		sub = "NOT YET WALKED"
	_sub_lbl = UIStyle.label(sub, &"CaptionLabel", 18)
	_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_lbl.custom_minimum_size = Vector2(260, 0)
	_sub_lbl.position = Vector2(size.x * 0.5 - 130.0, size.y + 32.0)
	_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_lbl)
	_refresh_labels()
	focus_entered.connect(_refresh_labels)
	focus_exited.connect(_refresh_labels)


func _refresh_labels() -> void:
	var col := UIStyle.CREAM if selectable else Color(UIStyle.CREAM, 0.42)
	if has_focus():
		col = UIStyle.AMBER
	_name_lbl.add_theme_color_override("font_color", col)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var focus := has_focus() or is_hovered()
	var ring := UIStyle.CREAM.lerp(UIStyle.NEON_TEAL, neon * 0.6)
	if focus:
		var g := 0.5 + 0.5 * sin(_t * 5.0)
		draw_circle(c, R + 14.0 + g * 3.0, Color(UIStyle.AMBER, 0.12))
		draw_arc(c, R + 9.0, 0.0, TAU, 48, Color(UIStyle.AMBER, 0.9), 3.0, true)
	if not selectable:
		draw_circle(c, R * 0.72, Color(0.08, 0.1, 0.13, 0.95))
		draw_arc(c, R * 0.72, 0.0, TAU, 40, Color(UIStyle.CREAM, 0.3), 2.0, true)
		if walked:
			_grade_text(c, R * 0.72, 0.5)
		return
	if walked:
		var gc := UIStyle.grade_color(grade)
		draw_circle(c, R, Color(0.06, 0.07, 0.09))
		draw_arc(c, R, 0.0, TAU, 48, gc, 4.0, true)
		_grade_text(c, R, 1.0)
	else:
		# Reachable, unwalked: pulsing beacon.
		var p := fmod(_t * 0.7, 1.0)
		draw_arc(c, R + p * 22.0, 0.0, TAU, 48, Color(UIStyle.AMBER, 0.6 * (1.0 - p)), 2.5, true)
		draw_circle(c, R, Color(0.06, 0.07, 0.09))
		draw_arc(c, R, 0.0, TAU, 48, UIStyle.AMBER, 4.0, true)
		draw_circle(c, R * 0.36, UIStyle.AMBER)
	if not walked and not focus:
		return
	draw_arc(c, R - 6.0, 0.0, TAU, 40, Color(ring, 0.18), 1.5, true)


func _grade_text(c: Vector2, r: float, alpha: float) -> void:
	if grade == "":
		draw_circle(c, r * 0.3, Color(UIStyle.CREAM, 0.5 * alpha))
		return
	var f := UIStyle.F_TITLE
	var fs := int(r * 1.45)
	var w := f.get_string_size(grade, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	draw_string(f, c + Vector2(-w * 0.5, asc * 0.5 - fs * 0.06), grade, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UIStyle.grade_color(grade), alpha))
