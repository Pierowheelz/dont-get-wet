extends Node
## Headless gameplay tests:  godot --headless --path . res://tests/run_tests.tscn
## Loaded and judged by tests/test_main.gd, which also fails the run on any logged error.

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


func _test_sun_drying() -> void:
	var sun: Array = []
	for f in level.data["features"]:
		if f["type"] == "sun":
			sun = [f["x"], f["x"] + f["w"]]
	if sun.is_empty():
		check(false, "main_street has a sun break to test")
		return
	var x: float = (sun[0] + sun[1]) * 0.5
	var shut: float = level.dry_rate(x, 0.0)
	check(shut > 0.0, "sun break, umbrella closed: dries at %.2f/s" % shut)
	check(level.dry_rate(x, 1.0) == 0.0, "sun break, umbrella open: the canopy shades him, no drying")
	check(Player.dry_factor(0.95) == 1.0 and Player.dry_factor(0.5) < 0.05,
		"drying runs at full rate when soaked and almost stops when fairly dry (%.3f at 50%%)" % Player.dry_factor(0.5))
	check(not level.player._exposed_at(x), "autopilot treats the sunlit lot as safe, so it closes the umbrella")


func _test_feedback_url() -> void:
	var url := Game.feedback_url()
	check(url.contains("template=feedback.yml") and url.ends_with("&version=%s" % ProjectSettings.get_setting("application/config/version")),
		"feedback link opens the form with the version filled in")


func _test_checkpoints() -> void:
	var cps: Array = level.checkpoints
	check(cps.size() == 3 and cps[0] < cps[1] and cps[1] < cps[2], "main_street has three ascending checkpoints: %s" % [cps])
	var p: Player = level.player
	Game.checkpoint = {}
	p.wet = 12.5
	p.stamina = 61.0
	level.elapsed = 33.0
	p.stats["puddles"] = 3
	var x1: float = cps[0]
	p.position = Vector3(x1 + 0.2, level.ground_y(x1), Tun.f("player_z"))
	level._check_checkpoints()
	var cp: Dictionary = Game.checkpoint
	check(cp.get("id", "") == "main_street" and cp.get("index", -1) == 0 and is_equal_approx(cp.get("x", 0.0), x1),
		"walking past checkpoint 1 stores it on Game: %s" % [cp.get("x")])
	check(is_equal_approx(cp.get("wet", -1.0), 12.5) and is_equal_approx(cp.get("stamina", -1.0), 61.0)
		and is_equal_approx(cp.get("elapsed", -1.0), 33.0), "the snapshot holds the wetness, stamina and time of that moment")
	p.wet = 40.0
	p.stamina = 5.0
	p.position.x = cps[1] - 1.0
	level._check_checkpoints()
	check(Game.checkpoint.get("index", -1) == 0 and is_equal_approx(Game.checkpoint.get("wet", -1.0), 12.5),
		"later wetness doesn't overwrite a checkpoint not yet reached")
	p.position.x = cps[1] + 0.2
	level._check_checkpoints()
	check(Game.checkpoint.get("index", -1) == 1 and is_equal_approx(Game.checkpoint.get("wet", -1.0), 40.0),
		"reaching checkpoint 2 replaces the snapshot")

	var x2: float = cps[1]   # a puddle lies before it, so a resume must not "step" from the start into it
	Game.checkpoint = {"id": "main_street", "index": 1, "x": x2, "wet": 12.5, "stamina": 61.0, "exhausted": false,
		"elapsed": 33.0, "stats": p.stats.duplicate(), "seen": {"gutter": true}, "car_hints": 1}
	Game.resuming = true
	level.queue_free()
	await _frames(2)
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	p = level.player
	check(is_equal_approx(p.position.x, x2) and level.resumed, "a resumed level puts the walker on the checkpoint (x=%.2f)" % p.position.x)
	check(is_equal_approx(p.wet, 12.5) and is_equal_approx(p.stamina, 61.0), "... with the wetness and stamina he had")
	check(is_equal_approx(level.elapsed, 33.0) and level._seen.has("gutter") and level._car_hints == 1 and p.stats["puddles"] == 3,
		"... and the clock, hint memory and stats")
	check(absf(level._cam_x - (p.position.x + Tun.f("camera_lead"))) < 0.5, "... with the camera already there (no pan)")
	check(level._next_cp == 2, "... and the next checkpoint is the third one")
	await _frames(10)
	check(is_equal_approx(p.wet, 12.5) and p.stats["puddles"] == 3, "the first steps after a resume stay dry (wet %.2f, puddles %d)" % [p.wet, p.stats["puddles"]])
	check(not Game.resuming, "the resume request is spent")
	Game.checkpoint = {}


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
	_test_sun_drying()
	_test_feedback_url()
	await _test_checkpoints()
	_test_dynamic_resolution()
	_run_tests()
	get_parent().finish(failures)


