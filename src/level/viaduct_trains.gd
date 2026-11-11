extends Node3D
## What moves on the monorail: the trains, their headlights, the sheet of water each one sheds, the
## rumble and the camera shake. Every frame is drawn from Track's pure functions of the level clock,
## so what you see and hear is exactly what Level.wash_at says gameplay does.

const SEG := 0.25                   # sheet segment width
const SHEET_ZS := [1.35, 2.05]      # behind and in front of the walker's line
const SHEET_SETS := 2               # sheets drawn at once: the two trains nearest the camera
const VIEW_M := 40.0                # trains further than this from the camera are hidden
const SOUND_LEAD := 2.4             # train_pass peaks this far into the file
const SHAKE := 0.035
const CAR_LEN := 9.4
const CAR_STEP := 9.8
const BOGIES := [2.2, 6.4]          # bogie wells, from each car's front
const WELL_LEN := 1.3
const SKIRT_Y := 3.4                # foot of the front skirt, below the back one: the side the camera sees
const ARCH_Y := 3.95                # the front skirt's foot over a bogie well
const WELL_GAP := 0.32              # front skirt to beam, room for the guide wheels
const NOSE_SKIRT := 1.6             # the front skirt rounds off over this much of the nose

var level: Node
var track: Track
var _trains: Array[Node3D] = []
var _sets: Array = []               # per sheet set: {sheets, mat, splash}
var _floors: Array = []             # per sheet layer: where the sheet lands, every SEG along the track
var _pass: AudioStreamPlayer
var _played := -1000000             # cycle of the last train whose rumble started
var _extra := 0.0                   # visuals keep running after the gameplay clock stops
var _last_elapsed := -1.0


func _ready() -> void:
	track = level.track
	_pass = AudioStreamPlayer.new()
	_pass.bus = &"SFX"
	if ResourceLoader.exists("res://assets/audio/train_pass.ogg"):
		_pass.stream = load("res://assets/audio/train_pass.ogg")
	add_child(_pass)
	var n := ceili((track.x1 - track.x0 + Track.TRAIN_LEN) / (Track.TRAIN_SPEED * track.period)) + 1
	for i in n:
		var train := _make_train()
		train.visible = false
		add_child(train)
		_trains.append(train)
	var quad := QuadMesh.new()
	quad.size = Vector2(SEG + 0.02, 1.0)
	var shader: Shader = load("res://src/fx/wash_sheet.gdshader")
	for k in SHEET_SETS:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var sheets: Array = []
		for i in ceili(Track.WASH_LEN / SEG) + 1:
			for z in SHEET_ZS:
				var mi := MeshInstance3D.new()
				mi.mesh = quad
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visible = false
				mi.position.z = z
				add_child(mi)
				sheets.append(mi)
		var splash := _make_splash()
		add_child(splash)
		_sets.append({"sheets": sheets, "mat": mat, "splash": splash})
	_find_floors()


## The deck and awning colliders only answer rays once physics has stepped.
func _find_floors() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for z in SHEET_ZS:
		var out := PackedFloat32Array()
		var x := track.x0
		while x <= track.x1 + SEG:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, _top(x, z) - 0.05, z), Vector3(x, -0.2, z), Player.COVER_MASK)
			var hit := space.intersect_ray(q)
			out.append(hit["position"].y if not hit.is_empty() else level.ground_y(x))
			x += SEG
		_floors.append(out)


## Where a sheet layer falls from: the deck's underside where one hangs over that layer, else the train's.
func _top(x: float, z: float) -> float:
	return Track.DECK_Y if z < Track.DECK_Z1 and track.deck_at(x) else Track.TRAIN_Y


func _process(delta: float) -> void:
	if level.elapsed == _last_elapsed:
		_extra += delta
	_last_elapsed = level.elapsed
	var t: float = level.elapsed + _extra
	var pl: Player = level.player
	var px := pl.position.x
	var cam: Camera3D = level.camera
	var cx := cam.position.x if cam else px
	var noses := track.noses(t)
	var shake := 0.0
	var washes: Array = []
	for i in _trains.size():
		var train := _trains[i]
		train.visible = i < noses.size() and noses[i] < cx + VIEW_M and noses[i] + Track.TRAIN_LEN > cx - VIEW_M
		if not train.visible:
			continue
		var nx := noses[i]
		train.position.x = nx
		var near := maxf(maxf(nx - px, px - (nx + Track.TRAIN_LEN)), 0.0)
		shake = maxf(shake, pow(clampf(1.0 - near / 18.0, 0.0, 1.0), 2.0))
		var wash := track.wash_span(nx)
		if not wash.is_empty():
			washes.append(wash)
	washes.sort_custom(func(a, b): return absf((a[0] + a[1]) * 0.5 - cx) < absf((b[0] + b[1]) * 0.5 - cx))
	for k in _sets.size():
		_draw_sheet(_sets[k], washes[k] if k < washes.size() else [], pl)
	_rumble(noses, t, px, pl.speed)
	if cam:
		cam.v_offset = SHAKE * shake * sin(t * 47.0) * sin(t * 13.0 + 1.1)
		cam.h_offset = SHAKE * 0.6 * shake * sin(t * 39.0 + 0.4)


