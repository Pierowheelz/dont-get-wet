extends Control
## City map: pick the next street (adjacent nodes only) and buy umbrella upgrades.

const C_TEXT := Color(0.92, 0.9, 0.85)
var _buttons := {}
var _preview: Label
var _tokens_lbl: Label
var _shop: VBoxContainer
var _map_rect := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.075, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := Label.new()
	title.text = "THE CITY"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", C_TEXT)
	title.position = Vector2(60, 40)
	add_child(title)
	var legend := Label.new()
	legend.text = "<  Country                                                                     City centre  >"
	legend.add_theme_color_override("font_color", Color(C_TEXT, 0.5))
	legend.add_theme_font_size_override("font_size", 20)
	legend.position = Vector2(140, 130)
	add_child(legend)
	_tokens_lbl = Label.new()
	_tokens_lbl.add_theme_font_size_override("font_size", 30)
	_tokens_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_tokens_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tokens_lbl.position = Vector2(-360, 50)
	add_child(_tokens_lbl)
	_preview = Label.new()
	_preview.add_theme_font_size_override("font_size", 24)
	_preview.add_theme_color_override("font_color", C_TEXT)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(900, 160)
	_preview.position = Vector2(140, 820)
	add_child(_preview)
	_build_nodes()
	_build_shop()
	_refresh_tokens()


func _map_to_screen(p: Array) -> Vector2:
	var s := get_viewport_rect().size
	_map_rect = Rect2(Vector2(120, 170), Vector2(s.x - 640, 600))
	return _map_rect.position + Vector2(float(p[0]), float(p[1])) * _map_rect.size


func _build_nodes() -> void:
	var focus_btn: Button
	for id in Game.nodes:
		var n: Dictionary = Game.nodes[id]
		var b := Button.new()
		var best: Dictionary = Game.best.get(id, {})
		b.text = n["name"] + ("\n%s · %d" % [best["grade"], best["score"]] if not best.is_empty() else "")
		b.custom_minimum_size = Vector2(190, 70)
		b.add_theme_font_size_override("font_size", 22)
		b.position = _map_to_screen(n["map_pos"]) - b.custom_minimum_size * 0.5
		b.disabled = not Game.can_select(id)
		if id == Game.current_node:
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		b.pressed.connect(func() -> void: Game.play_level(id))
		b.focus_entered.connect(func() -> void: _show_preview(id))
		b.mouse_entered.connect(func() -> void: _show_preview(id))
		add_child(b)
		_buttons[id] = b
		if not b.disabled and (focus_btn == null or (id != Game.current_node and not Game.completed.has(id))):
			focus_btn = b
	if focus_btn:
		focus_btn.grab_focus.call_deferred()
	queue_redraw()


func _draw() -> void:
	for id in Game.nodes:
		var a := _map_to_screen(Game.nodes[id]["map_pos"])
		for nb in Game.neighbors(id):
			if nb > id:
				var b := _map_to_screen(Game.nodes[nb]["map_pos"])
				draw_line(a, b, Color(1, 1, 1, 0.25), 4.0, true)


func _show_preview(id: String) -> void:
	var n: Dictionary = Game.nodes[id]
	var best: Dictionary = Game.best.get(id, {})
	var txt := "%s   %s\n%s" % [n["name"].to_upper(), "★".repeat(int(n.get("difficulty", 1))), n["blurb"]]
	if not best.is_empty():
		txt += "\nBest: %d (%s) — %d%% wet, %d:%02d" % [best["score"], best["grade"], int(best["wet"]),
			int(best["time"]) / 60, int(best["time"]) % 60]
	if not Game.can_select(id):
		txt += "\n(Too far — reach a neighbouring street first.)"
	_preview.text = txt


func _build_shop() -> void:
	_shop = VBoxContainer.new()
	_shop.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_shop.position = Vector2(-460, 140)
	_shop.custom_minimum_size = Vector2(420, 0)
	_shop.add_theme_constant_override("separation", 12)
	add_child(_shop)
	_fill_shop()


func _fill_shop() -> void:
	for c in _shop.get_children():
		c.queue_free()
	var h := Label.new()
	h.text = "UMBRELLA UPGRADES"
	h.add_theme_font_size_override("font_size", 26)
	h.add_theme_color_override("font_color", C_TEXT)
	_shop.add_child(h)
	var info := {&"sturdy": ["Sturdy frame", "Less stamina drain, less wind load"],
		&"wide": ["Wide canopy", "Covers more of you"],
		&"light": ["Featherweight", "Opens and closes faster"]}
	for u in Game.UPGRADES:
		var lvl := Game.upgrade_level(u)
		var cost := Game.upgrade_cost(u)
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 76)
		b.add_theme_font_size_override("font_size", 20)
		b.text = "%s  %s\n%s" % [info[u][0], "●".repeat(lvl) + "○".repeat(3 - lvl),
			("%s — %d tokens" % [info[u][1], cost]) if cost >= 0 else "Maxed out"]
		b.disabled = cost < 0 or Game.tokens < cost
		b.pressed.connect(func() -> void:
			if Game.buy_upgrade(u):
				_fill_shop()
				_refresh_tokens())
		_shop.add_child(b)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(420, 56)
	menu.add_theme_font_size_override("font_size", 22)
	menu.pressed.connect(Game.goto_menu)
	_shop.add_child(menu)


func _refresh_tokens() -> void:
	_tokens_lbl.text = "Tokens: %d" % Game.tokens


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		Game.goto_menu()
