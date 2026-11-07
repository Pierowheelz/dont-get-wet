extends Control
## Water beads that gather along the bottom edge of the title and drip off, one at a time.
## Place it over the title; drops form at the control's bottom edge.

const MAX_DROPS := 5
var color := Color(0.62, 0.78, 1.0, 0.85)
var fall_distance := 160.0
var _drops: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _spawn_t := 0.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


func _process(delta: float) -> void:
	_spawn_t -= delta
	if _spawn_t <= 0.0 and _drops.size() < MAX_DROPS and size.x > 0.0:
		_spawn_t = _rng.randf_range(0.7, 2.2)
		_drops.append({"x": _rng.randf_range(0.04, 0.96) * size.x, "grow": 0.0,
			"dur": _rng.randf_range(1.2, 2.6), "y": 0.0, "v": 0.0, "falling": false})
	for d in _drops:
		if not d["falling"]:
			d["grow"] = minf(1.0, float(d["grow"]) + delta / float(d["dur"]))
			if d["grow"] >= 1.0:
				d["falling"] = true
		else:
			d["v"] = float(d["v"]) + 900.0 * delta
			d["y"] = float(d["y"]) + float(d["v"]) * delta
	_drops = _drops.filter(func(d: Dictionary) -> bool: return float(d["y"]) < fall_distance)
	queue_redraw()


func _draw() -> void:
	var base := size.y
	for d in _drops:
		var g: float = d["grow"]
		var r := lerpf(1.5, 5.0, g)
		var p := Vector2(float(d["x"]), base + float(d["y"]))
		var a := 1.0 - clampf(float(d["y"]) / fall_distance, 0.0, 1.0)
		var c := Color(color, color.a * a)
		if d["falling"]:
			var stretch := clampf(float(d["v"]) / 900.0, 0.0, 1.0) * 14.0
			draw_line(p + Vector2(0, -stretch - r), p, Color(c, c.a * 0.5), r * 0.8, true)
			draw_circle(p, r * 0.8, c)
		else:
			# a bead hanging from the letter, neck thinning as it grows
			var hang := p + Vector2(0, r * 0.9 * g)
			draw_line(Vector2(p.x, base - 2.0), hang, Color(c, c.a * 0.7), r * (1.1 - g * 0.5), true)
			draw_circle(hang, r, c)
			draw_circle(hang + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 1, 0.6 * a))