func _draw_sheet(ss: Dictionary, wash: Array, pl: Player) -> void:
	var sheets: Array = ss["sheets"]
	var splash: GPUParticles3D = ss["splash"]
	splash.emitting = not wash.is_empty()
	if wash.is_empty():
		for mi: MeshInstance3D in sheets:
			mi.visible = false
		return
	var a: float = wash[0]
	var b: float = wash[1]
	var mat: ShaderMaterial = ss["mat"]
	mat.set_shader_parameter("front", a)
	mat.set_shader_parameter("back", a + Track.WASH_LEN)
	var umb := pl.umbrella
	var canopy := umb.canopy_center()
	var r := umb.current_radius() if pl.open > 0.3 and not pl._dropped_umbrella else 0.0
	var i := 0
	var x := a + SEG * 0.5
	while i < sheets.size():
		var on := x < b
		for l in SHEET_ZS.size():
			var z: float = SHEET_ZS[l]
			var mi: MeshInstance3D = sheets[i]
			i += 1
			mi.visible = on
			if not on:
				continue
			var top := _top(x, z)
			var bottom: float = level.ground_y(x)
			if not _floors.is_empty():
				var fl: PackedFloat32Array = _floors[l]
				bottom = fl[clampi(int((x - track.x0) / SEG), 0, fl.size() - 1)]
			if r > 0.0 and absf(x - canopy.x) < r and absf(z - canopy.z) < r:
				bottom = maxf(bottom, canopy.y + 0.12)
			mi.position = Vector3(x, (top + bottom) * 0.5, z)
			mi.scale.y = top - bottom
			mi.set_instance_shader_parameter("top_y", top)
		x += SEG
	splash.position = Vector3((a + b) * 0.5, 0.05, 1.7)
	(splash.process_material as ParticleProcessMaterial).emission_box_extents = Vector3((b - a) * 0.5, 0.02, 0.6)


## One train_pass per train the walker meets, started so its peak lands as the nose passes over him.
func _rumble(noses: PackedFloat32Array, t: float, px: float, speed: float) -> void:
	if not track.on_track(px):
		return
	var newest := track.cycle(t)
	for i in noses.size():
		var c := newest - i
		if c <= _played:
			continue
		var meet := (noses[i] - px) / (Track.TRAIN_SPEED + maxf(speed, 0.0))
		if meet > 0.0 and meet <= SOUND_LEAD:
			_played = c
			_pass.play(SOUND_LEAD - meet)


# --- the train model --------------------------------------------------------------------------
# Built for the view from the pavement. The camera, 2.6 m up, never sees above about 4.4 m on the
# train's front face, so the detail is in the front skirt: it hangs below the beam with lights along
# its foot, and bogie wells open in it where the guide wheels grip the beam. Static parts are merged
# into one mesh per material.

var _sts := {}


func _st(mat: Material) -> SurfaceTool:
	if not _sts.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sts[mat] = st
	return _sts[mat]


