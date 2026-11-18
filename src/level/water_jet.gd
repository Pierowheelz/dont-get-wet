class_name WaterJet
extends Node3D
## A telegraphed shotgun splash of water fired from an umbrella's tip. For `glint` seconds a glint
## flashes at the muzzle (it follows the muzzle while the shooter aims), then a burst of pellets
## leaves along the shaft, the way the umbrella points. The shaft can't point level (it is held at
## least MIN_ELEV up), so the burst arcs up and falls onto him; the shooter judges the range, so its
## speed is what lands it on his chest. Where it comes down decides it (block_share, from INCOMING_S
## back along the arc): an open canopy that shields most of his body blocks it, and the shove knocks
## the canopy aside for a moment (Player.jet_shove; Sturdy Frame tiers resist). Otherwise it soaks him
## (Player.soak, cause "shot", so a shot that soaks him fails the attempt as SHOT).
##   var jet := WaterJet.fire(level, func() -> Transform3D: return Transform3D(umb.global_basis, tip))
##   jet.resolved.connect(func(blocked: bool) -> void: ...)

signal resolved(blocked: bool)

enum Phase { GLINT, TRAVEL, SPENT }

const GLINT_S := 0.6
const AIM_TILT := 1.2         # rad of forward tilt a shooter holds: the shaft ~21° above level
const MIN_ELEV := 0.3         # rad: the shaft is never held flatter than this
const MAX_ELEV := 1.15
const GRAVITY := 9.8
const PELLETS := 46
const SPREAD := 0.1           # rad of cone half-angle
const SPEED_JITTER := 0.13     # the burst strings out along its path more than it spreads
const TRAIL := 5              # ghost copies behind each pellet, so it reads as a streak
const TRAIL_DT := 0.014
const BLOCK_SHARE := 0.5      # weighted share of his body the canopy must shield
const AIM_Y := 1.25           # the burst comes down on his chest
const INCOMING_S := 0.3       # the shot is judged from this far back along its arc

var level: Node
var muzzle: Callable          # () -> Transform3D: origin at the muzzle, basis.y along the shaft
var amount := -1.0            # wetness of a hit; -1 = Tun "wet_jet_hit"
var always_hits := false      # the canopy can't save him (the courier's parting shots)
var glint_s := GLINT_S
var phase := Phase.GLINT
var blocked := false
var _t := 0.0
var _from := Vector3.ZERO
var _v0 := Vector3.ZERO       # the centre pellet's launch velocity
var _flight := 1.0            # s until the centre pellet reaches his chest
var _pellets: Array = []      # [velocity offset from _v0 (Vector3)]
var _glint: MeshInstance3D
var _flash: OmniLight3D
var _mm: MultiMeshInstance3D
var _puff: GPUParticles3D
var _spray: GPUParticles3D


static func fire(p_level: Node, p_muzzle: Callable, p_amount := -1.0, p_glint := GLINT_S) -> WaterJet:
	var jet := WaterJet.new()
	jet.level = p_level
	jet.muzzle = p_muzzle
	jet.amount = p_amount
	jet.glint_s = p_glint
	p_level.add_child(jet)
	return jet


## Weighted share (0..1) of the walker's body samples that his canopy hides from `from`. A shut or
## dropped umbrella shields nothing.
static func block_share(p: Player, from: Vector3) -> float:
	if p._dropped_umbrella or p.open < 0.5:
		return 0.0
	var space := p.get_world_3d().direct_space_state
	var total := 0.0
	var shielded := 0.0
	for s in Player.SAMPLES:
		var at := p._sample_world(s[0])
		total += s[1]
		var q := PhysicsRayQueryParameters3D.create(from, at, Player.UMBRELLA_MASK)
		q.hit_back_faces = true
		q.hit_from_inside = true
		if not space.intersect_ray(q).is_empty():
			shielded += s[1]
	return shielded / total


## What a shot coming in from `from` does to him: blocked (and the canopy shoved) or a hit that soaks
## him by `wet` (default Tun "wet_jet_hit").
static func strike(p: Player, from: Vector3, wet := -1.0, force_hit := false) -> bool:
	var stopped := not force_hit and block_share(p, from) >= BLOCK_SHARE
	if stopped:
		p.jet_shove(Tun.f("jet_shove") * Game.jet_shove_mult())
	else:
		p.soak(wet if wet >= 0.0 else Tun.f("wet_jet_hit"), &"shot")
	var key := "jets_blocked" if stopped else "jets_hit"
	p.stats[key] = int(p.stats.get(key, 0)) + 1
	return stopped


## Launch speed along a shaft at `elev` above level that carries a pellet `dx` metres out and `dy`
## metres down (negative: up) onto the mark. The arc's flight time comes back as y.
static func ballistic(elev: float, dx: float, dy: float) -> Vector2:
	var c := cos(elev)
	var den := 2.0 * c * c * (dx * tan(elev) + dy)
	var v := sqrt(GRAVITY * dx * dx / maxf(den, 0.05))
	return Vector2(v, dx / (v * c))


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
	_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var dq := QuadMesh.new()
	dq.size = Vector2(0.12, 0.12)
	dq.material = _droplet_mat()
	mm.mesh = dq
	mm.instance_count = PELLETS * (TRAIL + 1)
	mm.visible_instance_count = 0
	_mm.multimesh = mm
	_mm.top_level = true
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.extra_cull_margin = 16.0
	add_child(_mm)
	_puff = _make_spray(28, 0.35, 0.8, 2.2)
	add_child(_puff)
	_spray = _make_spray(120, 0.7, 1.8, 4.2)
	add_child(_spray)
	_glint.global_position = muzzle.call().origin
	_sound("token", -10.0, 1.7)


