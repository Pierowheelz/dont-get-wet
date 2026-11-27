class_name DriveBy
extends Node3D
## The level's `drive_bys`: a black sedan that comes up the near lane of the road from behind the
## walker, splashes him as it passes, then slows ahead of him while a passenger sits up on the back
## window's sill and fires one telegraphed shot (WaterJet) back at him. When the walker passes an entry's x:
##   WARN   engine and tyre hiss from the left (the car is still out of shot), its headlights sweeping
##          the pavement ahead; the camera eases out (Level.camera_pull) so the lane is in frame.
##   PASS   its kerb-side wheels throw the road water at him (DropletBurst) from behind, then beside:
##          a canopy tilted back toward it stops what it meets.
##   AIM    once it is ahead, the passenger sits up: a 0.6 s glint, then the shot, from ahead: a
##          canopy tilted forward stops it. A shot that soaks him fails the attempt as SHOT.
##   AWAY   once the shot has landed it speeds off to the right; the camera eases back in.
## The splash and the shot are separate, each blocked its own way, so the canopy has to swing from
## back to forward between them. One car at a time; a checkpoint resume skips entries behind it.
## An entry may also set:
##   quiet    it comes with its headlights off (sidelights only), no sound and no hint while it is out
##            of shot, and the camera holds until it is about to enter the frame. The first anyone
##            hears of it is its tyres' hiss, `quiet_car_hiss_s` before the splash, and the splash is
##            a low sheet thrown across from beside him (QUIET_*), under the canopy whichever way it
##            tilts, worth `wet_quiet_splash`.
##   shot     false: no passenger and no shot. After the splash it rolls on beside him a moment,
##            then speeds away.
##   driver   "slicker": Fairweather at the wheel in his yellow slicker, hood up, dressed as
##            RaincoatFigure dresses him, turning his head to watch the walker as he goes by.

enum Phase { OFF, WARN, PASS, AIM, AWAY }

const CAR := preload("res://src/level/idling_car.gd")
const LANE_Z := 5.4           # the near lane, as the scenery traffic uses
const START_BACK := 34.0      # how far behind the walker the car is when the warning starts
const REL_SPEED := 13.0       # m/s faster than the walker until it is level with him
const PULL := 6.0             # metres the camera eases back while it passes
const SPLASH_FROM := 7.0      # its front wheel starts throwing water this far behind him...
const SPLASH_TO := 0.0        # ...and keeps on until it is level with him (the later bursts land ahead)
const SPLASH_BURSTS := 6
const SPLASH_DROPS := 160     # per burst
const SPLASH_SHARE := 0.9     # of wet_car_splash, once SPLASH_FULL of him is soaked
const SPLASH_FULL := 0.5
const SPLASH_PER_POINT := 22.0
const WHEEL := Vector3(1.35, 0.1, -0.85)    # the kerb-side front wheel, local to the car
const SPLASH_CARRY := 0.38    # share of the car's speed past him the thrown water keeps along the street
const SPLASH_UP := Vector2(5.6, 6.8)    # m/s up: a high arc that comes down on him from behind...
const SPLASH_IN := Vector2(3.2, 4.0)    # ...m/s across toward the pavement
# A quiet car's splash: a low, flat sheet off the wheel as it draws level, across the verge at his
# hips and chest. It is on him in about half a second and comes in under the canopy.
const QUIET_FROM := 1.6       # the front wheel starts throwing this far behind him...
const QUIET_TO := -0.4        # ...and stops just past him
const QUIET_CARRY := 0.12
const QUIET_UP := Vector2(3.9, 4.6)
const QUIET_IN := Vector2(5.0, 6.2)
const QUIET_HISS_FROM := 1.97 # s into car_pass at which a car warned from START_BACK is splashing him
const HISS_FADE_IN := 0.15    # s for a quiet car's hiss to come up from silence
const ROLL_REL := 3.0         # without a shot: m/s faster than him it rolls on at after the splash...
const ROLL_S := 1.4           # ...for this long once the splash has landed, before it speeds off
const MUZZLE := Vector3(-1.75, 1.3, -0.75)   # the passenger's umbrella tip as he aims back over the boot
const BRAKE := 14.0           # m/s² it sheds its speed with once past him
const AIM_LEAD := 7.5         # metres ahead of the walker the back window holds while the passenger aims
const SPLASH_LANDED := 1.1    # s into the pass by which the last of the splash on him has come down
const LEAN_AT := 1.2          # s into the pass the passenger starts to lean out (then the glint)
const LEAN_S := 0.3
const AWAY_ACCEL := 8.0
const AWAY_S := 2.2           # the camera holds out this long once it speeds away
const BACK_SEAT := Vector3(-0.75, 0.0, -0.42)
const SILL := Vector3(-0.75, 0.05, -0.75)   # where his feet are once he sits up on the back window's sill
const LEAN := 0.2             # rad he leans out toward the kerb, sitting up on the sill
const CABIN_LIGHT := 6.0      # the light on the passenger once he is up on the sill
const BRACE_BACK_S := 0.35    # the bots tilt back this long before the splash starts...
const BRACE_FIRE_S := 0.5     # ...and forward this long before the shot leaves
const SEAT_DROP := 0.47       # Fairweather's model stands this far down through the seat: hood under the roof, above the seat back
const FW_HEAD_Y := 1.67       # his eyes, up his model (the head in the side window once sunk)
const LOOK_MAX := 2.1         # rad he can turn from the windscreen toward the walker (over his shoulder)
const LOOK_RATE := 3.0        # rad/s

