extends Control
## Procedurally painted city map: blueprint paper, fields and a canal on the country side,
## a street grid that gets denser toward the city centre, neon specks downtown.
## Static — only redrawn on resize.

const PAPER_TOP := Color(0.075, 0.1, 0.145)
const PAPER_BOT := Color(0.05, 0.07, 0.1)
const GRID := Color(0.55, 0.7, 0.95, 0.05)
const WATER := Color(0.14, 0.27, 0.42)
const WATER_EDGE := Color(0.42, 0.62, 0.85, 0.55)
const FIELD := Color(0.24, 0.3, 0.22, 0.55)
const BLOCK := Color(0.2, 0.23, 0.29)
const BLOCK_DT := Color(0.29, 0.31, 0.37)
const STREET := Color(0.6, 0.66, 0.78, 0.1)

## Map scale: < 1 zooms out (smaller blocks, fields and canal), so the whole city fits.
const ZOOM := 0.8

## x (0..1 of map width) where the canal runs.
var canal_x := 0.4
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


## Canal centre-line at map-relative y (0..1) → map-relative x.
func canal_at(v: float) -> float:
	var k := size.y / maxf(size.x, 1.0) * 1.54   # meander in pixels, whatever the strip's length
	return canal_x + k * (0.035 * sin(v * 5.2 + 0.6) + 0.018 * sin(v * 11.0))


