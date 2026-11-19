extends OmniLight3D
## Flashing amber signal. `lens`, if set, is the lit lens mesh: it shows only while the light is on.
var lens: GeometryInstance3D
var _base := -1.0
var _t := randf()

func _process(delta: float) -> void:
	if _base < 0.0:
		_base = light_energy
	_t += delta
	var on := fmod(_t, 1.2) < 0.6
	light_energy = _base if on else 0.0
	if lens:
		lens.visible = on
