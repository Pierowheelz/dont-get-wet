extends CanvasLayer
## In-level UI: wetness & stamina meters, progress, timer, pause, fail and result screens.
## Public API used by Level: `level`, hint(text, duration), show_fail(), show_result(result).

const Drips := preload("res://src/ui/title_drips.gd")

const C_TEXT := UIStyle.CREAM
const C_WET := UIStyle.RAIN
const C_STA := UIStyle.AMBER
const C_BAD := UIStyle.DANGER

const FAIL_LINES := [
	"He's had enough. Maybe tomorrow.",
	"Soaked to the socks. He's going home.",
	"That suit was dry-clean only.",
	"The rain wins this round.",
	"He'll be wringing out that tie for a week.",
]

var level: Node
var _root: Control
var _meters: Control
var _progress: Control
var _time_lbl: Label
var _par_lbl: Label
var _hint_box: PanelContainer
var _hint: Label
var _overlay: Control
var _pause: Control
var _fade: ColorRect
var _touch: Control
var _sound: UISound

var _hint_t := 0.0
var _hint_template := ""
var _wet := 0.0          # displayed (smoothed) 0..1
var _sta := 1.0
var _drying_a := 0.0
var _t := 0.0
var _result_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sound = UISound.new()
	_sound.auto_focus_sound = false
	add_child(_sound)
	UISound.stop_menu_music(get_tree(), 1.5)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Soft dark band along the top so the HUD reads against bright shopfronts.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.5))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shade.offset_bottom = 190
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	_meters = DrawBox.new(_draw_meters, Vector2(480, 170), true)
	_meters.position = Vector2(40, 28)
	_root.add_child(_meters)

	_progress = DrawBox.new(_draw_progress, Vector2(640, 104), true)
	_progress.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_progress.offset_left = -320
	_progress.offset_right = 320
	_progress.offset_top = 20
	_progress.offset_bottom = 124
	_root.add_child(_progress)

	var tbox := VBoxContainer.new()
	tbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tbox.offset_left = -300
	tbox.offset_right = -44
	tbox.offset_top = 26
	tbox.add_theme_constant_override("separation", -4)
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tbox)
	var tcap := UIStyle.label("TIME", &"HudLabel", 18)
	tcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tbox.add_child(tcap)
	_time_lbl = UIStyle.label("0:00.0", &"StatLabel", 44)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tbox.add_child(_time_lbl)
	_par_lbl = UIStyle.label("PAR %s" % UIStyle.fmt_time(float(level.par_time)), &"HudLabel", 18)
	_par_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_par_lbl.modulate.a = 0.7
	tbox.add_child(_par_lbl)

	# Tutorial / hint pill, bottom centre.
	_hint_box = PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.03, 0.035, 0.05, 0.78)
	hsb.border_color = Color(UIStyle.AMBER, 0.6)
	hsb.border_width_left = 4
	hsb.set_corner_radius_all(6)
	hsb.content_margin_left = 30
	hsb.content_margin_right = 30
	hsb.content_margin_top = 14
	hsb.content_margin_bottom = 16
	_hint_box.add_theme_stylebox_override("panel", hsb)
	_hint_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_box.offset_bottom = -110
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.modulate.a = 0.0
	_root.add_child(_hint_box)
	_hint = UIStyle.label("", &"", 28)
	_hint.add_theme_font_override("font", UIStyle.F_BOLD)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_box.add_child(_hint)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)

	if Game.settings.get("touch_controls", false) or DisplayServer.is_touchscreen_available():
		_touch = preload("res://src/ui/touch_controls.gd").new()
		_root.add_child(_touch)

	Inputs.device_changed.connect(_on_device_changed)
	if level.level_id == Game.start_node and not Game.completed.has(level.level_id):
		_show_tutorial()


func _show_tutorial() -> void:
	# {action} tokens resolve when each line shows (and re-resolve if the device changes).
	var lines := [
		[1.0, "Rain soaks you wherever the sky is open."],
		[6.0, "{umbrella} — open the umbrella. It takes a moment."],
		[13.0, "Close it under cover: stamina only recovers while it's closed."],
		[20.0, "{hurry} — hurry (costs stamina).   {tilt} — tilt the umbrella."],
		[28.0, "Need to wait? Hold {stop} to stand still. Stamina recovers while the umbrella is closed."],
	]
	for l in lines:
		get_tree().create_timer(l[0]).timeout.connect(func() -> void: hint(l[1], 5.0))


