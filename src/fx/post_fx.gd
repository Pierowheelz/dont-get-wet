extends CanvasLayer
## Full-screen painterly post-process (sits under the HUD).

func _ready() -> void:
	layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/fx/painterly.gdshader")
	if Game.settings.get("low_quality", false):
		mat.set_shader_parameter("radius", 2)
	rect.material = mat
	add_child(rect)
