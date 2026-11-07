extends Node
## Registers input actions at startup and exposes analog control values that merge
## gamepad, keyboard/mouse and touch sources.

const DEADZONE := 0.08

## Set by the on-screen touch controls.
var touch_umbrella := 0.0
var touch_hurry := 0.0
var touch_tilt := 0.0
var touch_stop := false

## Mouse-wheel tilt is sticky: each notch nudges it, it resets when the umbrella closes.
var wheel_tilt := 0.0
var last_device := &"keyboard"   # &"keyboard", &"gamepad", &"touch"
const RAMP := 10.0               # digital inputs reach full in ~0.1 s (DESIGN §3)
var _ramped := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_axis(&"umbrella", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_key(&"umbrella", KEY_SPACE)
	_mouse(&"umbrella", MOUSE_BUTTON_RIGHT)
	_axis(&"hurry", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_key(&"hurry", KEY_SHIFT)
	_key(&"hurry_half", KEY_W)
	_key(&"hurry_half", KEY_D)
	_button(&"stop", JOY_BUTTON_LEFT_SHOULDER)
	_key(&"stop", KEY_S)
	_key(&"stop", KEY_CTRL)
	_axis(&"tilt_forward", JOY_AXIS_RIGHT_X, 1.0)
	_axis(&"tilt_back", JOY_AXIS_RIGHT_X, -1.0)
	_key(&"tilt_forward", KEY_E)
	_key(&"tilt_back", KEY_Q)
	_button(&"pause", JOY_BUTTON_START)
	_key(&"pause", KEY_ESCAPE)
	_key(&"pause", KEY_P)
	_button(&"restart", JOY_BUTTON_BACK)
	_key(&"restart", KEY_R)


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)


func _axis(action: StringName, axis: JoyAxis, dir: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = dir
	InputMap.action_add_event(action, ev)


func _button(action: StringName, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _key(action: StringName, key: Key) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _mouse(action: StringName, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


## Analog values pass straight through; digital jumps are eased so keys feel like triggers.
func _ramp(key: StringName, target: float) -> float:
	var now := Time.get_ticks_usec() / 1000000.0
	var prev: Array = _ramped.get(key, [target, now])
	var v := move_toward(float(prev[0]), target, RAMP * maxf(now - float(prev[1]), 0.0))
	if absf(target - float(prev[0])) < 0.2:
		v = target          # analog movement: no lag
	_ramped[key] = [v, now]
	return v


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		last_device = &"gamepad"
	elif event is InputEventKey or event is InputEventMouseButton:
		last_device = &"keyboard"
	elif event is InputEventScreenTouch:
		last_device = &"touch"
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel_tilt = clampf(wheel_tilt + 0.25, -1.0, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel_tilt = clampf(wheel_tilt - 0.25, -1.0, 1.0)


## 0..1 how far the umbrella trigger is held.
func umbrella() -> float:
	return _ramp(&"umbrella", clampf(maxf(Input.get_action_strength(&"umbrella"), touch_umbrella), 0.0, 1.0))


## 0..1 hurry amount (1 = full run).
func hurry() -> float:
	var v := Input.get_action_strength(&"hurry")
	if Input.is_action_pressed(&"hurry_half"):
		v = maxf(v, 0.5)
	return _ramp(&"hurry", clampf(maxf(v, touch_hurry), 0.0, 1.0))


## -1..1 tilt request (+ = forward).
func tilt() -> float:
	var stick := Input.get_action_strength(&"tilt_forward") - Input.get_action_strength(&"tilt_back")
	var v := stick
	if absf(touch_tilt) > absf(v):
		v = touch_tilt
	if absf(wheel_tilt) > absf(v):
		v = wheel_tilt
	return clampf(v, -1.0, 1.0)


func stop_pressed() -> bool:
	var t := touch_stop
	touch_stop = false
	return Input.is_action_just_pressed(&"stop") or t
