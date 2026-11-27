class_name Squall
extends Node3D
## The level's `squalls`: gusts that come down the lane. When the walker passes an entry's x, a gust
## sets off START_OFF metres upwind of that x (from ahead in a headwind or no wind, from behind in a
## tailwind: the sign of the street's `wind` there) and its front blows down the lane at SPEED for
## TRAVEL metres. Each spot it reaches is in the gust for the entry's `dur` seconds from the moment the
## front passes, rising over RISE and dying over FALL, so the gust is a band SPEED x dur long moving
## down the lane.
##
## In it the rain slants hard (Level.wind adds `gust_wind` in its direction), the trees shed their
## water on whoever is under them (Player._shower_exposure: only the open canopy straight above keeps
## it off) and an open umbrella is shoved about and costs `stamina_drain_gust`.
##
## Every gust is a pure function of the level clock from the moment it was triggered, so gameplay
## (Level.gust_at), the bots (they predict it with gust_at), the picture and the sound all agree.
## Telegraph: the roar rising from upwind from the moment it is triggered, the trees and hedges
## thrashing as the front reaches them (the `gust` uniform of every `&"foliage"` node, by its x),
## leaves and spray streaming along the hedge tops ahead of it, and the first one's hint. A checkpoint
## resume skips every entry whose x is behind it.

const SPEED := 8.0            # m/s the front blows down the lane
const START_OFF := 20.0       # it sets off this far upwind of the trigger x: from ahead it meets a walking walker ~2.2 s later
const TRAVEL := 70.0          # metres the front blows before the gust dies away
const END_FADE := 6.0         # it builds over this much of its path at the start and dies over this much at the end
const RISE := 0.4             # s a spot takes to reach full strength once the front reaches it
const FALL := 0.8             # s it takes to die away at the end of `dur`
const DUR := 3.0              # an entry's `dur` when it leaves it out
const STIR_M := 8.0           # the foliage stirs this far downwind of the front, before it arrives...
const STIR := 0.3             # ...up to this much
const ROAR_RISE_S := 1.2      # the roar swells over this long from the trigger
const ROAR_DB := 0.0
const LEAF_SPEED := 12.0      # m/s leaves and spray fly downwind, outrunning the front
const SHOWER_Y := 3.5         # the trees' water falls from under their canopies, about here
const VIEW_M := 32.0          # leaves, spray and the trees' shower are drawn within this of the camera
const HINT_DUR := 4.0

var level: Node
var entries: Array = []       # {x, dur} from the level, ascending x
var gusts: Array = []         # one per triggered entry: see launch()
var _next := 0
var _extra := 0.0             # visuals carry on after the gameplay clock stops
var _last_elapsed := -1.0
var _roar: AudioStream
var _foliage: Array = []      # [node, ShaderMaterials with a `gust` uniform, those with `gust_dir`, last value]
var _foliage_gathered := false
var _showers: Array = []      # [x0, x1, GPUParticles3D] under each lot of trees
var _low := false


