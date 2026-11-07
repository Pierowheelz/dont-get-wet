extends Node3D
## Background pedestrian (scenery only). Contract:
##   setup(seed)            colour variation + animation phase
##   set_walking(speed_mps) 0 = stand (idle behaviour), > 0 = walk (jog blend when hurrying)
##   kind                   &"walker" or &"stander"
## Model: MakeHuman/MPFB2 (CC0/CC-BY assets, see assets/CREDITS.md); animations: the walker's
## extracted Quaternius UAL clips (CC0), retargeted at import via SkeletonProfileHumanoid.
## Faces +X, feet at the origin, no root motion (the owner moves the node).

const PoseModifier := preload("res://assets/characters/pedestrians/ped_pose_modifier.gd")
const UMBRELLA := preload("res://assets/characters/pedestrians/umbrella/umbrella.tscn")
const ANIMS := {
	&"walk": preload("res://assets/characters/walker/anim/walk.res"),
	&"jog": preload("res://assets/characters/walker/anim/jog.res"),
	&"idle": preload("res://assets/characters/walker/anim/idle.res"),
}
## Metres per gait cycle at jog weight 0, .25, .5, .75, 1 on the walker (hips height 0.973 m);
## scaled by this body's hips height. See assets/characters/walker/test/measure_blend.gd.
const CYCLE_M := [1.39, 2.54, 3.69, 4.87, 5.81]
const REF_HIPS := 0.9728

@export var kind: StringName = &"walker"
@export var umbrella := false
@export var smoke := false
@export var watch := false
## Use the right (camera-side when facing +X) arm for the watch check.
@export var watch_right := true
## Hunch into the rain while walking (hood up / no umbrella).
@export_range(0.0, 1.0) var hunch := 0.0
## Shift of the umbrella hand toward the character's right (+Z), e.g. to share the umbrella.
@export var umbrella_side_offset := 0.0
## Colour variation: mesh-name substring -> Array[Color] (albedo multiplier, one picked per seed).
@export var tint_options: Dictionary = {}
@export var umbrella_colors: Array[Color] = [Color(0.09, 0.1, 0.13), Color(0.32, 0.06, 0.07),
		Color(0.08, 0.16, 0.3), Color(0.12, 0.22, 0.14), Color(0.42, 0.33, 0.12)]
## Speed (m/s) suggested to the spawner for this pedestrian.
@export var suggested_speed := 1.25

var _model: Node3D
var _skel: Skeleton3D
var _tree: AnimationTree
var _mod: Node
var _umbrella: Node3D
var _speed := 0.0
var _stop_s := 1.0
var _jog_s := 0.0
var _t := 0.0
var _stride_scale := 1.0
var _mats := {}  # Material -> mesh name (for tinting)


func _ready() -> void:
	_build()
	setup(int(get_instance_id() % 100000))


func _build() -> void:
	if _skel != null:
		return
	_model = $Model
	_skel = _model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	_stride_scale = _skel.motion_scale / REF_HIPS

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	var lib := AnimationLibrary.new()
	for k in ANIMS:
		lib.add_animation(k, ANIMS[k])
	_tree.add_animation_library(&"", lib)
	var bt := AnimationNodeBlendTree.new()
	var run := AnimationNodeBlend2.new()
	run.sync = true
	bt.add_node(&"walk", _clip(&"walk", true))
	bt.add_node(&"jog", _clip(&"jog", true))
	bt.add_node(&"run", run)
	bt.add_node(&"ts", AnimationNodeTimeScale.new())
	bt.add_node(&"idle", _clip(&"idle", false))
	bt.add_node(&"stop", AnimationNodeBlend2.new())
	bt.connect_node(&"run", 0, &"walk")
	bt.connect_node(&"run", 1, &"jog")
	bt.connect_node(&"ts", 0, &"run")
	bt.connect_node(&"stop", 0, &"ts")
	bt.connect_node(&"stop", 1, &"idle")
	bt.connect_node(&"output", 0, &"stop")
	_tree.tree_root = bt
	add_child(_tree)
	_tree.root_node = _tree.get_path_to(_model)

	_mod = PoseModifier.new()
	_mod.name = "PoseModifier"
	_skel.add_child(_mod)
	_mod.setup(_skel, ANIMS[&"idle"], _stride_scale)
	_mod.hold_pos.z += umbrella_side_offset
	var rel := Transform3D.IDENTITY
	var n: Node = _skel
	while n != self and n is Node3D:
		rel = (n as Node3D).transform * rel
		n = n.get_parent()
	_mod.char_from_skel = rel
	_mod.umbrella = 1.0 if umbrella else 0.0
	_mod.smoke = smoke
	_mod.watch = watch
	_mod.watch_right = watch_right

	if umbrella:
		_umbrella = UMBRELLA.instantiate()
		_attach(&"RightHand", _mod.grip_r_offset).add_child(_umbrella)
	if smoke:
		_attach(&"RightHand", _mod.hand_r_offset).add_child(_make_cigarette())
	_setup_materials()
	_apply(0.0)


func _clip(anim: StringName, normalised: bool) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim
	if normalised:
		a.use_custom_timeline = true
		a.timeline_length = 1.0
		a.stretch_time_scale = true
		a.loop_mode = Animation.LOOP_LINEAR
	return a


func _attach(bone: StringName, offset: Transform3D) -> Node3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skel.add_child(att)
	var g := Node3D.new()
	g.transform = offset
	att.add_child(g)
	return g


