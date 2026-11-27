class_name Helicopter
extends Node3D
## The level's `helicopters`: Skyway's turbine shuttles, flying low along the street between the
## terminal roof and the airport. When the walker passes an entry's x, one comes in from START_OFF
## metres ahead of that x (`dir` -1, flying right to left toward him) or behind it (`dir` 1) and
## flies TRAVEL metres along the street at `speed`, optionally stopping over `hover_x` for `hover_s`
## seconds on the way (braking into the hover and pulling away again at BRAKE).
##
## Its rotor wash is a footprint on the pavement under it, WASH_CORE either side of it at full
## strength and fading over WASH_EDGE beyond, moving with it. The downdraught drives the rain in under
## every kind of cover there (Player._rotor_exposure): only the open canopy held over him keeps it off.
##
## Every flight is a pure function of the level clock from the moment it was launched, so gameplay
## (Level.rotor_at), the bots (they predict it with rotor_at), the picture and the sound all agree.
## Telegraph: the rotor's thud building from its side, its searchlight sweeping the pavement ahead of
## it, rain blown in sideways under cover where the wash is, the camera shaking as it goes over, and
## the first one's hint. A checkpoint resume skips every entry whose x is behind it.

const SPEED := 6.0            # m/s along the street, unless the entry sets `speed`
const START_OFF := 50.0       # it comes in this far from the trigger x (ahead for dir -1, behind for 1)
const TRAVEL := 110.0         # metres it flies before it is gone
const BRAKE := 2.5            # m/s² into a hover and out of it again
const WASH_CORE := 3.0        # the wash is full strength within this of the point under it...
const WASH_EDGE := 1.2        # ...and fades out over this much further
const WASH_REACH := WASH_CORE + WASH_EDGE
const FLY_Z := 3.5            # over the pavement's front edge: the rotor reaches from the shopfronts out over the road
const ALT_MIN := 9.0          # rotor hub height: clear of a skyway's roof...
const ALT_MAX := 14.0         # ...and no higher than over the rooftops
const TOP_MARGIN := 0.5       # the hub flies this far below the top of the frame, so it is seen
const VIEW_M := 45.0          # drawn while within this of the camera
const HINT_S := 3.5           # the first one's hint shows this long before its wash reaches him
const SHAKE := 0.05
const SHAKE_M := 14.0         # the camera shakes while it is within this of him
const ROTOR_R := 4.0
const PULL := 4.0             # metres the camera eases out while one is within PULL_M of him...
const PULL_M := 28.0          # ...so it is seen whole as it passes
const ROTOR_SPIN := 15.0      # rad/s the drawn blades turn at (as film catches a rotor)
const LIGHT_AHEAD := 9.0      # where the searchlight falls, ahead of it along the street
const NOSE_LAMP := Vector3(2.5, -2.78, 0.0)
## A modelled helicopter replaces the code-built one when either file exists. Its root's origin is the
## main rotor hub, +X the nose, +Y up, 1 unit a metre (rotor radius about ROTOR_R, nose to tail about
## 11 m). Named nodes it may carry (each optional): "Rotor" (turned about its local Y), "TailRotor"
## (turned about its local Z), "SearchlightMount" (the beam starts at its origin; else NOSE_LAMP),
## "BeaconTop" / "BeaconBelly" (shown only while the anti-collision light flashes) and an
## OmniLight3D "Flash" (lit with the beacons).
const MODEL_PATHS := ["res://assets/vehicles/helicopter.tscn", "res://assets/vehicles/helicopter.glb"]

var level: Node
var entries: Array = []       # {x, dir, speed, hover_x, hover_s} from the level, ascending x
var flights: Array = []       # one per launched entry: see launch()
var _next := 0
var _extra := 0.0             # visuals keep flying after the gameplay clock stops
var _last_elapsed := -1.0
var _shook := false
var _pulled := false
var _template: Node3D
var _rotor_stream: AudioStream