func _draw() -> void:
	var s := size
	if s.x < 10.0:
		return
	_rng.seed = 1960
	# Paper
	var bg := PackedColorArray([PAPER_TOP, PAPER_TOP, PAPER_BOT, PAPER_BOT])
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]), bg)
	var step := 40.0 * ZOOM
	var x := 0.0
	while x < s.x:
		draw_line(Vector2(x, 0), Vector2(x, s.y), GRID, 1.0)
		x += step
	var y := 0.0
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), GRID, 1.0)
		y += step

	# Country fields (left of the canal): hatched patches.
	for i in int(canal_x * s.x * s.y / (10000.0 * ZOOM * ZOOM)):
		var fx := _rng.randf_range(0.0, canal_x * s.x - 60.0)
		var fy := _rng.randf_range(0.02, 0.95) * s.y
		var fw := _rng.randf_range(50.0, 120.0) * ZOOM
		var fh := _rng.randf_range(36.0, 90.0) * ZOOM
		var r := Rect2(fx, fy, fw, fh)
		draw_rect(r, Color(FIELD, FIELD.a * _rng.randf_range(0.5, 1.0)))
		var hx := 0.0
		while hx < fw + fh:
			var a := Vector2(fx + hx, fy)
			var b := Vector2(fx + hx - fh, fy + fh)
			var ca := _clip_to(r, a, b)
			if ca.size() == 2:
				draw_line(ca[0], ca[1], Color(0.5, 0.6, 0.4, 0.18), 1.0, true)
			hx += 9.0 * ZOOM
	# Country lanes
	for i in 7:
		var ly := _rng.randf_range(0.1, 0.9) * s.y
		var pts := PackedVector2Array()
		for k in 12:
			var u := float(k) / 11.0
			pts.append(Vector2(u * canal_x * s.x, ly + sin(u * 9.0 + i) * 18.0))
		draw_polyline(pts, Color(0.6, 0.6, 0.5, 0.18), 3.0, true)

	# City-light haze: warm sodium glow over the old town, cold neon glow downtown.
	for i in 14:
		var k := float(i) / 14.0
		draw_circle(Vector2(0.5 * s.x, 0.55 * s.y), lerpf(0.75, 0.08, k) * s.y, Color(1.0, 0.65, 0.3, 0.012))
		draw_circle(Vector2(0.97 * s.x, 0.5 * s.y), lerpf(1.1, 0.1, k) * s.y, Color(0.3, 0.9, 1.0, 0.014))

	# Town grid: block size shrinks toward the centre (right); outskirts have gaps.
	var x0 := canal_x * s.x + 60.0
	var bx := x0
	while bx < s.x:
		var u := bx / s.x
		var bw := lerpf(96.0, 40.0, clampf((u - canal_x) / (1.0 - canal_x), 0.0, 1.0)) * ZOOM
		var gap := lerpf(16.0, 9.0, u) * ZOOM
		var by := -_rng.randf_range(0.0, bw)
		var bh := bw * _rng.randf_range(0.8, 1.25)
		while by < s.y:
			var density := clampf((u - canal_x) * 1.5, 0.15, 1.0)
			if _rng.randf() < density + 0.1:
				var col := BLOCK.lerp(BLOCK_DT, clampf((u - 0.4) * 1.6, 0.0, 1.0))
				col = col.darkened(_rng.randf_range(0.0, 0.25))
				var r := Rect2(bx, by, bw, bh)
				draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.35))
				draw_rect(r, col)
				# Lit top/left edges, like ink on blueprint paper.
				draw_line(r.position, r.position + Vector2(bw, 0), Color(0.75, 0.85, 1.0, 0.16), 1.5)
				draw_line(r.position, r.position + Vector2(0, bh), Color(0.75, 0.85, 1.0, 0.1), 1.5)
				# Subdivide downtown blocks into building footprints.
				if u > 0.55 and _rng.randf() < 0.6:
					draw_line(Vector2(bx + bw * 0.5, by), Vector2(bx + bw * 0.5, by + bh), Color(0, 0, 0, 0.25), 2.0)
				# Neon toward the centre.
				if u > 0.6 and _rng.randf() < (u - 0.55) * 0.9:
					var neon: Color = [UIStyle.NEON_TEAL, UIStyle.NEON_PINK, UIStyle.AMBER][_rng.randi() % 3]
					var p := Vector2(bx + _rng.randf_range(0.2, 0.8) * bw, by + _rng.randf_range(0.2, 0.8) * bh)
					draw_circle(p, 9.0 * ZOOM, Color(neon, 0.08))
					draw_circle(p, 4.5 * ZOOM, Color(neon, 0.2))
					draw_circle(p, 2.0 * ZOOM, Color(neon, 0.95))
			by += bh + gap
		bx += bw + gap

	# Avenues (a few wider streets) over the grid.
	for i in 3:
		var ay := (0.2 + 0.3 * i + _rng.randf_range(-0.05, 0.05)) * s.y
		draw_line(Vector2(x0 - 30.0, ay), Vector2(s.x, ay + _rng.randf_range(-20, 20)), STREET, 7.0 * ZOOM, true)

	# Canal: wide band with bright banks and ripple marks.
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := 40
	for k in n + 1:
		var v := float(k) / float(n)
		var cx := canal_at(v) * s.x
		var w := (22.0 + 4.0 * sin(v * 7.0)) * ZOOM
		left.append(Vector2(cx - w, v * s.y))
		right.append(Vector2(cx + w, v * s.y))
	var poly := left.duplicate()
	var rr := right.duplicate()
	rr.reverse()
	poly.append_array(rr)
	draw_colored_polygon(poly, WATER)
	draw_polyline(left, WATER_EDGE, 2.5, true)
	draw_polyline(right, WATER_EDGE, 2.5, true)
	for k in 26:
		var v := _rng.randf()
		var cx := canal_at(v) * s.x + _rng.randf_range(-10, 10) * ZOOM
		var cy := v * s.y
		draw_arc(Vector2(cx, cy), 7.0 * ZOOM, PI * 1.15, PI * 1.85, 6, Color(0.6, 0.8, 1.0, 0.35), 1.5, true)
	_label_canal(s)



func _label_canal(s: Vector2) -> void:
	var f := UIStyle.F_ITALIC
	var p := Vector2(canal_at(0.18) * s.x + 20.0, 0.18 * s.y)
	draw_set_transform(p, PI * 0.5, Vector2.ONE)
	draw_string(f, Vector2.ZERO, "the old canal", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.78, 1.0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Clip segment a-b to rect r (simple parametric clip). Returns [] if outside.
func _clip_to(r: Rect2, a: Vector2, b: Vector2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		if absf(p[i]) < 0.0001:
			if q[i] < 0.0:
				return []
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]
