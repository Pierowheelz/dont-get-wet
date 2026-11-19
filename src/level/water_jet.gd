class_name WaterJet
extends Node3D
## A telegraphed shotgun splash of water fired from an umbrella's tip. For `glint` seconds a glint
## flashes at the muzzle (it follows the muzzle while the shooter aims), then a burst of pellets
## (a DropletBurst) leaves the way the umbrella points, nearly flat (SHOT_ELEV) and fast enough to
## reach his chest where he'll be. Each pellet that reaches his body wets him (WetBody.soak, cause "shot", so a
## shot that soaks him fails the attempt as SHOT); his canopy or an awning stops the ones that meet it, and
## a canopy that stops a good share is shoved aside for a moment (Player.jet_shove; Sturdy Frame
## tiers resist). What wets him is exactly what the player sees reach him.
##   var jet := WaterJet.fire(level, func() -> Transform3D: return Transform3D(umb.global_basis, tip))
##   jet.resolved.connect(func(blocked: bool) -> void: ...)

signal resolved(blocked: bool)

enum Phase { GLINT, TRAVEL, SPENT }

const GLINT_S := 0.6
const AIM_TILT := 1.36        # rad of forward tilt a shooter holds: the shaft ~12° above level
const AIM_RAISE := 0.25       # arm raise while aiming: the umbrella down at his chest, not overhead
const SHOT_ELEV := 0.09       # rad above level the burst leaves at: fast and nearly flat
const GRAVITY := 9.8
const PELLETS := 46
const SPREAD := 0.045         # rad, up and down: a tight burst, strung out along its path
const SPREAD_Z := 0.02        # rad across the street
const SPEED_JITTER := 0.13    # the burst strings out along its path more than it spreads
const HIT_FULL := 0.5         # share of his body (DropletBurst.exposure) a shot must soak to wet him `amount`
const HIT_PER_POINT := 3.0    # pellets that soak one body point
const SHOVE_MIN := 0.2        # share of the pellets his canopy has to stop before it's knocked aside
const AIM_Y := 1.25           # the burst is aimed at his chest

var level: Node
var muzzle: Callable          # () -> Transform3D: origin at the muzzle, basis.y along the shaft
var shooter: WetBody          # the one firing it, whom it never wets (null: scenery)
var amount := -1.0            # wetness of a full hit; -1 = Tun "wet_jet_hit"
var always_hits := false      # the canopy can't save him (the courier's parting shots)
var glint_s := GLINT_S
var phase := Phase.GLINT
var blocked := false
var burst: DropletBurst
var _flight := 1.0            # s until the centre pellet reaches him: the shot is decided just after
var _t := 0.0
var _glint: MeshInstance3D
var _flash: OmniLight3D
var _puff: GPUParticles3D


static func fire(p_level: Node, p_muzzle: Callable, p_amount := -1.0, p_glint := GLINT_S) -> WaterJet:
	var jet := WaterJet.new()
	jet.level = p_level
	jet.muzzle = p_muzzle
	jet.amount = p_amount
	jet.glint_s = p_glint
	p_level.add_child(jet)
	return jet


## [launch velocity, flight time] of the centre pellet: out the way the shaft points (along the
## street), SHOT_ELEV above level, fast enough to reach `aim` where a mark walking at `lead_speed` will be.
static func solve(from: Vector3, shaft: Vector3, aim: Vector3, lead_speed := 0.0) -> Array:
	var side := signf(shaft.x) if absf(shaft.x) > 0.05 else signf(aim.x - from.x)
	var elev := SHOT_ELEV
	var sol := Vector2.ZERO
	for i in 2:   # lead him by the flight time
		var dx := maxf((aim.x + lead_speed * sol.y - from.x) * side, 0.8)
		sol = ballistic(elev, dx, from.y - aim.y)
	var v := Vector3(side * cos(elev), sin(elev), 0.0) * sol.x
	v.z = (aim.z - from.z) / sol.y
	return [v, sol.y]


## Launch speed along a shaft at `elev` above level that carries a pellet `dx` metres out and `dy`
## metres down (negative: up) onto the mark. The arc's flight time comes back as y.
static func ballistic(elev: float, dx: float, dy: float) -> Vector2:
	var c := cos(elev)
	var den := 2.0 * c * c * (dx * tan(elev) + dy)
	var v := sqrt(GRAVITY * dx * dx / maxf(den, 0.05))
	return Vector2(v, dx / (v * c))


## Seconds until the burst leaves the muzzle (0 once it has).
func time_to_fire() -> float:
	return maxf(glint_s - _t, 0.0) if phase == Phase.GLINT else 0.0