func _make_cigarette() -> Node3D:
	var root := Node3D.new()
	var cig := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0035
	cm.bottom_radius = 0.0035
	cm.height = 0.075
	cm.radial_segments = 6
	cm.rings = 1
	cig.mesh = cm
	cig.rotation = Vector3(0, 0, PI * 0.5)  # across the fingers
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.9, 0.85)
	cig.material_override = m
	root.add_child(cig)
	var ember := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0045
	sm.height = 0.009
	sm.radial_segments = 6
	sm.rings = 3
	ember.mesh = sm
	ember.position = Vector3(0.038, 0, 0)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1.0, 0.35, 0.1)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.35, 0.05)
	em.emission_energy_multiplier = 3.0
	ember.material_override = em
	cig.add_child(ember)
	var smoke_fx := CPUParticles3D.new()
	smoke_fx.position = Vector3(0.0, 0.04, 0)
	smoke_fx.amount = 10
	smoke_fx.lifetime = 2.2
	smoke_fx.local_coords = false
	smoke_fx.direction = Vector3.UP
	smoke_fx.spread = 12.0
	smoke_fx.gravity = Vector3(0.05, 0.12, 0)
	smoke_fx.initial_velocity_min = 0.05
	smoke_fx.initial_velocity_max = 0.1
	smoke_fx.scale_amount_min = 0.6
	smoke_fx.scale_amount_max = 1.6
	var pm := QuadMesh.new()
	pm.size = Vector2(0.08, 0.08)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pmat.vertex_color_use_as_albedo = true
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	puff.width = 32
	puff.height = 32
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = pg
	pmat.albedo_texture = puff
	pm.material = pmat
	smoke_fx.mesh = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.8, 0.82, 0.16))
	grad.set_color(1, Color(0.8, 0.8, 0.82, 0.0))
	smoke_fx.color_ramp = grad
	ember.add_child(smoke_fx)
	return root


func _setup_materials() -> void:
	for mi in _skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.get_parent() is BoneAttachment3D or m.mesh == null:
			continue
		var n := String(m.name).to_lower()
		var is_hair := _is_hair(n)
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var d := src.duplicate() as StandardMaterial3D
			d.cull_mode = BaseMaterial3D.CULL_BACK
			d.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			d.roughness = 0.85
			if is_hair:
				d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				d.alpha_scissor_threshold = 0.45
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
				d.roughness = 0.6
			elif n.contains("eyebrow") or n.contains("eyelash"):
				d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
			elif n.contains("high-poly"):
				d.roughness = 0.35
				d.albedo_color = Color(0.75, 0.75, 0.75)
			elif n.ends_with("body"):
				d.roughness = 0.6
			elif n.contains("shoe") or n.contains("boot"):
				d.roughness = 0.4
			m.set_surface_override_material(s, d)
			_mats[d] = n


static func _is_hair(n: String) -> bool:
	for k in ["hair", "short0", "bob", "bun", "braid", "ponytail", "afro", "long0"]:
		if n.contains(k):
			return true
	return false


# --- Contract -----------------------------------------------------------------------------------

func setup(seed: int) -> void:
	_build()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for mat in _mats:
		var n: String = _mats[mat]
		var c := Color(0.75, 0.75, 0.75) if n.contains("high-poly") else Color.WHITE
		for key in tint_options:
			if n.contains(String(key)):
				var opts: Array = tint_options[key]
				if not opts.is_empty():
					c = opts[rng.randi() % opts.size()]
		if not n.ends_with("body") and not n.contains("high-poly") and not _is_hair(n) \
				and not n.contains("eye"):
			var v := rng.randf_range(0.88, 1.08)
			c = Color(c.r * v, c.g * v, c.b * v)
		(mat as StandardMaterial3D).albedo_color = c
	if _umbrella and not umbrella_colors.is_empty():
		var cm := (_umbrella.get_node("Canopy") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		cm.albedo_color = umbrella_colors[rng.randi() % umbrella_colors.size()]
	_mod.seed_phase = rng.randf_range(0.0, 30.0)
	_tree.advance(rng.randf_range(0.0, 2.5))


func set_walking(speed_mps: float) -> void:
	_speed = maxf(speed_mps, 0.0)


# ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_apply(delta)


func _apply(delta: float) -> void:
	_t += delta
	var walking := _speed > 0.05
	var k := 1.0 - exp(-delta * 5.0) if delta > 0.0 else 1.0
	_stop_s = lerpf(_stop_s, 0.0 if walking else 1.0, k)
	# Hurrying: blend toward the jog above ~1.7 m/s (capped like the player walker).
	var jog_target := clampf((_speed - 1.7) / 1.5, 0.0, 1.0) * 0.5
	_jog_s = lerpf(_jog_s, jog_target, k)
	var x := clampf(_jog_s, 0.0, 1.0) * (CYCLE_M.size() - 1)
	var i := mini(int(x), CYCLE_M.size() - 2)
	var cycle_m := minf(lerpf(CYCLE_M[i], CYCLE_M[i + 1], x - i), lerpf(1.39, 2.9, _jog_s * 2.0))
	cycle_m *= _stride_scale
	_tree.set(&"parameters/run/blend_amount", _jog_s)
	_tree.set(&"parameters/ts/scale", _speed / cycle_m)
	_tree.set(&"parameters/stop/blend_amount", _stop_s)
	_mod.time = _t
	_mod.hunch = hunch * (1.0 - _stop_s)
	_mod.look_around = _stop_s * (0.4 if umbrella else 1.0)
