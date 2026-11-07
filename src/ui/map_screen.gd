extends Control
## City map: pick the next street (adjacent nodes only) and buy umbrella upgrades.

const Canvas := preload("res://src/ui/city_map_canvas.gd")
const NodeButton := preload("res://src/ui/map_node_button.gd")
const SHOP_W := 520.0
const MARGIN := 64.0

const UPGRADE_INFO := {
	&"sturdy": ["Sturdy frame", "Less stamina drain, less wind load."],
	&"wide": ["Wide canopy", "Covers more of you."],
	&"light": ["Featherweight", "Opens and closes faster."],
}

var _map: Control             # map area (canvas + routes + nodes)
var _canvas: Control
var _routes: DrawBox
var _buttons := {}            # id -> NodeButton
var _card: PanelContainer
var _card_id := ""
var _card_tween: Tween
var _shop: VBoxContainer
var _tokens_lbl: Label
var _shop_buttons: Array[Button] = []
var _menu_btn: Button
var _umb_stats: HBoxContainer
var _sound: UISound
var _fade: ColorRect
var _t := 0.0
var _busy := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sound = UISound.new()
	add_child(_sound)
	UISound.start_menu_music(get_tree())

	var bg := ColorRect.new()
	bg.color = UIStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Header
	var head := VBoxContainer.new()
	head.position = Vector2(MARGIN, 34)
	head.add_theme_constant_override("separation", -6)
	add_child(head)
	head.add_child(UIStyle.label("WHERE TO TONIGHT?", &"KickerLabel"))
	head.add_child(UIStyle.label("THE CITY", &"HeaderLabel", 84))

	# Map area
	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.offset_left = MARGIN
	_map.offset_top = 170
	_map.offset_right = -(SHOP_W + MARGIN + 40.0)
	_map.offset_bottom = -110
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	_canvas = Canvas.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.add_child(_canvas)
	_routes = DrawBox.new(_draw_routes, Vector2.ZERO, true)
	_routes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.add_child(_routes)
	var legend_l := UIStyle.label("◂  COUNTRY", &"CaptionLabel")
	legend_l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend_l.position = Vector2(4, 12)
	legend_l.grow_vertical = Control.GROW_DIRECTION_END
	_map.add_child(legend_l)
	var legend_r := UIStyle.label("CITY CENTRE  ▸", &"CaptionLabel")
	legend_r.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	legend_r.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legend_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	legend_r.offset_left = -300
	legend_r.offset_top = 12
	legend_r.offset_bottom = 40
	_map.add_child(legend_r)

	_build_shop()
	_build_nodes()
	_build_card()

	var hints := KeyHints.new([["A", "Enter", "Walk / buy"], ["B", "Esc", "Main menu"]])
	hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hints.position = Vector2(MARGIN, -62)
	add_child(hints)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.5)
	_map.resized.connect(_layout_nodes)
	_layout_nodes.call_deferred()
	_refresh_tokens()


func _process(delta: float) -> void:
	_t += delta


# --- map --------------------------------------------------------------------------------------

func _map_point(id: String) -> Vector2:
	var p: Array = Game.nodes[id]["map_pos"]
	return Vector2(float(p[0]), float(p[1])) * _map.size


