extends RefCounted
## Shared mocap locomotion for the walker and the pedestrians.
## Clips: CMU Graphics Lab Motion Capture Database (free for any use), retargeted onto the MPFB
## skeleton by tools/mocap/build_clips.sh — relaxed walk (35_01), brisk walk (16_21), light jog
## (16_35), standing idle (77_02). All gait clips are in place, loop on one gait cycle and start
## on a left heel strike, so they are phase-locked on a normalised 1 s timeline.
##
## Tree: walk/brisk/jog -> BlendSpace1D "gait" (0 walk, .5 brisk, 1 jog; synced) -> TimeScale
## "ts" (gait cycles per second) -> Blend2 "stop" (1 = idle).

const ANIMS := {
	&"walk": preload("res://assets/characters/walker/anim/mocap/walk.res"),
	&"brisk": preload("res://assets/characters/walker/anim/mocap/brisk.res"),
	&"jog": preload("res://assets/characters/walker/anim/mocap/jog.res"),
	&"idle": preload("res://assets/characters/walker/anim/mocap/idle.res"),
}
## Natural ground speed (m/s, on the walker) of the walk, brisk and jog clips.
const GAIT_SPEED := [1.31, 1.80, 3.02]
## Ground distance (m) per gait cycle at gait position 0, .25, .5, .75, 1 on the walker
## (hips height REF_HIPS). Measured with assets/characters/walker/test/measure_blend.gd.
const CYCLE_M := [1.3, 1.47, 1.62, 1.81, 2.24]
const REF_HIPS := 0.9728


static func build_tree(model: Node3D, parent: Node) -> AnimationTree:
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	var lib := AnimationLibrary.new()
	for k in ANIMS:
		lib.add_animation(k, ANIMS[k])
	tree.add_animation_library(&"", lib)
	var bt := AnimationNodeBlendTree.new()
	var gait := AnimationNodeBlendSpace1D.new()
	gait.min_space = 0.0
	gait.max_space = 1.0
	gait.sync = true
	gait.add_blend_point(_clip(&"walk", true), 0.0, -1, &"walk")
	gait.add_blend_point(_clip(&"brisk", true), 0.5, -1, &"brisk")
	gait.add_blend_point(_clip(&"jog", true), 1.0, -1, &"jog")
	bt.add_node(&"gait", gait, Vector2(200, 100))
	bt.add_node(&"ts", AnimationNodeTimeScale.new(), Vector2(450, 100))
	bt.add_node(&"idle", _clip(&"idle", false), Vector2(450, 300))
	bt.add_node(&"stop", AnimationNodeBlend2.new(), Vector2(650, 150))
	bt.connect_node(&"ts", 0, &"gait")
	bt.connect_node(&"stop", 0, &"ts")
	bt.connect_node(&"stop", 1, &"idle")
	bt.connect_node(&"output", 0, &"stop")
	tree.tree_root = bt
	parent.add_child(tree)
	tree.root_node = tree.get_path_to(model)
	tree.active = true
	return tree


static func _clip(anim: StringName, normalised: bool) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = anim
	if normalised:
		n.use_custom_timeline = true
		n.timeline_length = 1.0
		n.stretch_time_scale = true
		n.start_offset = 0.0
		n.loop_mode = Animation.LOOP_LINEAR
	return n


## Gait blend position (0 walk .. 1 jog) whose natural speed matches `speed` (m/s, walker scale).
static func gait_for_speed(speed: float) -> float:
	if speed <= GAIT_SPEED[0]:
		return 0.0
	if speed <= GAIT_SPEED[1]:
		return 0.5 * (speed - GAIT_SPEED[0]) / (GAIT_SPEED[1] - GAIT_SPEED[0])
	return clampf(0.5 + 0.5 * (speed - GAIT_SPEED[1]) / (GAIT_SPEED[2] - GAIT_SPEED[1]), 0.5, 1.0)


## Metres per gait cycle at gait position `g` (walker scale).
static func cycle_length(g: float) -> float:
	var x := clampf(g, 0.0, 1.0) * (CYCLE_M.size() - 1)
	var i := mini(int(x), CYCLE_M.size() - 2)
	return lerpf(CYCLE_M[i], CYCLE_M[i + 1], x - i)


## Stride shortening for slow walking (< ~1.2 m/s): a slower person takes shorter steps rather
## than the same stride in slow motion. 1 = the clip's stride.
static func slow_stride(speed: float) -> float:
	return clampf(lerpf(0.8, 1.0, (speed - 0.5) / 0.6), 0.8, 1.0)


static func set_params(tree: AnimationTree, gait: float, cycles_per_s: float, stop: float) -> void:
	tree.set(&"parameters/gait/blend_position", gait)
	tree.set(&"parameters/ts/scale", cycles_per_s)
	tree.set(&"parameters/stop/blend_amount", stop)