func hint(text: String, duration := 3.0) -> void:
	var st: int = level.player.state if level and level.player else 0
	if st == Player.State.DEFEATED or st == Player.State.ENTERING or st == Player.State.DONE:
		return
	_hint_template = text
	_hint_t = duration
	_render_hint()
	var tw := create_tween().set_parallel()
	tw.tween_property(_hint_box, "modulate:a", 1.0, 0.25)
	tw.tween_property(_hint_box, "offset_bottom", -110.0, 0.3).from(-90.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Hint text may hold {action} tokens; they follow the device the player is using right now.
func _render_hint() -> void:
	_hint.text = Inputs.format_prompts(_hint_template)
	_hint_box.reset_size()
	_hint_box.offset_left = -_hint_box.get_combined_minimum_size().x * 0.5
	_hint_box.offset_right = -_hint_box.offset_left


func _on_device_changed(_dev: StringName) -> void:
	if _hint_t > 0.0 and _hint_template.contains("{"):
		_render_hint()


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	_t += delta
	var p: Player = level.player
	_wet = lerpf(_wet, p.wet / Tun.f("wet_max"), 1.0 - exp(-12.0 * delta))
	_sta = lerpf(_sta, p.stamina / Tun.f("stamina_max"), 1.0 - exp(-14.0 * delta))
	_drying_a = move_toward(_drying_a, 1.0 if p.drying > 0.0 and p.wet > 0.0 else 0.0, delta * 3.0)
	var t: float = level.elapsed
	_time_lbl.text = UIStyle.fmt_time(t, true)
	_time_lbl.add_theme_color_override("font_color", C_TEXT if t <= float(level.par_time) else C_TEXT.lerp(C_STA, 0.6))
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t < 0.6:
			_hint_box.modulate.a = maxf(0.0, _hint_t / 0.6)
	var ending: bool = p.state == Player.State.DEFEATED or p.state == Player.State.ENTERING or p.state == Player.State.DONE
	if Input.is_action_just_pressed(&"pause") and _overlay == null and (not ending or _pause):
		_toggle_pause()


func _unhandled_input(event: InputEvent) -> void:
	if _result_tween and _result_tween.is_running() and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		_result_tween.custom_step(60.0)
		return
	# Gamepad B / ui_cancel also resumes (Esc is the pause action itself, handled in _process).
	if _pause and event.is_action_pressed(&"ui_cancel") and not event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_sound.play(&"ui_back")
		_toggle_pause()


# --- meters -----------------------------------------------------------------------------------

func _draw_meters(ci: Control) -> void:
	if level == null or level.player == null:
		return
	var p: Player = level.player
	var fc := UIStyle.F_COND
	var fb := UIStyle.F_BOLD
	var shadow := Color(0, 0, 0, 0.55)
	var bar_x := 84.0
	var bar_w := 340.0

	# Wetness: a drop that fills, plus a bar. Pulses red when close to giving up.
	var danger := _wet > 0.75
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	var wet_col := C_WET.lerp(C_BAD, pulse * 0.85 if danger else 0.0)
	var drop_h := 64.0 * (1.0 + (0.06 * pulse if danger else 0.0))
	UIStyle.draw_drop(ci, Vector2(34, 46), drop_h, Color(C_TEXT, 0.9), wet_col, _wet)
	_caption(ci, Vector2(bar_x, 22), "WET", fc, 20, Color(C_TEXT, 0.85), shadow)
	var pct := "%d%%" % int(round(_wet * 100.0))
	var pw := fb.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_caption(ci, Vector2(bar_x + bar_w - pw, 24), pct, fb, 24, wet_col.lerp(C_TEXT, 0.3) if not danger else wet_col, shadow)
	_bar(ci, Rect2(bar_x, 34, bar_w, 16), _wet, wet_col)
	if danger:
		ci.draw_rect(Rect2(bar_x - 3, 31, bar_w + 6, 22), Color(C_BAD, 0.35 * pulse), false, 2.0)

	# Stamina: amber bar, red when exhausted.
	var sta_col := C_BAD if p.exhausted else C_STA
	var y0 := 86.0
	_bolt(ci, Vector2(34, y0 + 22), 34.0, sta_col)
	_caption(ci, Vector2(bar_x, y0 + 8), "EXHAUSTED" if p.exhausted else "STAMINA", fc, 20, Color(sta_col if p.exhausted else C_TEXT, 0.85), shadow)
	_bar(ci, Rect2(bar_x, y0 + 18, bar_w, 12), _sta, sta_col)

	# Drying off (sun patches, vents).
	if _drying_a > 0.01:
		var dc := Color(1.0, 0.78, 0.45, _drying_a)
		var sc := Vector2(34, 150)
		ci.draw_circle(sc, 7.0, dc)
		for i in 8:
			var a := TAU * float(i) / 8.0 + _t * 0.8
			ci.draw_line(sc + Vector2(cos(a), sin(a)) * 10.0, sc + Vector2(cos(a), sin(a)) * 14.0, dc, 2.0, true)
		_caption(ci, Vector2(bar_x, 157), "DRYING OFF…", fc, 22, dc, Color(0, 0, 0, 0.55 * _drying_a))


func _bar(ci: Control, r: Rect2, v: float, col: Color) -> void:
	var rad := r.size.y * 0.5
	_rounded(ci, r.grow(2.0), rad + 2.0, Color(0, 0, 0, 0.5))
	_rounded(ci, r, rad, Color(1, 1, 1, 0.08))
	if v > 0.003:
		var fw := maxf(r.size.y, r.size.x * clampf(v, 0.0, 1.0))
		_rounded(ci, Rect2(r.position, Vector2(fw, r.size.y)), rad, col)
		_rounded(ci, Rect2(r.position + Vector2(2, 2), Vector2(fw - 4, r.size.y * 0.3)), rad * 0.5, Color(1, 1, 1, 0.22))


func _rounded(ci: Control, r: Rect2, rad: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)


func _caption(ci: Control, pos: Vector2, text: String, f: Font, fs: int, col: Color, shadow: Color) -> void:
	ci.draw_string(f, pos + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, shadow)
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _bolt(ci: Control, c: Vector2, h: float, col: Color) -> void:
	var s := h / 34.0
	var pts := PackedVector2Array([
		Vector2(4, -17), Vector2(-9, 3), Vector2(-1, 3), Vector2(-5, 17), Vector2(9, -4), Vector2(1, -4), Vector2(5, -17)])
	for i in pts.size():
		pts[i] = c + pts[i] * s
	var sh := pts.duplicate()
	for i in sh.size():
		sh[i] += Vector2(0, 2)
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.5))
	ci.draw_colored_polygon(pts, col)


