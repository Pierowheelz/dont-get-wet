extends Control
## Title screen: a rainy street behind the title, the main menu, a replay list and settings.

const Backdrop := preload("res://src/ui/menu_backdrop.gd")
const Drips := preload("res://src/ui/title_drips.gd")
const PostFX := preload("res://src/fx/post_fx.gd")
const LEFT := 132.0
const COL_W := 560.0
const MAIN_Y := 490.0

var _ui: CanvasLayer
var _root: Control
var _page: VBoxContainer
var _page_name := ""
var _title_box: VBoxContainer
var _fade: ColorRect
var _bg_fade: ColorRect
var _dialog: Control
var _post: CanvasLayer
var _sound: UISound
var _hints: KeyHints
var _busy := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sound = UISound.new()
	add_child(_sound)
	var bd := Backdrop.new()
	add_child(bd)
	bd.loop_soon.connect(_dip_to_black)
	_set_painterly(bool(Game.settings.get("painterly", true)))

	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_root)
	# Backdrop-only fade (under the title and menu) for hiding the street loop.
	_bg_fade = ColorRect.new()
	_bg_fade.color = Color(0, 0, 0, 0)
	_bg_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg_fade)
	_shades()
	_build_title()

	_page = VBoxContainer.new()
	_page.position = Vector2(LEFT, MAIN_Y)
	_page.custom_minimum_size = Vector2(COL_W, 0)
	_page.add_theme_constant_override("separation", 12)
	_root.add_child(_page)

	_hints = KeyHints.new([["A", "Enter", "Select"], ["B", "Esc", "Back"]])
	_hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hints.position = Vector2(LEFT, -84)
	_root.add_child(_hints)
	var ver := UIStyle.label("A game by Peter Wells  ·  v%s alpha" % ProjectSettings.get_setting("application/config/version", "0.1.0"), &"CaptionLabel")
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.position = Vector2(-520, -84)
	ver.custom_minimum_size = Vector2(460, 0)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(ver)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE)

	UISound.start_menu_music(get_tree())
	_main_buttons()


# --- layout -----------------------------------------------------------------------------------

func _shades() -> void:
	# Darken the left of the frame (title + menu) and the bottom edge, keep the street visible.
	var left := TextureRect.new()
	left.texture = _gradient(Vector2(0, 0), Vector2(1, 0), [
		[0.0, Color(UIStyle.INK, 0.95)], [0.55, Color(UIStyle.INK, 0.86)], [1.0, Color(UIStyle.INK, 0.0)]])
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = 1300
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(left)
	# Soft radial pool of shadow behind the title so lit shop signs don't ghost through it.
	var halo := TextureRect.new()
	var hg := _gradient(Vector2(0.5, 0.5), Vector2(1.0, 0.5), [
		[0.0, Color(UIStyle.INK, 0.8)], [0.6, Color(UIStyle.INK, 0.55)], [1.0, Color(UIStyle.INK, 0.0)]])
	hg.fill = GradientTexture2D.FILL_RADIAL
	halo.texture = hg
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.position = Vector2(-160, 40)
	halo.size = Vector2(1500, 480)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(halo)
	var bottom := TextureRect.new()
	bottom.texture = _gradient(Vector2(0, 1), Vector2(0, 0), [
		[0.0, Color(UIStyle.INK, 0.85)], [1.0, Color(UIStyle.INK, 0.0)]])
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -220
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)


