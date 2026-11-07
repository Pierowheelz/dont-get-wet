extends Node3D
## Player character visual — implements docs/CONTRACTS.md §1.
## Model: MakeHuman/MPFB2 (CC0), animations: Quaternius Universal Animation Library (CC0),
## retargeted at import via SkeletonProfileHumanoid. Umbrella arm, slump, breathing and fists are
## procedural (walker_pose_modifier.gd) layered on top of the locomotion AnimationTree.

const PoseModifier := preload("res://assets/characters/walker/walker_pose_modifier.gd")
const HAIR_SHADER := preload("res://assets/characters/walker/walker_hair.gdshader")
const ANIMS := {
	&"walk": preload("res://assets/characters/walker/anim/walk.res"),
	&"jog": preload("res://assets/characters/walker/anim/jog.res"),
	&"idle": preload("res://assets/characters/walker/anim/idle.res"),
}

## The UAL jog is a long, deep-kneed stride; a full blend reads as a sprint/lunge. Running is a
## phase-locked walk/jog mix that tops out at this jog weight (a hurried office-worker trot).
@export_range(0.0, 1.0) var jog_blend_max := 0.5
## Ground distance (m) covered by one full gait cycle at jog weight 0, 0.25, 0.5, 0.75, 1.0.
## Measured on this skeleton with test/measure_blend.gd (planted-foot speed at 1 cycle/s).
const CYCLE_M := [1.39, 2.54, 3.69, 4.87, 5.81]
const SAD_STRIDE := 0.85
const MAX_RUN_CYCLE_M := 2.9  # shorter, shuffling steps when defeated

@onready var _model: Node3D = $Model
var _skel: Skeleton3D
var _tree: AnimationTree
var _mod: Node  # PoseModifier
var _grip_r: Node3D
var _grip_l: Node3D

var _speed := 0.0
var _run := 0.0
var _run_s := 0.0
var _stopped := false
var _stop_s := 0.0
var _breath_s := 0.0
var _mood: StringName = &"normal"
var _sad_s := 0.0
var _raise := 0.0
var _tilt := 0.0
var _droop := 0.0
var _wet := 0.0
var _t := 0.0

# material -> {base_color, base_rough, kind}
var _mats: Array[Dictionary] = []


func _ready() -> void:
	_build()


func _build() -> void:
	if _skel != null:
		return
	if _model == null:
		_model = $Model
	_skel = _model.find_child("GeneralSkeleton", true, false) as Skeleton3D

	# Locomotion tree: walk/jog normalised to a 1 s timeline and phase-locked (both start on a left
	# heel strike), so one TimeScale (= gait cycles per second) drives both with no foot drift.
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	var lib := AnimationLibrary.new()
	for k in ANIMS:
		lib.add_animation(k, ANIMS[k])
	_tree.add_animation_library(&"", lib)
	var bt := AnimationNodeBlendTree.new()
	var walk := _clip(&"walk", true)
	var jog := _clip(&"jog", true)
	var idle := _clip(&"idle", false)
	var run := AnimationNodeBlend2.new()
	run.sync = true
	var ts := AnimationNodeTimeScale.new()
	var stop := AnimationNodeBlend2.new()
	bt.add_node(&"walk", walk, Vector2(0, 0))
	bt.add_node(&"jog", jog, Vector2(0, 200))
	bt.add_node(&"run", run, Vector2(250, 100))
	bt.add_node(&"ts", ts, Vector2(450, 100))
	bt.add_node(&"idle", idle, Vector2(450, 300))
	bt.add_node(&"stop", stop, Vector2(650, 150))
	bt.connect_node(&"run", 0, &"walk")
	bt.connect_node(&"run", 1, &"jog")
	bt.connect_node(&"ts", 0, &"run")
	bt.connect_node(&"stop", 0, &"ts")
	bt.connect_node(&"stop", 1, &"idle")
	bt.connect_node(&"output", 0, &"stop")
	_tree.tree_root = bt
	add_child(_tree)
	_tree.root_node = _tree.get_path_to(_model)
	_tree.active = true

	_mod = PoseModifier.new()
	_mod.name = "PoseModifier"
	_skel.add_child(_mod)
	_mod.setup(_skel, ANIMS[&"idle"])
	var rel := Transform3D.IDENTITY
	var n: Node = _skel
	while n != self and n is Node3D:
		rel = (n as Node3D).transform * rel
		n = n.get_parent()
	_mod.char_from_skel = rel

	_grip_r = _make_grip(&"RightHand", _mod.grip_r_offset, "GripRight")
	_grip_l = _make_grip(&"LeftHand", _mod.grip_l_offset, "GripLeft")
	_setup_materials()
	_apply_params(0.0)


func _clip(anim: StringName, normalised: bool) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = anim
	if normalised:
		n.use_custom_timeline = true
		n.timeline_length = 1.0
		n.stretch_time_scale = true
		n.start_offset = 0.0
		n.loop_mode = Animation.LOOP_LINEAR
	return n


func _make_grip(bone: StringName, offset: Transform3D, grip_name: String) -> Node3D:
	var att := BoneAttachment3D.new()
	att.name = grip_name + "Bone"
	att.bone_name = bone
	_skel.add_child(att)
	var g := Node3D.new()
	g.name = grip_name
	g.transform = offset
	att.add_child(g)
	return g


