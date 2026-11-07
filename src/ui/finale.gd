extends Control
## The ending, shown once after the street that completes the city: the map with every street
## lighting up in turn, each street's best, a total, and the rain easing off as he lowers his
## umbrella. Continue goes to the map; credits and feedback are reachable from here.

const Canvas := preload("res://src/ui/city_map_canvas.gd")
const PANEL_W := 520.0
const MARGIN := 64.0
const NODE_R := 24.0
const RAIN_STREAKS := 160
const RAIN_AFTER := 0.12      # what's left of the rain once it has eased: a light drizzle
const CLOSING_LINE := "Every street walked, every awning known. Let it rain."

var _map: Control
var _ids: Array = []          # street ids in map order, country -> centre
var _lit := {}                # id -> 0..1, how lit its marker is
var _rain := 1.0              # 1 = downpour, eases toward a drizzle
var _umbrella := 1.0          # the walker's umbrella, closes as the rain eases
var _t := 0.0
var _rows: Array[Control] = []
var _total_lbl: Label
var _total_grade: Label
var _closing: Label
var _continue: Button
var _feedback: Button
var _credits: Control
var _sound: UISound
var _fade: ColorRect
var _show: Tween
var _easing: Tween            # the rain easing off, alongside the show
var _skipping := false
var _busy := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.finale_seen = true
	Game.save_game()
	_sound = UISound.new()
	add_child(_sound)
	UISound.start_menu_music(get_tree())
	_ids = Game.nodes.keys()
	_ids.sort_custom(func(a: String, b: String) -> bool:
		return float(Game.nodes[a]["map_pos"][0]) < float(Game.nodes[b]["map_pos"][0]))
	for id: String in _ids:
		_lit[id] = 0.0

	var bg := ColorRect.new()
	bg.color = UIStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var head := VBoxContainer.new()
	head.position = Vector2(MARGIN, 34)
	head.add_theme_constant_override("separation", -6)
	add_child(head)
	head.add_child(UIStyle.label("EVERY STREET WALKED", &"KickerLabel"))
	head.add_child(UIStyle.label("HOME AND DRY", &"HeaderLabel", 84))

	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.offset_left = MARGIN
	_map.offset_top = 170
	_map.offset_right = -(PANEL_W + MARGIN + 40.0)
	_map.offset_bottom = -110
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.clip_contents = true
	add_child(_map)
	var canvas := Canvas.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.add_child(canvas)
	var overlay := DrawBox.new(_draw_overlay, Vector2.ZERO, true)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.add_child(overlay)
	_closing = UIStyle.label(CLOSING_LINE, &"ItalicLabel", 32, UIStyle.CREAM)
	_closing.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_closing.offset_top = -86
	_closing.offset_bottom = -34
	_closing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_closing.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_closing.add_theme_constant_override("shadow_outline_size", 14)
	_closing.modulate.a = 0.0
	_map.add_child(_closing)

	_build_panel()

	var hints := KeyHints.new([["A", "Enter", "Select"], ["B", "Esc", "To the map"]])
	hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hints.position = Vector2(MARGIN, -62)
	add_child(hints)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_play_show()


func _process(delta: float) -> void:
	_t += delta


# --- right-hand panel -------------------------------------------------------------------------

func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -(PANEL_W + MARGIN)
	panel.offset_right = -MARGIN
	panel.offset_top = 64
	panel.offset_bottom = -110
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -6)
	hv.add_child(UIStyle.label("THE CITY, STREET BY STREET", &"KickerLabel"))
	hv.add_child(UIStyle.label("YOUR BEST", &"HeaderLabel"))
	v.add_child(hv)
	v.add_child(HSeparator.new())

	for id: String in _ids:
		var best: Dictionary = Game.best.get(id, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.modulate.a = 0.0
		v.add_child(row)
		var name_lbl := UIStyle.label(String(Game.nodes[id].get("name", id)).to_upper(), &"HeaderSmall", 34)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var score := UIStyle.label(str(int(best["score"])) if best.has("score") else "—", &"StatLabel", 30)
		score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(score)
		var g := String(best.get("grade", "-"))
		var grade := UIStyle.label(g, &"HeaderLabel", 48, UIStyle.grade_color(g))
		grade.custom_minimum_size = Vector2(44, 0)
		grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(grade)
		_rows.append(row)

	v.add_child(HSeparator.new())
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 18)
	v.add_child(trow)
	var tl := UIStyle.label("TOTAL", &"HeaderSmall", 44)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tl)
	_total_lbl = UIStyle.label("0", &"StatLabel", 52, UIStyle.GOLD)
	trow.add_child(_total_lbl)
	var overall := Game.grade_for(int(round(float(Game.total_score()) / maxf(1.0, _ids.size()))))
	_total_grade = UIStyle.label(overall, &"HeaderLabel", 64, UIStyle.grade_color(overall))
	_total_grade.custom_minimum_size = Vector2(44, 0)
	_total_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_grade.modulate.a = 0.0
	trow.add_child(_total_grade)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var prompt := UIStyle.label("This is an early alpha. Tell us what felt good, and what didn't.", &"MutedLabel", 21)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(prompt)
	_continue = _button(v, "Continue", &"", _leave_to_map)
	_continue.custom_minimum_size = Vector2(0, 66)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var credits := _button(h, "Credits", &"SmallButton", _open_credits)
	_feedback = _button(h, "Send feedback", &"SmallButton", _send_feedback)
	for b: Button in [credits, _feedback]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
	_continue.focus_neighbor_bottom = credits.get_path()
	credits.focus_neighbor_top = _continue.get_path()
	_feedback.focus_neighbor_top = _continue.get_path()