var level: Node
var phase := Phase.OFF
var jet: WaterJet
var splashes: Array[DropletBurst] = []
var splash_wet := 0.0         # what this car's splash put on him
var quiet := false            # the car on now (see the entry options above)
var shot := true
var slicker := false
var heard := false            # its sound has started: the first a player could know of it
var _splashes_done := 0
var _queue: Array = []        # {x, quiet, shot, slicker}, ascending x
var _next := 0
var _t := 0.0
var _speed := 0.0
var _bursts_left := 0
var _lean := 0.0
var _look := 0.0
var _car: Node3D
var _beams: Array[SpotLight3D] = []
var _passenger: Node3D
var _gun: Umbrella
var _cabin: OmniLight3D
var _hiss: AudioStreamPlayer3D
var _fairweather: Node3D      # his seat: the model and the lights that pick him out
var _fw_model: Node3D         # the walker model in the slicker, at the wheel
var _body: MeshInstance3D     # the car's body
var _closed_mesh: Mesh        # its own mesh: the cabin a solid painted box, the glass laid on it
var _open_mesh: ArrayMesh     # the same with the side windows open, for when he is at the wheel
var _frames: MeshInstance3D   # the pillars and window frames left round the open side windows
var _glass: Array[Material] = []   # the body's glass: as the kit car has it, and clearer for him


func _ready() -> void:
	for d in level.data.get("drive_bys", []):
		_queue.append({"x": float(d["x"]), "quiet": bool(d.get("quiet", false)), "shot": bool(d.get("shot", true)),
			"slicker": String(d.get("driver", "")) == "slicker"})
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	while _next < _queue.size() and _queue[_next]["x"] <= level.player.position.x:
		_next += 1
	_car = CAR.new()
	add_child(_car)
	for side in [-0.62, 0.62]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.93, 0.78)
		sl.light_energy = 14.0
		sl.spot_range = 34.0
		sl.spot_angle = 20.0
		sl.spot_attenuation = 0.6
		sl.light_volumetric_fog_energy = 3.0
		sl.position = Vector3(2.4, 0.7, side)
		# Dipped toward the kerb so the beams fall across the pavement ahead of the walker.
		sl.basis = Basis(Vector3.UP, -PI * 0.5 - 0.1) * Basis(Vector3.RIGHT, -0.06)
		_car.add_child(sl)
		_beams.append(sl)
	# It passes between the camera and the pavement, so the flank in shot is its unlit side: a cool
	# light rides above that side for the paint's shoulder and roof to catch, and the paint is a
	# shade off black so the body has a shape.
	var flank := OmniLight3D.new()
	flank.light_color = Color(0.62, 0.72, 1.0)
	flank.light_energy = 2.4
	flank.omni_range = 6.5
	flank.omni_attenuation = 1.3
	flank.light_volumetric_fog_energy = 0.0
	flank.position = Vector3(0.2, 2.5, 2.9)
	_car.add_child(flank)
	var body := _car.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var paint := body.get_surface_override_material(0) as StandardMaterial3D
	if paint:
		paint = paint.duplicate()
		paint.albedo_color = Color(0.045, 0.05, 0.065)
		paint.roughness = 0.26
		body.set_surface_override_material(0, paint)
	_passenger = (load(Player.CHARACTER_SCENE) as PackedScene).instantiate()
	_car.add_child(_passenger)
	# The cabin's light spills out with him as he sits up, or he is a dark suit against a dark street.
	_cabin = OmniLight3D.new()
	_cabin.light_color = Color(1.0, 0.84, 0.6)
	_cabin.omni_range = 2.8
	_cabin.omni_attenuation = 1.4
	_cabin.light_volumetric_fog_energy = 0.0
	_cabin.position = SILL + Vector3(-0.7, 1.6, 1.1)
	_cabin.light_energy = 0.0
	_car.add_child(_cabin)
	_gun = Umbrella.new()
	_gun.layer = Umbrella.NPC_UMBRELLA_LAYER
	_passenger.call("get_grip", &"right").add_child(_gun)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.bus = &"SFX"
	_hiss.stream = load("res://assets/audio/car_pass.ogg")
	_hiss.max_distance = 80.0
	_hiss.unit_size = 9.0
	_hiss.panning_strength = 1.6
	_hiss.pitch_scale = 0.9
	_car.add_child(_hiss)
	if _queue.any(func(d: Dictionary) -> bool: return d["slicker"]):
		_body = body
		_add_fairweather()
		_open_side_windows()
	visible = false