func _draw_progress(ci: Control) -> void:
	if level == null:
		return
	var w := ci.size.x
	var lvl_name := String(level.data.get("name", "")).to_upper()
	var f := UIStyle.F_TITLE
	var fs := 30
	var nw := f.get_string_size(lvl_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, Vector2((w - nw) * 0.5, 24 + 2), lvl_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
	ci.draw_string(f, Vector2((w - nw) * 0.5, 24), lvl_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(C_TEXT, 0.88))
	var y := 84.0   # track sits well below the title so the walker icon never covers it
	var x0 := 16.0
	var x1 := w - 46.0
	var prog: float = level.progress()
	ci.draw_line(Vector2(x0, y + 1), Vector2(x1, y + 1), Color(0, 0, 0, 0.5), 6.0, true)
	ci.draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.18), 4.0, true)
	var px := lerpf(x0, x1, prog)
	ci.draw_line(Vector2(x0, y), Vector2(px, y), Color(C_TEXT, 0.75), 4.0, true)
	for i in range(1, 4):
		var tx := lerpf(x0, x1, i / 4.0)
		ci.draw_line(Vector2(tx, y - 5), Vector2(tx, y + 5), Color(1, 1, 1, 0.22 if tx > px else 0.5), 2.0)
	# The inn at the end of the street, its window lit.
	UIStyle.draw_inn(ci, Vector2(x1 + 22, y + 9), 34.0, Color(C_TEXT, 0.85), Color(UIStyle.AMBER, 0.75 + 0.25 * sin(_t * 2.0)))
	# The walker, phase-locked to his pace.
	var moving: bool = level.player != null and level.player.speed > 0.05
	var phase: float = float(level.elapsed) * 7.0 if moving else 0.0
	UIStyle.draw_walker(ci, Vector2(px + 1, y + 1), 36.0, Color(0, 0, 0, 0.5), phase)
	UIStyle.draw_walker(ci, Vector2(px, y - 1), 36.0, C_TEXT, phase)


