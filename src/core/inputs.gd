extends Node
## Registers input actions at startup and exposes analog control values that merge
## gamepad, keyboard/mouse and touch sources.

const DEADZONE := 0.08

## Set by the on-screen touch controls.
var touch_umbrella := 0.0
var touch_hurry := 0.0
var touch_tilt := 0.0
var touch_stop := false

## Mouse tilt is sticky: sideways mouse motion moves it (left = back, right = forward) and it
## resets when the umbrella closes. Only counts while gameplay has the mouse captured.
var mouse_tilt := 0.0
## Fraction of the screen height of mouse travel that takes the umbrella from upright to full tilt.
const MOUSE_TILT_TRAVEL := 0.25
## Device the player is actually using; prompts/hints follow it. Starts as gamepad when one is
## plugged in, then switches on the first real press (key/mouse button/pad button/stick push).
var last_device := &"keyboard"   # &"keyboard", &"gamepad", &"touch"
signal device_changed(device: StringName)
const RAMP := 10.0               # digital inputs reach full in ~0.1 s (DESIGN §3)
var _ramped := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Input.get_connected_joypads().is_empty():
		last_device = &"gamepad"
	Input.joy_connection_changed.connect(_on_joy_connection)
	# Window-level hook sees every event before any node can mark it handled.
	get_window().window_input.connect(_track_device)
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
	_axis(&"tilt_forward_l", JOY_AXIS_LEFT_X, 1.0)
	_axis(&"tilt_back_l", JOY_AXIS_LEFT_X, -1.0)
	_key(&"tilt_forward_key", KEY_E)
	_key(&"tilt_back_key", KEY_Q)
	_button(&"pause", JOY_BUTTON_START)
	_key(&"pause", KEY_ESCAPE)
	_key(&"pause", KEY_P)
	_button(&"restart", JOY_BUTTON_BACK)
	# City map: shoulder buttons pick the map or the upgrade panel (mouse covers both on keyboard).
	_button(&"panel_map", JOY_BUTTON_LEFT_SHOULDER)
	_button(&"panel_shop", JOY_BUTTON_RIGHT_SHOULDER)
	# Godot's built-in UI actions have no gamepad face buttons by default: A = select, B = back.
	_button(&"ui_accept", JOY_BUTTON_A)
	_button(&"ui_cancel", JOY_BUTTON_B)
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
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return
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


func _set_device(dev: StringName) -> void:
	if dev != last_device:
		last_device = dev
		device_changed.emit(dev)


func _on_joy_connection(_device: int, connected: bool) -> void:
	if connected:
		_set_device(&"gamepad")
	elif last_device == &"gamepad" and Input.get_connected_joypads().is_empty():
		_set_device(&"keyboard")


## Only deliberate presses count: key/button releases (e.g. the Enter that launched the game, the
## click that focused the window) and small stick/trigger noise must not flip the device.
func _track_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if event.pressed:
			_set_device(&"gamepad")
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			_set_device(&"gamepad")
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.pressed and not event.is_echo():
			_set_device(&"keyboard")
	elif event is InputEventScreenTouch:
		if event.pressed:
			_set_device(&"touch")


## Short control prompt for a gameplay action on the current device ("Hold RT" / "Space").
func prompt(action: String) -> String:
	var pad := last_device == &"gamepad"
	match action:
		"umbrella": return "Hold RT" if pad else "Hold Right Mouse / Space"
		"hurry": return "LT" if pad else "Shift (W for a brisk walk)"
		"tilt": return "Either stick" if pad else "Move the mouse or Q / E"
		"tilt_forward": return "stick →" if pad else "mouse right / E"
		"stop": return "LB" if pad else "S"
	return action


## Fills {action} tokens in a hint with prompts for the current device.
func format_prompts(text: String) -> String:
	for a in ["umbrella", "hurry", "tilt_forward", "tilt", "stop"]:
		text = text.replace("{%s}" % a, prompt(a))
	return text


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var dx: float = event.screen_relative.x
		var travel := maxf(DisplayServer.screen_get_size().y * MOUSE_TILT_TRAVEL, 1.0)
		mouse_tilt = clampf(mouse_tilt + dx / travel, -1.0, 1.0)
		if absf(dx) > 4.0:
			_set_device(&"keyboard")


## The cursor is hidden and captured only while the walker is actually out walking; pause,
## end screens, menus, touch play and bot runs get the normal cursor.
func _process(_delta: float) -> void:
	var want := Input.MOUSE_MODE_CAPTURED if _in_gameplay() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _in_gameplay() -> bool:
	if Game.autopilot or last_device == &"touch" or get_tree().paused:
		return false
	var lvl := get_tree().current_scene as Level
	if lvl == null or lvl.player == null or lvl.finished:
		return false
	return lvl.player.state == Player.State.WALK or lvl.player.state == Player.State.STOPPED


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
	# Either stick tilts; if both are pushed at once, average them so they don't fight.
	var right := Input.get_action_strength(&"tilt_forward") - Input.get_action_strength(&"tilt_back")
	var left := Input.get_action_strength(&"tilt_forward_l") - Input.get_action_strength(&"tilt_back_l")
	var stick := (right + left) * 0.5 if (right != 0.0 and left != 0.0) else right + left
	var keys := Input.get_action_strength(&"tilt_forward_key") - Input.get_action_strength(&"tilt_back_key")
	var v := stick
	if absf(keys) > absf(v):
		v = keys
	if absf(touch_tilt) > absf(v):
		v = touch_tilt
	if absf(mouse_tilt) > absf(v):
		v = mouse_tilt
	return clampf(v, -1.0, 1.0)


func stop_held() -> bool:
	return Input.is_action_pressed(&"stop") or touch_stop
