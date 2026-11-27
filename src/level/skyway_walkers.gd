extends Node3D
## Passengers walking a skyway's gallery: each paces from one end to the other and turns back.
## Scenery only (SkywayBuilder adds them); a gentle bob stands in for a gait at that distance.

var _walkers: Array = []   # [node, x0, x1, speed (signed)]
var _t := 0.0


func add_walker(n: Node3D, x0: float, x1: float, speed: float) -> void:
	_walkers.append([n, x0, x1, speed])
	n.rotation.y = 0.0 if speed > 0.0 else PI


func _process(delta: float) -> void:
	_t += delta
	for w in _walkers:
		var n: Node3D = w[0]
		n.position.x += w[3] * delta
		if n.position.x > w[2] and w[3] > 0.0 or n.position.x < w[1] and w[3] < 0.0:
			w[3] = -w[3]
			n.rotation.y = 0.0 if w[3] > 0.0 else PI
		n.position.y = SkywayBuilder.DECK_Y + absf(sin(_t * 5.5 + n.position.z * 3.0)) * 0.03