func _build_nodes() -> void:
	var focus_btn: Button = null
	for id: String in Game.nodes:
		var n: Dictionary = Game.nodes[id]
		var b := NodeButton.new()
		_map.add_child(b)
		b.setup(id, n, Game.run.best.get(id, {}))
		b.pressed.connect(func() -> void: _pick(id))
		b.focus_entered.connect(func() -> void: _show_card(id))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		_buttons[id] = b
		if Game.can_select(id) and (focus_btn == null or (id != Game.run.current_node and not Game.run.completed.has(id))):
			focus_btn = b
	# Left/right walks the map in order, and steps across into the shop from the rightmost node.
	var ids: Array = _buttons.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return float(Game.nodes[a]["map_pos"][0]) < float(Game.nodes[b]["map_pos"][0]))
	for i in ids.size():
		var b: Button = _buttons[ids[i]]
		if i > 0:
			b.focus_neighbor_left = (_buttons[ids[i - 1]] as Button).get_path()
		if i < ids.size() - 1:
			b.focus_neighbor_right = (_buttons[ids[i + 1]] as Button).get_path()
		elif not _shop_buttons.is_empty():
			b.focus_neighbor_right = _shop_buttons[0].get_path()
	var back_to_map: Button = _buttons.get(Game.run.current_node, _buttons[ids[-1]])
	for sb: Button in _shop_buttons:
		sb.focus_neighbor_left = back_to_map.get_path()
	_menu_btn.focus_neighbor_left = back_to_map.get_path()
	if focus_btn:
		focus_btn.grab_focus.call_deferred()


func _layout_nodes() -> void:
	for id: String in _buttons:
		var b: Button = _buttons[id]
		b.position = _map_point(id) - b.size * 0.5
	if _card_id != "":
		_place_card(_card_id, false)


func _pick(id: String) -> void:
	if _busy:
		return
	if not Game.can_select(id):
		_sound.play(&"ui_denied")
		_shake(_buttons[id])
		return
	_busy = true
	Game.choose(id)
	_sound.play(&"ui_confirm")
	UISound.stop_menu_music(get_tree(), 0.9)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	tw.tween_callback(func() -> void: Game.play_level(id))


func _shake(c: Control) -> void:
	var x := c.position.x
	var tw := create_tween()
	for i in 4:
		tw.tween_property(c, "position:x", x + (8.0 if i % 2 == 0 else -8.0), 0.04)
	tw.tween_property(c, "position:x", x, 0.04)


func _draw_routes(ci: Control) -> void:
	if _buttons.is_empty():
		return
	# Routes between neighbouring streets.
	for id: String in Game.nodes:
		var a := _map_point(id)
		for nb: String in Game.neighbors(id):
			if nb <= id or not Game.nodes.has(nb):
				continue
			var b := _map_point(nb)
			var open := Game.can_select(id) and Game.can_select(nb)
			var walked := Game.run.completed.has(id) and Game.run.completed.has(nb)
			var col := Color(UIStyle.CREAM, 0.22)
			if walked:
				col = Color(UIStyle.CREAM, 0.55)
			if open:
				col = Color(UIStyle.AMBER, 0.85)
			ci.draw_line(a, b, Color(0, 0, 0, 0.45), 11.0, true)
			_dashed(ci, a, b, col, 5.0, 16.0, 10.0, _t * 18.0 if open else 0.0)
	# Current position: a little walker under an umbrella above the marker, bobbing.
	if Game.nodes.has(Game.run.current_node):
		var p := _map_point(Game.run.current_node) + Vector2(0, -NodeButton.R - 16.0 + sin(_t * 3.0) * 3.0)
		UIStyle.draw_walker(ci, p, 46.0, UIStyle.AMBER, _t * 6.0)
	# Leader line from the preview card down to the focused street.
	if _card_id != "" and _card.modulate.a > 0.05:
		var np := _map_point(_card_id)
		var top := _card.position + Vector2(0, _card.size.y) - _map.position
		var from := Vector2(clampf(np.x, top.x + 20.0, top.x + _card.size.x - 20.0), top.y)
		var to := np + Vector2(0, -NodeButton.R - 12.0)
		if _card_id == Game.run.current_node:
			to.y -= 62.0
		var a := _card.modulate.a
		if to.y > from.y + 8.0:
			ci.draw_line(from, to, Color(UIStyle.AMBER, 0.7 * a), 2.0, true)
			ci.draw_circle(to, 4.0, Color(UIStyle.AMBER, a))