# --- pause ------------------------------------------------------------------------------------

## Closes the pause panel if open (used when an end sequence starts).
func close_pause() -> void:
	if _pause:
		_toggle_pause()


func _toggle_pause() -> void:
	if _pause:
		var old := _pause
		_pause = null
		get_tree().paused = false
		var tw := old.create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.12)
		tw.tween_callback(old.queue_free)
		return
	get_tree().paused = true
	_sound.play(&"ui_confirm", -6.0)
	var p: Player = level.player
	var stats := "%d%% wet    ·    %s    ·    %d%% of the way" % [
		int(round(p.wet / Tun.f("wet_max") * 100.0)), UIStyle.fmt_time(level.elapsed), int(level.progress() * 100.0)]
	_pause = _panel("PAUSED", String(level.data.get("name", "")).to_upper(), stats, [
		["Resume", _toggle_pause],
		["Restart", func() -> void: Game.play_level(level.level_id)],
		["City map", Game.goto_map],
		["Main menu", Game.goto_menu],
	], true)


# --- end screens ------------------------------------------------------------------------------

func show_fail() -> void:
	var line: String = FAIL_LINES[randi() % FAIL_LINES.size()]
	var stats := "Made it %d%% of the way, in %s." % [int(level.progress() * 100.0), UIStyle.fmt_time(level.elapsed)]
	_overlay = _panel("YOU GOT WET", line, stats, [
		["Restart", func() -> void: Game.play_level(level.level_id)],
		["City map", Game.goto_map],
		["Main menu", Game.goto_menu],
	], false, true)


