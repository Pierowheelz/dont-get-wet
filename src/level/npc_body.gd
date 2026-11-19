class_name NpcBody
extends WetBody
## An NPC water can soak: the walker's own model in the grey suit under the same black umbrella.
## The umbrella's collider is on Umbrella.NPC_UMBRELLA_LAYER, so it stops shots flown at him but
## never the rain on the walker. His suit darkens as he gets wet. Whoever owns him moves him and
## poses `visual` and `umbrella` until he is soaked; then he leaves his owner (`soaked` fires), gives
## up as the walker does (WetBody._give_up), trudges off the left and is freed once out of shot.
## Out of sight (hidden) he can't be wet.

signal soaked

const OFF_LEFT := 12.0        # metres left of the camera that put him out of shot for good
const GONE_AFTER_S := 20.0

var grip: Node3D


func _ready() -> void:
	visual = (load(Player.CHARACTER_SCENE) as PackedScene).instantiate()
	add_child(visual)
	visual.call("set_wetness", 0.0)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.7
	fill.omni_range = 3.0
	fill.omni_attenuation = 1.5
	fill.position = Vector3(0.35, 1.15, 1.0)
	fill.light_specular = 0.3
	add_child(fill)
	grip = visual.call("get_grip", &"right")
	umbrella = Umbrella.new()     # the walker's own, so he reads as his double
	umbrella.layer = Umbrella.NPC_UMBRELLA_LAYER
	grip.add_child(umbrella)
	set_process(false)


func wettable() -> bool:
	return wet < wet_max() and is_visible_in_tree()


func soak(amount: float, cause: StringName) -> void:
	if not wettable():
		return
	super.soak(amount, cause)
	visual.call("set_wetness", wet / wet_max())
	if wet >= wet_max():
		_soaked.call_deferred()   # bursts call this mid physics step: leave the tree after it


## Leaves his owner (keeping where he stands) and walks off on his own.
func _soaked() -> void:
	reparent(level)
	_give_up()
	visual.call("set_umbrella_pose", 0.0, 0.0, 0.0)
	visual.call("set_umbrella_open", 0.0)
	set_process(true)
	soaked.emit()


func _process(delta: float) -> void:
	_trudge(delta)
	visual.call("set_motion", speed, 0.0)
	visual.call("set_stopped", speed < 0.05)
	var cam: Camera3D = level.camera
	if _end_t > GONE_AFTER_S or (cam and global_position.x < cam.global_position.x - OFF_LEFT):
		umbrella.reparent(level)   # it stays lying where he dropped it
		queue_free()