## Fairweather at the wheel: the walker's model in the slicker (RaincoatFigure.dress), sunk through
## the seat so his hooded head fills the side window under the roof, with a little of the
## dashboard's glow and a cool fill from the camera side so the yellow reads through the glass.
func _add_fairweather() -> void:
	_fairweather = Node3D.new()
	_fairweather.name = "Fairweather"
	_fairweather.position = CAR.DRIVER + Vector3(0.0, -SEAT_DROP, 0.0)
	_car.add_child(_fairweather)
	_fw_model = (load(Player.CHARACTER_SCENE) as PackedScene).instantiate()
	_fw_model.name = "Model"
	_fairweather.add_child(_fw_model)
	RaincoatFigure.dress(_fw_model)
	_fw_model.call("set_motion", 0.0, 0.0)
	_fw_model.call("set_stopped", true)
	# Both lights sit inside the cabin and have no specular, so the glass shows him, not them.
	var glow := OmniLight3D.new()     # the dashboard's glow, up under his hood
	glow.light_color = Color(1.0, 0.8, 0.5)
	glow.light_energy = 0.8
	glow.omni_range = 1.0
	glow.light_specular = 0.0
	glow.light_volumetric_fog_energy = 0.0
	glow.position = Vector3(0.45, FW_HEAD_Y - 0.25, 0.0)
	_fairweather.add_child(glow)
	var fill := OmniLight3D.new()     # a cool fill from the camera side, so the yellow reads
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.light_energy = 2.4
	fill.omni_range = 1.5
	fill.omni_attenuation = 1.0
	fill.light_specular = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.position = Vector3(0.1, FW_HEAD_Y + 0.1, 0.75)
	_fairweather.add_child(fill)
	_fairweather.visible = false


## The kit sedan's cabin is a painted box with its glass laid on the outside, so nobody inside it
## shows. For Fairweather the side panels behind the glass come out (the flat of each side between
## the belt and roof bevels, in the body's paint surface), and their pillars and frames go back as
## painted strips round the glass, so he is seen through the windows. The measurements are
## car_sedan's greenhouse (tools/blender/props.py, sedan): belt and roof, each side's glass at the
## same fractions along it.
const CABIN_BELT := [-1.62, 0.95, 0.94, 0.9]    # rear x, front x, y, half width at the belt line
const CABIN_ROOF := [-0.98, 0.28, 1.42, 0.76]   # ... and at the roof line
const GLASS_U := [[0.1, 0.5], [0.54, 0.9]]      # rear to front along the side, each pane
const GLASS_V := [0.12, 0.86]                   # belt to roof


