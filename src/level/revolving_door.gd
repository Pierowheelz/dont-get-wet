extends Node3D
## The `revolving_door` prop: a hotel's glass drum set into the facade at x, its four leaves turning
## slowly, a brass canopy disc on top and warm light inside. Dressing only: no collider, nothing the
## rain model sees.

const R := 0.95
const H := 2.35
const Z := 0.25               # the drum's centre: half in the building, half out on the pavement
const TURN := 0.45            # rad/s

var _leaves: Node3D


func _ready() -> void:
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.6, 0.3)
	brass.metallic = 0.9
	brass.roughness = 0.25
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.85, 0.9, 0.26)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.04
	glass.metallic_specular = 1.0
	glass.rim_enabled = true
	glass.rim = 0.5
	for y in [0.03, H + 0.09]:
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = R + 0.08
		cm.bottom_radius = R + 0.08
		cm.height = 0.06 if y < 1.0 else 0.18
		cm.radial_segments = 32
		disc.mesh = cm
		disc.material_override = brass
		disc.position = Vector3(0.0, y, Z)
		add_child(disc)
	for side in [-1.0, 1.0]:   # the jambs where the drum meets the facade line, so its outline reads
		var jamb := MeshInstance3D.new()
		var jm := CylinderMesh.new()
		jm.top_radius = 0.04
		jm.bottom_radius = 0.04
		jm.height = H
		jamb.mesh = jm
		jamb.material_override = brass
		jamb.position = Vector3(side * R, H * 0.5 + 0.06, Z)
		add_child(jamb)
	var shell := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = R
	sm.bottom_radius = R
	sm.height = H
	sm.cap_top = false
	sm.cap_bottom = false
	sm.radial_segments = 32
	shell.mesh = sm
	shell.material_override = glass
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = Vector3(0.0, H * 0.5 + 0.06, Z)
	add_child(shell)
	_leaves = Node3D.new()
	_leaves.position = Vector3(0.0, 0.06, Z)
	add_child(_leaves)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.05
	pm.height = H
	post.mesh = pm
	post.material_override = brass
	post.position.y = H * 0.5
	_leaves.add_child(post)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.y = TAU * i / 4.0
		_leaves.add_child(arm)
		var pane := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(R - 0.08, H - 0.12, 0.025)
		pane.mesh = bm
		pane.material_override = glass
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pane.position = Vector3((R - 0.08) * 0.5 + 0.03, H * 0.5, 0.0)
		arm.add_child(pane)
		for y in [0.08, H - 0.08]:
			var rail := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(R - 0.06, 0.05, 0.04)
			rail.mesh = rm
			rail.material_override = brass
			rail.position = Vector3((R - 0.06) * 0.5 + 0.03, y, 0.0)
			arm.add_child(rail)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.52)
	lamp.light_energy = 1.6
	lamp.omni_range = 2.8
	lamp.light_volumetric_fog_energy = 0.0
	lamp.position = Vector3(0.0, H - 0.3, Z)
	add_child(lamp)


func _process(delta: float) -> void:
	_leaves.rotation.y += TURN * delta
