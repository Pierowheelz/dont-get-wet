class_name RaincoatFigure
extends Node3D
## A man in a yellow fisherman's slicker, hood up and buttoned down the front, over the walker's grey
## trousers and shoes, with a furled umbrella carried at the hip like a rifle, tip forward. Built on the
## walker's own model and locomotion and dressed by assets/characters/walker/source/build_slicker.py.
## Rain never wets him. Scenery only: no collider and nothing the rain model sees; whoever places him
## moves him, or lets him walk himself.
##   facing   +1 faces +x, -1 faces -x; the umbrella is always in the camera-side hand
##   pose     STAND, WATCH (turned three-quarters toward the street), WALK (at walk_speed)
##   smoking  a cigarette at his lips: a slow ember and a thin wisp of smoke

enum Pose { STAND, WATCH, WALK }

const OUTFIT := "res://assets/characters/walker/slicker.glb"
const SUIT := "res://assets/characters/walker/slicker_suit.webp"
const PARTS := ["slicker_skirt", "slicker_hood", "slicker_flap", "slicker_buttons", "slicker_cords"]
const WATCH_TURN := 0.75     # rad turned from his facing toward the camera while he watches
const TURN_RATE := 2.5       # rad/s
const CANOPY := Color(0.07, 0.07, 0.08)
# The cigarette, in the walker model's glTF space (+Z forward, +X his left): the left corner of the
# lips, pointing forward, down and a little out.
const MOUTH := Vector3(0.024, 1.606, 0.146)
const CIG_DIR := Vector3(0.3, -0.45, 1.0)
const CIG_LEN := 0.06
const DRAG_EVERY := Vector2(4.0, 8.0)   # s between drags on it
const WISP_SHADER := preload("res://src/fx/smoke_wisp.gdshader")
const WISP_SIZE := Vector2(0.3, 0.55)   # m: the quad the thread of smoke is drawn on
const WISP_TRAIL := 0.8                 # quad half widths the thread leans back while he walks

@export var facing := 1:
	set(v):
		v = -1 if v < 0 else 1
		if v == facing:
			return
		facing = v
		if model:
			_build()
@export var pose := Pose.STAND
@export var smoking := false:
	set(v):
		smoking = v
		if _cig:
			_cig.visible = v
			_smoke.visible = v
## WALK: move along x at walk_speed in his facing (off: the owner moves the node).
@export var advance := true
@export var walk_speed := 1.25
## Optional: a Level, for the ground height as he walks.
var level: Node

var model: Node3D            # walker.gd: set_motion, set_carry, get_grip ...
var umbrella: Umbrella
var fill: OmniLight3D        # a soft cool fill from the camera side, so the yellow reads in the dark
var _cig: Node3D
var _ember_mat: StandardMaterial3D
var _smoke: MeshInstance3D
var _wisp: ShaderMaterial
var _trail := 0.0             # how far the smoke leans back from the way he walks
var _yaw := 0.0
var _drag_in := 2.0
var _drag := 0.0
var _drag_t := -1.0


func _ready() -> void:
	_build()


func _build() -> void:
	if model:
		model.free()
		_cig = null
	model = (load(Player.CHARACTER_SCENE) as PackedScene).instantiate()
	model.set("umbrella_left", facing < 0)   # the camera is on his right while he faces +x
	add_child(model)
	_dress()
	if fill == null:
		fill = OmniLight3D.new()
		fill.light_color = Color(0.85, 0.9, 1.0)
		fill.light_energy = 0.22
		fill.omni_range = 2.2
		fill.omni_attenuation = 1.5
		fill.light_specular = 0.25
		add_child(fill)
	fill.position = Vector3(0.3 * facing, 1.3, 1.0)
	model.call("set_carry", 1.0)
	umbrella = Umbrella.new()
	umbrella.canopy_color = CANOPY
	# Grip +Y runs along the shaft to the tip; turned over so the crook hangs below the fist.
	umbrella.basis = Basis(Vector3.UP, PI)
	(model.call("get_grip", &"right") as Node3D).add_child(umbrella)
	umbrella._body.collision_layer = 0
	umbrella.set_state(0.0, Game.umbrella_radius(0), 0.0)
	_build_cigarette()
	_yaw = _target_yaw()
	model.rotation.y = _yaw


## Materials and added meshes only, never a reshaped body: the walker's suit dyed slicker yellow over
## his grey trousers, and the skirt, hood and buttons skinned to his skeleton.
func _dress() -> void:
	var skel := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var outfit := (load(OUTFIT) as PackedScene).instantiate()
	for part in PARTS:
		var mi := outfit.find_child(part, true, false) as MeshInstance3D
		mi.owner = null
		mi.reparent(skel, false)
	outfit.free()
	var suit := StandardMaterial3D.new()
	suit.albedo_texture = load(SUIT)
	suit.roughness_texture = suit.albedo_texture   # alpha: glossy oilskin, matte trousers
	suit.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	for m in skel.find_children("*", "MeshInstance3D", true, false):
		if String(m.name).to_lower().contains("elegantsuit"):
			(m as MeshInstance3D).set_surface_override_material(0, suit)


