extends OmniLight3D
## Occasional neon stutter.
var _base := -1.0
var _t := randf() * 20.0
var _off := 0.0

func _process(delta: float) -> void:
	if _base < 0.0:
		_base = light_energy
	_t += delta
	if _off > 0.0:
		_off -= delta
		light_energy = _base * (0.15 if int(_off * 30.0) % 2 == 0 else 0.8)
	else:
		light_energy = _base
		if randf() < delta * 0.08:
			_off = randf_range(0.1, 0.5)
