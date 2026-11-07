extends CanvasLayer
## Full-screen painterly post-process (sits under the HUD).

func _ready() -> void:
	layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/fx/painterly.gdshader")
	rect.material = mat
	add_child(rect)