func _ready() -> void:
	for s in level.data.get("squalls", []):
		entries.append({"x": float(s["x"]), "dur": maxf(float(s.get("dur", DUR)), 0.1)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	while _next < entries.size() and entries[_next]["x"] <= level.player.position.x:
		_next += 1
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists("res://assets/audio/gust_loop" + ext):
			_roar = load("res://assets/audio/gust_loop" + ext)
			break
	if _roar is AudioStreamWAV:
		var w := _roar as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif _roar is AudioStreamOggVorbis:
		(_roar as AudioStreamOggVorbis).loop = true
	_low = Game.settings.get("low_quality", false)
	if not entries.is_empty():
		for span in level.tree_spans:
			var sh := _make_shower(span[0], span[1])
			add_child(sh)
			_showers.append([span[0], span[1], sh])


## Where the next one is triggered (INF when none is left).
func next_x() -> float:
	return entries[_next]["x"] if _next < entries.size() else INF


# --- the gust: pure functions of the level clock --------------------------------------------------

## Sets entry `i`'s gust off at level-clock time t0. Everything it does follows from here.
func launch(i: int, t0: float) -> Dictionary:
	var e: Dictionary = entries[i]
	var dir := 1.0 if level.wind(e["x"], false) > 0.0 else -1.0
	var g := {"i": i, "t0": t0, "dir": dir, "dur": e["dur"], "start": e["x"] - dir * START_OFF, "fx": null}
	g["end"] = t0 + TRAVEL / SPEED + e["dur"]
	gusts.append(g)
	if is_inside_tree():
		if not _foliage_gathered:
			_gather_foliage()
		_dress(g)
	return g


## Signed 0..1 strength of gust g at x at level-clock time t (+ blowing toward +X).
func _push(g: Dictionary, x: float, t: float) -> float:
	var s: float = (x - g["start"]) * g["dir"]
	if s < 0.0 or s > TRAVEL:
		return 0.0
	var u: float = t - g["t0"] - s / SPEED
	var dur: float = g["dur"]
	if u <= 0.0 or u >= dur:
		return 0.0
	var k := minf(minf(u / RISE, (dur - u) / FALL), 1.0)
	k *= clampf(s / END_FADE, 0.0, 1.0) * clampf((TRAVEL - s) / END_FADE, 0.0, 1.0)
	return k * g["dir"]


## Signed strength of the strongest gust at x at level-clock time t (+ blowing toward +X).
func push_at(x: float, t: float) -> float:
	var best := 0.0
	for g: Dictionary in gusts:
		var k := _push(g, x, t)
		if absf(k) > absf(best):
			best = k
	return best


## 0..1 how hard a gust is blowing at x at level-clock time t.
func gust_at(x: float, t: float) -> float:
	return absf(push_at(x, t))


## Seconds until a triggered gust reaches x (0 while one is on x, INF if none will).
func gust_eta(x: float, t: float) -> float:
	var best := INF
	for g: Dictionary in gusts:
		var s: float = (x - g["start"]) * g["dir"]
		if s < 0.0 or s > TRAVEL:
			continue
		var arrive: float = g["t0"] + s / SPEED
		if t < arrive + g["dur"]:
			best = minf(best, maxf(arrive - t, 0.0))
	return best


## Where gust g's band lies at time t: [upwind end, downwind end] as x, or [] before it sets off.
func _band(g: Dictionary, t: float) -> Array:
	var tau: float = t - g["t0"]
	if tau < 0.0:
		return []
	var front: float = g["start"] + g["dir"] * minf(SPEED * tau, TRAVEL)
	var tail: float = g["start"] + g["dir"] * clampf(SPEED * (tau - g["dur"]), 0.0, TRAVEL)
	return [minf(front, tail), maxf(front, tail)]


## 0..1 how hard foliage at x thrashes: the gust itself, and a stir just ahead of its front.
func foliage_at(x: float, t: float) -> float:
	var v := 0.0
	for g: Dictionary in gusts:
		v = maxf(v, absf(_push(g, x, t)))
		var tau: float = t - g["t0"]
		if tau >= 0.0 and SPEED * tau < TRAVEL:
			var ahead: float = (x - g["start"]) * g["dir"] - SPEED * tau
			if ahead > 0.0 and ahead < STIR_M:
				v = maxf(v, STIR * (1.0 - ahead / STIR_M) * clampf(tau / ROAR_RISE_S, 0.0, 1.0))
	return v


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
		level.hint_once("gust", "A gust. Umbrella up under the trees ({umbrella}).", HINT_DUR)
	var t: float = level.elapsed + _extra
	var cam: Camera3D = level.camera
	var cx := cam.global_position.x if cam else p.position.x
	for g: Dictionary in gusts:
		if g["fx"] != null:
			_draw(g, t, cx, p.position.x)
	_shake_foliage(t)
	for sh: Array in _showers:
		var k := 0.0
		if absf(clampf(cx, sh[0], sh[1]) - cx) < VIEW_M:
			k = gust_at(clampf(p.position.x, sh[0], sh[1]), t)
		var ps: GPUParticles3D = sh[2]
		ps.emitting = k > 0.05
		ps.amount_ratio = clampf(k, 0.0, 1.0)


func _draw(g: Dictionary, t: float, cx: float, px: float) -> void:
	var fx: Dictionary = g["fx"]
	if t > g["end"] + 2.5:
		for n: Node in fx.values():
			n.queue_free()
		g["fx"] = null
		return
	var band := _band(g, t)
	if band.is_empty():
		return
	var dir: float = g["dir"]
	var swell := clampf((t - g["t0"]) / ROAR_RISE_S, 0.0, 1.0) * clampf(g["end"] - t, 0.0, 1.0)
	# The roar comes from the nearest part of the gust; inside it, from just upwind of him.
	var roar: AudioStreamPlayer3D = fx.get("roar")
	if roar:
		var sx := clampf(px, band[0], band[1])
		if sx == px:
			sx = px - dir * 2.0
		roar.global_position = Vector3(sx, 2.5, 1.6)
		roar.volume_db = ROAR_DB + linear_to_db(maxf(swell, 0.001))
	# Leaves and spray stream along the hedge tops from the upwind edge of the frame, or from the
	# front while it is still coming, and fly on ahead of it.
	var ex := clampf(cx - dir * 10.0, band[0], band[1])
	var on: bool = band[1] - band[0] > 0.5 and absf(ex - cx) < VIEW_M and t < g["end"]
	for key in ["leaves", "spray"]:
		var ps: GPUParticles3D = fx[key]
		ps.emitting = on
		ps.amount_ratio = swell
		ps.global_position.x = ex


## Thrashes every `&"foliage"` node by the gust at its x.
func _shake_foliage(t: float) -> void:
	for f: Array in _foliage:
		var n: Node3D = f[0]
		if not is_instance_valid(n):
			continue
		var v := foliage_at(n.global_position.x, t)
		if absf(v - f[3]) < 0.005:
			continue
		f[3] = v
		if n.has_method("set_gust"):
			n.call("set_gust", v)
		for m: ShaderMaterial in f[1]:
			m.set_shader_parameter("gust", v)
		var push := push_at(n.global_position.x, t)
		for m: ShaderMaterial in f[2]:
			m.set_shader_parameter("gust_dir", signf(push) if push != 0.0 else -1.0)


## Finds the street's foliage: nodes in group `&"foliage"`. One with a `set_gust(v)` method is driven
## through it; otherwise every ShaderMaterial on it or under it that declares a `gust` uniform gets its
## own copy (so each tree moves by its own x) and is set directly, `gust_dir` too if it has one.
func _gather_foliage() -> void:
	_foliage_gathered = true
	for n in get_tree().get_nodes_in_group(&"foliage"):
		if not n is Node3D:
			continue
		var mats: Array = []
		var dirs: Array = []
		if not n.has_method("set_gust"):
			var geoms: Array = n.find_children("*", "GeometryInstance3D", true, false)
			if n is GeometryInstance3D:
				geoms.push_front(n)
			for gi: GeometryInstance3D in geoms:
				_own_materials(gi, mats, dirs)
		_foliage.append([n, mats, dirs, 0.0])


func _own_materials(gi: GeometryInstance3D, mats: Array, dirs: Array) -> void:
	if gi.material_override is ShaderMaterial:
		var m := _own(gi.material_override as ShaderMaterial, mats, dirs)
		if m:
			gi.material_override = m
		return
	var mi := gi as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var sm := mi.get_active_material(i) as ShaderMaterial
		if sm:
			var m := _own(sm, mats, dirs)
			if m:
				mi.set_surface_override_material(i, m)


## A copy of `sm` for one node if its shader has a `gust` uniform, else null.
func _own(sm: ShaderMaterial, mats: Array, dirs: Array) -> ShaderMaterial:
	if sm.shader == null:
		return null
	var names := sm.shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
	if not names.has("gust"):
		return null
	var m := sm.duplicate() as ShaderMaterial
	m.set_shader_parameter("gust", 0.0)
	mats.append(m)
	if names.has("gust_dir"):
		dirs.append(m)
	return m


# --- the picture and the sound --------------------------------------------------------------------

## Gives a triggered gust its roar and its leaves and spray.
func _dress(g: Dictionary) -> void:
	var fx := {}
	var leaves := _make_leaves(g["dir"])
	add_child(leaves)
	fx["leaves"] = leaves
	var spray := _make_spray(g["dir"])
	add_child(spray)
	fx["spray"] = spray
	if _roar:
		var snd := AudioStreamPlayer3D.new()
		snd.stream = _roar
		snd.bus = &"SFX"
		snd.unit_size = 9.0
		snd.max_distance = 90.0
		snd.panning_strength = 1.3
		snd.volume_db = -60.0
		snd.position = Vector3(g["start"], 2.5, 1.6)
		add_child(snd)
		snd.play(float(g["i"] % 4) * 1.4)
		fx["roar"] = snd
	g["fx"] = fx


## Torn leaves tumbling along the hedge tops and past him, downwind and faster than the front.
func _make_leaves(dir: float) -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = 50 if _low else 140
	sp.lifetime = 2.2
	sp.local_coords = false
	sp.emitting = false
	sp.position = Vector3(0.0, 2.3, 0.2)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.0, 0.9, 1.3)
	pm.direction = Vector3(dir, 0.12, 0.25)
	pm.spread = 14.0
	pm.initial_velocity_min = LEAF_SPEED * 0.7
	pm.initial_velocity_max = LEAF_SPEED * 1.15
	pm.gravity = Vector3(0, -1.6, 0)
	pm.damping_min = 0.1
	pm.damping_max = 0.5
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.hue_variation_min = -0.06
	pm.hue_variation_max = 0.08
	pm.turbulence_enabled = not _low
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.085)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.55, 0.6, 0.28)
	lm.roughness = 0.7
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	lm.vertex_color_use_as_albedo = true
	lm.emission_enabled = true
	lm.emission = Color(0.22, 0.24, 0.1)
	q.material = lm
	sp.draw_pass_1 = q
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visibility_aabb = AABB(Vector3(-30, -4, -4), Vector3(60, 10, 8))
	return sp