func _build_cigarette() -> void:
	var skel := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var glb_root := model.get_node("Model") as Node3D
	var glb_from_skel := Transform3D.IDENTITY
	var n: Node = skel
	while n != glb_root:
		glb_from_skel = (n as Node3D).transform * glb_from_skel
		n = n.get_parent()
	var head := skel.find_bone("Head")
	var along := CIG_DIR.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var at_lips := Transform3D(Basis(along, side.cross(along), side), MOUTH)   # +X along the cigarette
	var att := BoneAttachment3D.new()
	att.bone_name = &"Head"
	skel.add_child(att)
	_cig = Node3D.new()
	_cig.transform = skel.get_bone_global_rest(head).affine_inverse() * glb_from_skel.affine_inverse() * at_lips
	att.add_child(_cig)

	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0038
	cm.bottom_radius = 0.0038
	cm.height = CIG_LEN
	cm.radial_segments = 6
	cm.rings = 1
	stick.mesh = cm
	stick.rotation.z = -PI * 0.5   # cylinder +Y onto +X
	stick.position.x = CIG_LEN * 0.5 - 0.006
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.93, 0.91, 0.86)
	paper.roughness = 0.8
	stick.material_override = paper
	_cig.add_child(stick)

	var ember := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0048
	sm.height = 0.0096
	sm.radial_segments = 8
	sm.rings = 4
	ember.mesh = sm
	ember.position.x = CIG_LEN - 0.006
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.albedo_color = Color(1.0, 0.32, 0.08)
	_ember_mat.emission_enabled = true
	_ember_mat.emission = Color(1.0, 0.3, 0.05)
	ember.material_override = _ember_mat
	_cig.add_child(ember)

	# One thread of smoke: an upright quad from the ember up (smoke_wisp.gdshader), kept square to the
	# street whichever way his head turns (see _process).
	_smoke = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = WISP_SIZE
	quad.center_offset = Vector3(0.0, WISP_SIZE.y * 0.5, 0.0)
	_smoke.mesh = quad
	_wisp = ShaderMaterial.new()
	_wisp.shader = WISP_SHADER
	_smoke.material_override = _wisp
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.top_level = true
	ember.add_child(_smoke)
	_cig.visible = smoking
	_smoke.visible = smoking
	_set_ember(0.0)


func _process(delta: float) -> void:
	var walking := pose == Pose.WALK
	model.call("set_motion", walk_speed if walking else 0.0, 0.0)
	if _smoke:
		# Walking, he leaves it behind him: the thread leans back.
		_trail = move_toward(_trail, -facing * WISP_TRAIL if walking else 0.0, delta * 2.0)
		_wisp.set_shader_parameter(&"drift", _trail)
		_smoke.global_transform = Transform3D(Basis.IDENTITY, (_smoke.get_parent() as Node3D).global_position)
	if walking and advance:
		position.x += facing * walk_speed * delta
		if level and level.has_method("ground_y"):
			position.y = level.ground_y(position.x)
	_yaw = move_toward(_yaw, _target_yaw(), TURN_RATE * delta)
	model.rotation.y = _yaw
	if smoking:
		_smoulder(delta)


## Facing +x is no turn; -x a half turn. Watching, he turns toward the camera (+z) from there.
func _target_yaw() -> float:
	var yaw := 0.0 if facing > 0 else PI
	if pose == Pose.WATCH:
		yaw -= facing * WATCH_TURN
	return yaw


## Now and then a drag: the ember brightens over half a second and dies back.
func _smoulder(delta: float) -> void:
	_drag_in -= delta
	if _drag_in <= 0.0:
		_drag_in = randf_range(DRAG_EVERY.x, DRAG_EVERY.y)
		_drag_t = 0.0
	if _drag_t >= 0.0:
		_drag_t += delta
		_drag = smoothstep(0.0, 0.5, _drag_t) * (1.0 - smoothstep(0.6, 2.0, _drag_t))
		if _drag_t > 2.0:
			_drag_t = -1.0
	_set_ember(_drag + 0.08 * sin(Time.get_ticks_msec() * 0.006))


func _set_ember(glow: float) -> void:
	_ember_mat.emission_energy_multiplier = 1.0 + 2.5 * glow


## The level's `slickers`: [{x, z, facing, pose, smoking}], scenery standing where the plan puts them.
static func place_all(lvl: Node) -> void:
	for d in lvl.data.get("slickers", []):
		var fig := RaincoatFigure.new()
		fig.name = "RaincoatFigure"
		fig.level = lvl
		var x := float(d["x"])
		fig.pose = {"stand": Pose.STAND, "watch": Pose.WATCH, "walk": Pose.WALK}.get(String(d.get("pose", "stand")), Pose.STAND)
		fig.facing = int(d.get("facing", 1))
		fig.smoking = bool(d.get("smoking", false))
		fig.position = Vector3(x, lvl.ground_y(x), float(d.get("z", 0.8)))
		lvl.add_child(fig)
	place_debug(lvl)


## Screenshot aid (never in a level file): `--slicker=X[,stand|watch|walk[,1|-1[,smoke[,Z]]]]` places one
## on the street at x X (default lane z 0.8); `--slicker-close` frames the first one with a close camera.
static func place_debug(lvl: Node) -> void:
	var first: RaincoatFigure
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--slicker="):
			continue
		var f: PackedStringArray = a.substr(10).split(",")
		var fig := RaincoatFigure.new()
		fig.name = "RaincoatFigure"
		fig.level = lvl
		var x := float(f[0])
		if f.size() > 1:
			fig.pose = {"stand": Pose.STAND, "watch": Pose.WATCH, "walk": Pose.WALK}.get(f[1], Pose.STAND)
		if f.size() > 2:
			fig.facing = int(f[2])
		fig.smoking = f.size() > 3 and f[3] == "smoke"
		fig.position = Vector3(x, lvl.ground_y(x), float(f[4]) if f.size() > 4 else 0.8)
		lvl.add_child(fig)
		if first == null:
			first = fig
	if first and OS.get_cmdline_user_args().has("--slicker-close"):
		var cam := Camera3D.new()
		cam.fov = 30.0
		first.add_child(cam)
		cam.position = Vector3(0.0, 1.0, 4.4)
		cam.make_current.call_deferred()
