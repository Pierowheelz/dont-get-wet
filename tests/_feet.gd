extends Node3D
var w: Node3D
var cam: Camera3D
func _ready() -> void:
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.4, 0.45, 0.55)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(-0.8, 0.5, 0); add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10, 10); ground.mesh = pm; add_child(ground)
	w = load("res://assets/characters/walker/walker.tscn").instantiate(); add_child(w)
	cam = Camera3D.new(); cam.fov = 30; add_child(cam); cam.make_current()
	var mode := "idle"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="): mode = a.substr(5)
	w.set_motion(0.0 if mode == "idle" else 1.3, 0.0)
func _process(delta: float) -> void:
	if w.has_method("set_motion"):
		w.position.x += (0.0 if w.get("_speed") == 0.0 else 1.3) * delta
	cam.position = Vector3(w.position.x + 0.1, 0.25, 1.6)
	cam.look_at(Vector3(w.position.x + 0.1, 0.12, 0.0))
