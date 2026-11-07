extends SceneTree
## Generates res://src/ui/theme.tres (the project-wide UI theme).
##   godot --headless --path . -s res://src/ui/theme_gen.gd
## Edit values here and re-run rather than editing the .tres by hand.

const OUT := "res://src/ui/theme.tres"
const P := preload("res://src/ui/ui_style.gd")


func _init() -> void:
	var t := Theme.new()
	var body: FontFile = load("res://assets/fonts/Barlow-Medium.ttf")
	var body_reg: FontFile = load("res://assets/fonts/Barlow-Regular.ttf")
	var bold: FontFile = load("res://assets/fonts/Barlow-SemiBold.ttf")
	var italic: FontFile = load("res://assets/fonts/Barlow-Italic.ttf")
	var cond: FontFile = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	var bebas: FontFile = load("res://assets/fonts/BebasNeue-Regular.ttf")

	var display := FontVariation.new()
	display.base_font = bebas
	display.spacing_glyph = 2
	var display_wide := FontVariation.new()
	display_wide.base_font = bebas
	display_wide.spacing_glyph = 6
	var caps := FontVariation.new()
	caps.base_font = cond
	caps.spacing_glyph = 2
	var tabular := FontVariation.new()
	tabular.base_font = bold
	tabular.opentype_features = {"tnum": 1}

	t.default_font = body
	t.default_font_size = 26

	# --- Label + variations -------------------------------------------------------------
	t.set_color("font_color", "Label", P.CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "Label", 2)
	_label_var(t, "TitleLabel", display_wide, 176, P.CREAM)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 8)
	t.set_constant("shadow_outline_size", "TitleLabel", 18)
	_label_var(t, "HeaderLabel", display, 64, P.CREAM)
	_label_var(t, "HeaderSmall", display, 40, P.CREAM)
	_label_var(t, "KickerLabel", caps, 22, P.AMBER)
	_label_var(t, "BodyLabel", body_reg, 26, Color(P.CREAM, 0.86))
	_label_var(t, "MutedLabel", body_reg, 22, P.MUTED)
	_label_var(t, "ItalicLabel", italic, 26, Color(P.CREAM, 0.72))
	_label_var(t, "CaptionLabel", caps, 20, P.MUTED)
	_label_var(t, "StatLabel", tabular, 30, P.CREAM)
	_label_var(t, "HudLabel", caps, 20, Color(P.CREAM, 0.8))
	for v in ["HudLabel", "StatLabel", "CaptionLabel"]:
		t.set_color("font_shadow_color", v, Color(0, 0, 0, 0.6))
		t.set_constant("shadow_offset_x", v, 0)
		t.set_constant("shadow_offset_y", v, 2)
		t.set_constant("shadow_outline_size", v, 4)

	# --- Button -------------------------------------------------------------------------
	t.set_font("font", "Button", display)
	t.set_font_size("font_size", "Button", 40)
	t.set_color("font_color", "Button", Color(P.CREAM, 0.88))
	t.set_color("font_hover_color", "Button", P.AMBER)
	t.set_color("font_focus_color", "Button", P.AMBER)
	t.set_color("font_hover_pressed_color", "Button", P.INK)
	t.set_color("font_pressed_color", "Button", P.INK)
	t.set_color("font_disabled_color", "Button", Color(P.CREAM, 0.28))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0))
	t.set_color("icon_normal_color", "Button", Color(P.CREAM, 0.88))
	t.set_color("icon_focus_color", "Button", P.AMBER)
	t.set_color("icon_hover_color", "Button", P.AMBER)
	t.set_constant("h_separation", "Button", 14)
	t.set_stylebox("normal", "Button", _box(Color(0.05, 0.056, 0.07, 0.62), Color(1, 1, 1, 0.07), [0, 0, 0, 2]))
	t.set_stylebox("hover", "Button", _box(Color(0.13, 0.11, 0.08, 0.85), P.AMBER, [6, 0, 0, 2]))
	t.set_stylebox("pressed", "Button", _box(P.AMBER, P.AMBER, [6, 0, 0, 2]))
	t.set_stylebox("hover_pressed", "Button", _box(P.AMBER, P.AMBER, [6, 0, 0, 2]))
	t.set_stylebox("disabled", "Button", _box(Color(0.05, 0.056, 0.07, 0.35), Color(1, 1, 1, 0.03), [0, 0, 0, 2]))
	var focus := _box(Color(1.0, 0.71, 0.29, 0.1), P.AMBER, [6, 2, 2, 2])
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("focus", "Button", focus)

	# Small secondary button (map shop, pause menu extras).
	t.set_type_variation("SmallButton", "Button")
	t.set_font("font", "SmallButton", caps)
	t.set_font_size("font_size", "SmallButton", 24)

	# Upgrade / list row buttons: body font, left aligned, taller.
	t.set_type_variation("RowButton", "Button")
	t.set_font("font", "RowButton", bold)
	t.set_font_size("font_size", "RowButton", 26)
	t.set_stylebox("normal", "RowButton", _box(Color(0.06, 0.066, 0.082, 0.8), Color(1, 1, 1, 0.08), [0, 0, 0, 1], 18, 14))
	t.set_stylebox("hover", "RowButton", _box(Color(0.12, 0.105, 0.08, 0.92), P.AMBER, [6, 0, 0, 1], 18, 14))
	t.set_stylebox("pressed", "RowButton", _box(Color(0.25, 0.18, 0.08, 0.95), P.AMBER, [6, 0, 0, 1], 18, 14))
	t.set_stylebox("hover_pressed", "RowButton", _box(Color(0.25, 0.18, 0.08, 0.95), P.AMBER, [6, 0, 0, 1], 18, 14))
	t.set_stylebox("disabled", "RowButton", _box(Color(0.05, 0.055, 0.068, 0.6), Color(1, 1, 1, 0.04), [0, 0, 0, 1], 18, 14))
	t.set_color("font_pressed_color", "RowButton", P.CREAM)
	t.set_color("font_hover_pressed_color", "RowButton", P.CREAM)
	t.set_color("font_disabled_color", "RowButton", Color(P.CREAM, 0.45))

	# --- Panels -------------------------------------------------------------------------
	var panel := _box(P.PANEL, Color(1, 1, 1, 0.1), [1, 1, 1, 1], 36, 30)
	panel.set_corner_radius_all(4)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 28
	panel.shadow_offset = Vector2(0, 10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var card := panel.duplicate() as StyleBoxFlat
	card.border_color = P.AMBER
	card.border_width_top = 4
	card.border_width_left = 0
	card.border_width_right = 0
	card.border_width_bottom = 0
	card.content_margin_left = 28
	card.content_margin_right = 28
	card.content_margin_top = 22
	card.content_margin_bottom = 24
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)
	var clear := StyleBoxEmpty.new()
	t.set_type_variation("ClearPanel", "PanelContainer")
	t.set_stylebox("panel", "ClearPanel", clear)

	# --- Sliders ------------------------------------------------------------------------
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = P.AMBER_DIM
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := track.duplicate() as StyleBoxFlat
	fill_hi.bg_color = P.AMBER
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", _circle_tex(30, P.CREAM, Color(0, 0, 0, 0.5)))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(30, P.AMBER, Color(0, 0, 0, 0.5)))
	t.set_icon("grabber_disabled", "HSlider", _circle_tex(30, Color(P.CREAM, 0.3), Color(0, 0, 0, 0.5)))
	var sfocus := StyleBoxFlat.new()
	sfocus.draw_center = false
	sfocus.border_color = P.AMBER
	sfocus.set_border_width_all(2)
	sfocus.set_corner_radius_all(6)
	sfocus.set_expand_margin_all(10)
	t.set_stylebox("focus", "HSlider", sfocus)

	# --- Progress bars ------------------------------------------------------------------
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0, 0, 0, 0.45)
	pbg.set_corner_radius_all(6)
	var pfg := StyleBoxFlat.new()
	pfg.bg_color = P.RAIN
	pfg.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", pfg)
	t.set_font("font", "ProgressBar", caps)
	t.set_font_size("font_size", "ProgressBar", 18)

	# --- Scrolling ----------------------------------------------------------------------
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(P.CREAM, 0.35)
	grab.set_corner_radius_all(4)
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = P.AMBER
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())

	# --- Tooltip ------------------------------------------------------------------------
	var tip := _box(Color(0.05, 0.055, 0.07, 0.96), P.AMBER, [0, 2, 0, 0], 14, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", P.CREAM)
	t.set_font("font", "TooltipLabel", body_reg)
	t.set_font_size("font_size", "TooltipLabel", 22)

	# --- Separators ---------------------------------------------------------------------
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.12)
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 18)

	var err := ResourceSaver.save(t, OUT)
	print("theme saved: ", OUT, " err=", err)
	quit()


func _label_var(t: Theme, name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)


## StyleBoxFlat with per-side border widths [left, top, right, bottom].
func _box(bg: Color, border: Color, widths: Array, mx := 30, my := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = widths[0]
	s.border_width_top = widths[1]
	s.border_width_right = widths[2]
	s.border_width_bottom = widths[3]
	s.set_corner_radius_all(2)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.anti_aliasing = true
	return s


func _circle_tex(d: int, col: Color, ring: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var outer := clampf(d * 0.5 - r, 0.0, 1.0)
			var inner := clampf(d * 0.5 - 3.0 - r, 0.0, 1.0)
			var px := ring.lerp(col, inner)
			px.a = outer * lerpf(ring.a, col.a, inner)
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)
