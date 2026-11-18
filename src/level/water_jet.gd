class_name WaterJet
extends Node3D
## A telegraphed jet of water fired at the walker. For GLINT_S a glint flashes at the muzzle (it
## follows `muzzle` while the shooter aims), then a stream crosses to him at SPEED. Where it meets him
## decides it (block_share): an open canopy that shields most of his body from the muzzle blocks it,
## and the shove knocks the canopy aside for a moment (Player.jet_shove; Sturdy Frame tiers resist).
## Otherwise it soaks him (Player.soak, cause "shot", so a jet that soaks him fails the attempt as SHOT).
##   var jet := WaterJet.fire(level, func() -> Vector3: return tip.global_position)
##   jet.resolved.connect(func(blocked: bool) -> void: ...)

signal resolved(blocked: bool)

enum Phase { GLINT, TRAVEL, SPENT }

const GLINT_S := 0.6
const SPEED := 16.0
const BLOCK_SHARE := 0.5     # weighted share of his body the canopy must shield from the muzzle
const AIM_Y := 1.25          # the stream aims at his chest
const FADE_S := 0.25

var level: Node
var muzzle: Callable          # () -> Vector3, world position of the muzzle
var phase := Phase.GLINT
var blocked := false
var _t := 0.0
var _from := Vector3.ZERO
var _head := 0.0              # metres of stream out of the muzzle
var _glint: MeshInstance3D
var _flash: OmniLight3D
var _stream: MeshInstance3D
var _stream_mat: StandardMaterial3D
var _spray: GPUParticles3D


static func fire(p_level: Node, p_muzzle: Callable) -> WaterJet:
	var jet := WaterJet.new()
	jet.level = p_level
	jet.muzzle = p_muzzle
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


## What a jet from `from` does to him: blocked (and the canopy shoved) or a hit that soaks him.
static func strike(p: Player, from: Vector3) -> bool:
	var stopped := block_share(p, from) >= BLOCK_SHARE
	if stopped:
		p.jet_shove(Tun.f("jet_shove") * Game.jet_shove_mult())
	else:
		p.soak(Tun.f("wet_jet_hit"), &"shot")
	var key := "jets_blocked" if stopped else "jets_hit"
	p.stats[key] = int(p.stats.get(key, 0)) + 1
	return stopped


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
	_stream = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.045
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	_stream.mesh = cyl
	_stream_mat = StandardMaterial3D.new()
	_stream_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stream_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stream_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_stream_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.85)
	_stream.material_override = _stream_mat
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stream.visible = false
	add_child(_stream)
	_spray = _make_spray()
	add_child(_spray)
	_glint.global_position = muzzle.call()
	_sound("token", -10.0, 1.7)


func _process(delta: float) -> void:
	_t += delta
	var p: Player = level.player
	match phase:
		Phase.GLINT:
			var f := _t / GLINT_S
			_glint.global_position = muzzle.call()
			var pulse := 0.25 + 0.4 * sin(PI * minf(f * 1.4, 1.0)) + 0.05 * sin(_t * 60.0)
			_glint.scale = Vector3.ONE * pulse
			_glint.rotation.z = f * 1.2
			_flash.global_position = _glint.global_position
			_flash.light_energy = 2.0 * pulse
			if _t >= GLINT_S:
				phase = Phase.TRAVEL
				_from = muzzle.call()
				_glint.visible = false
				_flash.light_energy = 0.0
				_stream.visible = true
				_sound("puddle_splash", -6.0, 1.9)
		Phase.TRAVEL:
			var to := _aim(p)
			_head += SPEED * delta
			var reach := _from.distance_to(to)
			_draw_stream(_from, _from.lerp(to, minf(_head / reach, 1.0)))
			if _head >= reach:
				phase = Phase.SPENT
				_t = 0.0
				blocked = strike(p, _from)
				_spray.global_position = _impact(p, to)
				_spray.restart()
				_sound("puddle_splash" if blocked else "car_splash", -3.0 if blocked else -2.0, 1.3 if blocked else 1.5)
				resolved.emit(blocked)
		Phase.SPENT:
			_stream_mat.albedo_color.a = 0.85 * (1.0 - _t / FADE_S)
			if _t >= FADE_S:
				_stream.visible = false
			if _t >= 1.2:
				queue_free()


func _aim(p: Player) -> Vector3:
	return p.global_position + Vector3(0.0, AIM_Y, 0.0)


## Where the stream breaks: on the canopy if it got in the way, else on his coat.
func _impact(p: Player, to: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(_from, to, Player.UMBRELLA_MASK)
	q.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if blocked and not hit.is_empty() else to - (to - _from).normalized() * 0.15


func _draw_stream(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := maxf(d.length(), 0.01)
	_stream.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d / len)) * Basis.from_scale(Vector3(1.0, len, 1.0)), (a + b) * 0.5)


func _sound(name: String, db: float, pitch: float) -> void:
	var au: Node = level.get("audio")
	if au and au.has_method("play"):
		au.play(name, db, pitch)


func _make_spray() -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = 90
	sp.lifetime = 0.6
	sp.one_shot = true
	sp.explosiveness = 0.9
	sp.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1.0, 0.8, 0.0)
	pm.spread = 60.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.75, 0.85, 1.0, 0.7)
	dm.albedo_texture = CarHazard._droplet_tex()
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = dm
	sp.draw_pass_1 = q
	sp.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
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