func _process(delta: float) -> void:
	_t += delta
	var p: Player = level.player
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
				_launch(p)
		Phase.TRAVEL:
			_draw_pellets(_t)
			if _t >= _flight:
				_resolve(p)
		Phase.SPENT:
			if _t >= 1.2:
				queue_free()


## The burst leaves along the shaft. Its speed is set so the centre pellet comes down on his chest
## where he'll be by then (he keeps walking).
func _launch(p: Player) -> void:
	var m: Transform3D = muzzle.call()
	_from = m.origin
	var shaft := m.basis.y.normalized()
	var aim := p.global_position + Vector3(0.0, AIM_Y, 0.0)
	var side := signf(shaft.x) if absf(shaft.x) > 0.05 else signf(aim.x - _from.x)
	var elev := clampf(atan2(shaft.y, absf(shaft.x)), MIN_ELEV, MAX_ELEV)
	var sol := Vector2.ZERO
	for i in 2:   # lead him by the flight time
		var dx := maxf((aim.x + p.speed * sol.y - _from.x) * side, 0.8)
		sol = ballistic(elev, dx, _from.y - aim.y)
	_flight = sol.y
	_v0 = Vector3(side * cos(elev), sin(elev), 0.0) * sol.x
	_v0.z = (aim.z - _from.z) / _flight
	for i in PELLETS:
		var u := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0)
		var dir := (_v0.normalized() + u * SPREAD).normalized()
		_pellets.append(dir * _v0.length() * (1.0 + randf_range(-SPEED_JITTER, SPEED_JITTER)) - _v0)
	phase = Phase.TRAVEL
	_t = 0.0
	_glint.visible = false
	_flash.light_energy = 0.0
	_puff_at(_from, _v0.normalized())
	_sound("car_splash", -8.0, 2.1)


func _pos(t: float, dv := Vector3.ZERO) -> Vector3:
	var v := _v0 + dv
	return _from + v * t + Vector3(0.0, -0.5 * GRAVITY * t * t, 0.0)


func _draw_pellets(t: float) -> void:
	var mm := _mm.multimesh
	mm.visible_instance_count = mm.instance_count
	var fade := clampf(t / 0.08, 0.0, 1.0)
	for i in PELLETS:
		for k in TRAIL + 1:
			var tk := maxf(t - k * TRAIL_DT, 0.0)
			var s := 1.0 - 0.14 * k
			mm.set_instance_transform(i * (TRAIL + 1) + k, Transform3D(Basis.from_scale(Vector3.ONE * s), _pos(tk, _pellets[i])))
			mm.set_instance_color(i * (TRAIL + 1) + k, Color(1, 1, 1, fade * (0.85 - 0.13 * k)))


func _resolve(p: Player) -> void:
	phase = Phase.SPENT
	_t = 0.0
	_mm.multimesh.visible_instance_count = 0
	var incoming := _pos(maxf(_flight - INCOMING_S, 0.0))
	blocked = strike(p, incoming, amount, always_hits)
	var to := _pos(_flight)
	_spray.global_position = _impact(incoming, to)
	var pm := _spray.process_material as ParticleProcessMaterial
	pm.direction = Vector3(signf(_v0.x) * 0.6, 0.9 if blocked else 0.5, 0.0)
	_spray.restart()
	_sound("puddle_splash" if blocked else "car_splash", -3.0 if blocked else -1.0, 1.3 if blocked else 1.4)
	resolved.emit(blocked)


## Where it breaks: on the canopy if it got in the way, else on his coat.
func _impact(from: Vector3, to: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, to, Player.UMBRELLA_MASK)
	q.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if blocked and not hit.is_empty() else to - (to - from).normalized() * 0.15


func _puff_at(at: Vector3, dir: Vector3) -> void:
	_puff.global_position = at
	(_puff.process_material as ParticleProcessMaterial).direction = dir
	_puff.restart()


func _sound(name: String, db: float, pitch: float) -> void:
	var au: Node = level.get("audio")
	if au and au.has_method("play"):
		au.play(name, db, pitch)


static func _droplet_mat() -> StandardMaterial3D:
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(0.78, 0.88, 1.0, 1.0)
	dm.albedo_texture = CarHazard._droplet_tex()
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	return dm


## A one-shot burst of droplets, like a car's splash.
func _make_spray(n: int, life: float, v_min: float, v_max: float) -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = n
	sp.lifetime = life
	sp.one_shot = true
	sp.explosiveness = 0.92
	sp.emitting = false
	sp.top_level = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1.0, 0.8, 0.0)
	pm.spread = 55.0
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.14
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var dm := _droplet_mat()
	dm.vertex_color_use_as_albedo = false
	dm.albedo_color = Color(0.75, 0.85, 1.0, 0.75)
	q.material = dm
	sp.draw_pass_1 = q
	sp.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
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
