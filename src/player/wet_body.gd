class_name WetBody
extends Node3D
## Anything water can wet: the walker, and every NPC a shot can soak. A body stands with its feet at
## its origin, facing its local +X, and is measured on the same weighted SAMPLES wherever water
## lands on it (rain, streams and sheets for the walker; the droplets of a DropletBurst for every
## body). Each body has its own wetness, out of wet_max(); its canopy, if it holds one open, is a
## collider on canopy_mask(), and stops droplets flown at it. A weatherproof body is wet only by
## shots. When a body is soaked it gives up the same way every time: drops its umbrella and trudges
## off the left of the screen (_give_up, then _trudge each frame).

const GROUP := &"wet_bodies"

## Body sample points (local, facing +X) and their weights for exposure, to rain, streams, washes and
## the droplets of a splash or shot alike. Nothing below the knees: no umbrella can cover the shins.
const SAMPLES := [
	[Vector3(0.0, 1.74, 0.0), 2.0],     # head
	[Vector3(0.02, 1.5, 0.19), 1.4],    # shoulders
	[Vector3(0.02, 1.5, -0.19), 1.4],
	[Vector3(0.13, 1.22, 0.0), 1.0],    # chest
	[Vector3(-0.13, 1.22, 0.0), 1.0],   # back
	[Vector3(0.0, 0.95, 0.12), 0.8],    # hips
	[Vector3(0.12, 0.55, 0.0), 0.6],    # knees
	[Vector3(-0.1, 0.55, 0.0), 0.5],
]

const GIVE_UP_PAUSE := 0.9         # s he stands, dropping the umbrella, before he turns to trudge off
const TRUDGE_SPEED := 0.75

var level: Node
var wet := 0.0
var weatherproof := false          # only shots wet it: rain, gutters and splashes never do
var visual: Node3D                 # the walker model (walker.gd contract)
var umbrella: Umbrella
var speed := 0.0
var _dropped_umbrella := false
var _end_t := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func wet_max() -> float:
	return Tun.f("wet_max")


## Water can still reach it (it isn't already beaten or gone).
func wettable() -> bool:
	return true


## Adds `amount` of wetness from `cause` (&"shot", &"splash", ...). Bodies decide what a full soak does.
func soak(amount: float, _cause: StringName) -> void:
	wet = minf(wet + amount, wet_max())


## The physics layer its own canopy is on (0 while it has none up).
func canopy_mask() -> int:
	if umbrella == null or _dropped_umbrella:
		return 0
	return umbrella.layer


## A sample point (local) as the body holds itself right now; the walker leans his while he opens
## the umbrella. Unposed by default.
func pose_sample(local: Vector3) -> Vector3:
	return local


func sample_world(local: Vector3) -> Vector3:
	return global_transform * pose_sample(local)


## The body samples in world space: [position, weight] for each of SAMPLES.
func body_samples() -> Array:
	var out := []
	for s in SAMPLES:
		out.append([sample_world(s[0]), s[1]])
	return out


## Unit vector across the street from the body (its side-on plane is the one this is normal to).
func across() -> Vector3:
	return global_basis.z.normalized()


## The bodies of `level`, in the tree now.
static func of_level(lv: Node) -> Array:
	return lv.get_tree().get_nodes_in_group(GROUP).filter(func(b: Node) -> bool: return b.level == lv)


## Soaked: sad face, umbrella dropped half-folded at his feet. _trudge then walks him off the left.
func _give_up() -> void:
	visual.call("set_mood", &"sad")
	_dropped_umbrella = true
	var start := umbrella.global_transform
	umbrella.top_level = true
	umbrella.global_transform = start
	var land := Transform3D(Basis.from_euler(Vector3(0.2, randf() * TAU, PI * 0.55)),
		Vector3(start.origin.x + 0.25, level.ground_y(start.origin.x) + 0.1, start.origin.z + 0.3))
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		umbrella.global_transform = start.interpolate_with(land, t), 0.0, 1.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	umbrella.set_state(0.5, umbrella.radius, 0.0)
	_end_t = 0.0


## One frame of the walk off after _give_up: he stops, turns round and trudges off to the left.
func _trudge(delta: float) -> void:
	_end_t += delta
	if _end_t < GIVE_UP_PAUSE:
		speed = move_toward(speed, 0.0, 3.0 * delta)
	else:
		rotation.y = move_toward(rotation.y, PI, 4.0 * delta)
		speed = move_toward(speed, TRUDGE_SPEED, 1.5 * delta)
		position.x -= speed * delta
	position.y = level.ground_y(position.x)
