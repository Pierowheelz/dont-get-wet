extends OmniLight3D
## Flashing amber signal.
var _base := -1.0
var _t := randf()

func _process(delta: float) -> void:
	if _base < 0.0:
		_base = light_energy
	_t += delta
	light_energy = _base if fmod(_t, 1.2) < 0.6 else 0.0