## Water torn off the hedge tops and the verge in streaks.
func _make_spray(dir: float) -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = 90 if _low else 240
	sp.lifetime = 0.7
	sp.local_coords = false
	sp.emitting = false
	sp.position = Vector3(0.0, 1.75, 0.6)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.5, 0.35, 1.4)
	pm.direction = Vector3(dir, 0.05, 0.1)
	pm.spread = 8.0
	pm.initial_velocity_min = LEAF_SPEED * 0.8
	pm.initial_velocity_max = LEAF_SPEED * 1.3
	pm.gravity = Vector3(0, -4.0, 0)
	pm.particle_flag_align_y = true
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.42)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.albedo_color = Color(0.72, 0.8, 0.92, 0.35)
	q.material = dm
	sp.draw_pass_1 = q
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visibility_aabb = AABB(Vector3(-30, -3, -4), Vector3(60, 8, 8))
	return sp


## The trees' water coming down in sheets of big drops under a lot of trees, from x0 to x1.
func _make_shower(x0: float, x1: float) -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	var w := maxf(x1 - x0, 1.0)
	sp.amount = int(w * (8.0 if _low else 22.0))
	sp.lifetime = 0.8
	sp.local_coords = false
	sp.emitting = false
	sp.position = Vector3((x0 + x1) * 0.5, SHOWER_Y, 1.6)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.5, 0.4, 1.7)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.24)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.albedo_color = Color(0.7, 0.78, 0.9, 0.4)
	q.material = dm
	sp.draw_pass_1 = q
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visibility_aabb = AABB(Vector3(-w * 0.5 - 1.0, -SHOWER_Y - 0.5, -2.5), Vector3(w + 2.0, SHOWER_Y + 1.5, 5.0))
	return sp