func _ready() -> void:
	for h in level.data.get("helicopters", []):
		entries.append({"x": float(h["x"]), "dir": -1.0 if float(h.get("dir", -1)) < 0.0 else 1.0,
			"speed": float(h.get("speed", SPEED)), "hover_x": float(h.get("hover_x", NAN)),
			"hover_s": float(h.get("hover_s", 3.0))})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	while _next < entries.size() and entries[_next]["x"] <= level.player.position.x:
		_next += 1
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists("res://assets/audio/rotor_loop" + ext):
			_rotor_stream = load("res://assets/audio/rotor_loop" + ext)
			break
	if _rotor_stream is AudioStreamWAV:
		var w := _rotor_stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif _rotor_stream is AudioStreamOggVorbis:
		(_rotor_stream as AudioStreamOggVorbis).loop = true
	if not entries.is_empty():
		_template = _load_model()


func _load_model() -> Node3D:
	for path in MODEL_PATHS:
		if ResourceLoader.exists(path):
			var m := (load(path) as PackedScene).instantiate() as Node3D
			if m:
				return m
	return _make_model()


func _exit_tree() -> void:
	if _template and not _template.is_inside_tree():
		_template.free()
		_template = null


## Where the next one is triggered (INF when none is left).
func next_x() -> float:
	return entries[_next]["x"] if _next < entries.size() else INF


# --- the flight: pure functions of the level clock ------------------------------------------------

## Sends entry `i` on its way at level-clock time t0. Its whole flight follows from here.
func launch(i: int, t0: float) -> Dictionary:
	var e: Dictionary = entries[i]
	var f := {"i": i, "t0": t0, "dir": e["dir"], "v": e["speed"], "start": e["x"] - e["dir"] * START_OFF,
		"sh": -1.0, "hold": 0.0, "alt": _cruise_alt(), "node": null}
	var v: float = f["v"]
	var stop := v * v / (2.0 * BRAKE)
	if not is_nan(e["hover_x"]) and e["hover_s"] > 0.0:
		var sh: float = (e["hover_x"] - f["start"]) * f["dir"]
		if sh > stop and sh < TRAVEL - stop:
			f["sh"] = sh
			f["hold"] = e["hover_s"]
		else:
			push_warning("helicopter at x=%.1f: hover_x %.1f is off its flight path" % [e["x"], e["hover_x"]])
	f["end"] = _tau_at(f, TRAVEL)
	flights.append(f)
	if is_inside_tree():
		_dress(f)
	return f


## Metres flown `tau` seconds after launch.
func _s(f: Dictionary, tau: float) -> float:
	var v: float = f["v"]
	tau = maxf(tau, 0.0)
	var sh: float = f["sh"]
	if sh < 0.0:
		return minf(v * tau, TRAVEL)
	var tb := v / BRAKE
	var db := v * tb * 0.5
	var t1 := (sh - db) / v
	if tau < t1:
		return v * tau
	if tau < t1 + tb:
		var u := tau - t1
		return sh - db + v * u - 0.5 * BRAKE * u * u
	var t2: float = t1 + tb + f["hold"]
	if tau < t2:
		return sh
	if tau < t2 + tb:
		var u2 := tau - t2
		return sh + 0.5 * BRAKE * u2 * u2
	return minf(sh + db + v * (tau - t2 - tb), TRAVEL)


## Speed `tau` seconds after launch.
func _v(f: Dictionary, tau: float) -> float:
	var v: float = f["v"]
	var sh: float = f["sh"]
	if sh < 0.0:
		return v
	var tb := v / BRAKE
	var t1 := (sh - v * tb * 0.5) / v
	var t2: float = t1 + tb + f["hold"]
	if tau < t1 or tau >= t2 + tb:
		return v
	if tau < t1 + tb:
		return v - BRAKE * (tau - t1)
	if tau < t2:
		return 0.0
	return BRAKE * (tau - t2)


## Seconds after launch it first reaches `s` metres along its path.
func _tau_at(f: Dictionary, s: float) -> float:
	var v: float = f["v"]
	var sh: float = f["sh"]
	if sh < 0.0:
		return s / v
	var tb := v / BRAKE
	var db := v * tb * 0.5
	var t1 := (sh - db) / v
	var t2: float = t1 + tb + f["hold"]
	if s <= sh - db:
		return s / v
	if s < sh:
		return t1 + (v - sqrt(maxf(v * v - 2.0 * BRAKE * (s - sh + db), 0.0))) / BRAKE
	if s <= sh + db:
		return (t1 + tb if s <= sh else t2 + sqrt(2.0 * (s - sh) / BRAKE))
	return t2 + tb + (s - sh - db) / v


