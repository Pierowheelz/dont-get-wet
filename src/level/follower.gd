extends Node3D
## The level's `follower`: a man in a long coat and hat who keeps pace behind the walker. At each
## `appear` x the walker passes he walks in from the left edge of the frame, holds just inside it for
## `hold` seconds, then slows and drifts back out. He copies the walker's stops and hurries LAG
## seconds late. Scenery only: he never touches the walker or the rain model.

enum Phase { OFF, ENTER, HOLD, LEAVE }

const MANIFEST := "res://assets/characters/pedestrians/peds.json"
const LAG := 0.6
const LANE_Z := 0.8          # the back lane: further from the camera, so the frame edge sits further behind the walker
const HOLD_FRAC := 0.1       # where he holds, as a fraction of the screen width from the left edge
const OUT_MARGIN := 1.2      # metres past the left frame edge that put him wholly out of shot
const MIN_GAP := 3.0
const HEAR_GAP := 6.0        # his footsteps carry this far behind the walker
const CATCH_UP := 0.8        # fastest he closes in on his mark, m/s over the walker's pace
const FALL_BACK := 0.5       # fastest he drops back
const ACCEL := 3.0
const RAINCOAT := Color(0.5, 0.42, 0.3)

var level: Node
var phase := Phase.OFF
var speed := 0.0
var _appear: Array = []      # [x, hold] ascending
var _next := 0
var _hold_left := 0.0
var _samples: Array = []     # [time, walker speed or 0 while he isn't walking], oldest first
var _t := 0.0
var _model: Node3D
var _umbrella: Umbrella
var _skel: Skeleton3D
var _hand := -1
var _steps: AudioStreamPlayer3D
var _step_phase := 0.0


func _ready() -> void:
	var spec: Dictionary = level.data["follower"]
	for a in spec.get("appear", []):
		_appear.append([float(a["x"]), float(a.get("hold", 6.0))])
	_appear.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# A checkpoint resume spawns the walker past some appearances; those stay spent.
	while _next < _appear.size() and _appear[_next][0] <= level.player.position.x:
		_next += 1
	_build_model(String(spec.get("model", "old_man")))
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = &"SFX"
	_steps.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_steps.panning_strength = 2.0
	_steps.volume_db = -15.0
	_steps.position.y = 0.2
	add_child(_steps)
	visible = false
	position = Vector3(-100.0, 0.0, LANE_Z)


func _build_model(id: String) -> void:
	var scene := ""
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for p in (d if d is Array else []):
		if p["id"] == id:
			scene = p["scene"]
	if scene == "" or not ResourceLoader.exists(scene):
		push_warning("follower model %s not found" % id)
		return
	_model = (load(scene) as PackedScene).instantiate()
	# His umbrella stays furled (carried below), and his coat and hat are always the same.
	_model.set("umbrella", false)
	_model.set("tint_options", {"fedora": [Color(0.45, 0.4, 0.34)]})
	add_child(_model)
	_model.call("setup", 4242)
	_dress_raincoat()
	# He walks the dark back lane at the frame edge; a soft fill keeps the coat and hat readable.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.8
	fill.omni_range = 2.6
	fill.omni_attenuation = 1.5
	fill.position = Vector3(0.3, 1.3, 1.0)
	fill.light_specular = 0.2
	add_child(fill)
	_skel = _model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if _skel:
		_hand = _skel.find_bone("RightHand")
	_umbrella = Umbrella.new()
	_umbrella.canopy_color = Color(0.07, 0.07, 0.08)
	_umbrella.top_level = true
	add_child(_umbrella)
	_umbrella.set_state(0.0, Game.umbrella_radius(), 0.0)
	(func() -> void: _umbrella._body.collision_layer = 0).call_deferred()