func _open_side_windows() -> void:
	_closed_mesh = _body.mesh
	_open_mesh = ArrayMesh.new()
	for i in _closed_mesh.get_surface_count():
		var arrays := _closed_mesh.surface_get_arrays(i)
		if i == 0:
			arrays = _without_side_panels(arrays)
		_open_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_open_mesh.surface_set_material(i, _closed_mesh.surface_get_material(i))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var strips := [[0.0, GLASS_U[0][0], 0.0, 1.0], [GLASS_U[0][1], GLASS_U[1][0], 0.0, 1.0],
			[GLASS_U[1][1], 1.0, 0.0, 1.0], [GLASS_U[0][0], GLASS_U[1][1], 0.0, GLASS_V[0]],
			[GLASS_U[0][0], GLASS_U[1][1], GLASS_V[1], 1.0]]
		for r in strips:
			var q := [_side_point(side, r[0], r[2]), _side_point(side, r[1], r[2]), _side_point(side, r[1], r[3]),
				_side_point(side, r[0], r[3])]
			st.set_normal(Vector3(0.0, 0.0, side))
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[k])
	_frames = MeshInstance3D.new()
	_frames.mesh = st.commit()
	var paint := (_body.get_surface_override_material(0) as StandardMaterial3D)
	if paint:
		paint = paint.duplicate()
		paint.cull_mode = BaseMaterial3D.CULL_DISABLED
		_frames.material_override = paint
	_frames.visible = false
	_body.add_child(_frames)
	_glass = [_body.get_surface_override_material(2), _body.get_surface_override_material(2)]
	if _glass[0] is StandardMaterial3D:
		_glass[1] = _glass[0].duplicate()
		(_glass[1] as StandardMaterial3D).albedo_color.a = 0.25


## A point on one side of the greenhouse: u from rear to front, v from belt to roof.
func _side_point(side: float, u: float, v: float) -> Vector3:
	var belt := Vector3(lerpf(CABIN_BELT[0], CABIN_BELT[1], u), CABIN_BELT[2], side * CABIN_BELT[3])
	var roof := Vector3(lerpf(CABIN_ROOF[0], CABIN_ROOF[1], u), CABIN_ROOF[2], side * CABIN_ROOF[3])
	return belt.lerp(roof, v)