## World x of flight f at level-clock time t (NAN when it isn't flying then).
func x_at(f: Dictionary, t: float) -> float:
	var tau: float = t - f["t0"]
	if tau < 0.0 or tau > f["end"]:
		return NAN
	return f["start"] + f["dir"] * _s(f, tau)


## When flight f is right over x (INF if it never is).
func time_over(f: Dictionary, x: float) -> float:
	var s: float = (x - f["start"]) * f["dir"]
	return f["t0"] + _tau_at(f, s) if s >= 0.0 and s <= TRAVEL else INF


## 0..1 how hard the wash is driving the rain at x at level-clock time t.
func rotor_at(x: float, t: float) -> float:
	var k := 0.0
	for f: Dictionary in flights:
		var hx := x_at(f, t)
		if not is_nan(hx):
			k = maxf(k, clampf(1.0 - (absf(x - hx) - WASH_CORE) / WASH_EDGE, 0.0, 1.0))
	return k


## Seconds until the wash reaches x (0 while it is on x, INF if no launched flight will reach it).
func rotor_eta(x: float, t: float) -> float:
	if rotor_at(x, t) > 0.0:
		return 0.0
	var best := INF
	for f: Dictionary in flights:
		var tau: float = t - f["t0"]
		if tau > f["end"]:
			continue
		var need: float = (x - f["start"]) * f["dir"] - WASH_REACH
		if need < _s(f, tau) or need > TRAVEL:
			continue
		best = minf(best, f["t0"] + _tau_at(f, need) - t)
	return maxf(best, 0.0)


## The hub flies just under the top of the frame (with the camera eased out by PULL) where it
## crosses the street, between ALT_MIN and ALT_MAX, so whatever camera the street sets it is seen.
func _cruise_alt() -> float:
	var cam: Camera3D = level.camera if level else null
	if cam == null:
		return ALT_MAX
	var out: float = PULL - float(level.get("_cam_pull"))
	var depth := cam.position.z + out - FLY_Z
	var top := cam.position.y + out * Level.CAM_PULL_RISE + depth * tan(deg_to_rad(cam.fov * 0.5) + cam.rotation.x)
	return clampf(top - TOP_MARGIN, ALT_MIN, ALT_MAX)


# --- loop ----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null:
		return
	if level.elapsed == _last_elapsed:
		_extra += delta
	_last_elapsed = level.elapsed
	var playing := p.state == Player.State.WALK or p.state == Player.State.STOPPED
	while playing and _next < entries.size() and p.position.x >= entries[_next]["x"]:
		launch(_next, level.elapsed)
		_next += 1
	if playing and level.rotor_eta(p.position.x, level.elapsed) < HINT_S:
		level.hint_once("rotor", "Rotor wash! It blows the rain in under cover. Umbrella up ({umbrella}).", 4.5)
	var t: float = level.elapsed + _extra
	var cam: Camera3D = level.camera
	var cx := cam.global_position.x if cam else p.position.x
	var shake := 0.0
	var pull := false
	for f: Dictionary in flights:
		var node: Node3D = f["node"]
		if node == null:
			continue
		var tau: float = t - f["t0"]
		if tau > f["end"]:
			node.queue_free()
			f["node"] = null
			continue
		var hx: float = f["start"] + f["dir"] * _s(f, tau)
		var seen := absf(hx - cx) < VIEW_M
		_draw(f, node, hx, tau, t, seen)
		var near := absf(hx - p.position.x)
		shake = maxf(shake, pow(clampf(1.0 - near / SHAKE_M, 0.0, 1.0), 2.0))
		pull = pull or near < PULL_M
	# Ease the camera out while one is near, and back in once it has gone (unless something else,
	# a drive-by, has the camera out by then).
	if pull and level.camera_pull < PULL:
		level.camera_pull = PULL
		_pulled = true
	elif not pull and _pulled:
		if level.camera_pull == PULL:
			level.camera_pull = 0.0
		_pulled = false
	if cam and (shake > 0.0 or _shook):
		cam.v_offset = SHAKE * shake * sin(t * 41.0) * sin(t * 11.0 + 0.7)
		cam.h_offset = SHAKE * 0.6 * shake * sin(t * 33.0 + 0.4)
		_shook = shake > 0.0


