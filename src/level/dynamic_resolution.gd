class_name DynamicResolution
extends Node
## Lowers the 3D render resolution while a street misses 60 fps on a GPU-bound machine, and raises
## it again once there's headroom. The painterly filter blurs detail finer than its brush anyway.

const STEPS: Array[float] = [1.0, 0.85, 0.75, 0.67, 0.6]
const FRAME_MISS_MS := 18.2    # slower than 55 fps
const GPU_BUDGET_MS := 15.0
const WINDOW_S := 1.0
const SETTLE_S := 2.0          # after the street loads and after each change
const UP_HEADROOM := 0.85      # step up when the predicted GPU time fits this share of the budget
const UP_AFTER_S := 4.0        # ...for this long
const UP_LOCK_S := 60.0        # no stepping up for this long after a step up had to be undone

## The step the last street ended on, so the next one starts there instead of relearning it.
static var _carry := 0

var step := 0   # index into STEPS
var clock := 0.0
var _settle := SETTLE_S
var _window := 0.0
var _frame_ms: PackedFloat32Array = []
var _gpu_ms: PackedFloat32Array = []
var _last_us := 0
var _headroom_s := 0.0
var _last_up_s := -1e9
var _up_locked_until := 0.0


func _ready() -> void:
	if Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--profile=")):
		queue_free()   # the profiler compares fixed configurations
		return
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_set_step(_carry)
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	_carry = step
	get_viewport().scaling_3d_scale = 1.0


func _process(delta: float) -> void:
	# Wall time, not delta: --fixed-fps runs report a constant delta.
	var now := Time.get_ticks_usec()
	var wall := (now - _last_us) / 1000.0
	_last_us = now
	clock += delta
	if _settle > 0.0:
		_settle -= delta
		return
	_frame_ms.append(wall)
	_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	_window += delta
	if _window < WINDOW_S:
		return
	var frame := _median(_frame_ms)
	var gpu := _median(_gpu_ms)
	_frame_ms.clear()
	_gpu_ms.clear()
	_window = 0.0
	observe(frame, gpu)


## One second's median frame and GPU time (ms) in; steps the resolution when they call for it.
func observe(frame: float, gpu: float) -> void:
	if frame > FRAME_MISS_MS and gpu > GPU_BUDGET_MS and step < STEPS.size() - 1:
		if clock - _last_up_s < SETTLE_S + WINDOW_S * 3.0:
			_up_locked_until = clock + UP_LOCK_S
		_set_step(step + 1)
		return
	var predicted := gpu * pow(STEPS[maxi(step - 1, 0)] / STEPS[step], 2.0)
	if step > 0 and clock >= _up_locked_until and predicted < GPU_BUDGET_MS * UP_HEADROOM:
		_headroom_s += WINDOW_S
		if _headroom_s >= UP_AFTER_S:
			_last_up_s = clock
			_set_step(step - 1)
	else:
		_headroom_s = 0.0


func _set_step(i: int) -> void:
	step = i
	_headroom_s = 0.0
	_settle = SETTLE_S
	get_viewport().scaling_3d_scale = STEPS[i]
	if OS.get_cmdline_user_args().has("--fps-log"):
		print("dynamic resolution: %.2f" % STEPS[i])


static func _median(v: PackedFloat32Array) -> float:
	var s := v.duplicate()
	s.sort()
	return s[s.size() / 2]
