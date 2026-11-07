extends CanvasLayer
## In-level UI: wetness & stamina meters, progress, timer, pause, fail and result screens.

var level: Node
var _wet_bar: ProgressBar
var _sta_bar: ProgressBar
var _sta_box: Control
var _progress: ProgressBar
var _time_lbl: Label
var _hint: Label
var _overlay: Control
var _pause: Control
var _shake_t := 0.0
var _sta_style: StyleBoxFlat
var _wet_style: StyleBoxFlat
var _drip_icon: Label
var _fade: ColorRect
var _hint_t := 0.0
var _touch: Control
var _drying_lbl: Label

const C_TEXT := Color(0.92, 0.9, 0.85)
const C_WET := Color(0.35, 0.6, 0.95)
const C_STA := Color(0.95, 0.78, 0.35)
const C_BAD := Color(0.95, 0.3, 0.25)


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := VBoxContainer.new()
	panel.position = Vector2(40, 32)
	panel.add_theme_constant_override("separation", 10)
	root.add_child(panel)
	var wet_row := _meter_row("WET", C_WET)
	_wet_bar = wet_row[1]
	_wet_style = wet_row[2]
	panel.add_child(wet_row[0])
	var sta_row := _meter_row("STAMINA", C_STA)
	_sta_bar = sta_row[1]
	_sta_style = sta_row[2]
	_sta_box = sta_row[0]
	panel.add_child(_sta_box)
	_drying_lbl = Label.new()
	_drying_lbl.text = "drying off..."
	_drying_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	_drying_lbl.add_theme_font_size_override("font_size", 20)
	_drying_lbl.modulate.a = 0.0
	panel.add_child(_drying_lbl)

	# Progress along the street (top centre) + timer (top right).
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(520, 8)
	_progress.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_progress.position = Vector2(-260, 44)
	_progress.max_value = 1.0
	_progress.step = 0.0
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(1, 1, 1, 0.12)
	pbg.set_corner_radius_all(4)
	var pfg := StyleBoxFlat.new()
	pfg.bg_color = Color(1, 1, 1, 0.55)
	pfg.set_corner_radius_all(4)
	_progress.add_theme_stylebox_override("background", pbg)
	_progress.add_theme_stylebox_override("fill", pfg)
	root.add_child(_progress)
	var name_lbl := Label.new()
	name_lbl.text = String(level.data.get("name", "")).to_upper()
	name_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	name_lbl.position = Vector2(-260, 12)
	name_lbl.custom_minimum_size = Vector2(520, 0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color(C_TEXT, 0.8))
	name_lbl.add_theme_font_size_override("font_size", 18)
	root.add_child(name_lbl)

	_time_lbl = Label.new()
	_time_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_time_lbl.position = Vector2(-180, 32)
	_time_lbl.custom_minimum_size = Vector2(140, 0)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_lbl.add_theme_font_size_override("font_size", 28)
	_time_lbl.add_theme_color_override("font_color", C_TEXT)
	root.add_child(_time_lbl)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-500, -120)
	_hint.custom_minimum_size = Vector2(1000, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.add_theme_color_override("font_color", C_TEXT)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(_hint)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)

	if Game.settings.get("touch_controls", false) or DisplayServer.is_touchscreen_available():
		_touch = preload("res://src/ui/touch_controls.gd").new()
		root.add_child(_touch)

	level.player.stop_refused.connect(_on_stop_refused)
	if level.level_id == Game.start_node and not Game.completed.has(level.level_id):
		_show_tutorial()


func _meter_row(title: String, color: Color) -> Array:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(C_TEXT, 0.75))
	row.add_child(lbl)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(340, 18)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(9)
	bg.border_color = Color(1, 1, 1, 0.18)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(9)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	row.add_child(bar)
	return [row, bar, fg]


func _show_tutorial() -> void:
	var lines := [
		[1.0, "Rain soaks you wherever the sky is open."],
		[6.0, _key_text("umbrella") + " — open the umbrella. It takes a moment."],
		[13.0, "Close it under cover: stamina only recovers while it's closed."],
		[20.0, _key_text("hurry") + " — hurry (costs stamina).   " + _key_text("tilt") + " — tilt the umbrella."],
		[28.0, "Low on stamina? " + _key_text("stop") + " lets you stop for a breather under cover."],
	]
	for l in lines:
		get_tree().create_timer(l[0]).timeout.connect(func() -> void: hint(l[1], 5.0))