func _button(parent: Container, text: String, variation: StringName, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void:
		if _busy or _credits != null:
			return
		_finish_show()
		cb.call())
	b.mouse_entered.connect(func() -> void:
		if _credits == null:
			b.grab_focus())
	parent.add_child(b)
	return b


# --- the show ---------------------------------------------------------------------------------

func _play_show() -> void:
	var tw := create_tween()
	_show = tw
	tw.tween_property(_fade, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	_easing = create_tween()
	_easing.tween_property(self, "_rain", RAIN_AFTER, 4.8).set_delay(0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.3)
	for i in _ids.size():
		var id: String = _ids[i]
		var row: Control = _rows[i]
		tw.tween_callback(func() -> void:
			_sfx(&"token", -6.0, 0.9 + 0.07 * i)
			create_tween().tween_property(row, "modulate:a", 1.0, 0.3))
		tw.tween_method(func(x: float) -> void: _lit[id] = x, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(x: float) -> void:
		var shown := int(round(x))
		if _total_lbl.text != str(shown) and shown % 151 == 0:
			_sfx(&"ui_move", -12.0, 0.8 + x / 6000.0)
		_total_lbl.text = str(shown), 0.0, float(Game.total_score()), 1.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_sfx(&"umbrella_open", 0.0, 0.8)
		_total_grade.pivot_offset = _total_grade.size * 0.5
		var st := create_tween().set_parallel()
		st.tween_property(_total_grade, "modulate:a", 1.0, 0.12)
		st.tween_property(_total_grade, "scale", Vector2.ONE, 0.25).from(Vector2(2.4, 2.4)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	tw.tween_interval(0.6)
	# The rain has eased: he closes his umbrella.
	tw.tween_callback(func() -> void: _sfx(&"umbrella_close", -2.0))
	tw.tween_property(self, "_umbrella", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_closing, "modulate:a", 1.0, 1.6)
	tw.finished.connect(func() -> void:
		_skipping = false
		_continue.grab_focus()
		if Game.debug_auto_continue:
			get_tree().create_timer(2.0).timeout.connect(_leave_to_map))


## Jump to the end of the show (any confirm/back/click while it plays).
func _finish_show() -> void:
	if _show and _show.is_running():
		_skipping = true
		_easing.kill()
		_rain = RAIN_AFTER
		_show.custom_step(60.0)


func _sfx(sound: StringName, db := 0.0, pitch := 1.0) -> void:
	if not _skipping:
		_sound.play(sound, db, pitch)


func _map_point(id: String) -> Vector2:
	var p: Array = Game.nodes[id]["map_pos"]
	return Vector2(float(p[0]), float(p[1])) * _map.size


func _draw_overlay(ci: Control) -> void:
	var s := ci.size
	var calm := 1.0 - _rain
	# Warm light spreading over the city as the rain eases.
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([Color(UIStyle.AMBER, 0.0), Color(UIStyle.AMBER, 0.0),
			Color(UIStyle.AMBER, 0.16 * calm), Color(UIStyle.AMBER, 0.1 * calm)]))
	# Routes light up once both ends are lit.
	for id: String in _ids:
		for nb: String in Game.neighbors(id):
			if nb <= id or not _lit.has(nb):
				continue
			var a := _map_point(id)
			var b := _map_point(nb)
			var on := minf(_lit[id], _lit[nb])
			ci.draw_line(a, b, Color(0, 0, 0, 0.45), 11.0, true)
			ci.draw_line(a, b, Color(UIStyle.CREAM, 0.22).lerp(Color(UIStyle.AMBER, 0.9), on), 5.0, true)
	for id: String in _ids:
		_draw_street(ci, id, _lit[id])
	if Game.nodes.has(Game.current_node):
		var p := _map_point(Game.current_node) + Vector2(0, -NODE_R - 16.0 + sin(_t * 3.0) * 3.0)
		UIStyle.draw_walker(ci, p, 46.0, UIStyle.AMBER, _t * 6.0, _umbrella)
	_draw_rain(ci, s)


func _draw_street(ci: Control, id: String, lit: float) -> void:
	var c := _map_point(id)
	var grade := String(Game.best.get(id, {}).get("grade", ""))
	var gc := UIStyle.grade_color(grade) if grade != "" else UIStyle.AMBER
	if lit > 0.0:
		var pulse := 0.5 + 0.5 * sin(_t * 2.0 + c.x * 0.01)
		ci.draw_circle(c, NODE_R + 26.0 * lit + pulse * 4.0, Color(UIStyle.AMBER, 0.1 * lit))
		ci.draw_circle(c, NODE_R + 12.0 * lit, Color(UIStyle.AMBER, 0.16 * lit))
	ci.draw_circle(c, NODE_R, Color(0.06, 0.07, 0.09))
	ci.draw_arc(c, NODE_R, 0.0, TAU, 48, Color(UIStyle.CREAM, 0.3).lerp(gc, lit), 4.0, true)
	var f := UIStyle.F_TITLE
	if grade != "":
		var fs := int(NODE_R * 1.45)
		var w := f.get_string_size(grade, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, c + Vector2(-w * 0.5, f.get_ascent(fs) * 0.5 - fs * 0.06), grade,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(gc, 0.35 + 0.65 * lit))
	var street := String(Game.nodes[id].get("name", id)).to_upper()
	var nw := f.get_string_size(street, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	var np := c + Vector2(-nw * 0.5, NODE_R + 44.0)
	ci.draw_string_outline(f, np, street, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, 10, Color(0, 0, 0, 0.8))
	ci.draw_string(f, np, street, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(UIStyle.CREAM, 0.42).lerp(UIStyle.CREAM, lit))


func _draw_rain(ci: Control, s: Vector2) -> void:
	var n := int(RAIN_STREAKS * _rain)
	var slant := Vector2(-5.0, 26.0)
	for i in n:
		# Cheap per-streak hash so each drop keeps its column and speed.
		var hx := fmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var hy := fmod(sin(i * 78.233) * 12543.123, 1.0)
		var speed := 700.0 + 500.0 * absf(hy)
		var x := absf(hx) * (s.x + 60.0)
		var y := fmod(absf(hy) * s.y + _t * speed, s.y + 60.0) - 30.0
		ci.draw_line(Vector2(x, y), Vector2(x, y) + slant, Color(UIStyle.RAIN, 0.28), 1.5, true)


# --- leaving, credits, feedback ---------------------------------------------------------------

func _leave_to_map() -> void:
	_busy = true
	_sound.play(&"ui_confirm")
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(Game.goto_map)


func _send_feedback() -> void:
	_sound.play(&"ui_confirm")
	Game.open_feedback()
	_feedback.text = "Opened in browser"
	_feedback.create_tween().tween_callback(func() -> void: _feedback.text = "Send feedback").set_delay(3.0)


func _open_credits() -> void:
	_sound.play(&"ui_confirm")
	var prev := get_viewport().gui_get_focus_owner()
	_credits = ColorRect.new()
	(_credits as ColorRect).color = Color(0, 0, 0, 0.0)
	_credits.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_credits)
	create_tween().tween_property(_credits, "color:a", 0.78, 0.25)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	v.add_child(UIStyle.label("CREDITS", &"HeaderSmall", 0, UIStyle.AMBER))
	var rt := RichTextLabel.new()
	rt.scroll_active = true
	rt.custom_minimum_size = Vector2(820, 600)
	rt.focus_mode = Control.FOCUS_ALL
	rt.add_theme_font_size_override("normal_font_size", 22)
	rt.text = FileAccess.get_file_as_string("res://data/credits.txt")
	v.add_child(rt)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(220, 64)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.mouse_entered.connect(back.grab_focus)
	v.add_child(back)
	var close := func() -> void:
		_sound.play(&"ui_back")
		_credits.queue_free()
		_credits = null
		if is_instance_valid(prev):
			prev.grab_focus()
	back.pressed.connect(close)
	_credits.set_meta(&"close", close)
	back.focus_neighbor_top = rt.get_path()
	back.focus_neighbor_bottom = back.get_path()
	rt.focus_neighbor_bottom = back.get_path()
	rt.focus_neighbor_top = rt.get_path()
	back.grab_focus.call_deferred()
	# Let the credits roll on their own until the player scrolls.
	var bar := rt.get_v_scroll_bar()
	var roll := rt.create_tween()
	roll.tween_interval(1.5)
	roll.tween_method(func(y: float) -> void: bar.value = y, 0.0, 2000.0, 60.0)
	rt.gui_input.connect(func(_e: InputEvent) -> void: roll.kill())
	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.2)


func _unhandled_input(event: InputEvent) -> void:
	var accept := event.is_action_pressed(&"ui_accept")
	var cancel := event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")
	var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if _show and _show.is_running():
		if accept or cancel or click:
			get_viewport().set_input_as_handled()
			_finish_show()
		return
	if not cancel or _busy:
		return
	get_viewport().set_input_as_handled()
	if _credits != null:
		(_credits.get_meta(&"close") as Callable).call()
	else:
		_leave_to_map()
