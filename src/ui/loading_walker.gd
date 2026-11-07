extends Control
## Loading-card walker: the same little figure under an umbrella that marks you on the map,
## bobbing along in place while the street builds.

const SIZE := 76.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var p := Vector2(0, sin(_t * 3.0) * 4.0)
	UIStyle.draw_walker(self, p, SIZE, Color(1, 1, 1, 0.9), _t * 6.0)