## The paint surface's triangles less the flat of each greenhouse side (facing out across the
## street, between the belt and roof bevels).
func _without_side_panels(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var mid := (a + b + c) / 3.0
		var n := (b - a).cross(c - a).normalized()
		var side_panel := absf(n.z) > 0.8 and absf(mid.z) > 0.6 and mid.y > CABIN_BELT[2] + 0.05 			and mid.y < CABIN_ROOF[2] - 0.05 and mid.x > CABIN_BELT[0] and mid.x < CABIN_BELT[1]
		if not side_panel:
			kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
	arrays[Mesh.ARRAY_INDEX] = kept
	return arrays


## Where the next one starts (INF when none is left).
func next_x() -> float:
	return _queue[_next]["x"] if _next < _queue.size() else INF


## A car is on its way or still in shot, as far as anyone could tell (a quiet one from its hiss): no
## resting, no refilling, keep the canopy up.
func coming() -> bool:
	return phase != Phase.OFF and phase != Phase.AWAY and heard


## Which way the canopy should face now: -1 back toward the car's splash, +1 forward toward the
## passenger's shot, 0 when neither is due (the bots tilt this way, and only then: tilted over, the
## canopy lets the rain in). A quiet car's sheet comes in under the canopy whichever way it tilts, so
## it reads 0 until a passenger's shot is due.
func brace() -> float:
	if not heard:
		return 0.0
	match phase:
		Phase.WARN:
			if quiet:
				return 0.0
			return -1.0 if _to_splash() / REL_SPEED < BRACE_BACK_S else 0.0
		Phase.PASS:
			if _t < SPLASH_LANDED:
				return 0.0 if quiet else -1.0
			if not shot:
				return 0.0
			return 1.0 if LEAN_AT + LEAN_S + WaterJet.GLINT_S - _t < BRACE_FIRE_S else 0.0
		Phase.AIM:
			if jet == null or not is_instance_valid(jet) or jet.phase == WaterJet.Phase.SPENT:
				return 0.0
			return 1.0 if jet.time_to_fire() < BRACE_FIRE_S else 0.0
	return 0.0


## Metres the front wheel still has to close before it starts throwing water at him.
func _to_splash() -> float:
	return level.player.position.x - (position.x + WHEEL.x) - (QUIET_FROM if quiet else SPLASH_FROM)


func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null:
		return
	_t += delta
	var playing := p.state == Player.State.WALK or p.state == Player.State.STOPPED
	match phase:
		Phase.OFF:
			if playing and _next < _queue.size() and p.position.x >= _queue[_next]["x"]:
				_begin()
				_next += 1
			return
		Phase.WARN:
			_speed = p.speed + REL_SPEED
			if quiet:
				_quiet_cues()
			if _to_splash() <= 0.0:
				_set_phase(Phase.PASS)
				_bursts_left = SPLASH_BURSTS
		Phase.PASS:
			if _bursts_left > 0:
				_speed = p.speed + REL_SPEED
				var done := float(SPLASH_BURSTS - _bursts_left) / float(SPLASH_BURSTS - 1)
				var from := lerpf(QUIET_FROM, QUIET_TO, done) if quiet else lerpf(SPLASH_FROM, SPLASH_TO, done)
				if p.position.x - (position.x + WHEEL.x) <= from:
					_splash(p)
					_bursts_left -= 1
			elif not shot:
				_speed = move_toward(_speed, p.speed + ROLL_REL, BRAKE * delta)
			else:
				_speed = move_toward(_speed, _hold_speed(p, REL_SPEED), BRAKE * delta)
			if not shot:
				if _t >= SPLASH_LANDED + ROLL_S:
					_set_phase(Phase.AWAY)
			else:
				_t_lean(delta, _t >= LEAN_AT)
				if _t >= LEAN_AT + LEAN_S:
					_set_phase(Phase.AIM)
					jet = WaterJet.fire(level, _muzzle)
		Phase.AIM:
			_speed = move_toward(_speed, _hold_speed(p, 4.0), BRAKE * delta)
			_t_lean(delta, true)
			if jet == null or not is_instance_valid(jet) or jet.phase == WaterJet.Phase.SPENT:
				_set_phase(Phase.AWAY)
		Phase.AWAY:
			_speed += AWAY_ACCEL * delta
			_t_lean(delta, false)
			if _t >= AWAY_S:
				level.set("camera_pull", 0.0)
				if position.x > level.camera.global_position.x + 40.0:
					_set_phase(Phase.OFF)
					visible = false
					_hiss.stop()
	if heard and _hiss.volume_db < 0.0:
		_hiss.volume_db = minf(_hiss.volume_db + 40.0 * delta / HISS_FADE_IN, 0.0)
	position.x += _speed * delta
	_pose()
	_look_at_walker(delta, p)


## A quiet car gives itself away only as it arrives: `quiet_car_hiss_s` before the splash its tyres'
## hiss starts and the camera eases out, nothing sooner.
func _quiet_cues() -> void:
	var eta := _to_splash() / REL_SPEED
	if not heard and eta <= Tun.f("quiet_car_hiss_s"):
		heard = true
		level.set("camera_pull", PULL)
		_hiss.volume_db = -40.0
		_hiss.play(maxf(QUIET_HISS_FROM - eta, 0.0))


## Speed that brings the back window to AIM_LEAD ahead of him and holds it there.
func _hold_speed(p: Player, faster: float) -> float:
	var ahead := position.x + BACK_SEAT.x - p.position.x
	return p.speed + clampf((AIM_LEAD - ahead) * 2.0, -2.0, faster)


func _begin() -> void:
	var p: Player = level.player
	# The entry due (a plain car if none is: a test or debug call may send one past the last).
	var d: Dictionary = _queue[_next] if _next < _queue.size() else {"quiet": false, "shot": true, "slicker": false}
	quiet = d["quiet"]
	shot = d["shot"]
	slicker = d["slicker"]
	position = Vector3(p.position.x - START_BACK, LevelBuilder.ROAD_Y, LANE_Z)
	_speed = p.speed + REL_SPEED
	_lean = 0.0
	_look = 0.0
	jet = null
	splashes.clear()
	splash_wet = 0.0
	_splashes_done = 0
	_set_phase(Phase.WARN)
	visible = true
	for b in _beams:
		b.visible = not quiet    # a quiet car comes on its sidelights (the kit car's own dim lamps)
	_car.driver.visible = not slicker
	if _fairweather:
		_fairweather.visible = slicker
		_body.mesh = _open_mesh if slicker else _closed_mesh
		_body.set_surface_override_material(2, _glass[1] if slicker else _glass[0])
		_frames.visible = slicker
	heard = not quiet
	_hiss.volume_db = 0.0
	if quiet:
		return
	level.set("camera_pull", PULL)
	_hiss.play()
	if level.has_method("hint_once"):
		level.hint_once("drive_by", "Headlights. Behind.", 3.0)


func _set_phase(ph: Phase) -> void:
	phase = ph
	_t = 0.0


## One burst of road water off the kerb-side front wheel, thrown up and over at the pavement and
## carried forward by the car's speed: from behind him at first, then from beside him. A quiet car's
## is a low sheet thrown straight across at him.
func _splash(p: Player) -> void:
	var at := global_transform * WHEEL
	var starts := PackedVector3Array()
	var vels := PackedVector3Array()
	var fwd: float = p.speed + REL_SPEED * (QUIET_CARRY if quiet else SPLASH_CARRY)
	var up := QUIET_UP if quiet else SPLASH_UP
	var across := QUIET_IN if quiet else SPLASH_IN
	for i in SPLASH_DROPS:
		starts.append(at + Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.1), randf_range(-0.1, 0.1)))
		vels.append(Vector3(fwd + randf_range(-1.0, 1.0), randf_range(up.x, up.y), -randf_range(across.x, across.y)))
	var amount := Tun.f("wet_quiet_splash" if quiet else "wet_car_splash") * SPLASH_SHARE / float(SPLASH_BURSTS)
	var b := DropletBurst.spawn(level, starts, vels, amount, {"full": SPLASH_FULL / float(SPLASH_BURSTS),
		"per_point": SPLASH_PER_POINT / float(SPLASH_BURSTS), "cause": &"splash", "color": Color(0.7, 0.78, 0.9, 0.55)})
	splashes.append(b)
	b.done.connect(func(_landed: int, _stopped: int) -> void:
		splash_wet += b.given_to(p)
		_splashes_done += 1
		if _splashes_done == SPLASH_BURSTS and is_instance_valid(p):
			p.splash_done(splash_wet))
	if _bursts_left == SPLASH_BURSTS:
		var au: Node = level.get("audio")
		if au and au.has_method("play"):
			au.play("car_splash", -2.0, 1.15)