func _gradient(from: Vector2, to: Vector2, stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for s: Array in stops:
		g.add_point(float(s[0]), s[1])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = from
	t.fill_to = to
	t.width = 256
	t.height = 256
	return t


func _build_title() -> void:
	_title_box = VBoxContainer.new()
	_title_box.position = Vector2(LEFT, 150)
	_title_box.add_theme_constant_override("separation", 0)
	_root.add_child(_title_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	_title_box.add_child(row)
	row.add_child(UIStyle.label("DON'T GET", &"TitleLabel"))
	var wet := UIStyle.label("WET", &"TitleLabel", 0, UIStyle.RAIN)
	row.add_child(wet)
	var drips := Drips.new()
	drips.set_anchors_preset(Control.PRESET_FULL_RECT)
	drips.offset_bottom = -30
	wet.add_child(drips)
	var tag := UIStyle.label("He isn't dressed for it.", &"ItalicLabel")
	_title_box.add_child(tag)
	# entrance
	_title_box.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_title_box, "modulate:a", 1.0, 1.6).set_delay(0.5)
	tw.tween_property(_title_box, "position:y", 150.0, 1.6).from(176.0).set_delay(0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _dip_to_black() -> void:
	# Cover the walker looping back to the start of the street.
	var tw := create_tween()
	tw.tween_property(_bg_fade, "color:a", 1.0, 1.4)
	tw.tween_interval(0.9)
	tw.tween_property(_bg_fade, "color:a", 0.0, 1.6)


func _set_painterly(on: bool) -> void:
	if on and _post == null:
		_post = PostFX.new()
		add_child(_post)
	elif not on and _post != null:
		_post.queue_free()
		_post = null


# --- pages ------------------------------------------------------------------------------------

func _clear(page_name: String) -> void:
	var was_main := _page_name == "main" or _page_name == ""
	_page_name = page_name
	var compact := page_name != "main"
	if compact == was_main:
		# Sub-pages shrink the title out of the way so long lists fit on screen.
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_title_box, "scale", Vector2.ONE * (0.6 if compact else 1.0), 0.35)
		tw.tween_property(_page, "position:y", 380.0 if compact else MAIN_Y, 0.35)
	_sound.hush()
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()


func _btn(text: String, cb: Callable, variation: StringName = &"", sound: StringName = &"ui_confirm", parent: Control = _page) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(COL_W, 70)
	if variation != &"":
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void:
		if _busy or _dialog != null:
			return
		_sound.play(sound)
		if cb.is_valid():
			cb.call())
	b.mouse_entered.connect(func() -> void:
		if _dialog == null:
			b.grab_focus())
	parent.add_child(b)
	return b


func _animate_page() -> void:
	var i := 0
	for c in _page.get_children():
		if c is Control:
			var ctl := c as Control
			ctl.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_interval(0.04 * i)
			tw.tween_property(ctl, "modulate:a", 1.0, 0.25)
			i += 1


func _main_buttons() -> void:
	_clear("main")
	var first: Button
	if Game.runs.is_empty():
		first = _btn("Start walking", _start_run.bind(""))
	elif Game.runs.has(""):
		first = _btn("Continue", _continue_run.bind(""))
		_page.add_child(_progress(Game.runs[""], "%d of %d streets walked   ·   %d tokens"))
	else:
		first = _slots()
	if not Game.run.completed.is_empty():
		_btn("Replay a street", _replay_list)
	_btn("Settings", _settings)
	_btn("Credits", _credits)
	_btn("Quit", func() -> void: get_tree().quit(), &"", &"ui_back")
	first.grab_focus.call_deferred()
	_animate_page()


## "← Continue" / "Continue →" side by side, one per direction, each with its progress and a New run
## button once it has a save. Returns the button to focus first.
func _slots() -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_page.add_child(row)
	var mains: Array[Button] = []
	var restarts: Array[Button] = []
	var first: Button
	for side: String in Run.DIRECTIONS:
		var r: Run = Game.runs.get(side)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)
		var word := "Continue" if r else "Start"
		var b := _btn("← " + word if side == "left" else word + " →",
			_continue_run.bind(side) if r else _start_run.bind(side), &"", &"ui_confirm", col)
		b.custom_minimum_size.x = (COL_W - 12.0) * 0.5
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT if side == "left" else HORIZONTAL_ALIGNMENT_RIGHT
		mains.append(b)
		if r == null:
			continue
		if r == Game.run or first == null:
			first = b
		var info := _progress(r, "%d of %d streets · %d tokens", side == "right")
		info.add_theme_constant_override("margin_bottom", 0)
		col.add_child(info)
		var nr := _btn("New run…", _confirm_new_run.bind(side), &"SmallButton", &"ui_confirm", col)
		nr.custom_minimum_size = Vector2(b.custom_minimum_size.x, 44)
		nr.alignment = b.alignment
		restarts.append(nr)
	for pair: Array[Button] in [mains, restarts]:
		if pair.size() == 2:
			pair[0].focus_neighbor_right = pair[1].get_path()
			pair[1].focus_neighbor_left = pair[0].get_path()
	return first