## The pellets' launch velocities round `v0`: fanned up and down in the walker's plane, a little
## across it, and strung out in speed.
static func pellets(v0: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var speed := v0.length()
	var d := v0 / speed
	var up := Vector3(-d.y, d.x, 0.0).normalized() if absf(d.x) + absf(d.y) > 0.01 else Vector3.UP
	var across := d.cross(up).normalized()
	for i in PELLETS:
		var dir := (d + up * randf_range(-SPREAD, SPREAD) + across * randf_range(-SPREAD_Z, SPREAD_Z)).normalized()
		out.append(dir * speed * (1.0 + randf_range(-SPEED_JITTER, SPEED_JITTER)))
	return out


func _ready() -> void:
	_glint = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_glint.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.no_depth_test = true
	gm.albedo_texture = _star_tex()
	gm.albedo_color = Color(0.9, 0.97, 1.0)
	_glint.material_override = gm
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glint)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(0.8, 0.9, 1.0)
	_flash.omni_range = 2.5
	_flash.light_energy = 0.0
	add_child(_flash)
	_puff = _make_puff()
	add_child(_puff)
	_glint.global_position = muzzle.call().origin


func _process(delta: float) -> void:
	_t += delta
	match phase:
		Phase.GLINT:
			var f := _t / glint_s
			_glint.global_position = muzzle.call().origin
			var pulse := 0.25 + 0.4 * sin(PI * minf(f * 1.4, 1.0)) + 0.05 * sin(_t * 60.0)
			_glint.scale = Vector3.ONE * pulse
			_glint.rotation.z = f * 1.2
			_flash.global_position = _glint.global_position
			_flash.light_energy = 2.0 * pulse
			if _t >= glint_s:
				_launch(level.player)
		Phase.TRAVEL:
			# Decided once the burst has gone past him; strays fly on and fall, but he can lower the canopy.
			if _t >= _flight * (1.0 + SPEED_JITTER) + 0.1:
				_on_landed(burst.landed_on(level.player), burst.stopped_by(level.player), level.player)
		Phase.SPENT:
			if _t >= 1.0:
				queue_free()


func _launch(p: Player) -> void:
	var m: Transform3D = muzzle.call()
	var from := m.origin
	var aim := p.global_position + Vector3(0.0, AIM_Y, 0.0)
	var sol := solve(from, m.basis.y.normalized(), aim, p.speed)
	var v0: Vector3 = sol[0]
	_flight = sol[1]
	var vels := pellets(v0)
	var starts := PackedVector3Array()
	starts.resize(vels.size())
	starts.fill(from)
	var full := amount if amount >= 0.0 else Tun.f("wet_jet_hit")
	burst = DropletBurst.spawn(level, starts, vels, full,
		{"full": HIT_FULL, "per_point": HIT_PER_POINT, "cause": &"shot", "shooter": shooter, "through_umbrella": always_hits,
		"size": 0.12, "trail": 5, "color": Color(0.78, 0.88, 1.0, 0.85)})
	phase = Phase.TRAVEL
	_t = 0.0
	_glint.visible = false
	_flash.light_energy = 0.0
	_puff.global_position = from
	(_puff.process_material as ParticleProcessMaterial).direction = v0.normalized()
	_puff.restart()
	_sound("car_splash", -8.0, 2.1)


## The burst has gone past him: blocked if none reached him. A canopy that stopped enough of them is shoved.
func _on_landed(landed: int, stopped: int, p: Player) -> void:
	blocked = landed == 0
	if stopped >= PELLETS * SHOVE_MIN and is_instance_valid(p):
		p.jet_shove(Tun.f("jet_shove") * Game.jet_shove_mult() * clampf(float(stopped) / (PELLETS * 0.6), 0.0, 1.0))
	if is_instance_valid(p):
		var key := "jets_blocked" if blocked else "jets_hit"
		p.stats[key] = int(p.stats.get(key, 0)) + 1
		_sound("puddle_splash" if blocked else "car_splash", -3.0 if blocked else -1.0, 1.3 if blocked else 1.4)
	phase = Phase.SPENT
	_t = 0.0
	resolved.emit(blocked)


func _sound(name: String, db: float, pitch: float) -> void:
	var au: Node = level.get("audio")
	if au and au.has_method("play"):
		au.play(name, db, pitch)


## A small puff of spray at the muzzle as it fires.
func _make_puff() -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = 28
	sp.lifetime = 0.35
	sp.one_shot = true
	sp.explosiveness = 0.92
	sp.emitting = false
	sp.top_level = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1.0, 0.2, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.75, 0.85, 1.0, 0.75)
	dm.albedo_texture = CarHazard._droplet_tex()
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = dm
	sp.draw_pass_1 = q
	sp.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	return sp


## A four-pointed star: a soft core with long thin rays, white on clear.
static func _star_tex() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var core := exp(-(u * u + v * v) * 18.0)
			var rays := exp(-absf(u) * 40.0) * (1.0 - absf(v)) + exp(-absf(v) * 40.0) * (1.0 - absf(u))
			var a := clampf(core + rays * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
