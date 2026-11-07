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
	_run_tests()
	print("\n%s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- runs: one per direction out of the start street ------------------------------------------

func _run_tests() -> void:
	var g := {
		"s": {"map_pos": [0.5, 0.5], "neighbors": ["a", "b"]},
		"a": {"map_pos": [0.3, 0.5], "neighbors": ["s", "c", "c2"]},
		"c": {"map_pos": [0.1, 0.5], "neighbors": ["a"]},
		"c2": {"map_pos": [0.6, 0.2], "neighbors": ["a"]},
		"b": {"map_pos": [0.7, 0.5], "neighbors": ["s", "d"]},
		"d": {"map_pos": [0.9, 0.5], "neighbors": ["b", "e"]},
		"e": {"map_pos": [0.95, 0.5], "neighbors": ["d"]},
	}
	var br := Game.derive_branches(g, "s")
	check(br == {"s": "", "a": "left", "c": "left", "c2": "left", "b": "right", "d": "right", "e": "right"},
		"branches follow the start neighbour a street is reached through: %s" % br)

	var start := Game.start_node
	var lefts: Array = Game.nodes.keys().filter(func(id: String) -> bool: return Game.branch[id] == "left")
	var rights: Array = Game.nodes.keys().filter(func(id: String) -> bool: return Game.branch[id] == "right")
	var lnb: String = Game.neighbors(start).filter(func(id: String) -> bool: return Game.branch[id] == "left")[0]
	var rnb: String = Game.neighbors(start).filter(func(id: String) -> bool: return Game.branch[id] == "right")[0]
	check(Game.branch[start] == "" and lefts.size() >= 2 and rights.size() >= 1, "city map has the start between two sides")

	var undecided := Run.new("", start)
	undecided.completed = [start]
	Game.runs = {"": undecided}
	Game.run = undecided
	check(Game.can_select(lnb) and Game.can_select(rnb), "undecided run can head either way from the start")
	Game.choose(start)
	check(Game.run.direction == "" and Game.runs.keys() == [""], "replaying the start street doesn't pick a direction")
	Game.choose(rnb)
	check(Game.run == undecided and Game.run.direction == "right" and Game.runs.keys() == ["right"],
		"first street off the start commits the undecided run to that side: %s" % [Game.runs.keys()])
	check(Game.run.completed == [start], "committed run keeps its progress")
	check(not Game.can_select(lnb) and Game.can_select(rnb) and Game.can_select(start),
		"a right run can't select the left branch, still selects the start and the right")
	Game.run.completed = [start, rnb]
	Game.run.current_node = rnb
	Game.choose(lnb)
	check(Game.run.direction == "right", "a committed run never changes direction")

	var dir := OS.get_temp_dir().path_join("dgw_tests_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	Game.save_path = dir.path_join("save.json")
	Game.autopilot = false

	var legacy := func(current: String, walked: Array) -> void:
		var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"current_node": current, "completed": walked, "tokens": 9,
			"best": {start: {"score": 800, "wet": 10.0, "time": 40.0, "grade": "B"}},
			"upgrades": {"sturdy": 1, "wide": 0, "light": 2}, "settings": {"music": 0.3}}))
		f.close()
		Game.load_game()
	legacy.call(rnb, [start, lnb, rnb])
	check(Game.runs.keys() == ["right"] and Game.run.direction == "right" and Game.run.current_node == rnb,
		"old save on both sides migrates to current_node's side: %s" % [Game.runs.keys()])
	check(Game.run.tokens == 9 and Game.run.upgrades[&"light"] == 2 and Game.run.best.has(start) and Game.settings["music"] == 0.3,
		"old save keeps tokens, upgrades, bests and settings")
	legacy.call(start, [start, lefts[0], lefts[1], rights[0]])
	check(Game.runs.keys() == ["left"] and Game.run.current_node == start,
		"old save back on the start migrates to the side with more streets walked: %s" % [Game.runs.keys()])
	legacy.call(start, [start])
	check(Game.runs.keys() == [""], "old save with only the start migrates to an undecided run")

	Game.reset_progress()
	Game.new_run("left")
	Game.run.tokens = 7
	Game.run.completed = [start, lnb]
	Game.run.current_node = lnb
	Game.run.best = {lnb: {"score": 912, "wet": 4.0, "time": 51.0, "grade": "A"}}
	Game.run.upgrades[&"sturdy"] = 2
	Game.new_run("right")
	Game.run.tokens = 3
	Game.run.completed = [start]
	Game.save_game()
	Game.runs = {}
	Game.load_game()
	var l: Run = Game.runs.get("left")
	var r: Run = Game.runs.get("right")
	check(l != null and r != null and Game.run == r, "both runs reload, the last one played is active")
	check(l.tokens == 7 and l.current_node == lnb and l.completed == [start, lnb] and int(l.best[lnb]["score"]) == 912 \
		and l.upgrades[&"sturdy"] == 2, "left run reloads with its own progress")
	check(r.tokens == 3 and r.completed == [start] and r.upgrades[&"sturdy"] == 0, "right run reloads with its own progress")
	Game.resume_run("left")
	Game.run.current_node = start
	check(Game.can_select(lnb) and not Game.can_select(rnb), "a reloaded left run, back on the start, still locks out the right branch")

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	Game.autopilot = true
	Game.runs = {}
	Game.run = Run.new("", start)
