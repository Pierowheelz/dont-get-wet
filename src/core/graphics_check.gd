class_name GraphicsCheck
extends Node
## First-launch hardware check on the title screen: times the GPU rendering the menu's street and
## turns on Low graphics when the heaviest street would miss 60 fps. Runs once per save, never after
## the player has chosen a graphics setting themselves.

signal decided(low: bool, menu_gpu_ms: float)

## Heaviest street's GPU frame (p95) over the menu's (median), measured with tools/profile.sh
## at 1080p and 3440x1440: 1.34 and 1.24.
const LEVEL_OVER_MENU := 1.35
## GPU budget for the heaviest street: 60 fps with headroom for the CPU's share of the frame.
const LEVEL_BUDGET_MS := 15.0
const SKIP_S := 1.0        # menu load and first shader compiles
const MEASURE_S := 3.0
const MIN_FRAMES := 5      # a very slow GPU gets few frames in MEASURE_S

var _t := 0.0
var _samples: PackedFloat32Array = []
var _vsync := DisplayServer.VSYNC_ENABLED


static func should_run() -> bool:
	return not Game.autopilot and not Game.settings["graphics_checked"] and not Game.settings["low_quality"] \
		and DisplayServer.get_name() != "headless"


static func wants_low(menu_gpu_ms: float) -> bool:
	return menu_gpu_ms * LEVEL_OVER_MENU > LEVEL_BUDGET_MS


## The Low graphics preset for a street's environment and moon (the level and the menu backdrop).
static func apply_low(env: Environment, moon: DirectionalLight3D) -> void:
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	env.fog_density = 0.02
	env.glow_intensity = 0.5
	moon.shadow_enabled = false


func _ready() -> void:
	# With vsync on, a GPU that finishes early drops its clocks and reads up to ~1.5x slow.
	# Uncapped for these few seconds, it runs flat out and the timer reads its real cost.
	_vsync = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_t += delta
	if _t < SKIP_S:
		return
	_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	if _t < SKIP_S + MEASURE_S or _samples.size() < MIN_FRAMES:
		return
	_stop()
	queue_free()
	if Game.settings["graphics_checked"]:
		return   # the player set Low graphics while it ran
	_samples.sort()
	var gpu := _samples[_samples.size() / 2]
	for a in OS.get_cmdline_user_args():   # testing: --fake-gpu-ms=N stands in for the measurement
		if a.begins_with("--fake-gpu-ms="):
			gpu = float(a.substr(14))
	var low := wants_low(gpu)
	Game.settings["graphics_checked"] = true
	Game.settings["low_quality"] = low
	Game.save_game()
	print("graphics check: menu GPU %.2f ms -> %s" % [gpu, "Low" if low else "High"])
	decided.emit(low, gpu)


## Also when the title screen goes before the check finishes: it runs again next launch.
func _exit_tree() -> void:
	_stop()


func _stop() -> void:
	if not is_processing():
		return
	set_process(false)
	DisplayServer.window_set_vsync_mode(_vsync)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