func _progress(r: Run, fmt: String, right := false) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_right" if right else "margin_left", 30)
	m.add_theme_constant_override("margin_bottom", 6)
	var l := UIStyle.label(fmt % [r.completed.size(), Game.reachable_count(r), r.tokens], &"MutedLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	m.add_child(l)
	return m


func _start_run(side: String) -> void:
	Game.new_run(side)
	_go_map()


func _continue_run(side: String) -> void:
	Game.resume_run(side)
	_go_map()


func _go_map() -> void:
	if Game.run.completed.is_empty():
		_leave(func() -> void: Game.play_level(Game.start_node), true)
	else:
		_leave(Game.goto_map, false)


func _leave(cb: Callable, stop_music: bool) -> void:
	_busy = true
	if stop_music:
		UISound.stop_menu_music(get_tree(), 0.8)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.tween_callback(cb)


func _replay_list() -> void:
	_clear("replay")
	var heading: String = {"": "", "left": "  ·  ← RUN", "right": "  ·  RUN →"}[Game.run.direction]
	_page.add_child(UIStyle.label("REPLAY A STREET" + heading, &"HeaderSmall", 0, UIStyle.AMBER))
	var first: Button = null
	var ids: Array = []
	for id: String in Game.nodes:   # map order, country -> centre
		if Game.run.completed.has(id) and not Game.other_way(id):
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return float(Game.nodes[a]["map_pos"][0]) < float(Game.nodes[b]["map_pos"][0]))
	for id: String in ids:
		var n: Dictionary = Game.nodes.get(id, {})
		var best: Dictionary = Game.run.best.get(id, {})
		var b := _row(String(n.get("name", id)), best, func() -> void: _leave(func() -> void: Game.play_level(id), true))
		if first == null:
			first = b
	var back := _btn("Back", _main_buttons, &"", &"ui_back")
	(first if first else back).grab_focus.call_deferred()
	_animate_page()


func _row(title: String, best: Dictionary, cb: Callable) -> Button:
	var b := _btn("", cb, &"RowButton")
	b.custom_minimum_size = Vector2(COL_W + 160, 84)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 26
	h.offset_right = -22
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 22)
	b.add_child(h)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", -4)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(name_box)
	name_box.add_child(UIStyle.label(title.to_upper(), &"HeaderSmall", 36))
	if not best.is_empty():
		name_box.add_child(UIStyle.label("%d%% wet   ·   %s" % [int(best.get("wet", 0)), UIStyle.fmt_time(float(best.get("time", 0)))], &"MutedLabel", 20))
	var score := UIStyle.label(str(int(best.get("score", 0))) if not best.is_empty() else "—", &"StatLabel", 34)
	score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(score)
	var g := String(best.get("grade", "-"))
	var grade := UIStyle.label(g, &"HeaderLabel", 58, UIStyle.grade_color(g))
	grade.custom_minimum_size = Vector2(48, 0)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(grade)
	for c in [score, grade]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _credits() -> void:
	_clear("credits")
	_page.add_child(UIStyle.label("CREDITS", &"HeaderSmall", 0, UIStyle.AMBER))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = false
	rt.fit_content = false
	rt.scroll_active = true
	rt.custom_minimum_size = Vector2(760, 360)
	rt.focus_mode = Control.FOCUS_ALL
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.text = FileAccess.get_file_as_string("res://data/credits.txt") if FileAccess.file_exists("res://data/credits.txt") else ""
	rt.add_theme_font_size_override("normal_font_size", 22)
	_page.add_child(rt)
	var back := _btn("Back", _main_buttons, &"", &"ui_back")
	back.grab_focus.call_deferred()
	_animate_page()


func _settings() -> void:
	_clear("settings")
	_page.add_child(UIStyle.label("SETTINGS", &"HeaderSmall", 0, UIStyle.AMBER))
	var p := _toggle_row("Painterly filter", "painterly", func(on: bool) -> void: _set_painterly(on))
	_toggle_row("Touch controls", "touch_controls", Callable())
	_toggle_row("Low graphics (Steam Deck / laptops)", "low_quality", Callable())
	_slider_row("Music", "music")
	_slider_row("Sound effects", "sfx")
	var reset := _btn("Reset progress…", _confirm_reset, &"RowButton")
	reset.add_theme_color_override("font_color", Color(UIStyle.DANGER, 0.9))
	reset.add_theme_color_override("font_focus_color", UIStyle.DANGER)
	reset.add_theme_color_override("font_hover_color", UIStyle.DANGER)
	_btn("Back", func() -> void:
		Game.save_game()
		_main_buttons(), &"", &"ui_back")
	p.grab_focus.call_deferred()
	_animate_page()


