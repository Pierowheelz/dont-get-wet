extends Node3D
## What moves on the viaducts: each span's train, its headlight, the sheet of water it shakes off
## the deck, the rumble and the camera shake. Every frame is drawn from Viaduct's pure functions of
## the level clock, so what you see and hear is exactly what Level.wash_at says gameplay does.

const SEG := 0.25                   # sheet segment width
const SHEET_ZS := [1.15, 2.05]      # behind and in front of the walker's line
const SOUND_LEAD := 2.4             # train_pass peaks this far into the file
const SHAKE := 0.035

var level: Node
var _spans: Array = []              # per viaduct: {v, train, sheets, mat, splash, floor, cycle}
var _pass: AudioStreamPlayer
var _extra := 0.0                   # visuals keep running after the gameplay clock stops
var _last_elapsed := -1.0


func _ready() -> void:
	_pass = AudioStreamPlayer.new()
	_pass.bus = &"SFX"
	if ResourceLoader.exists("res://assets/audio/train_pass.ogg"):
		_pass.stream = load("res://assets/audio/train_pass.ogg")
	add_child(_pass)
	var quad := QuadMesh.new()
	quad.size = Vector2(SEG + 0.02, 1.0)
	for v: Viaduct in level.viaducts:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://src/fx/wash_sheet.gdshader")
		mat.set_shader_parameter("top_y", Viaduct.DECK_Y)
		var sheets: Array = []
		for i in ceili(Viaduct.WASH_LEN / SEG) + 1:
			for z in SHEET_ZS:
				var mi := MeshInstance3D.new()
				mi.mesh = quad
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visible = false
				mi.position.z = z
				add_child(mi)
				sheets.append(mi)
		var train := _make_train()
		add_child(train)
		var splash := _make_splash()
		add_child(splash)
		_spans.append({"v": v, "train": train, "sheets": sheets, "mat": mat, "splash": splash, "floor": PackedFloat32Array(),
			"cycle": -1})
	_find_floors()


## The deck and awning colliders only answer rays once physics has stepped.
func _find_floors() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for sp: Dictionary in _spans:
		sp["floor"] = _sheet_floor(sp["v"])


func _process(delta: float) -> void:
	if level.elapsed == _last_elapsed:
		_extra += delta
	_last_elapsed = level.elapsed
	var t: float = level.elapsed + _extra
	var pl: Player = level.player
	var px := pl.position.x
	var shake := 0.0
	for sp: Dictionary in _spans:
		var v: Viaduct = sp["v"]
		var noses := v.noses(t)
		var train: Node3D = sp["train"]
		train.visible = not noses.is_empty()
		if train.visible:
			train.position.x = noses[0]
		var wash: Array = []
		for nx in noses:
			var near := maxf(maxf(nx - px, px - (nx + Viaduct.TRAIN_LEN)), 0.0)
			if px > v.x0 - 6.0 and px < v.x1 + 6.0:
				shake = maxf(shake, pow(clampf(1.0 - near / 18.0, 0.0, 1.0), 2.0))
			if wash.is_empty():
				wash = v.wash_span(nx)
		_draw_sheet(sp, wash, pl)
		_rumble(sp, v, t, px, pl.speed)
	var cam: Camera3D = level.camera
	if cam:
		cam.v_offset = SHAKE * shake * sin(t * 47.0) * sin(t * 13.0 + 1.1)
		cam.h_offset = SHAKE * 0.6 * shake * sin(t * 39.0 + 0.4)


## Where each sheet segment stops falling: the pavement, or the awning beneath the deck.
func _sheet_floor(v: Viaduct) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var space := get_world_3d().direct_space_state
	var x := v.x0
	while x <= v.x1 + SEG:
		var z: float = SHEET_ZS[1]
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, Viaduct.DECK_Y - 0.05, z), Vector3(x, -0.2, z), Player.COVER_MASK)
		var hit := space.intersect_ray(q)
		out.append(hit["position"].y if not hit.is_empty() else level.ground_y(x))
		x += SEG
	return out


func _draw_sheet(sp: Dictionary, wash: Array, pl: Player) -> void:
	var sheets: Array = sp["sheets"]
	var splash: GPUParticles3D = sp["splash"]
	splash.emitting = not wash.is_empty()
	if wash.is_empty():
		for mi: MeshInstance3D in sheets:
			mi.visible = false
		return
	var v: Viaduct = sp["v"]
	var a: float = wash[0]
	var b: float = wash[1]
	var mat: ShaderMaterial = sp["mat"]
	mat.set_shader_parameter("front", a)
	mat.set_shader_parameter("back", a + Viaduct.WASH_LEN)
	var floor_y: PackedFloat32Array = sp["floor"]
	var umb := pl.umbrella
	var canopy := umb.canopy_center()
	var r := umb.current_radius() if pl.open > 0.3 and not pl._dropped_umbrella else 0.0
	var i := 0
	var x := a + SEG * 0.5
	while i < sheets.size():
		var on := x < b
		for z in SHEET_ZS:
			var mi: MeshInstance3D = sheets[i]
			i += 1
			mi.visible = on
			if not on:
				continue
			var bottom: float = level.ground_y(x) if floor_y.is_empty() else floor_y[clampi(int((x - v.x0) / SEG), 0, floor_y.size() - 1)]
			if r > 0.0 and absf(x - canopy.x) < r and absf(z - canopy.z) < r:
				bottom = maxf(bottom, canopy.y + 0.12)
			mi.position = Vector3(x, (Viaduct.DECK_Y + bottom) * 0.5, z)
			mi.scale.y = Viaduct.DECK_Y - bottom
		x += SEG
	splash.position = Vector3((a + b) * 0.5, 0.05, 1.6)
	(splash.process_material as ParticleProcessMaterial).emission_box_extents = Vector3((b - a) * 0.5, 0.02, 0.6)