func _draw(f: Dictionary, node: Node3D, hx: float, tau: float, t: float, seen: bool) -> void:
	var dir: float = f["dir"]
	var v := _v(f, tau)
	var braking := 0.0
	if f["sh"] >= 0.0 and v < f["v"] - 0.01:
		braking = 1.0 if _v(f, tau + 0.05) < v else -1.0
	# Nose down to fly, nose up to flare into the hover, and a slow bob.
	var pitch: float = -0.09 * v / f["v"] + 0.1 * braking
	f["pitch"] = lerpf(f.get("pitch", pitch), pitch, 0.1)
	node.position = Vector3(hx, f["alt"] + 0.18 * sin(t * 1.3 + f["i"]), FLY_Z)
	node.basis = Basis(Vector3.UP, 0.0 if dir > 0.0 else PI) * Basis(Vector3.BACK, f["pitch"] + 0.015 * sin(t * 0.9))
	node.visible = seen
	var rotor := node.get_node_or_null("Rotor") as Node3D
	if rotor:
		rotor.rotation.y = -t * ROTOR_SPIN
	var tail := node.get_node_or_null("TailRotor") as Node3D
	if tail:
		tail.rotation.z = t * ROTOR_SPIN * 3.1
	var on := fmod(t + f["i"] * 0.37, 1.1) < 0.12
	for b in ["BeaconTop", "BeaconBelly"]:
		var beacon := node.get_node_or_null(b) as Node3D
		if beacon:
			beacon.visible = on
	var flash := node.get_node_or_null("Flash") as OmniLight3D
	if flash:
		flash.light_energy = 5.0 if on else 0.0
	var fill: OmniLight3D = f["fill"]
	fill.global_position = Vector3(hx, f["alt"] - 1.9, FLY_Z + 3.2)
	# The searchlight sweeps the pavement ahead of it; hovering, it searches round under it.
	var mount := node.get_node_or_null("SearchlightMount") as Node3D
	var lamp: Vector3 = mount.global_position if mount else node.to_global(NOSE_LAMP)
	var ahead := LIGHT_AHEAD * clampf(v / f["v"], 0.25, 1.0)
	var target := Vector3(hx + dir * (ahead + 2.5 * sin(t * 0.85 + f["i"])), 0.0, 1.6 + 1.2 * sin(t * 0.53))
	var spot: SpotLight3D = f["spot"]
	spot.global_position = lamp
	spot.look_at(target, Vector3.UP)
	var beam: MeshInstance3D = f["beam"]
	var to := target - lamp
	var len := to.length()
	var bdir := to / len
	var w := len * tan(deg_to_rad(spot.spot_angle) * 0.55)
	beam.global_transform = Transform3D(Basis(Quaternion(Vector3.DOWN, bdir)) * Basis.from_scale(Vector3(w, len, w)), lamp + bdir * len * 0.5)
	beam.visible = seen
	# The wash: rain driven in sideways under cover, and spray thrown up off the pavement.
	var spray: GPUParticles3D = f["spray"]
	var mist: GPUParticles3D = f["mist"]
	spray.emitting = seen
	mist.emitting = seen
	spray.global_position = Vector3(hx, 2.3, 1.75)
	mist.global_position = Vector3(hx, 0.25, 1.75)


# --- the model ------------------------------------------------------------------------------------

## Gives a launched flight its helicopter, searchlight, wash spray and rotor sound.
func _dress(f: Dictionary) -> void:
	var node := _template.duplicate() as Node3D
	node.visible = false
	add_child(node)
	f["node"] = node
	var hx: float = f["start"]
	node.position = Vector3(hx, f["alt"], FLY_Z)
	var low: bool = Game.settings.get("low_quality", false)
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.92, 0.96, 1.0)
	spot.light_energy = 40.0
	spot.spot_range = 26.0
	spot.spot_angle = 11.0
	spot.spot_attenuation = 0.4
	spot.light_volumetric_fog_energy = 4.0
	spot.shadow_enabled = not low
	spot.top_level = true
	node.add_child(spot)
	f["spot"] = spot
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	var bm := ShaderMaterial.new()
	bm.shader = load("res://src/fx/headlight_beam.gdshader")
	bm.set_shader_parameter("tint", Color(0.85, 0.92, 1.0))
	bm.set_shader_parameter("strength", 0.16)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.top_level = true
	node.add_child(beam)
	f["beam"] = beam
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.7, 0.78, 1.0)
	fill.light_energy = 2.6
	fill.omni_range = 6.0
	fill.omni_attenuation = 1.2
	fill.light_volumetric_fog_energy = 0.0
	fill.top_level = true
	node.add_child(fill)
	f["fill"] = fill
	var spray := _make_spray(low)
	node.add_child(spray)
	f["spray"] = spray
	var mist := _make_mist(low)
	node.add_child(mist)
	f["mist"] = mist
	if _rotor_stream:
		var snd := AudioStreamPlayer3D.new()
		snd.stream = _rotor_stream
		snd.bus = &"SFX"
		snd.unit_size = 10.0
		snd.max_distance = 140.0
		snd.panning_strength = 1.4
		snd.volume_db = -1.0
		snd.position = Vector3(0.0, -1.5, 0.0)
		node.add_child(snd)
		snd.play(randf() * 3.0)