func _toggle_row(text: String, key: String, on_change: Callable) -> Button:
	var b := _btn(text, Callable(), &"RowButton")
	var val := UIStyle.label("", &"HeaderSmall", 34)
	val.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	val.offset_left = -120
	val.offset_right = -22
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(val)
	var refresh := func() -> void:
		var on := bool(Game.settings.get(key, false))
		val.text = "ON" if on else "OFF"
		val.add_theme_color_override("font_color", UIStyle.AMBER if on else UIStyle.MUTED)
	refresh.call()
	b.pressed.connect(func() -> void:
		if _dialog != null:
			return
		Game.settings[key] = not bool(Game.settings.get(key, false))
		Game.save_game()
		refresh.call()
		if on_change.is_valid():
			on_change.call(bool(Game.settings[key])))
	return b


func _slider_row(text: String, key: String) -> HSlider:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.066, 0.082, 0.8)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.border_width_bottom = 1
	sb.content_margin_left = 18
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(COL_W, 70)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	panel.add_child(h)
	var lbl := UIStyle.label(text, &"", 26)
	lbl.add_theme_font_override("font", UIStyle.F_BOLD)
	lbl.custom_minimum_size = Vector2(200, 0)
	h.add_child(lbl)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Game.settings.get(key, 1.0))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := UIStyle.label("%d%%" % int(round(s.value * 100.0)), &"StatLabel", 24)
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	s.value_changed.connect(func(v: float) -> void:
		Game.settings[key] = v
		val.text = "%d%%" % int(round(v * 100.0))
		if key == "music":
			UISound.update_menu_music_volume(get_tree())
		else:
			_sound.play(&"ui_move"))
	s.focus_entered.connect(func() -> void: lbl.add_theme_color_override("font_color", UIStyle.AMBER))
	s.focus_exited.connect(func() -> void: lbl.remove_theme_color_override("font_color"))
	s.mouse_entered.connect(func() -> void:
		if _dialog == null:
			s.grab_focus())
	_page.add_child(panel)
	return s


# --- confirmations ----------------------------------------------------------------------------

func _confirm_reset() -> void:
	_confirm("RESET PROGRESS?", "Every run, best score, token and umbrella upgrade will be lost, and he'll start again on Main Street. Settings are kept.",
		"Reset", func() -> void:
			Game.reset_progress()
			_main_buttons())


func _confirm_new_run(side: String) -> void:
	var title := "NEW ← RUN?" if side == "left" else "NEW RUN →?"
	var text := "This run's best scores, tokens and umbrella upgrades will be lost, and he'll start again on Main Street."
	if Game.runs.size() > 1:
		text += " Your other run is kept."
	_confirm(title, text, "New run", _start_run.bind(side))


func _confirm(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	var prev := get_viewport().gui_get_focus_owner()
	_dialog = ColorRect.new()
	(_dialog as ColorRect).color = Color(0, 0, 0, 0.0)
	_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dialog)
	create_tween().tween_property(_dialog, "color:a", 0.7, 0.25)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(700, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	var hdr := UIStyle.label(title, &"HeaderLabel", 0, UIStyle.DANGER)
	v.add_child(hdr)
	var body := UIStyle.label(text, &"BodyLabel")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(640, 0)
	v.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var close := func() -> void:
		_dialog.queue_free()
		_dialog = null
		if is_instance_valid(prev):
			prev.grab_focus()
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(220, 64)
	cancel.pressed.connect(func() -> void:
		_sound.play(&"ui_back")
		close.call())
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = ok_text
	ok.custom_minimum_size = Vector2(220, 64)
	ok.add_theme_color_override("font_color", UIStyle.DANGER)
	ok.add_theme_color_override("font_focus_color", UIStyle.DANGER)
	ok.add_theme_color_override("font_hover_color", UIStyle.DANGER)
	ok.pressed.connect(func() -> void:
		_sound.play(&"ui_confirm")
		_dialog.queue_free()
		_dialog = null
		on_ok.call())
	row.add_child(ok)
	# Trap focus inside the dialog.
	for b: Button in [cancel, ok]:
		var other: Button = ok if b == cancel else cancel
		b.focus_neighbor_top = b.get_path()
		b.focus_neighbor_bottom = b.get_path()
		b.focus_neighbor_left = other.get_path()
		b.focus_neighbor_right = other.get_path()
		b.focus_next = other.get_path()
		b.focus_previous = other.get_path()
		b.mouse_entered.connect(b.grab_focus)
	_dialog.set_meta(&"close", close)
	cancel.grab_focus.call_deferred()
	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.2)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") and not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()
	if _dialog != null:
		_sound.play(&"ui_back")
		(_dialog.get_meta(&"close") as Callable).call()
	elif _page_name != "main":
		_sound.play(&"ui_back")
		if _page_name == "settings":
			Game.save_game()
		_main_buttons()