## The passenger's aim: out of the back window, back down the street (WaterJet reads the shaft as +y).
func _muzzle() -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, PI * 0.5), global_transform * MUZZLE)


func _t_lean(delta: float, out: bool) -> void:
	_lean = move_toward(_lean, 1.0 if out else 0.0, delta / LEAN_S)


## The passenger sits low in the back, then sits up on the kerb-side back window's sill, his chest
## above the roof, facing back down the street with the furled umbrella levelled at the walker.
func _pose() -> void:
	var l := smoothstep(0.0, 1.0, _lean)
	_passenger.visible = shot and (l > 0.02 or phase == Phase.AIM)
	_cabin.light_energy = CABIN_LIGHT * l
	_passenger.basis = Basis(Vector3.RIGHT, -LEAN * l) * Basis(Vector3.UP, PI)
	_passenger.position = (BACK_SEAT + Vector3(0.0, -0.75, 0.0)).lerp(SILL, l)
	_passenger.call("set_motion", 0.0, 0.0)
	_passenger.call("set_stopped", true)
	var aim := WaterJet.AIM_TILT * l
	_passenger.call("set_umbrella_pose", lerpf(0.0, WaterJet.AIM_RAISE, l), aim, 0.0)
	_passenger.call("set_umbrella_open", 0.0)
	_gun.set_state(0.0, Game.umbrella_radius(0), 0.0)


## Fairweather keeps his eyes on the walker: eyes front while the car is far behind him, turning
## toward the kerb as it draws level and back over his shoulder once it is past.
func _look_at_walker(delta: float, p: Player) -> void:
	if not slicker or _fairweather == null:
		return
	var d := _car.to_local(p.global_position + Vector3(0.0, 1.5, 0.0)) - _fairweather.position
	var want := clampf(atan2(-d.z, d.x), -LOOK_MAX, LOOK_MAX)
	_look = move_toward(_look, want, LOOK_RATE * delta)
	_fw_model.rotation.y = _look