## Rain in the wash, driven in sideways under cover toward the shopfronts and out along the street.
func _make_spray(low: bool) -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = 260 if low else 700
	sp.lifetime = 0.55
	sp.local_coords = false
	sp.top_level = true
	sp.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(WASH_CORE, 2.1, 1.7)
	pm.direction = Vector3(0.0, -0.55, -1.0)
	pm.spread = 50.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 7.0
	pm.radial_accel_min = 5.0
	pm.radial_accel_max = 9.0
	pm.gravity = Vector3(0, -7.0, 0)
	pm.particle_flag_align_y = true
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.026, 0.36)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.albedo_color = Color(0.72, 0.8, 0.95, 0.8)
	q.material = dm
	sp.draw_pass_1 = q
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visibility_aabb = AABB(Vector3(-10, -4, -6), Vector3(20, 10, 12))
	return sp


## Spray thrown up off the wet pavement and blown out along it from under the rotor.
func _make_mist(low: bool) -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = 60 if low else 140
	sp.lifetime = 1.1
	sp.local_coords = false
	sp.top_level = true
	sp.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(WASH_CORE * 0.8, 0.1, 1.6)
	pm.direction = Vector3(0.0, 0.35, 0.0)
	pm.spread = 80.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.radial_accel_min = 4.0
	pm.radial_accel_max = 7.0
	pm.gravity = Vector3(0, -0.4, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(0.6, 0.66, 0.78, 0.1)
	var puff := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = g
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	dm.albedo_texture = puff
	q.material = dm
	sp.draw_pass_1 = q
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visibility_aabb = AABB(Vector3(-10, -2, -6), Vector3(20, 6, 12))
	return sp


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


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, basis := Basis.IDENTITY, part_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	if part_name != "":
		mi.name = part_name
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 32
	c.rings = 12
	return c


static func _cyl(top: float, bottom: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


## The stand-in until a modelled one is in MODEL_PATHS: a 1960s turbine shuttle in Skyway livery, built for the view from below and to one side: white
## enamel over polished aluminium, a teal cheatline under a row of lit cabin windows, SKYWAY on both
## flanks, a glazed bubble nose with the crew inside, a turbine hump with its exhausts, five blades
## over a blurred disc, a tail rotor, nav lights and two red beacons. Local +X is the nose; the
## origin is the rotor hub.
func _make_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Helicopter"
	var white := _mat(Color(0.9, 0.9, 0.87), 0.15, 0.32)
	var alu := _mat(Color(0.62, 0.65, 0.7), 0.85, 0.28)
	var teal := _mat(Color(0.05, 0.5, 0.52), 0.2, 0.35)
	var navy := _mat(Color(0.06, 0.12, 0.3), 0.2, 0.4)
	var dark := _mat(Color(0.06, 0.06, 0.07), 0.4, 0.6)
	var rubber := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.8)
	var chrome := _mat(Color(0.92, 0.92, 0.95), 1.0, 0.12)
	var windows := _mat(Color(1.0, 0.84, 0.58), 0.0, 0.4, 2.2)
	var red := _mat(Color(1.0, 0.1, 0.08), 0.0, 0.4, 5.0)
	var green := _mat(Color(0.15, 1.0, 0.35), 0.0, 0.4, 4.0)
	var lamp := _mat(Color(1.0, 1.0, 0.95), 0.0, 0.2, 8.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.35, 0.62, 0.66, 0.42)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.4
	glass.roughness = 0.04
	glass.emission_enabled = true
	glass.emission = Color(0.2, 0.5, 0.45)
	glass.emission_energy_multiplier = 0.25
	var along := Basis(Vector3.BACK, PI * 0.5)    # a mesh's +Y axis laid along -X
	var cy := -1.75                                # the cabin's centre line
	# Cabin: white upper, aluminium belly, the cheatline and windows along both flanks.
	_part(root, _capsule(1.05, 6.4), white, Vector3(0.0, cy, 0.0), along * Basis.from_scale(Vector3(1.0, 1.0, 0.92)))
	_part(root, _capsule(0.95, 6.0), alu, Vector3(0.1, cy - 0.28, 0.0), along * Basis.from_scale(Vector3(1.0, 1.0, 0.9)))
	_part(root, _box(Vector3(4.3, 0.2, 1.96)), teal, Vector3(0.0, cy - 0.12, 0.0))
	_part(root, _box(Vector3(4.3, 0.05, 1.98)), navy, Vector3(0.0, cy - 0.25, 0.0))
	for k in 6:
		_part(root, _box(Vector3(0.4, 0.32, 1.93)), windows, Vector3(-1.55 + k * 0.6, cy + 0.2, 0.0))
	for side in [1.0, -1.0]:
		var name_lbl := Label3D.new()
		name_lbl.text = "SKYWAY"
		name_lbl.font_size = 56
		name_lbl.pixel_size = 0.0075
		name_lbl.modulate = Color(0.08, 0.16, 0.36)
		name_lbl.outline_size = 0
		name_lbl.shaded = true
		name_lbl.double_sided = false
		name_lbl.position = Vector3(-0.15, cy - 0.5, 0.9 * side)
		name_lbl.basis = Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
		root.add_child(name_lbl)
	# Bubble nose with a chrome collar, two crew inside, and the searchlight under its chin.
	_part(root, _ball(1.0), glass, Vector3(2.5, cy - 0.08, 0.0), Basis.from_scale(Vector3(1.1, 0.95, 0.9)))
	_part(root, _cyl(0.93, 0.93, 0.1, 32), chrome, Vector3(2.12, cy - 0.06, 0.0), along)
	for z in [-0.35, 0.35]:
		_part(root, _ball(0.17), dark, Vector3(2.55, cy + 0.2, z))
		_part(root, _box(Vector3(0.3, 0.42, 0.3)), navy, Vector3(2.5, cy - 0.15, z))
	var panel := OmniLight3D.new()
	panel.light_color = Color(0.4, 1.0, 0.7)
	panel.light_energy = 0.6
	panel.omni_range = 1.4
	panel.light_volumetric_fog_energy = 0.0
	panel.position = Vector3(2.9, cy - 0.3, 0.0)
	root.add_child(panel)
	_part(root, _cyl(0.17, 0.2, 0.3), chrome, NOSE_LAMP + Vector3(0.0, 0.12, 0.0))
	_part(root, _ball(0.13), lamp, NOSE_LAMP, Basis.IDENTITY, "SearchlightMount")
	# Turbine hump, its intakes and exhausts; the mast and hub.
	_part(root, _capsule(0.55, 3.3), white, Vector3(-0.3, cy + 1.0, 0.0), along * Basis.from_scale(Vector3(1.0, 1.0, 0.9)))
	for z in [-0.3, 0.3]:
		_part(root, _cyl(0.17, 0.17, 0.08), dark, Vector3(1.32, cy + 1.02, z), along)
		_part(root, _cyl(0.2, 0.16, 0.6), dark, Vector3(-1.95, cy + 1.0, z * 1.4), Basis(Vector3.UP, -signf(z) * 0.4) * along)
	_part(root, _cyl(0.12, 0.14, 0.55), alu, Vector3(0.0, -0.3, 0.0))
	_part(root, _cyl(0.26, 0.3, 0.22), chrome, Vector3(0.0, 0.0, 0.0))
	# Main rotor: the blades turn in the Rotor node over a blurred disc.
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	root.add_child(rotor)
	for k in 5:
		var arm := Node3D.new()
		arm.rotation.y = TAU * k / 5.0
		rotor.add_child(arm)
		_part(arm, _box(Vector3(ROTOR_R - 0.2, 0.05, 0.3)), dark, Vector3(ROTOR_R * 0.5 + 0.1, 0.05, 0.0), Basis(Vector3.RIGHT, 0.08))
		_part(arm, _box(Vector3(0.3, 0.052, 0.31)), white, Vector3(ROTOR_R - 0.15, 0.05, 0.0))
	var disc := PlaneMesh.new()
	disc.size = Vector2(ROTOR_R * 2.0, ROTOR_R * 2.0)
	var dmat := ShaderMaterial.new()
	dmat.shader = load("res://src/fx/rotor_disc.gdshader")
	var dm := _part(root, disc, dmat, Vector3(0.0, 0.06, 0.0))
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tail boom, fin, tailplane and tail rotor.
	_part(root, _cyl(0.22, 0.55, 5.4), white, Vector3(-5.05, cy + 0.35, 0.0), along)
	_part(root, _cyl(0.235, 0.565, 2.2, 16), teal, Vector3(-3.65, cy + 0.35, 0.0), along * Basis.from_scale(Vector3(1.0, 1.0, 1.0)))
	_part(root, _box(Vector3(1.0, 1.6, 0.09)), white, Vector3(-7.55, cy + 1.05, 0.0), Basis(Vector3.BACK, 0.38))
	_part(root, _box(Vector3(0.55, 0.45, 0.1)), teal, Vector3(-7.85, cy + 1.65, 0.0), Basis(Vector3.BACK, 0.38))
	_part(root, _box(Vector3(0.62, 0.06, 2.0)), white, Vector3(-6.7, cy + 0.32, 0.0))
	var tail := Node3D.new()
	tail.name = "TailRotor"
	tail.position = Vector3(-7.55, cy + 1.0, -0.2)
	root.add_child(tail)
	for k in 2:
		_part(tail, _box(Vector3(1.45, 0.14, 0.03)), dark, Vector3.ZERO, Basis(Vector3.BACK, PI * 0.5 * k))
	var tdisc := PlaneMesh.new()
	tdisc.size = Vector2(1.5, 1.5)
	var tdm := _part(tail, tdisc, dmat, Vector3(0.0, 0.0, -0.02), Basis(Vector3.RIGHT, PI * 0.5))
	tdm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Wheels on short struts.
	for w in [Vector3(-0.5, cy - 1.18, 0.85), Vector3(-0.5, cy - 1.18, -0.85), Vector3(2.0, cy - 1.12, 0.0)]:
		_part(root, _box(Vector3(0.1, 0.5, 0.1)), alu, w + Vector3(0.0, 0.3, -0.2 * signf(w.z)))
		_part(root, _cyl(0.24, 0.24, 0.16), rubber, w, Basis(Vector3.RIGHT, PI * 0.5))
	# Nav lights (starboard green on +Z, port red on -Z, white at the tail) and the beacons.
	_part(root, _ball(0.08), green, Vector3(0.6, cy - 0.55, 0.93))
	_part(root, _ball(0.08), red, Vector3(0.6, cy - 0.55, -0.93))
	_part(root, _ball(0.07), lamp, Vector3(-7.9, cy + 0.3, 0.0))
	_part(root, _ball(0.1), red, Vector3(-1.3, cy + 1.55, 0.0), Basis.IDENTITY, "BeaconTop")
	_part(root, _ball(0.1), red, Vector3(-0.2, cy - 1.0, 0.0), Basis.IDENTITY, "BeaconBelly")
	var flash := OmniLight3D.new()
	flash.name = "Flash"
	flash.light_color = Color(1.0, 0.15, 0.1)
	flash.omni_range = 12.0
	flash.omni_attenuation = 1.3
	flash.light_volumetric_fog_energy = 0.6
	flash.position = Vector3(-0.2, cy - 1.3, 0.0)
	root.add_child(flash)
	# A cool downlight from the belly: the wash shows in it.
	var down := OmniLight3D.new()
	down.light_color = Color(0.75, 0.85, 1.0)
	down.light_energy = 2.0
	down.omni_range = 12.0
	down.omni_attenuation = 1.0
	down.light_volumetric_fog_energy = 1.2
	down.position = Vector3(0.0, cy - 1.6, 0.0)
	root.add_child(down)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override in [red, green, lamp, windows]:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root
