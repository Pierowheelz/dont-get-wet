extends Node
## Headless gameplay tests:  godot --headless --path . res://tests/run_tests.tscn

var failures := 0
var level: Node


func _ready() -> void:
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _place(x: float, open: float, tilt := 0.0) -> float:
	var p: Player = level.player
	p.position = Vector3(x, level.ground_y(x), Tun.f("player_z"))
	p.open = open
	p.tilt = tilt
	p.visual.set_umbrella_pose(p.arm_raise(), tilt, 0.0)
	await _frames(3)
	p._update_umbrella()
	await _frames(2)
	return p._rain_exposure()


func _run() -> void:
	Game.current_level = "main_street"
	Game.autopilot = true
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	await _frames(5)
	var p: Player = level.player
	p.set_physics_process(false)
	var data: Dictionary = level.data
	var covered_x := -1.0
	var open_x := -1.0
	for lot in data["lots"]:
		if lot["cover"] == "awning" and not lot.has("tears") and lot["w"] >= 4 and covered_x < 0:
			covered_x = lot["x"] + lot["w"] * 0.5
		if lot["cover"] == "none" and lot["w"] >= 4 and open_x < 0:
			open_x = lot["x"] + lot["w"] * 0.5
	print("covered_x=", covered_x, " open_x=", open_x)
	var e := await _place(covered_x, 0.0)
	check(e < 0.05, "under awning, umbrella closed: exposure %.2f ~ 0" % e)
	e = await _place(open_x, 0.0)
	check(e > 0.95, "open sky, umbrella closed: exposure %.2f ~ 1" % e)
	e = await _place(open_x, 1.0)
	check(e < 0.4, "open sky, umbrella open: exposure %.2f < 0.4" % e)
	var sweep := []
	for o in [0.1, 0.2, 0.3, 0.4, 0.5, 0.7]:
		sweep.append("%.1f:%.2f" % [o, await _place(open_x, o)])
	print("  exposure by open amount: ", " ".join(sweep))
	var e_part := await _place(open_x, 0.65)   # canopy ~60% spread (Umbrella.canopy_spread)
	check(e_part > e and e_part < 0.95, "partly-open umbrella protects partially: %.2f" % e_part)
	# Car splash: forward tilt should shield most of it.
	for cfg in [[0.0, 0.0], [1.0, 0.0], [1.0, 0.85]]:
		await _place(open_x, cfg[0], cfg[1])
		p.wet = 0.0
		var src := Vector3(p.position.x + 2.6, 2.1, p.position.z)
		p.receive_splash(src, 28.0)
		print("  splash open=%.1f tilt=%.2f -> wet %.1f" % [cfg[0], cfg[1], p.wet])
	print("umbrella center ", p.umbrella.canopy_center(), " player ", p.global_position, " radius ", p.umbrella.current_radius())
	print("\n%s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)
