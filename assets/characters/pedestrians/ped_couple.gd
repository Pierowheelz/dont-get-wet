extends Node3D
## Two pedestrians sharing one umbrella (he holds it between them). Same contract as ped.gd.

@export var kind: StringName = &"walker"
@export var suggested_speed := 1.1


func setup(seed: int) -> void:
	$Him.setup(seed)
	$Her.setup(seed * 7919 + 13)


func set_walking(speed_mps: float) -> void:
	$Him.set_walking(speed_mps)
	$Her.set_walking(speed_mps)
