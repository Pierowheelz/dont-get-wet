extends Node
## Frame-time profiler for a level (testing): --profile=OUT.json [--perf-off=a,b] [--perf-secs=N].
## Waits for the level to settle, samples CPU / GPU frame time for N seconds with vsync off, writes
## a JSON summary and quits. --perf-off switches named rendering features off first, so each
## feature's cost is the difference against a run without it.
## --perf-ab=DIR instead pauses the level and saves the same frame twice as it is (a0, a1: the
## noise floor from shader TIME) and once with --perf-off applied (b), for an image diff.

const WARMUP := 3.0

var out_path := ""
var off: PackedStringArray = []
var secs := 12.0
var ab_dir := ""
var _t := 0.0
var _armed := false
var _frames: Array = []   # [wall_ms, cpu_ms, gpu_ms, process_ms, physics_ms]
var _last_us := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			out_path = a.substr(10)
		if a.begins_with("--perf-off="):
			off = a.substr(11).split(",", false)
		if a.begins_with("--perf-secs="):
			secs = float(a.substr(12))
		if a.begins_with("--perf-ab="):
			ab_dir = a.substr(10)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().has("--perf-vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## The scene to measure: a level once its player exists, or the title screen when no --level is given.
func _level() -> Node:
	var cs := get_tree().current_scene
	if cs is Level:
		return cs if cs.player != null else null
	return cs if cs != null and Game.current_level == "" else null


func _process(delta: float) -> void:
	var lvl := _level()
	if lvl == null:
		return
	_t += delta
	if _t < WARMUP:
		return
	if ab_dir != "":
		_ab(lvl)
		set_process(false)
		return
	if not _armed:
		_armed = true
		_apply_off(lvl)
		_t = WARMUP
		_last_us = Time.get_ticks_usec()
		return
	var now := Time.get_ticks_usec()
	var wall := (now - _last_us) / 1000.0
	_last_us = now
	var vp := get_viewport().get_viewport_rid()
	_frames.append([wall,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(vp),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	if _t >= WARMUP + secs:
		_write(lvl)
		get_tree().quit()


func _ab(lvl: Node) -> void:
	get_tree().paused = true
	for shot in ["a0", "a1", "b"]:
		if shot == "b":
			_apply_off(lvl)
		for i in 8:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [ab_dir, shot])
	get_tree().quit()


func _nodes(root: Node, cls: String) -> Array:
	return root.find_children("*", cls, true, false)


func _apply_off(lvl: Node) -> void:
	var env: Environment = (_nodes(lvl, "WorldEnvironment")[0] as WorldEnvironment).environment
	var vp := get_viewport()
	for f in off:
		match f:
			"ssr": env.ssr_enabled = false
			"ssao": env.ssao_enabled = false
			"vfog": env.volumetric_fog_enabled = false
			"fog": env.fog_enabled = false
			"glow": env.glow_enabled = false
			"adjust": env.adjustment_enabled = false
			"sky":
				env.background_mode = Environment.BG_COLOR
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			"msaa": vp.msaa_3d = Viewport.MSAA_DISABLED
			"fxaa": vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"half_res": vp.scaling_3d_scale = 0.5
			"scale85": vp.scaling_3d_scale = 0.85
			"scale75": vp.scaling_3d_scale = 0.75
			"scale67": vp.scaling_3d_scale = 0.67
			"scale60": vp.scaling_3d_scale = 0.6
			"vfog64": RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)
			"shadowq1":
				RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
				RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
			"shadows":
				for l in _nodes(lvl, "Light3D"):
					l.shadow_enabled = false
			"point_shadows":
				for l in _nodes(lvl, "Light3D"):
					if not l is DirectionalLight3D:
						l.shadow_enabled = false
			"sun_shadow":
				for l in _nodes(lvl, "DirectionalLight3D"):
					l.shadow_enabled = false
			"lights":
				for l in _nodes(lvl, "Light3D"):
					if not l is DirectionalLight3D:
						l.visible = false
			"painterly":
				for c in _nodes(lvl, "CanvasLayer"):
					if c.get_script() == preload("res://src/fx/post_fx.gd"):
						c.visible = false
			"rain":
				lvl.rain_fx.visible = false
			"particles":
				for p in _nodes(lvl, "GPUParticles3D"):
					p.visible = false
					p.emitting = false
			"hud":
				lvl.hud.visible = false
			_: push_error("perf-off: unknown feature %s" % f)


func _stats(col: int) -> Dictionary:
	var v: Array = _frames.map(func(r: Array) -> float: return r[col])
	v.sort()
	var n := v.size()
	var sum := 0.0
	for x in v:
		sum += x
	return {"mean": sum / n, "p50": v[n / 2], "p95": v[int(n * 0.95)], "max": v[n - 1]}


func _write(lvl: Node) -> void:
	var lights := _nodes(lvl, "Light3D")
	var shadowed := lights.filter(func(l: Light3D) -> bool: return l.shadow_enabled and l.visible)
	var particles := 0
	for p in _nodes(lvl, "GPUParticles3D"):
		if p.visible:
			particles += p.amount
	var res := {
		"level": Game.current_level if Game.current_level != "" else "menu", "off": off, "frames": _frames.size(),
		"size": get_viewport().get_visible_rect().size,
		"adapter": RenderingServer.get_video_adapter_name(),
		"frame_ms": _stats(0), "cpu_ms": _stats(1), "gpu_ms": _stats(2),
		"process_ms": _stats(3), "physics_ms": _stats(4),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"lights": lights.size(), "shadowed_lights": shadowed.size(), "particles": particles,
		"meshes": _nodes(lvl, "MeshInstance3D").size(),
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	print("PROFILE ", JSON.stringify(res))
