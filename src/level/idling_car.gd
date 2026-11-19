extends Node3D
## The `idling_sedan` prop: a black sedan stopped nose-out in a side street, engine running. Wipers sweep,
## exhaust curls from the tailpipe, parking lights glow and a hat sits behind the wheel. It never
## moves and has no gameplay effect. Built from the car_sedan kit model (faces +X, origin at the
## ground centre); the local positions below are measured off that model.

const MODEL := "res://assets/props/car_sedan.glb"
const PAINT := "res://assets/materials/car_paint_black.tres"
const SCREEN_BASE := Vector3(0.87, 1.0, 0.0)      # bottom edge of the windscreen
const SCREEN_UP := Vector3(-0.757, 0.654, 0.0)    # up the glass
const WIPER_ZS := [-0.5, 0.12]
const WIPER_LEN := 0.44
const WIPE_S := 1.3                                # one sweep and back
const DRIVER := Vector3(-0.05, 0.0, -0.38)         # seat under the steering wheel (the far side)

var _wipers: Array[Node3D] = []
var _t := 0.0


func _ready() -> void:
	var car: Node3D = load(MODEL).instantiate() if ResourceLoader.exists(MODEL) else CarHazard.greybox_car()
	add_child(car)
	var meshes := car.find_children("*", "MeshInstance3D", true, false)
	var body: MeshInstance3D = meshes[0] if not meshes.is_empty() else null
	if body and body.mesh and body.mesh.get_surface_count() > 7:
		if ResourceLoader.exists(PAINT):
			body.set_surface_override_material(0, load(PAINT))
		var glass := StandardMaterial3D.new()   # see-through enough to show the man at the wheel
		glass.albedo_color = Color(0.05, 0.06, 0.08, 0.42)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.05
		glass.metallic = 0.4
		body.set_surface_override_material(2, glass)
		var tail := StandardMaterial3D.new()
		tail.albedo_color = Color(0.7, 0.05, 0.04)
		tail.emission_enabled = true
		tail.emission = Color(1.0, 0.08, 0.05)
		tail.emission_energy_multiplier = 1.6
		body.set_surface_override_material(7, tail)
		# At night the mirror chrome has only black sky to reflect, which left the hubcaps and bumpers
		# black and each wheel a bare whitewall ring: a duller chrome that takes the street's light,
		# and the whitewalls knocked back to match it.
		var chrome := StandardMaterial3D.new()
		chrome.albedo_color = Color(0.74, 0.76, 0.8)
		chrome.metallic = 0.7
		chrome.roughness = 0.32
		body.set_surface_override_material(3, chrome)
		var whitewall := StandardMaterial3D.new()
		whitewall.albedo_color = Color(0.4, 0.4, 0.38)
		whitewall.roughness = 0.6
		body.set_surface_override_material(8, whitewall)
	_driver()
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.4, 0.41, 0.43)   # the arms' chrome catches the light as they sweep
	rubber.metallic = 0.8
	rubber.roughness = 0.3
	for z in WIPER_ZS:
		var pivot := Node3D.new()
		pivot.position = SCREEN_BASE + Vector3(0.0, 0.0, z)
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(WIPER_LEN, 0.025, 0.03)
		arm.mesh = bm
		arm.material_override = rubber
		arm.position = Vector3(WIPER_LEN * 0.5, 0.02, 0.0)
		pivot.add_child(arm)
		add_child(pivot)
		_wipers.append(pivot)
	add_child(_exhaust())
	for side in [-0.62, 0.62]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.9, 0.7)
		sl.light_energy = 1.6
		sl.spot_range = 9.0
		sl.spot_angle = 26.0
		sl.light_volumetric_fog_energy = 2.0
		sl.position = Vector3(2.75, 0.66, side)
		sl.rotation = Vector3(0, -PI * 0.5, 0)
		sl.rotation.z = -0.08
		add_child(sl)
	var lamp := OmniLight3D.new()   # the street's light catching the wet roof, so the black car has a shape
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 2.2
	lamp.omni_range = 4.5
	lamp.omni_attenuation = 1.2
	lamp.light_volumetric_fog_energy = 0.0
	lamp.position = Vector3(0.6, 2.8, -1.4)
	add_child(lamp)
	var dash := OmniLight3D.new()   # the dashboard's glow lights the hat from below, so it reads through the glass
	dash.light_color = Color(1.0, 0.75, 0.45)
	dash.light_energy = 2.5
	dash.omni_range = 1.3
	dash.position = Vector3(0.45, 1.0, DRIVER.z)
	add_child(dash)


## A man's head and shoulders in a dark coat, and a fedora: a silhouette, never a face.
func _driver() -> void:
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.05, 0.05, 0.06)
	coat.roughness = 0.8
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.2, 0.18, 0.16)
	felt.roughness = 0.9
	var parts := [
		[_capsule(0.21, 0.5), Vector3(0.0, 0.92, 0.0), coat],
		[_sphere(0.1), Vector3(0.02, 1.14, 0.0), coat],
		[_cyl(0.2, 0.2, 0.018), Vector3(0.02, 1.215, 0.0), felt],
		[_cyl(0.105, 0.115, 0.11), Vector3(0.02, 1.28, 0.0), felt],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[2]
		mi.position = DRIVER + p[1]
		add_child(mi)


static func _capsule(r: float, h: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


static func _sphere(r: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.2
	return m


static func _cyl(r0: float, r1: float, h: float) -> Mesh:
	var m := CylinderMesh.new()
	m.bottom_radius = r0
	m.top_radius = r1
	m.height = h
	return m


func _exhaust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.4
	p.position = Vector3(-2.8, 0.28, -0.55)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1.0, 0.25, 0.0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.0, 0.18, 0.0)
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.55))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.42)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.64, 0.68, 0.32)
	m.albedo_texture = CarHazard._droplet_tex()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-4, -1, -2), Vector3(5, 4, 4))
	return p


func _process(delta: float) -> void:
	_t += delta
	# Both blades sweep together, from lying along the bottom of the glass up and back.
	var phase := 0.5 - 0.5 * cos(TAU * _t / WIPE_S)
	var ang := lerpf(0.08, 1.75, phase)
	var normal := Vector3(0.654, 0.757, 0.0)
	var dir := Vector3.BACK * cos(ang) + SCREEN_UP * sin(ang)
	var b := Basis(dir, normal, dir.cross(normal)).orthonormalized()
	for w in _wipers:
		w.basis = b