## Each observe() is one second of play: median frame and GPU time in ms.
func _test_dynamic_resolution() -> void:
	var dr := DynamicResolution.new()
	add_child(dr)
	dr.set_process(false)
	var last := DynamicResolution.STEPS.size() - 1
	var feed := func(frame: float, gpu: float, secs: int) -> void:
		for i in secs:
			dr.clock += 1.0
			dr.observe(frame, gpu)
	feed.call(16.7, 3.0, 10)
	check(dr.step == 0, "a GPU with headroom keeps full resolution")
	feed.call(33.3, 6.0, 5)
	check(dr.step == 0, "missing 60 fps with the GPU under budget (CPU-bound) keeps full resolution")
	feed.call(33.3, 22.0, 1)
	check(dr.step == 1 and is_equal_approx(get_viewport().scaling_3d_scale, DynamicResolution.STEPS[1]),
		"missing 60 fps with the GPU over budget lowers the resolution a step")
	feed.call(33.3, 22.0, 10)
	check(dr.step == last, "sustained misses go down to the floor and stop there")
	feed.call(16.7, 5.0, 3)
	check(dr.step == last, "three seconds of headroom isn't enough to step up")
	feed.call(16.7, 5.0, 1)
	check(dr.step == last - 1, "four seconds of headroom steps up")
	feed.call(33.3, 22.0, 1)
	check(dr.step == last, "a step up that misses again is undone")
	feed.call(16.7, 5.0, 30)
	check(dr.step == last, "... and stepping up stays locked for a while")
	feed.call(16.7, 5.0, 40)
	check(dr.step < last, "... then unlocks")
	var carried := dr.step
	remove_child(dr)
	check(is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "leaving the street restores full resolution")
	dr.free()
	var dr2 := DynamicResolution.new()
	add_child(dr2)
	check(dr2.step == carried, "the next street starts at the step the last one ended on")
	dr2.free()
	get_viewport().scaling_3d_scale = 1.0


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

	# Upgrades and tokens stay with their direction through the real flow, reloading from disk between
	# steps: an undecided first run buys on the start street and commits right, then a left run starts,
	# buys and finishes a street, and play switches back and forth.
	var reload := func() -> void:
		Game.save_game()
		Game.runs = {}
		Game.load_game()
	var upg := func(r: Run) -> Array:
		return Run.UPGRADES.map(func(k: StringName) -> int: return int(r.upgrades[k]))
	Game.reset_progress()
	Game.new_run("")
	Game.finish_level(start, 0.0, 10.0, 10.0)
	Game.run.tokens = 20
	Game.buy_upgrade(&"wide")
	Game.choose(rnb)
	reload.call()
	var right_upg: Array = upg.call(Game.runs["right"])
	var right_tokens: int = Game.runs["right"].tokens
	check(right_upg == [0, 1, 0], "undecided run's upgrade commits with it to the right: %s" % [right_upg])
	Game.new_run("left")
	check(upg.call(Game.run) == [0, 0, 0] and Game.run.tokens == 0, "a new left run starts with no upgrades or tokens")
	Game.run.tokens = 20
	Game.buy_upgrade(&"sturdy")
	Game.buy_upgrade(&"light")
	Game.finish_level(start, 0.0, 10.0, 10.0)
	Game.choose(lnb)
	reload.call()
	check(Game.run.direction == "left" and upg.call(Game.run) == [1, 0, 1], "left run keeps its own upgrades: %s" % [upg.call(Game.run)])
	check(upg.call(Game.runs["right"]) == right_upg and Game.runs["right"].tokens == right_tokens,
		"buying and scoring on the left leaves the right run untouched: %s" % [upg.call(Game.runs["right"])])
	Game.resume_run("right")
	Game.run.tokens += 20
	Game.buy_upgrade(&"wide")
	reload.call()
	check(Game.run.direction == "right" and upg.call(Game.run) == [0, 2, 0], "right run upgrades on top of its own: %s" % [upg.call(Game.run)])
	check(upg.call(Game.runs["left"]) == [1, 0, 1], "and the left run still has only its own: %s" % [upg.call(Game.runs["left"])])
	Game.resume_run("left")
	check(Game.umbrella_radius() == Game.umbrella_radius(0) and Game.umbrella_drain_mult() == Game.umbrella_drain_mult(1),
		"the walker uses the active run's upgrades after switching")

	# Coming-soon streets: on the map in road order, never selectable, not counted as reachable.
	var order := Game.map_order()
	check(order.size() == Game.nodes.size() and order.has(start), "map order lists every street once: %s" % [order])
	var si := order.find(start)
	check(order.slice(0, si).all(func(id: String) -> bool: return Game.branch[id] == "left")
		and order.slice(si + 1).all(func(id: String) -> bool: return Game.branch[id] == "right"),
		"map order runs left side, start, right side")
	check(order[si - 1] == lnb and order[si + 1] == rnb, "the start's neighbours sit either side of it in map order")
	var soon: Array = Game.nodes.keys().filter(func(id: String) -> bool: return Game.is_soon(id))
	check(not soon.is_empty(), "the map shows streets that aren't built yet")
	var everywhere := Run.new("left", start)
	everywhere.completed = Game.nodes.keys()
	Game.run = everywhere
	for id: String in soon:
		everywhere.current_node = Game.neighbors(id)[0]
		check(not Game.can_select(id), "coming-soon %s can't be picked even from next door" % id)
		check(not Game.nodes[id].has("file") and Game.branch.has(id), "coming-soon %s has a side but no level file" % id)
	var built_left := Game.nodes.keys().filter(func(id: String) -> bool:
		return not Game.is_soon(id) and Game.branch[id] in ["", "left"]).size()
	check(Game.reachable_count(everywhere) == built_left, "streets-walked count leaves out coming-soon streets")

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	Game.autopilot = true
	Game.runs = {}
	Game.run = Run.new("", start)