## The pedestrian kit has no long coat: recolour the jacket as a raincoat and hang a skirt of the
## same cloth from the waist to the knee.
func _dress_raincoat() -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = RAINCOAT
	cloth.roughness = 0.7
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).to_lower().contains("double-breasted"):
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				(mi as MeshInstance3D).set_surface_override_material(s, cloth)
	var hem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.19
	cm.bottom_radius = 0.25
	cm.height = 0.5
	cm.radial_segments = 16
	cm.rings = 1
	hem.mesh = cm
	hem.material_override = cloth
	hem.scale = Vector3(1.0, 1.0, 0.8)
	hem.position.y = 0.73
	_model.add_child(hem)


func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null or level.camera == null:
		return
	_t += delta
	_samples.append([_t, p.speed if p.state == Player.State.WALK else 0.0])
	while _samples.size() > 1 and _samples[1][0] <= _t - LAG:
		_samples.pop_front()
	if _next < _appear.size() and p.position.x >= _appear[_next][0]:
		_appear_for(_appear[_next][1])
		_next += 1
	if phase == Phase.OFF:
		return
	_step(delta, p)


func _appear_for(hold: float) -> void:
	_hold_left = hold
	match phase:
		Phase.OFF:
			position.x = _frame_x(0.0) - OUT_MARGIN
			speed = level.player.speed
			phase = Phase.ENTER
			visible = true
		Phase.LEAVE:
			phase = Phase.ENTER


## How far behind the walker he aims to be in each phase.
func _target_gap() -> float:
	var px: float = level.player.position.x
	match phase:
		Phase.ENTER, Phase.HOLD:
			return maxf(MIN_GAP + 0.4, px - _frame_x(HOLD_FRAC))
		Phase.LEAVE:
			return px - _frame_x(0.0) + OUT_MARGIN + 0.5
	return INF


func _step(delta: float, p: Player) -> void:
	var lagged: float = _samples[0][1]
	var gap := p.position.x - position.x
	var target := _target_gap()
	var want := 0.0
	if lagged > 0.05:
		want = maxf(lagged + clampf((gap - target) * 0.8, -FALL_BACK, CATCH_UP), 0.0)
	speed = move_toward(speed, want, ACCEL * delta)
	position.x = minf(position.x + speed * delta, p.position.x - MIN_GAP)
	position.y = level.ground_y(position.x)
	gap = p.position.x - position.x
	match phase:
		Phase.ENTER:
			if gap <= target + 0.2:
				phase = Phase.HOLD
		Phase.HOLD:
			_hold_left -= delta
			if _hold_left <= 0.0:
				phase = Phase.LEAVE
		Phase.LEAVE:
			if position.x < _frame_x(0.0) - OUT_MARGIN:
				phase = Phase.OFF
				visible = false
				speed = 0.0
	if _model:
		_model.call("set_walking", speed)
	if _hand >= 0:
		var hand := _skel.global_transform * _skel.get_bone_global_pose(_hand)
		# Carried furled like a cane: shaft pointing down and a little ahead.
		_umbrella.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI + 0.18), hand.origin)
	_footsteps(delta, gap)


## World x at a fraction of the screen width, on his lane.
func _frame_x(frac: float) -> float:
	var cam: Camera3D = level.camera
	var vp := get_viewport().get_visible_rect().size
	return cam.project_position(Vector2(vp.x * frac, vp.y * 0.6), cam.global_position.z - LANE_Z).x


func _footsteps(delta: float, gap: float) -> void:
	if speed < 0.1:
		return
	var run := clampf((speed - Tun.f("walk_speed")) / (Tun.f("run_speed") - Tun.f("walk_speed")), 0.0, 1.0)
	_step_phase += speed * delta / lerpf(0.75, 1.1, run)
	if _step_phase < 1.0:
		return
	_step_phase -= 1.0
	if gap > HEAR_GAP:
		return
	var s := load("res://assets/audio/footstep_wet_%d.ogg" % randi_range(1, 4)) as AudioStream
	if s:
		_steps.stream = s
		_steps.pitch_scale = randf_range(0.82, 0.92)
		_steps.play()

