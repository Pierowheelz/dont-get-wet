extends Light3D
## A failing street lamp: it stutters off and on, now and then going out for a second or two.
## `lens` (optional) is the lamp's glowing face, dimmed with it.

var lens: GeometryInstance3D
var _base := -1.0
var _t := 0.0
var _off_until := 0.0


func _process(delta: float) -> void:
	if _base < 0.0:
		_base = light_energy
		_t = fmod(global_position.x * 1.37, 10.0)
	_t += delta
	var on := 1.0
	if _t < _off_until:
		on = 0.0
	elif sin(_t * 0.7) * sin(_t * 1.9 + 0.4) > 0.82:
		_off_until = _t + 0.6 + fmod(_t * 3.1, 1.4)
		on = 0.0
	elif sin(_t * 37.0) * sin(_t * 23.0) > 0.6:
		on = 0.35   # the stutter
	light_energy = _base * on
	if lens:
		lens.transparency = 1.0 - (0.15 + 0.85 * on)