func _panel(title: String, kicker: String, body: String, buttons: Array, vertical: bool, fail := false) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.8 if fail else 0.72, 0.6)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(760, 0)
	center.add_child(box)
	var k := UIStyle.label(kicker, &"KickerLabel", 24)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t := UIStyle.label(title, &"TitleLabel", 150 if fail else 120)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if fail:
		t.add_theme_color_override("font_color", UIStyle.RAIN)
		k.add_theme_font_override("font", UIStyle.F_ITALIC)
		k.add_theme_font_size_override("font_size", 32)
		k.add_theme_color_override("font_color", Color(C_TEXT, 0.85))
		box.add_child(t)
		box.add_child(k)
		var drips := Drips.new()
		drips.set_anchors_preset(Control.PRESET_FULL_RECT)
		drips.offset_left = 120
		drips.offset_right = -120
		drips.offset_bottom = -26
		drips.fall_distance = 260.0
		t.add_child(drips)
	else:
		box.add_child(k)
		box.add_child(t)
	if body != "":
		var b := UIStyle.label(body, &"MutedLabel", 24)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	box.add_child(gap)
	var holder: BoxContainer
	if vertical:
		holder = VBoxContainer.new()
	else:
		holder = HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_theme_constant_override("separation", 12 if vertical else 18)
	box.add_child(holder)
	var first := _buttons(holder, buttons, Vector2(400, 64) if vertical else Vector2(260, 66))
	if vertical:
		for c in holder.get_children():
			(c as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if first:
		first.grab_focus.call_deferred()
	# Fade + settle (scale, so the CenterContainer keeps control of position).
	box.modulate.a = 0.0
	box.resized.connect(func() -> void: box.pivot_offset = box.size * 0.5)
	var tw := create_tween().set_parallel()
	tw.tween_property(box, "modulate:a", 1.0, 0.5).set_delay(0.15)
	tw.tween_property(box, "scale", Vector2.ONE, 0.6).from(Vector2(1.04, 1.04)).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hide_hint()
	return dim


func _hide_hint() -> void:
	_hint_t = 0.0
	_hint_box.modulate.a = 0.0


func _buttons(holder: Container, buttons: Array, size: Vector2) -> Button:
	var first: Button = null
	for spec: Array in buttons:
		var btn := Button.new()
		btn.text = spec[0]
		btn.custom_minimum_size = size
		var cb: Callable = spec[1]
		btn.pressed.connect(func() -> void:
			_sound.play(&"ui_confirm")
			cb.call())
		btn.focus_entered.connect(func() -> void: _sound.play(&"ui_move", -6.0))
		btn.mouse_entered.connect(btn.grab_focus)
		holder.add_child(btn)
		if first == null:
			first = btn
	return first


func show_result(r: Dictionary) -> void:
	if Game.debug_auto_continue:
		get_tree().create_timer(2.0).timeout.connect(Game.goto_map)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_overlay = dim
	_hide_hint()
	create_tween().tween_property(dim, "color:a", 0.74, 0.6)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(860, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -8)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UIStyle.label("SHELTER REACHED", &"KickerLabel", 24))
	hv.add_child(UIStyle.label(String(level.data.get("name", "")).to_upper(), &"HeaderLabel", 84))
	# Grade stamp (slams in after the count-up).
	var grade := String(r["grade"])
	var stamp := DrawBox.new(func(ci: Control) -> void: _draw_stamp(ci, grade), Vector2(170, 150))
	stamp.pivot_offset = Vector2(85, 75)
	stamp.modulate.a = 0.0
	head.add_child(stamp)
	v.add_child(HSeparator.new())

	# Score breakdown.
	var dry := clampf(1.0 - float(r["wet"]) / 100.0, 0.0, 1.0)   # r["wet"] is a percentage
	var dry_pts := int(round(Tun.f("score_dry_weight") * dry))
	var time_pts := int(r["score"]) - dry_pts
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	v.add_child(rows)
	var row_a := _result_row(rows, "DRYNESS", "%d%% wet" % int(round(float(r["wet"]))), dry_pts)
	var row_b := _result_row(rows, "TIME", "%s   (par %s)" % [UIStyle.fmt_time(float(r["time"])), UIStyle.fmt_time(float(r["par"]))], time_pts)
	v.add_child(HSeparator.new())
	var total := HBoxContainer.new()
	v.add_child(total)
	var tl := UIStyle.label("SCORE", &"HeaderSmall", 44)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total.add_child(tl)
	var best_tag := UIStyle.label("", &"KickerLabel", 22, UIStyle.GOLD)
	best_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_tag.modulate.a = 0.0
	total.add_child(best_tag)
	var score_lbl := UIStyle.label("0", &"StatLabel", 64)
	score_lbl.custom_minimum_size = Vector2(170, 0)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_child(score_lbl)

	# Tokens.
	var tok_row := HBoxContainer.new()
	tok_row.add_theme_constant_override("separation", 10)
	v.add_child(tok_row)
	var earned := int(r["tokens"])
	var tokens_lbl := UIStyle.label("", &"BodyLabel", 24)
	tokens_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tok_row.add_child(tokens_lbl)
	var coins: Array[Control] = []
	for i in mini(earned, 10):
		var c := DrawBox.new(func(ci: Control) -> void: _draw_coin(ci, ci.size * 0.5, 15.0), Vector2(36, 36))
		c.pivot_offset = Vector2(18, 18)
		c.modulate.a = 0.0
		tok_row.add_child(c)
		coins.append(c)
	if earned > 0:
		tokens_lbl.text = "+%d token%s   ·   you have %d" % [earned, "" if earned == 1 else "s", Game.tokens]
	elif r["best"]:
		tokens_lbl.text = "No new tokens — a token for every 100 points above your old best."
	else:
		tokens_lbl.text = "No tokens — beat your best of %d to earn more." % int(r["prev_score"])
	tokens_lbl.add_theme_color_override("font_color", UIStyle.GOLD if earned > 0 else UIStyle.MUTED)
	tokens_lbl.modulate.a = 0.0

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	var first := _buttons(btns, [
		["Continue", Game.goto_map],
		["Replay", func() -> void: Game.play_level(level.level_id)],
	], Vector2(250, 66))

	# --- choreography ---
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(card, "modulate:a", 1.0, 0.4)
	tw.tween_callback(func() -> void: _reveal(row_a))
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void: _reveal(row_b))
	tw.tween_interval(0.35)
	var count_time := 1.3
	tw.tween_method(func(x: float) -> void:
		var shown := int(round(x))
		if score_lbl.text != str(shown) and shown % 37 == 0:
			_sound.play(&"ui_move", -12.0, 0.8 + x / 1000.0)
		score_lbl.text = str(shown), 0.0, float(r["score"]), count_time).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		stamp.modulate.a = 1.0
		_sound.play(&"umbrella_open", 0.0, 0.8)
		var st := create_tween().set_parallel()
		st.tween_property(stamp, "scale", Vector2.ONE, 0.22).from(Vector2(2.6, 2.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_property(stamp, "rotation", deg_to_rad(-10.0), 0.22).from(deg_to_rad(-30.0))
		var sc := create_tween()
		sc.tween_property(score_lbl, "scale", Vector2(1.12, 1.12), 0.08)
		sc.tween_property(score_lbl, "scale", Vector2.ONE, 0.2))
	if r["best"]:
		best_tag.text = "NEW BEST!" + ("   was %d   " % int(r["prev_score"]) if int(r["prev_score"]) > 0 else "   ")
		tw.tween_interval(0.3)
		tw.tween_callback(func() -> void:
			best_tag.pivot_offset = best_tag.size * 0.5
			var bt := create_tween().set_parallel()
			bt.tween_property(best_tag, "modulate:a", 1.0, 0.2)
			bt.tween_property(best_tag, "scale", Vector2.ONE, 0.35).from(Vector2(1.6, 1.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var glow := create_tween().set_loops(4)
			glow.tween_property(best_tag, "modulate", Color(1.4, 1.3, 1.0), 0.25)
			glow.tween_property(best_tag, "modulate", Color.WHITE, 0.25))
	tw.tween_interval(0.25)
	tw.tween_property(tokens_lbl, "modulate:a", 1.0, 0.3)
	for c in coins:
		tw.tween_callback(func() -> void:
			_sound.play(&"token", -6.0)
			var ct := create_tween().set_parallel()
			ct.tween_property(c, "modulate:a", 1.0, 0.1)
			ct.tween_property(c, "scale", Vector2.ONE, 0.25).from(Vector2(0.2, 0.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		tw.tween_interval(0.14)
	# Buttons take focus once the choreography is done; confirm/back before that skips ahead.
	tw.finished.connect(func() -> void:
		if first:
			first.grab_focus())
	_result_tween = tw


func _result_row(parent: Container, title: String, detail: String, pts: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var a := UIStyle.label(title, &"CaptionLabel", 24)
	a.custom_minimum_size = Vector2(150, 0)
	h.add_child(a)
	var d := UIStyle.label(detail, &"BodyLabel", 26)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(d)
	var p := UIStyle.label("+%d" % pts, &"StatLabel", 30, Color(C_TEXT, 0.9))
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(p)
	h.modulate.a = 0.0
	parent.add_child(h)
	return h


func _reveal(c: Control) -> void:
	_sound.play(&"ui_move", -8.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(c, "modulate:a", 1.0, 0.25)
	tw.tween_property(c, "position:x", c.position.x, 0.3).from(c.position.x - 20.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw_stamp(ci: Control, grade: String) -> void:
	var c := ci.size * 0.5
	var col := UIStyle.grade_color(grade)
	var r := minf(c.x, c.y) - 6.0
	ci.draw_circle(c, r, Color(col, 0.12))
	ci.draw_arc(c, r, 0.0, TAU, 64, col, 5.0, true)
	ci.draw_arc(c, r - 9.0, 0.0, TAU, 64, Color(col, 0.6), 2.0, true)
	var f := UIStyle.F_TITLE
	var fs := int(r * 1.5)
	var w := f.get_string_size(grade, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), grade, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var cap := "GRADE"
	var cf := UIStyle.F_COND
	var cw := cf.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	ci.draw_string(cf, c + Vector2(-cw * 0.5, -r * 0.52), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col, 0.8))


func _draw_coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.12), r, Color(0.35, 0.22, 0.05))
	ci.draw_circle(c, r, UIStyle.GOLD)
	ci.draw_arc(c, r * 0.78, 0.0, TAU, 32, Color(0.6, 0.4, 0.1, 0.8), maxf(1.0, r * 0.1), true)
	UIStyle.draw_umbrella(ci, c + Vector2(0, r * 0.08), r, Color(0.45, 0.28, 0.06))