func _setup_materials() -> void:
	for mi in _skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name).to_lower()
		if n.contains("teeth"):
			m.visible = false  # mouth is closed; avoids teeth poking through the lips
			continue
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var kind := "cloth"
			if n.contains("body"):
				kind = "skin"
			elif n.contains("short02"):
				kind = "hair"
			elif n.contains("eyebrow") or n.contains("eyelash"):
				kind = "lash"
			elif n.contains("high-poly"):
				kind = "eye"
			elif n.contains("shoes"):
				kind = "shoe"
			var mat: Material
			if kind == "hair":
				var sm := ShaderMaterial.new()
				sm.shader = HAIR_SHADER
				sm.set_shader_parameter(&"albedo_tex", src.albedo_texture)
				mat = sm
			else:
				var d := src.duplicate() as StandardMaterial3D
				d.cull_mode = BaseMaterial3D.CULL_BACK
				d.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				match kind:
					"lash":
						d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
						d.cull_mode = BaseMaterial3D.CULL_DISABLED
					"skin":
						d.roughness = 0.62
					"cloth":
						d.roughness = 0.88
						d.albedo_color = Color(0.92, 0.9, 0.86)
					"shoe":
						d.roughness = 0.35
					"eye":
						d.roughness = 0.1
				mat = d
			m.set_surface_override_material(s, mat)
			var base_c := Color.WHITE
			var base_r := 1.0
			if mat is StandardMaterial3D:
				base_c = (mat as StandardMaterial3D).albedo_color
				base_r = (mat as StandardMaterial3D).roughness
			_mats.append({"mat": mat, "kind": kind, "c": base_c, "r": base_r})
	_apply_wetness()


func _apply_wetness() -> void:
	for e in _mats:
		var mat: Material = e.mat
		var w := _wet
		match e.kind:
			"cloth":
				var sm := mat as StandardMaterial3D
				sm.albedo_color = (e.c as Color) * lerpf(1.0, 0.55, w)
				sm.roughness = lerpf(e.r, 0.76, w)
				sm.metallic_specular = lerpf(0.5, 0.52, w)
			"shoe":
				var sm := mat as StandardMaterial3D
				sm.albedo_color = (e.c as Color) * lerpf(1.0, 0.8, w)
				sm.roughness = lerpf(e.r, 0.12, w)
			"skin":
				var sm := mat as StandardMaterial3D
				sm.roughness = lerpf(e.r, 0.42, w)
				sm.metallic_specular = lerpf(0.5, 0.6, w)
			"hair":
				(mat as ShaderMaterial).set_shader_parameter(&"wetness", w)


func _process(delta: float) -> void:
	_apply_params(delta)


func _apply_params(delta: float) -> void:
	if _tree == null:
		return
	_t += delta
	var k_fast := 1.0 - exp(-delta * 8.0)
	var k_slow := 1.0 - exp(-delta * 3.0)
	_run_s = lerpf(_run_s, _run, k_fast) if delta > 0.0 else _run
	var idle_target := 1.0 if (_stopped or _speed < 0.05) else 0.0
	_stop_s = lerpf(_stop_s, idle_target, 1.0 - exp(-delta * 5.0)) if delta > 0.0 else idle_target
	var breath_target := 1.0 if _stopped else 0.0
	_breath_s = lerpf(_breath_s, breath_target, k_slow) if delta > 0.0 else breath_target
	var sad_target := 1.0 if _mood == &"sad" else 0.0
	_sad_s = lerpf(_sad_s, sad_target, k_slow) if delta > 0.0 else sad_target

	# Gait cycles per second so the planted foot moves at the ground speed (no skating).
	var jog_w := _run_s * jog_blend_max
	# The jog's natural stride is too long for our run speeds; past ~2.9 m/cycle we keep a believable
	# cadence instead and accept a little slide during the jog's very short ground contacts.
	var cycle_m := minf(cycle_length(jog_w), lerpf(1.39, MAX_RUN_CYCLE_M, _run_s))
	cycle_m *= lerpf(1.0, SAD_STRIDE, _sad_s * (1.0 - _run_s))
	var cps := maxf(_speed, 0.0) / cycle_m
	_tree.set(&"parameters/run/blend_amount", jog_w)
	_tree.set(&"parameters/ts/scale", cps)
	_tree.set(&"parameters/stop/blend_amount", _stop_s)

	_mod.raise = _raise
	_mod.tilt = _tilt
	_mod.droop = _droop
	_mod.sad = _sad_s * (1.0 - _run_s)
	_mod.breath = _breath_s
	_mod.time = _t


## Metres travelled per gait cycle for a given jog blend weight (linear table lookup).
static func cycle_length(jog_w: float) -> float:
	var x := clampf(jog_w, 0.0, 1.0) * (CYCLE_M.size() - 1)
	var i := mini(int(x), CYCLE_M.size() - 2)
	return lerpf(CYCLE_M[i], CYCLE_M[i + 1], x - i)


# --- Contract API (docs/CONTRACTS.md §1) ----------------------------------------------------------

func set_motion(speed_mps: float, run_amount: float) -> void:
	_speed = maxf(speed_mps, 0.0)
	_run = clampf(run_amount, 0.0, 1.0)


func set_stopped(stopped: bool) -> void:
	_stopped = stopped


func set_umbrella_pose(raise: float, tilt: float, droop: float) -> void:
	_raise = clampf(raise, 0.0, 1.0)
	_tilt = tilt
	_droop = clampf(droop, 0.0, 1.0)


func set_wetness(w: float) -> void:
	_wet = clampf(w, 0.0, 1.0)
	if not _mats.is_empty():
		_apply_wetness()


func set_mood(mood: StringName) -> void:
	_mood = mood


func get_grip(hand: StringName) -> Node3D:
	_build()
	return _grip_r if hand == &"right" else _grip_l
