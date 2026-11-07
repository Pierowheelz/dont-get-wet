extends OmniLight3D
## Fire-light flicker.
var _base := -1.0
var _t := randf() * 10.0

func _process(delta: float) -> void:
	if _base < 0.0:
		_base = light_energy
	_t += delta
	light_energy = _base * (0.8 + 0.2 * sin(_t * 13.0) * sin(_t * 7.3 + 1.0) + 0.1 * sin(_t * 23.0))
