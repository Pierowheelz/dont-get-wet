class_name RaincoatFigure
extends Node3D
## A man in a yellow fisherman's slicker, hood up and buttoned down the front, over the walker's grey
## trousers and shoes, with a furled umbrella hanging from his fist like a cane. Built on the walker's
## own model and locomotion and dressed by assets/characters/walker/source/build_slicker.py.
## Rain never wets him. Scenery only: no collider and nothing the rain model sees; whoever places him
## moves him, or lets him walk himself.
##   facing   +1 faces +x, -1 faces -x; the umbrella is always in the camera-side hand
##   pose     STAND, WATCH (turned three-quarters toward the street), WALK (at walk_speed)

enum Pose { STAND, WATCH, WALK }

const OUTFIT := "res://assets/characters/walker/slicker.glb"
const SUIT := "res://assets/characters/walker/slicker_suit.webp"
const PARTS := ["slicker_skirt", "slicker_hood", "slicker_flap", "slicker_buttons", "slicker_cords"]
const WATCH_TURN := 0.75     # rad turned from his facing toward the camera while he watches
const TURN_RATE := 2.5       # rad/s
const CANOPY := Color(0.07, 0.07, 0.08)
const CANE_LEAN := 0.18      # rad the furled umbrella's tip leans ahead of straight down

@export var facing := 1:
	set(v):
		v = -1 if v < 0 else 1
		if v == facing:
			return
		facing = v
		if model:
			_build()
@export var pose := Pose.STAND
## WALK: move along x at walk_speed in his facing (off: the owner moves the node).
@export var advance := true
@export var walk_speed := 1.25
## Optional: a Level, for the ground height as he walks.
var level: Node

var model: Node3D            # walker.gd: set_motion, get_grip ...
var umbrella: Umbrella
var fill: OmniLight3D        # a soft cool fill from the camera side, so the yellow reads in the dark
var _grip: Node3D
var _yaw := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	if model:
		model.free()
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
	umbrella = Umbrella.new()
	umbrella.canopy_color = CANOPY
	_grip = model.call("get_grip", &"right")
	_grip.add_child(umbrella)
	umbrella._body.collision_layer = 0
	umbrella.set_state(0.0, Game.umbrella_radius(0), 0.0)
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


func _process(delta: float) -> void:
	var walking := pose == Pose.WALK
	model.call("set_motion", walk_speed if walking else 0.0, 0.0)
	if walking and advance:
		position.x += facing * walk_speed * delta
		if level and level.has_method("ground_y"):
			position.y = level.ground_y(position.x)
	_yaw = move_toward(_yaw, _target_yaw(), TURN_RATE * delta)
	model.rotation.y = _yaw
	# Furled, it hangs from the fist like a cane, tip down and a little ahead (as the follower's does).
	umbrella.basis = _grip.global_basis.orthonormalized().inverse() * Basis(Vector3(0, 0, 1), PI + CANE_LEAN * facing)


## Facing +x is no turn; -x a half turn. Watching, he turns toward the camera (+z) from there.
func _target_yaw() -> float:
	var yaw := 0.0 if facing > 0 else PI
	if pose == Pose.WATCH:
		yaw -= facing * WATCH_TURN
	return yaw


## The level's `slickers`: [{x, z, facing, pose}], scenery standing where the plan puts them.
static func place_all(lvl: Node) -> void:
	for d in lvl.data.get("slickers", []):
		var fig := RaincoatFigure.new()
		fig.name = "RaincoatFigure"
		fig.level = lvl
		var x := float(d["x"])
		fig.pose = {"stand": Pose.STAND, "watch": Pose.WATCH, "walk": Pose.WALK}.get(String(d.get("pose", "stand")), Pose.STAND)
		fig.facing = int(d.get("facing", 1))
		fig.position = Vector3(x, lvl.ground_y(x), float(d.get("z", 0.8)))
		lvl.add_child(fig)
	place_debug(lvl)


## Screenshot aid (never in a level file): `--slicker=X[,stand|watch|walk[,1|-1[,Z]]]` places one
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
		fig.position = Vector3(x, lvl.ground_y(x), float(f[3]) if f.size() > 3 else 0.8)
		lvl.add_child(fig)
		if first == null:
			first = fig
	if first and OS.get_cmdline_user_args().has("--slicker-close"):
		var cam := Camera3D.new()
		cam.fov = 30.0
		first.add_child(cam)
		cam.position = Vector3(0.0, 1.0, 4.4)
		cam.make_current.call_deferred()