## One train_pass per train the walker meets near a span, started so its peak lands as the nose
## passes over him.
func _rumble(sp: Dictionary, v: Viaduct, t: float, px: float, speed: float) -> void:
	if px < v.x0 - 10.0 or px > v.x1 + 10.0:
		return
	var cycle := floori((t - v.phase) / v.period)
	if cycle == sp["cycle"]:
		return
	var meet := (v.nose(t) - px) / (Viaduct.TRAIN_SPEED + maxf(speed, 0.0))
	if meet > 0.0 and meet <= SOUND_LEAD:
		sp["cycle"] = cycle
		_pass.play(SOUND_LEAD - meet)


## A streamlined monorail set on the guideway: three bevelled cars, a lit window band, a headlight
## that throws its beam down over the deck's edge onto the pavement ahead.
func _make_train() -> Node3D:
	var root := Node3D.new()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.86, 0.87, 0.9)
	body.metallic = 0.85
	body.roughness = 0.22
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.85, 0.18, 0.15)
	stripe.roughness = 0.4
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.86, 0.6)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.82, 0.55)
	glass.emission_energy_multiplier = 1.4
	var y0 := Viaduct.DECK_TOP + 0.35
	var prof := PackedVector2Array([Vector2(0.75, y0), Vector2(2.55, y0), Vector2(2.85, y0 + 0.5),
		Vector2(2.85, y0 + 1.7), Vector2(2.45, y0 + 2.35), Vector2(0.85, y0 + 2.35), Vector2(0.45, y0 + 1.7),
		Vector2(0.45, y0 + 0.5)])
	for k in 3:
		var xa := 0.8 + k * 9.8
		root.add_child(ViaductBuilder.extrude(prof, xa, xa + 9.4, body))
		root.add_child(ViaductBuilder.extrude(PackedVector2Array([Vector2(2.84, y0 + 0.35), Vector2(2.9, y0 + 0.35),
			Vector2(2.9, y0 + 0.55), Vector2(2.84, y0 + 0.55)]), xa, xa + 9.4, stripe))
		root.add_child(ViaductBuilder.extrude(PackedVector2Array([Vector2(2.84, y0 + 1.0), Vector2(2.88, y0 + 1.0),
			Vector2(2.88, y0 + 1.5), Vector2(2.84, y0 + 1.5)]), xa + 0.6, xa + 8.8, glass))
	var nose := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.2
	sm.height = 2.4
	nose.mesh = sm
	nose.material_override = body
	nose.scale = Vector3(0.9, 0.95, 1.0)
	nose.position = Vector3(1.0, y0 + 1.2, 1.65)
	root.add_child(nose)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.light_energy = 16.0
	lamp.spot_range = 22.0
	lamp.spot_angle = 24.0
	lamp.spot_attenuation = 0.5
	lamp.light_volumetric_fog_energy = 2.5
	lamp.shadow_enabled = false
	lamp.position = Vector3(-0.2, Viaduct.DECK_TOP - 0.1, Viaduct.DECK_Z1 + 0.3)
	lamp.rotation = Vector3(0.0, PI * 0.5, 0.0)    # local -Z -> world -X
	lamp.rotate_object_local(Vector3.RIGHT, -0.5)
	root.add_child(lamp)
	# The beam itself, so it reads through the painterly filter: a faint additive cone along the lamp.
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = 1.8
	cone.height = 13.0
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	var bm := ShaderMaterial.new()
	bm.shader = load("res://src/fx/headlight_beam.gdshader")
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := Vector3(-cos(0.5), -sin(0.5), 0.0)
	beam.transform = Transform3D(Basis(Quaternion(Vector3.DOWN, dir)), lamp.position + dir * 6.5)
	root.add_child(beam)
	return root



func _make_splash() -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = 160
	sp.lifetime = 0.5
	sp.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.0, 0.02, 0.6)
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, -9.8, 0)
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.75, 0.82, 0.95, 0.6)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = dm
	sp.draw_pass_1 = q
	sp.visibility_aabb = AABB(Vector3(-8, -1, -2), Vector3(16, 4, 4))
	return sp