func _box(mat: Material, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var rect := PackedVector2Array([Vector2(z0, y0), Vector2(z1, y0), Vector2(z1, y1), Vector2(z0, y1)])
	ViaductBuilder.loft_into(_st(mat), [[x0, rect], [x1, rect]])


## A wheel turning about a vertical axis, as a 12-sided prism.
func _wheel(mat: Material, x: float, z: float, y0: float, y1: float, r: float) -> void:
	var sections: Array = []
	for k in 7:
		var a := PI * k / 6.0
		var hz := maxf(r * sin(a), 0.01)
		sections.append([x - r * cos(a), PackedVector2Array([Vector2(z - hz, y0), Vector2(z + hz, y0),
			Vector2(z + hz, y1), Vector2(z - hz, y1)])])
	ViaductBuilder.loft_into(_st(mat), sections)


## Sections rounding `prof` off over |length| into a blunt tip at x_tip: a quarter ellipse, never
## narrower than `least`. A negative length rounds off toward lower x (a tail). Ascending x either way.
static func _rounded(prof: PackedVector2Array, cz: float, cy: float, x_tip: float, length: float, least: float) -> Array:
	var out: Array = []
	for k in 6:
		var f := k / 5.0
		var s := maxf(sqrt(1.0 - (1.0 - f) * (1.0 - f)), least)
		out.append([x_tip + length * f, _squeezed(prof, cz, cy, s, s)])
	if length < 0.0:
		out.reverse()
	return out


## A (z, y) profile squeezed toward (cz, cy): s across, v up.
static func _squeezed(prof: PackedVector2Array, cz: float, cy: float, s: float, v: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in prof:
		out.append(Vector2(cz + (p.x - cz) * s, cy + (p.y - cy) * v))
	return out


func _mat(color: Color, metal: float, rough: float, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## A three-car streamliner straddling the beam: the body above it, a skirt either side, the front
## one deep enough to read from the street. Local x runs from the nose (0) back to the tail.
func _make_train() -> Node3D:
	_sts = {}
	var root := Node3D.new()
	var paint := _mat(Color(0.9, 0.88, 0.82), 0.25, 0.35, 0.06)   # enamel catching the neon, never black
	var stripe := _mat(Color(0.85, 0.16, 0.13), 0.2, 0.4)
	var dark := _mat(Color(0.1, 0.11, 0.13), 0.6, 0.5)
	var rubber := _mat(Color(0.05, 0.05, 0.06), 0.0, 0.8)
	var chrome := _mat(Color(0.92, 0.92, 0.95), 1.0, 0.12)
	var amber := _mat(Color(1.0, 0.62, 0.18), 0.0, 0.4, 3.0)
	var cyan := _mat(Color(0.3, 1.0, 0.92), 0.0, 0.4, 2.5)
	var red := _mat(Color(1.0, 0.12, 0.1), 0.0, 0.4, 4.0)
	var lens := _mat(Color(1.0, 0.97, 0.88), 0.0, 0.2, 6.0)
	var z0 := Track.TRAIN_Z0
	var z1 := Track.TRAIN_Z1
	var cz := (z0 + z1) * 0.5
	var belly := Track.BEAM_TOP + 0.1
	var inner0 := Track.BEAM_Z0 - 0.12
	var inner1 := Track.BEAM_Z1 + WELL_GAP
	var hull := PackedVector2Array([Vector2(z0, belly), Vector2(z1, belly), Vector2(z1, belly + 1.4),
		Vector2(z1 - 0.4, belly + 2.0), Vector2(z0 + 0.4, belly + 2.0), Vector2(z0, belly + 1.4)])
	var back := PackedVector2Array([Vector2(z0, Track.TRAIN_Y + 0.12), Vector2(z0 + 0.12, Track.TRAIN_Y),
		Vector2(inner0, Track.TRAIN_Y), Vector2(inner0, belly), Vector2(z0, belly)])
	var front := PackedVector2Array([Vector2(inner1, SKIRT_Y + 0.08), Vector2(inner1 + 0.08, SKIRT_Y),
		Vector2(z1 - 0.18, SKIRT_Y), Vector2(z1, SKIRT_Y + 0.18), Vector2(z1, belly), Vector2(inner1, belly)])
	var arch := _squeezed(front, cz, belly, 1.0, (belly - ARCH_Y) / (belly - SKIRT_Y))
	var fz := (inner1 + z1) * 0.5
	for k in 3:
		var xa := k * CAR_STEP
		var xb := xa + CAR_LEN
		var head := 2.4 if k == 0 else 0.0
		var tail := 1.2 if k == 2 else 0.0
		# Body and back skirt: unseen from the street, kept plain, nose and tail tapered.
		var sec: Array = _rounded(hull, cz, belly + 0.9, xa, head, 0.3) if head > 0.0 else [[xa, hull]]
		var bsec: Array = _rounded(back, cz, belly, xa, head, 0.3) if head > 0.0 else [[xa, back]]
		if tail > 0.0:
			sec.append_array(_rounded(hull, cz, belly + 0.9, xb, -tail, 0.6))
			bsec.append_array(_rounded(back, cz, belly, xb, -tail, 0.6))
		else:
			sec.append([xb, hull])
			bsec.append([xb, back])
		ViaductBuilder.loft_into(_st(paint), sec)
		ViaductBuilder.loft_into(_st(paint), bsec)
		# Front skirt: full depth between the bogie wells, raised into an arch over each well.
		var stations: Array = _rounded(front, fz, belly, xa, NOSE_SKIRT, 0.3) if head > 0.0 else [[xa, front]]
		for bx in BOGIES:
			stations.append([xa + bx - 0.15, front])
			stations.append([xa + bx + 0.05, arch])
			stations.append([xa + bx + WELL_LEN - 0.05, arch])
			stations.append([xa + bx + WELL_LEN + 0.15, front])
		if tail > 0.0:
			stations.append_array(_rounded(front, fz, belly, xb, -0.6, 0.6))
		else:
			stations.append([xb, front])
		ViaductBuilder.loft_into(_st(paint), stations)
		# Along the skirt's foot: a chrome lip, a red stripe above it and amber markers between the
		# wells; under it, a neon strip along the inner edge.
		var runs := [[xa + (NOSE_SKIRT if head > 0.0 else 0.15)]]
		for bx in BOGIES:
			runs[-1].append(xa + bx - 0.2)
			runs.append([xa + bx + WELL_LEN + 0.2])
		runs[-1].append(xb - (0.6 if tail > 0.0 else 0.15))
		for r in runs:
			var ra: float = r[0]
			var rb: float = r[1]
			_box(chrome, ra, rb, z1 - 0.02, z1 + 0.02, SKIRT_Y + 0.14, SKIRT_Y + 0.19)
			_box(stripe, ra, rb, z1 - 0.01, z1 + 0.025, SKIRT_Y + 0.26, SKIRT_Y + 0.36)
			_box(cyan, ra + 0.1, rb - 0.1, inner1 + 0.1, inner1 + 0.15, SKIRT_Y - 0.03, SKIRT_Y + 0.01)
			var mx := ra + 0.5
			while mx < rb - 0.3:
				_box(amber, mx - 0.12, mx + 0.12, z1 - 0.1, z1 + 0.03, SKIRT_Y + 0.02, SKIRT_Y + 0.12)
				mx += 1.5
		# Bogies in the wells: a dark frame with chrome-hubbed guide wheels pressed against the beam.
		for bx in BOGIES:
			var b0: float = xa + bx + 0.1
			var b1: float = xa + bx + WELL_LEN - 0.1
			_box(dark, b0, b1, inner1 - 0.02, inner1 + 0.3, ARCH_Y - 0.25, belly)
			_box(chrome, b0 + 0.05, b1 - 0.05, inner1 + 0.29, inner1 + 0.32, ARCH_Y - 0.2, ARCH_Y - 0.12)
			for wx in [b0 + 0.3, b1 - 0.3]:
				var wz := Track.BEAM_Z1 + 0.18
				_wheel(rubber, wx, wz, Track.BEAM_Y + 0.08, Track.BEAM_Y + 0.26, 0.18)
				_wheel(chrome, wx, wz, Track.BEAM_Y + 0.05, Track.BEAM_Y + 0.09, 0.09)
		if k < 2:
			_box(dark, xb - 0.05, xb + CAR_STEP - CAR_LEN + 0.05, z0 + 0.3, z1 - 0.3, belly + 0.1, belly + 1.8)
	# Headlamp set into the skirt's nose, tail lamp at the back.
	_box(lens, 0.2, 0.4, fz - 0.18, fz + 0.18, SKIRT_Y + 0.55, SKIRT_Y + 0.75)
	var tx := 2.0 * CAR_STEP + CAR_LEN
	_box(red, tx - 0.06, tx + 0.02, fz - 0.3, fz + 0.3, SKIRT_Y + 0.5, SKIRT_Y + 0.65)
	for mat: Material in _sts:
		var mi := MeshInstance3D.new()
		mi.mesh = (_sts[mat] as SurfaceTool).commit()
		mi.material_override = mat
		if mat in [amber, cyan, red, lens]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_sts = {}
	# Underglow on the pavement as it passes.
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.4, 1.0, 0.92)
	glow.light_energy = 1.6
	glow.omni_range = 6.0
	glow.omni_attenuation = 1.4
	glow.shadow_enabled = false
	glow.position = Vector3(tx * 0.5, SKIRT_Y - 0.5, fz)
	root.add_child(glow)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.light_energy = 16.0
	lamp.spot_range = 22.0
	lamp.spot_angle = 24.0
	lamp.spot_attenuation = 0.5
	lamp.light_volumetric_fog_energy = 2.5
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.1, SKIRT_Y + 0.65, fz)
	lamp.rotation = Vector3(0.0, PI * 0.5, 0.0)    # local -Z -> world -X
	lamp.rotate_object_local(Vector3.RIGHT, -0.4)
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
	var dir := Vector3(-cos(0.4), -sin(0.4), 0.0)
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