func _dashed(ci: Control, a: Vector2, b: Vector2, col: Color, width: float, dash: float, gap: float, offset: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 1.0:
		return
	var dir := d / L
	var t := -fmod(offset, dash + gap)
	while t < L:
		var t0 := maxf(t, 0.0)
		var t1 := minf(t + dash, L)
		if t1 > t0:
			ci.draw_line(a + dir * t0, a + dir * t1, col, width, true)
		t += dash + gap


# --- preview card ----------------------------------------------------------------------------

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.theme_type_variation = &"CardPanel"
	_card.custom_minimum_size = Vector2(0, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	add_child(_card)


func _show_card(id: String) -> void:
	_card_id = id
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	var n: Dictionary = Game.nodes[id]
	var best: Dictionary = Game.run.best.get(id, {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)

	# Left: what & where.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size = Vector2(390, 0)
	row.add_child(left)
	var kick := "YOU ARE HERE" if id == Game.run.current_node else ("WALKED" if Game.run.completed.has(id) else "UNEXPLORED")
	left.add_child(UIStyle.label(kick, &"KickerLabel", 20))
	left.add_child(UIStyle.label(String(n.get("name", id)).to_upper(), &"HeaderLabel", 56))
	var blurb := UIStyle.label(String(n.get("blurb", "")), &"BodyLabel", 22)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(390, 0)
	left.add_child(blurb)

	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	sep.add_theme_stylebox_override("separator", _vline())
	row.add_child(sep)

	# Right: difficulty, record, and whether you can go there.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(290, 0)
	row.add_child(right)
	var diff := int(n.get("difficulty", 1))
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 12)
	dr.add_child(UIStyle.label("DIFFICULTY", &"CaptionLabel", 18))
	var drops := func(ci: Control) -> void:
		for i in 5:
			var on := i < diff
			UIStyle.draw_drop(ci, Vector2(10.0 + i * 20.0, 13.0), 21.0,
				Color(UIStyle.RAIN, 0.95 if on else 0.3), UIStyle.RAIN_DEEP.lerp(UIStyle.RAIN, 0.45), 1.0 if on else 0.0)
	dr.add_child(DrawBox.new(drops, Vector2(104, 26)))
	right.add_child(dr)
	if best.is_empty():
		right.add_child(UIStyle.label("No record yet.", &"MutedLabel"))
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 20)
		var g := String(best.get("grade", "-"))
		var gl := _stat(grid, "GRADE", g)
		gl.add_theme_color_override("font_color", UIStyle.grade_color(g))
		_stat(grid, "BEST", str(int(best.get("score", 0))))
		_stat(grid, "WET", "%d%%" % int(best.get("wet", 0)))
		_stat(grid, "TIME", UIStyle.fmt_time(float(best.get("time", 0))))
		right.add_child(grid)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	if not Game.can_select(id):
		var why := "This run heads the other way." if Game.other_way(id) else "Too far — walk a neighbouring street first."
		var far := UIStyle.label(why, &"ItalicLabel", 21, Color(UIStyle.DANGER, 0.95))
		far.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		far.custom_minimum_size = Vector2(290, 0)
		right.add_child(far)
	else:
		right.add_child(UIStyle.label("WALK THIS STREET  ▸" if not Game.run.completed.has(id) else "WALK IT AGAIN  ▸", &"KickerLabel", 22, UIStyle.CREAM))
	_place_card(id, true)


func _vline() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.vertical = true
	l.color = Color(1, 1, 1, 0.12)
	l.thickness = 2
	return l


func _stat(parent: Container, title: String, value: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.add_child(UIStyle.label(title, &"CaptionLabel", 16))
	var l := UIStyle.label(value, &"StatLabel", 30)
	box.add_child(l)
	parent.add_child(box)
	return l


## The card docks along the top of the map (where there are no streets) above the focused node,
## with a leader line down to it, so it never hides a neighbouring street.
func _place_card(id: String, animate: bool) -> void:
	_card.reset_size()
	var cs := _card.get_combined_minimum_size()
	var p := _map.position + _map_point(id)
	var target := Vector2(p.x - cs.x * 0.5, _map.position.y + 18.0)
	target.x = clampf(target.x, _map.position.x + 18.0, _map.position.x + _map.size.x - cs.x - 18.0)
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	if animate:
		_card.position = target + Vector2(0, -10)
		_card.modulate.a = 0.0 if _card.modulate.a < 0.5 else _card.modulate.a
		_card_tween = create_tween().set_parallel()
		_card_tween.tween_property(_card, "position", target, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_card_tween.tween_property(_card, "modulate:a", 1.0, 0.16)
	else:
		_card.position = target


func _hide_card() -> void:
	_card_id = ""
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	_card_tween = create_tween()
	_card_tween.tween_property(_card, "modulate:a", 0.0, 0.15)


# --- upgrade shop -----------------------------------------------------------------------------

func _build_shop() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -(SHOP_W + MARGIN)
	panel.offset_right = -MARGIN
	panel.offset_top = 64
	panel.offset_bottom = -110
	add_child(panel)
	_shop = VBoxContainer.new()
	_shop.add_theme_constant_override("separation", 14)
	panel.add_child(_shop)
	var head := HBoxContainer.new()
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UIStyle.label("THE UMBRELLA SHOP", &"KickerLabel"))
	hv.add_child(UIStyle.label("UPGRADES", &"HeaderLabel"))
	head.add_child(hv)
	var tok := HBoxContainer.new()
	tok.add_theme_constant_override("separation", 10)
	tok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tok.add_child(DrawBox.new(func(ci: Control) -> void: _draw_token(ci, ci.size * 0.5, 20.0), Vector2(44, 44)))
	_tokens_lbl = UIStyle.label("0", &"StatLabel", 40, UIStyle.GOLD)
	tok.add_child(_tokens_lbl)
	head.add_child(tok)
	_shop.add_child(head)
	var note := UIStyle.label("Tokens come from beating your best score on a street.", &"MutedLabel", 20)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop.add_child(note)
	_shop.add_child(HSeparator.new())
	for u: StringName in Run.UPGRADES:
		var b := _upgrade_button(u)
		_shop_buttons.append(b)
		_shop.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop.add_child(spacer)
	_shop.add_child(UIStyle.label("YOUR UMBRELLA", &"KickerLabel", 18, UIStyle.MUTED))
	_umb_stats = HBoxContainer.new()
	_umb_stats.add_theme_constant_override("separation", 30)
	_shop.add_child(_umb_stats)
	_shop.add_child(HSeparator.new())
	_menu_btn = Button.new()
	_menu_btn.text = "Main menu"
	_menu_btn.theme_type_variation = &"SmallButton"
	_menu_btn.custom_minimum_size = Vector2(0, 56)
	_menu_btn.pressed.connect(_back_to_menu)
	_menu_btn.mouse_entered.connect(_menu_btn.grab_focus)
	_menu_btn.focus_entered.connect(_hide_card)
	_shop.add_child(_menu_btn)
	_shop_buttons[-1].focus_neighbor_bottom = _menu_btn.get_path()
	_menu_btn.focus_neighbor_top = _shop_buttons[-1].get_path()


func _upgrade_button(u: StringName) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.custom_minimum_size = Vector2(0, 112)
	var info: Array = UPGRADE_INFO.get(u, [String(u), ""])
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 22
	h.offset_right = -18
	h.offset_top = 10
	h.offset_bottom = -10
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var paint_icon := func(ci: Control) -> void:
		var lvl := Game.upgrade_level(u)
		var col := UIStyle.AMBER if b.has_focus() else UIStyle.CREAM
		UIStyle.draw_umbrella(ci, ci.size * 0.5 + Vector2(0, 4), 46.0 + (6.0 if u == &"wide" else 0.0) * lvl, col, 1.0)
	var icon := DrawBox.new(paint_icon, Vector2(64, 64), true)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var name_lbl := UIStyle.label(String(info[0]).to_upper(), &"HeaderSmall", 34)
	v.add_child(name_lbl)
	var desc := UIStyle.label(String(info[1]), &"MutedLabel", 20)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var paint_pips := func(ci: Control) -> void:
		var lvl := Game.upgrade_level(u)
		for i in 3:
			var r := Rect2(i * 34.0, 4.0, 28.0, 8.0)
			ci.draw_rect(r, UIStyle.AMBER if i < lvl else Color(1, 1, 1, 0.12))
	var pips := DrawBox.new(paint_pips, Vector2(100, 14), true)
	v.add_child(pips)
	var cost_box := VBoxContainer.new()
	cost_box.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_box.custom_minimum_size = Vector2(92, 0)
	h.add_child(cost_box)
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_END
	cost_row.add_theme_constant_override("separation", 6)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_box.add_child(cost_row)
	var cost_lbl := UIStyle.label("", &"StatLabel", 32)
	cost_row.add_child(cost_lbl)
	var coin := DrawBox.new(func(ci: Control) -> void: _draw_token(ci, ci.size * 0.5, 12.0), Vector2(28, 28))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_row.add_child(coin)
	var need := UIStyle.label("", &"CaptionLabel", 16)
	need.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_box.add_child(need)
	var refresh := func() -> void:
		var cost := Game.upgrade_cost(u)
		if cost < 0:
			cost_lbl.text = "MAX"
			cost_lbl.add_theme_color_override("font_color", UIStyle.GOOD)
			coin.visible = false
			need.text = "FULLY UPGRADED"
		else:
			cost_lbl.text = str(cost)
			var ok := Game.run.tokens >= cost
			cost_lbl.add_theme_color_override("font_color", UIStyle.GOLD if ok else Color(UIStyle.DANGER, 0.85))
			need.text = "BUY" if ok else "NEED %d MORE" % (cost - Game.run.tokens)
			need.add_theme_color_override("font_color", Color(UIStyle.GOLD, 0.8) if ok else UIStyle.MUTED)
			v.modulate.a = 1.0 if ok else 0.62
			icon.modulate.a = v.modulate.a
		name_lbl.add_theme_color_override("font_color", UIStyle.AMBER if b.has_focus() else UIStyle.CREAM)
	refresh.call()
	b.set_meta(&"refresh", refresh)
	b.focus_entered.connect(refresh)
	b.focus_exited.connect(refresh)
	b.focus_entered.connect(_hide_card)
	b.mouse_entered.connect(b.grab_focus)
	b.pressed.connect(func() -> void:
		if Game.buy_upgrade(u):
			_sound.play(&"ui_confirm")
			_sound.play(&"token", -4.0, 1.15)
			_refresh_tokens()
			var tw := create_tween()
			tw.tween_property(b, "modulate", Color(1.5, 1.3, 0.9), 0.08)
			tw.tween_property(b, "modulate", Color.WHITE, 0.3)
		else:
			_sound.play(&"ui_denied")
			_shake(b))
	return b


func _draw_token(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.12), r, Color(0.35, 0.22, 0.05))
	ci.draw_circle(c, r, UIStyle.GOLD)
	ci.draw_arc(c, r * 0.78, 0.0, TAU, 32, Color(0.6, 0.4, 0.1, 0.8), maxf(1.0, r * 0.1), true)
	UIStyle.draw_umbrella(ci, c + Vector2(0, r * 0.08), r * 1.0, Color(0.45, 0.28, 0.06))


func _refresh_tokens() -> void:
	_tokens_lbl.text = str(Game.run.tokens)
	for c in _umb_stats.get_children():
		c.queue_free()
	_stat(_umb_stats, "CANOPY", "%.2f m" % Game.umbrella_radius())
	_stat(_umb_stats, "OPENS IN", "%.2f s" % Game.umbrella_open_time())
	_stat(_umb_stats, "STRAIN", "%d%%" % int(round(Game.umbrella_drain_mult() * 100.0)))
	for b in _shop_buttons:
		(b.get_meta(&"refresh") as Callable).call()


func _back_to_menu() -> void:
	if _busy:
		return
	_busy = true
	_sound.play(&"ui_back")
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(Game.goto_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_to_menu()