func _key_text(action: String) -> String:
	var pad := Inputs.last_device == &"gamepad"
	match action:
		"umbrella": return "Hold RT" if pad else "Hold Right Mouse / Space"
		"hurry": return "LT" if pad else "Shift (W for a brisk walk)"
		"tilt": return "Right stick" if pad else "Q / E or mouse wheel"
		"stop": return "LB" if pad else "S"
	return action


func hint(text: String, duration := 3.0) -> void:
	_hint.text = text
	_hint_t = duration
	_hint.modulate.a = 1.0


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	var p: Player = level.player
	_wet_bar.value = p.wet / Tun.f("wet_max") * 100.0
	_sta_bar.value = p.stamina / Tun.f("stamina_max") * 100.0
	var danger := p.wet / Tun.f("wet_max") > 0.75
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	_wet_style.bg_color = C_WET.lerp(C_BAD, pulse if danger else 0.0)
	var sta_col := C_STA
	if p.exhausted:
		sta_col = C_BAD
	elif p.stamina <= Tun.f("stop_threshold") * Tun.f("stamina_max"):
		sta_col = C_STA.lerp(C_BAD, 0.5)
	if _shake_t > 0.0:
		_shake_t -= delta
		sta_col = C_BAD if int(_shake_t * 20.0) % 2 == 0 else C_STA
		_sta_box.position.x = sin(_shake_t * 70.0) * 8.0 * (_shake_t / 0.5)
	else:
		_sta_box.position.x = 0.0
	_sta_style.bg_color = sta_col
	_drying_lbl.modulate.a = move_toward(_drying_lbl.modulate.a, 1.0 if p.drying > 0.0 and p.wet > 0.0 else 0.0, delta * 3.0)
	_progress.value = level.progress()
	var t: float = level.elapsed
	_time_lbl.text = "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t < 0.6:
			_hint.modulate.a = maxf(0.0, _hint_t / 0.6)
	if Input.is_action_just_pressed(&"pause") and _overlay == null:
		_toggle_pause()


func _on_stop_refused() -> void:
	_shake_t = 0.5


# --- pause ----------------------------------------------------------------------------------

func _toggle_pause() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
		get_tree().paused = false
		return
	get_tree().paused = true
	_pause = _panel("PAUSED", "", [
		["Resume", _toggle_pause],
		["Restart", func() -> void: Game.play_level(level.level_id)],
		["City map", Game.goto_map],
		["Main menu", Game.goto_menu],
	])


# --- end screens ----------------------------------------------------------------------------

func show_fail() -> void:
	_overlay = _panel("YOU GOT WET", "He's had enough. Maybe tomorrow.", [
		["Restart", func() -> void: Game.play_level(level.level_id)],
		["City map", Game.goto_map],
		["Main menu", Game.goto_menu],
	])


func show_result(r: Dictionary) -> void:
	var body := "Wetness  %d%%\nTime  %d:%02d  (par %d:%02d)\n\nScore  %d    Grade  %s" % [
		int(r["wet"]), int(r["time"]) / 60, int(r["time"]) % 60, int(r["par"]) / 60, int(r["par"]) % 60,
		r["score"], r["grade"]]
	if r["best"] and r["prev_score"] > 0:
		body += "\nNew best! (was %d)" % r["prev_score"]
	body += "\n\n+%d tokens   (you have %d)" % [r["tokens"], Game.tokens]
	_overlay = _panel("SHELTER REACHED", body, [
		["Continue", Game.goto_map],
		["Replay", func() -> void: Game.play_level(level.level_id)],
	])


func _panel(title: String, body: String, buttons: Array) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.72, 0.5)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(640, 0)
	box.position = Vector2(-320, -260)
	box.add_theme_constant_override("separation", 18)
	dim.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", C_TEXT)
	box.add_child(t)
	if body != "":
		var b := Label.new()
		b.text = body
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color(C_TEXT, 0.85))
		box.add_child(b)
	var first: Button
	for spec in buttons:
		var btn := Button.new()
		btn.text = spec[0]
		btn.custom_minimum_size = Vector2(320, 56)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 26)
		btn.pressed.connect(spec[1])
		box.add_child(btn)
		if first == null:
			first = btn
	if first:
		first.grab_focus.call_deferred()
	return dim
