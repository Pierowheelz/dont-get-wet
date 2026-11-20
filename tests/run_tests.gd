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


func _idle_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _place(x: float, open: float, tilt := 0.0) -> float:
	var p: Player = level.player
	p.position = Vector3(x, level.ground_y(x), Tun.f("player_z"))
	p.open = open
	p.tilt = tilt
	p.visual.set_umbrella_pose(p.arm_raise(), tilt, 0.0)
	await _frames(3)
	p._update_umbrella()
	await get_tree().process_frame   # the canopy rebuilds its collider in _process
	for i in 2:   # raycasts see the moved canopy only after physics has stepped
		await get_tree().physics_frame
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
	var floor_rate: float = Tun.f("wet_max") * 0.01 / 5.0
	check(Player.dry_speed(shut, 0.95) == shut and Player.dry_speed(shut, 0.6) < shut * 0.1,
		"drying runs at full rate when soaked and slows sharply when fairly dry (%.3f/s at 60%%)" % Player.dry_speed(shut, 0.6))
	check(is_equal_approx(Player.dry_speed(shut, 0.0), floor_rate),
		"drying never drops below 1%% per 5 s (%.3f/s when bone dry)" % Player.dry_speed(shut, 0.0))
	check(Player.dry_speed(0.0, 0.0) == 0.0 and Player.dry_speed(0.05, 0.0) == 0.05,
		"the floor never dries him outside a warm spot or faster than the spot itself")
	check(not level.player._exposed_at(x), "autopilot treats the sunlit lot as safe, so it closes the umbrella")


func _test_feedback_url() -> void:
	var url := Game.feedback_url()
	check(url.contains("template=feedback.yml") and url.ends_with("&version=%s" % ProjectSettings.get_setting("application/config/version")),
		"feedback link opens the form with the version filled in")


## The score card's "beat your best by N" is the gap to the first score that pays another token.
func _test_next_token() -> void:
	var k := Tun.f("tokens_per_point")
	var exact := true
	for best in [0, 153, 154, 800, 900, 923]:
		var need := Game.points_to_next_token(best)
		exact = exact and need > 0 and floor((best + need) * k) == floor(best * k) + 1 and floor((best + need - 1) * k) == floor(best * k)
	check(exact, "points to the next token land exactly on the score that pays it")
	check(Game.points_to_next_token(1000) == 0, "a best with no paying score left above it asks for nothing")


## A street's `load` and `fail` lines from levels/index.json; streets without them keep the defaults.
func _test_street_text() -> void:
	const HUD := preload("res://src/ui/hud.gd")
	Game.nodes["_text_test"] = {"name": "Test Lane", "load": "Nobody followed you.", "fail": ["One.", "Two."]}
	Game._show_loading("_text_test")
	var name_lbl: Label = Game._loading.get_node("ColorRect/Label")
	var line_lbl: Label = Game._loading.get_node("ColorRect/Line")
	check(name_lbl.text == "Walking to Test Lane…" and line_lbl.text == "Nobody followed you.",
		"the loading card shows the street's load line under its name: %s / %s" % [name_lbl.text, line_lbl.text])
	Game._show_loading("main_street")
	check(line_lbl.text == "", "a street without a load line shows only its name")
	Game.hide_loading()
	var seen := {}
	for i in 40:
		seen[HUD.fail_line("_text_test")] = true
	check(seen.keys().size() == 2 and seen.has("One.") and seen.has("Two."), "a street's fail lines replace the generic pool: %s" % [seen.keys()])
	seen = {}
	for i in 40:
		seen[HUD.fail_line("main_street")] = true
	check(seen.keys().all(func(l: String) -> bool: return HUD.FAIL_LINES.has(l)), "a street without fail lines draws from the generic pool")
	Game.nodes["_text_test"]["fail"] = {"wet": ["Damp."], "shot": ["Bang."]}
	check(HUD.fail_line("_text_test", &"shot") == "Bang." and HUD.fail_line("_text_test") == "Damp."
		and HUD.fail_line("_text_test", &"lost") == "", "fail lines keyed by cause: each cause draws its own, none for a cause without lines")
	Game.nodes.erase("_text_test")


## Main Street with extra level fields, loaded as its own street; the walker stays where the test puts him.
func _street_with(extra: Dictionary) -> Level:
	var d: Dictionary = Game.level_data("main_street")
	d.merge(extra, true)
	var path := OS.get_temp_dir().path_join("dgw_street_%d.json" % OS.get_process_id())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	Game.nodes["_street_test"] = {"name": "Street Test", "file": path}
	Game.current_level = "_street_test"
	var lv: Level = load("res://src/level/level.tscn").instantiate()
	add_child(lv)
	lv.player.set_physics_process(false)
	await _frames(3)
	return lv


## A hit that soaks him fails the attempt for its cause; plain rain stays "wet".
func _test_fail_cause() -> void:
	var lv := await _street_with({})
	var p: Player = lv.player
	_unhook_defeat(p)
	p.wet = Tun.f("wet_max") - 1.0
	p.soak(5.0, &"shot")
	p._physics_process(1.0 / 60.0)
	check(p.state == Player.State.DEFEATED and p.fail_cause == &"shot", "a jet that soaks him fails as SHOT: %s" % p.fail_cause)
	await _drop_street(lv)
	lv = await _street_with({})
	p = lv.player
	_unhook_defeat(p)
	p.wet = Tun.f("wet_max") + 1.0
	p._physics_process(1.0 / 60.0)
	check(p.fail_cause == &"wet", "soaked by the weather fails as YOU GOT WET: %s" % p.fail_cause)
	await _drop_street(lv)


func _key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


## After he gives up he trudges off for about 5 s; any press after a moment's grace skips to the
## fail card, which reports how far he got. The press that skips (even R) does nothing else.
func _test_walk_off() -> void:
	Game.autopilot = false   # under --autopilot a defeat quits
	var lv := await _street_with({})
	var p: Player = lv.player
	p.position.x = lv.end_x * 0.5
	p.wet = Tun.f("wet_max") + 1.0
	p._physics_process(1.0 / 60.0)
	var made := lv.progress()
	p.position.x -= 3.0   # the trudge back
	_key(KEY_R, true)
	await _idle_frames(2)
	_key(KEY_R, false)
	await _idle_frames(2)
	check(lv.hud._overlay == null and not Game._building, "a key down as he gives up neither skips the walk-off nor restarts")
	await _wall(0.5)
	_key(KEY_R, true)
	await _idle_frames(3)
	_key(KEY_R, false)
	await _idle_frames(3)
	check(lv.hud._overlay != null and not Game._building, "R during the walk-off skips to the fail card without restarting")
	var made_txt := "Made it %d%% of the way" % int(made * 100.0)
	check(labels_of(lv.hud._overlay).any(func(l: String) -> bool: return l.begins_with(made_txt)),
		"the card says how far he got before trudging back: %s" % made_txt)
	await _drop_street(lv)

	lv = await _street_with({})
	p = lv.player
	p.wet = Tun.f("wet_max") + 1.0
	p._physics_process(1.0 / 60.0)
	await _wall(0.5)
	_key(KEY_ENTER, true)
	await _idle_frames(3)
	_key(KEY_ENTER, false)
	await _idle_frames(3)
	check(lv.hud._overlay != null and not Game._building, "Enter skips to the card and doesn't press its focused button")
	await _drop_street(lv)

	lv = await _street_with({})
	p = lv.player
	p.wet = Tun.f("wet_max") + 1.0
	p._physics_process(1.0 / 60.0)
	var t0 := Time.get_ticks_msec()
	while lv.hud._overlay == null and Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	check(took > 4.5 and took < 5.5, "left alone, the walk-off lasts about 5 s (%.1f s)" % took)
	await _drop_street(lv)
	Game.autopilot = true


func labels_of(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		labels_of(c, out)
	return out


## A man to shoot at (or stand under), on the back lane at x, facing the walker. With `canopy` he
## holds his umbrella open and brought down at the walker as when he fires; `over` holds it upright
## overhead instead.
func _npc(x: float, canopy := false, over := false) -> NpcBody:
	var npc := NpcBody.new()
	npc.level = level
	level.add_child(npc)
	npc.position = Vector3(x, level.ground_y(x), 1.25)
	npc.rotation.y = PI if x > level.player.position.x else 0.0
	var aim := 0.0 if over or not canopy else WaterJet.AIM_TILT
	npc.visual.call("set_umbrella_pose", 1.0 if over else (WaterJet.AIM_RAISE if canopy else 0.0), aim, 0.0)
	npc.visual.call("set_umbrella_open", 1.0 if canopy or over else 0.0)
	npc.umbrella.set_state(1.0 if canopy or over else 0.0, Game.umbrella_radius(0), 0.0)
	for i in 3:
		await get_tree().process_frame
	await _frames(2)
	return npc


## One shot from the walker, umbrella furled and its shaft raised and aimed level-ish toward `side`
## (full tilt); returns the burst once it has landed.
func _fire(side := 1.0) -> DropletBurst:
	var p: Player = level.player
	var g: WaterGun = p.gun
	if p.open <= 0.0:
		p.aim = 1.0
		p.tilt = side * Tun.f("umbrella_max_tilt")
		for i in 3:
			await get_tree().process_frame   # the pose and the shaft follow
	g.shots = g.capacity()
	g.recoil = 0.0   # the walker's physics (which lets it settle) is off in these tests
	for i in 2:
		await get_tree().process_frame
	var b := g.fire()
	await b.done
	await get_tree().process_frame   # out of the burst's physics step before the test moves on
	return b


## `n` shots at a man, his wetness reset after each: [droplets his canopy stopped, droplets that
## reached him, mean wetness a shot]. Averaged, because one stray droplet on the head is a third of a hit.
func _shots_at(man: NpcBody, n: int) -> Array:
	var out := [0, 0, 0.0]
	for i in n:
		var b := await _fire()
		out[0] += b.stopped_by(man)
		out[1] += b.landed_on(man)
		out[2] += man.wet / n
		man.wet = 0.0
	return out


func _pad_axis(axis: JoyAxis, v: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = v
	Input.parse_input_event(ev)


## The umbrella trigger ignores the last bit of travel at each end, and opens partway in between.
func _test_trigger_ends() -> void:
	var lv := await _street_with({})
	var p: Player = lv.player
	_unhook_defeat(p)
	var covered_x := -1.0
	var open_x := -1.0
	for lot in lv.data["lots"]:
		if lot["cover"] == "awning" and not lot.has("tears") and lot["w"] >= 8 and covered_x < 0:
			covered_x = lot["x"] + 1.0
		if lot["cover"] == "none" and lot["w"] >= 4 and open_x < 0:
			open_x = lot["x"] + lot["w"] * 0.5
	Game.autopilot = false
	p.set_physics_process(true)
	Input.action_press(&"stop")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.10)
	p.position.x = covered_x
	p._prev_x = covered_x
	p.stamina = 40.0
	await _frames(60)
	check(p.open == 0.0 and p.stamina > 50.0, "a finger resting on RT leaves the umbrella shut and stamina recovering (open %.3f, stamina 40 -> %.1f)" % [p.open, p.stamina])
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.5)
	await _frames(90)
	check(p.open > 0.3 and p.open < 0.7, "a half-pulled RT half-opens it: %.2f" % p.open)
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.96)
	p.position.x = open_x
	p._prev_x = open_x
	await _frames(90)
	var wet_was := p.wet
	await _frames(60)
	check(p.open == 1.0 and p.wet == wet_was, "RT not quite bottomed out opens it fully, dry in the open (open %.3f, wet +%.2f)" % [p.open, p.wet - wet_was])
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	Input.action_release(&"stop")
	Game.autopilot = true
	await _drop_street(lv)


## Headless can't capture the mouse, so these set Inputs.mouse_tilt as sideways mouse motion would.
func _test_tilt_hand_off() -> void:
	Game.autopilot = false
	Input.action_press(&"stop")
	Input.action_press(&"umbrella")
	var lv := await _street_with({})
	var p: Player = lv.player
	_unhook_defeat(p)
	p.set_physics_process(true)
	Inputs.mouse_tilt = 0.5
	await _frames(90)
	check(p.tilt > 0.3, "the mouse tilts the open umbrella: %.2f rad" % p.tilt)
	_pad_axis(JOY_AXIS_RIGHT_X, 0.8)
	await _frames(10)
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _frames(90)
	check(absf(p.tilt) < 0.05, "once a stick has tilted it, the sticks at rest hold it upright: %.2f rad" % p.tilt)
	Inputs.mouse_tilt = -1.0
	await _drop_street(lv)
	lv = await _street_with({})
	p = lv.player
	_unhook_defeat(p)
	p.set_physics_process(true)
	await _frames(90)
	check(p.open == 1.0 and absf(p.tilt) < 0.05, "a restarted street starts with the umbrella upright: %.2f rad" % p.tilt)
	Inputs.mouse_tilt = 0.5
	await _frames(90)
	check(p.tilt > 0.3, "... and the mouse tilts it again: %.2f rad" % p.tilt)
	Input.action_release(&"umbrella")
	Input.action_release(&"stop")
	Game.autopilot = true
	await _drop_street(lv)


func _touch(lv: Level, at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = down
	ev.position = lv.get_viewport().get_final_transform() * at
	Input.parse_input_event(ev)
	await _idle_frames(2)


## Touch controls: hints name the on-screen buttons, a finger held through a restart lets go, and
## the pause button pauses.
func _test_touch_controls() -> void:
	Game.settings["touch_controls"] = true
	Game.autopilot = false
	var lv := await _street_with({})
	var p: Player = lv.player
	_unhook_defeat(p)
	p.set_physics_process(true)
	var tc: Control = lv.hud._touch
	tc._layout()
	await _touch(lv, tc._stop_rect.get_center(), true)
	lv.hud.hint("{umbrella} — open the umbrella.   Hold {stop} to stand still.")
	check(lv.hud._hint.text == "Hold UMBRELLA — open the umbrella.   Hold STOP to stand still.",
		"on touch, hints name the on-screen buttons: '%s'" % lv.hud._hint.text)
	await _touch(lv, tc._umb_rect.get_center(), true)
	await _drop_street(lv)
	lv = await _street_with({})
	p = lv.player
	_unhook_defeat(p)
	p.set_physics_process(true)
	await _frames(90)
	check(p.open == 0.0 and p.state == Player.State.WALK, "fingers held through a restart don't hold the new street's umbrella or stop (open %.2f)" % p.open)
	tc = lv.hud._touch
	tc._layout()
	await _touch(lv, tc._pause_rect.get_center(), true)
	await _touch(lv, tc._pause_rect.get_center(), false)
	check(get_tree().paused and lv.hud._pause != null, "the touch pause button pauses")
	await _touch(lv, tc._pause_rect.get_center(), true)
	await _touch(lv, tc._pause_rect.get_center(), false)
	check(not get_tree().paused, "... and tapping it again resumes")
	Game.settings["touch_controls"] = false
	Game.autopilot = true
	Inputs._set_device(&"keyboard")
	await _drop_street(lv)


## The walker's shot: range per Long Barrel tier, two clean hits soak a man (one at Pressure tier 3),
## a man's canopy stops it, and his canopy never keeps the rain off the walker. The water refills
## slowly by itself and fast stopped under a stream, and the shot is locked before the sixth street.
func _test_umbrella_shot() -> void:
	level = await _street_with({})
	var p: Player = level.player
	_unhook_defeat(p)
	check(not p.gun.armed and Game.street_number("main_street") == 1, "the test street isn't armed: %s" % p.gun.armed)
	var shots_was := p.gun.shots
	p.gun.step(0.5, true)
	check(p.gun.shots == shots_was and p.gun.recoil == 0.0, "unarmed, the fire button does nothing")
	check(Game.street_number("viaduct_road") == 5 and Game.street_number("atomic_avenue") == 5
		and Game.street_number("the_bypass") == 6 and Game.street_number("rocket_row") == 6,
		"streets are numbered from Main Street: the level-5 and level-6 streets on both paths")
	check(not Game.armed("viaduct_road") and not Game.armed("atomic_avenue") and Game.armed("the_bypass") and Game.armed("rocket_row"),
		"the shot is locked before level 6 and armed from it")
	p.gun.armed = true
	var x0 := 162.6
	await _place(x0, 0.0)
	await _fire()   # raises the furled shaft, so the muzzle below is where it fires from
	var upg_was: Dictionary = Game.run.upgrades.duplicate()
	var direct := Tun.f("gun_hit")
	for tier in 4:
		Game.run.upgrades[&"barrel"] = tier
		var reach := Game.gun_range()
		var mx := p.gun.muzzle().x
		var near := await _npc(mx + reach - 1.0)
		var near_landed := (await _fire()).landed_on(near)
		var near_wet := near.wet
		near.queue_free()
		var far := await _npc(mx + reach + 0.6)
		var far_landed := (await _fire()).landed_on(far)
		check(near_wet >= direct * 0.95 and far.wet == 0.0 and far_landed == 0,
			"Long Barrel tier %d: a man %.1f m off takes a full hit (%.1f, %d droplets), one %.1f m off stays dry" % [tier, reach - 1.0, near_wet, near_landed, reach + 0.6])
		far.queue_free()
	Game.run.upgrades[&"barrel"] = 0
	var man := await _npc(p.gun.muzzle().x + 3.0)
	await _fire()
	var one := man.wet
	await _fire()
	await _frames(2)
	check(one >= direct * 0.95 and one < man.wet_max() and man.wet >= man.wet_max() and not man.wettable(),
		"two direct hits soak a man: %.1f after one, %.1f of %.0f after two" % [one, man.wet, man.wet_max()])
	check(man.get_parent() == level and man._dropped_umbrella, "soaked, he drops his umbrella and walks off on his own")
	var at := man.position.x
	await get_tree().create_timer(2.5).timeout
	check(is_instance_valid(man) and man.position.x < at - 0.3 and man.global_basis.x.x < 0.0,
		"... turning round to trudge off the left (%.2f m so far)" % (at - man.position.x if is_instance_valid(man) else 0.0))
	if is_instance_valid(man):
		man.queue_free()
	Game.run.upgrades[&"pressure"] = 3
	man = await _npc(p.gun.muzzle().x + 3.0)
	await _fire()
	check(man.wet >= man.wet_max(), "Pressure tier 3: one direct hit soaks him (%.1f)" % man.wet)
	man.queue_free()
	Game.run.upgrades[&"pressure"] = 0
	man = await _npc(p.gun.muzzle().x + 3.0, true)
	var shield := await _shots_at(man, 3)
	check(shield[2] < direct * 0.35 and shield[0] > shield[1] * 8,
		"his canopy, brought down at the walker, stops the shot: %d droplets stopped, %d through, wet %.1f a shot" % shield)
	man.queue_free()
	man = await _npc(x0 + 2.5)
	await _fire(-1.0)
	check(man.wet == 0.0, "aimed behind, a man ahead stays dry")
	man.queue_free()
	man = await _npc(p.gun.muzzle().x - 3.0)
	await _fire(-1.0)
	check(man.wet >= direct * 0.95, "aimed behind, it soaks a man behind (%.1f)" % man.wet)
	man.queue_free()
	Game.run.upgrades = upg_was

	# Rain: a man under an open umbrella right over the walker keeps none of it off him.
	var rx := 43.5   # an open lot in the rain
	var bare := await _place(rx, 0.0)
	man = await _npc(rx, false, true)
	man.position.z = p.position.z
	await _frames(3)
	var head := p.sample_world(WetBody.SAMPLES[0][0])
	var q := PhysicsRayQueryParameters3D.create(head, head + Vector3.UP * 3.0, Umbrella.NPC_UMBRELLA_LAYER)
	var over := not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	var under := await _place(rx, 0.0)
	check(over and bare > 0.95 and absf(under - bare) < 0.001,
		"a man's open canopy over the walker's head (%s) keeps no rain off him: exposure %.2f, %.2f without it" % [over, under, bare])
	man.queue_free()

	# Refill: one a second stopped under a stream with the umbrella open; about one per 25 s with the
	# open canopy out in the rain; none furled or under cover.
	var gx: float = level.gutters[0]
	await _place(gx, 1.0)
	p.state = Player.State.STOPPED
	p._gutter_exposure()
	var stream := p.gun.refill_rate()
	p.state = Player.State.WALK
	await _place(rx, 1.0)
	var rain := p.gun.refill_rate()
	await _place(rx, 0.0)
	var furled := p.gun.refill_rate()
	var cx := -1.0
	for lot in level.data["lots"]:
		if lot["cover"] == "awning" and not lot.has("tears") and lot["w"] >= 4 and cx < 0.0:
			cx = lot["x"] + lot["w"] * 0.5
	await _place(cx, 1.0)
	var covered := p.gun.refill_rate()
	p.gun.shots = 0.0
	await _place(rx, 1.0)
	p.gun.step(25.0, false)
	check(absf(stream - 1.0) < 0.01 and absf(rain - 0.04) < 0.005 and furled == 0.0 and covered == 0.0
		and absf(p.gun.shots - 1.0) < 0.01,
		"refill: %.2f a second under a stream, %.2f open in the rain (one shot in 25 s), %.2f furled, %.2f under an awning" % [stream, rain, furled, covered])
	await _drop_street(level)

	var r := Run.new("left", Game.start_node)
	var run_was := Game.run
	Game.run = r
	r.completed = [Game.start_node, "canal_row", "mill_road", "kiln_street"]
	check(not Game.upgrade_offered(&"barrel") and not Game.upgrade_offered(&"pressure") and Game.upgrade_offered(&"sturdy"),
		"the shop holds back Long Barrel and Pressure until a level-5 street is walked")
	r.completed.append("viaduct_road")
	check(Game.upgrade_offered(&"barrel") and Game.upgrade_offered(&"pressure"), "... and offers them once it is")
	Game.run = run_was


## The level quits the game on defeat under --autopilot; tests that defeat him keep it running.
func _unhook_defeat(p: Player) -> void:
	for c in p.defeated.get_connections():
		p.defeated.disconnect(c["callable"])


func _drop_street(lv: Level) -> void:
	lv.queue_free()
	await _frames(2)
	DirAccess.remove_absolute(Game.nodes["_street_test"]["file"])
	Game.nodes.erase("_street_test")
	Game.current_level = "main_street"
	Game.checkpoint = {}


func _test_street_hints() -> void:
	var cp: float = level.checkpoints[0]
	level.queue_free()
	await _frames(2)
	var hints := {"hints": [{"x": cp + 6.0, "text": "Second.", "dur": 3.0}, {"x": cp - 6.0, "text": "First.", "dur": 3.0}]}
	var lv := await _street_with(hints)
	var p: Player = lv.player
	p.position.x = cp - 5.5
	await _idle_frames(2)
	check(lv.hud._hint_template == "First.", "a hint shows when the walker passes its x: '%s'" % lv.hud._hint_template)
	lv.hud._hint_template = ""
	p.position.x = cp - 8.0
	await _idle_frames(2)
	p.position.x = cp - 5.0
	await _idle_frames(2)
	check(lv.hud._hint_template != "First.", "walking back over a hint doesn't show it again")
	p.position.x = cp + 6.5
	await _idle_frames(2)
	check(lv.hud._hint_template == "Second.", "the next hint shows at its own x")
	await _drop_street(lv)

	Game.debug_resume_cp = 0
	lv = await _street_with(hints)
	Game.debug_resume_cp = -1
	p = lv.player
	check(is_equal_approx(p.position.x, cp) and lv.hud._hint_template != "First.",
		"resuming from a checkpoint past a hint doesn't show it")
	p.position.x = cp + 6.5
	await _idle_frames(2)
	check(lv.hud._hint_template == "Second.", "... and the hints after the checkpoint still show")
	await _drop_street(lv)


func _wall(secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Hints and the first-play tutorial run on play time: a pause holds them, and a hint on screen
## when you pause is back with its time left when you resume.
func _test_pause_holds_hints() -> void:
	var lv := await _street_with({})
	var hud: Node = lv.hud
	hud._show_tutorial()
	hud._toggle_pause()
	await _wall(1.5)
	check(hud._hint_template == "", "a tutorial line due while paused doesn't show behind the pause panel")
	hud._toggle_pause()
	await _wall(1.2)
	check(hud._hint_template.begins_with("Rain soaks you") and hud._hint_box.is_visible_in_tree(),
		"... it shows once play resumes: '%s'" % hud._hint_template)
	hud.hint("Held.", 2.0)
	await _idle_frames(3)
	hud._toggle_pause()
	check(not hud._hint_box.is_visible_in_tree(), "a hint on screen hides behind the pause panel")
	await _wall(2.5)
	hud._toggle_pause()
	check(hud._hint_template == "Held." and hud._hint_box.is_visible_in_tree() and hud._hint_t > 1.8,
		"... and is back with its time left on resume (%.2f s)" % hud._hint_t)
	await _wall(2.5)
	check(hud._hint_box.modulate.a == 0.0, "... then fades out, nothing stuck on screen (alpha %.2f)" % hud._hint_box.modulate.a)
	await _drop_street(lv)


## While a street builds behind the loading card, nothing pauses and no menu action fires.
func _test_no_pause_while_building() -> void:
	var lv := await _street_with({})
	Game._building = true
	Input.action_press(&"pause")
	await _idle_frames(2)
	Input.action_release(&"pause")
	await _idle_frames(1)
	check(lv.hud._pause == null, "the pause key does nothing behind the loading card")
	var scene := get_tree().current_scene
	Game.goto_map()
	Game.goto_menu()
	await _idle_frames(2)
	check(get_tree().current_scene == scene, "City map and Main menu do nothing while a street builds")
	Game._building = false
	await _drop_street(lv)


## Losing the window, or unplugging the pad in use, pauses play; not once he has given up.
func _test_pause_when_away() -> void:
	var lv := await _street_with({})
	var hud: Node = lv.hud
	check(not hud.pause_when_away, "headless runs never pause for focus")
	hud.pause_when_away = true
	hud.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _idle_frames(2)
	check(get_tree().paused and hud._pause != null, "the window losing focus opens the pause panel")
	hud._toggle_pause()
	var dev_was: StringName = Inputs.last_device
	var press := InputEventJoypadButton.new()
	press.device = 0
	press.button_index = JOY_BUTTON_X
	press.pressed = true
	Input.parse_input_event(press)
	await _idle_frames(2)
	press = press.duplicate()
	press.pressed = false
	Input.parse_input_event(press)
	await _idle_frames(2)
	Input.joy_connection_changed.emit(1, false)
	await _idle_frames(2)
	check(not get_tree().paused, "unplugging a pad nobody is using doesn't pause")
	Input.joy_connection_changed.emit(0, false)
	await _idle_frames(2)
	check(get_tree().paused and hud._pause != null, "unplugging the pad in use opens the pause panel")
	hud._toggle_pause()
	Inputs._set_device(dev_was)
	lv.player.state = Player.State.DEFEATED
	hud.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _idle_frames(2)
	check(not get_tree().paused, "losing focus after he gives up doesn't pause")
	await _drop_street(lv)


## Runs `secs` of play with the walker at `walk_speed` (0 = holding stop); returns the closest the follower came.
func _walk(lv: Level, secs: float, walk_speed: float) -> float:
	var p: Player = lv.player
	var fol: Node3D = lv.get_node("Follower")
	p.state = Player.State.STOPPED if walk_speed == 0.0 else Player.State.WALK
	p.speed = walk_speed
	var closest := INF
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		if fol.visible:
			closest = minf(closest, p.position.x - fol.position.x)
	return closest


## His back is in shot, but a metre behind him isn't.
func _hugs_left_edge(lv: Level, fol: Node3D) -> bool:
	var back := lv.camera.unproject_position(fol.global_position + Vector3(-0.3, 1.0, 0)).x
	var behind := lv.camera.unproject_position(fol.global_position + Vector3(-1.0, 1.0, 0)).x
	return back > 0.0 and behind < 0.0


func _test_follower() -> void:
	var window_was := get_window().size
	get_window().size = Vector2i(1920, 1080)   # headless defaults to a square window
	var lv := await _street_with({"follower": {"appear": [{"x": 20.0, "hold": 12.0}]},
		"figures": [{"x": 5.0}, {"x": 9.0, "facing": "away"}]})
	var p: Player = lv.player
	var fol: Node3D = lv.get_node("Follower")
	var figs: Array = lv.get_children().filter(func(c: Node) -> bool: return c.get("_figures") != null)[0]._figures
	var faces: Array = figs.map(func(fg: Array) -> Vector3: return (fg[0] as Node3D).global_basis.x.snappedf(0.01))
	check(faces == [Vector3(1, 0, 0), Vector3(0, 0, -1)], "figures face up the street, or with facing away toward the building: %s" % [faces])
	check(not fol.visible, "the follower is nowhere until the walker reaches his first appearance")
	p.position.x = 19.0
	var closest := await _walk(lv, 5.0, 1.3)
	check(fol.visible, "he walks in once the walker passes the appearance x")
	check(_hugs_left_edge(lv, fol), "he holds just inside the left edge of a 16:9 frame (%.1f m behind the walker)" % (p.position.x - fol.position.x))
	get_window().size = Vector2i(2520, 1080)
	closest = minf(closest, await _walk(lv, 4.0, 1.3))
	check(_hugs_left_edge(lv, fol), "... and of a 21:9 frame (%.1f m behind the walker)" % (p.position.x - fol.position.x))
	get_window().size = Vector2i(1920, 1080)
	closest = minf(closest, await _walk(lv, 2.0, 1.3))
	closest = minf(closest, await _walk(lv, 0.35, 0.0))
	check(fol.get("speed") > 0.5, "when the walker stops, he keeps walking a moment (%.2f m/s)" % fol.get("speed"))
	closest = minf(closest, await _walk(lv, 1.0, 0.0))
	check(fol.get("speed") < 0.05, "... then stops too (%.2f m/s)" % fol.get("speed"))
	closest = minf(closest, await _walk(lv, 1.5, 2.0))
	check(fol.get("speed") > 1.7, "when the walker hurries, he hurries (%.2f m/s)" % fol.get("speed"))
	closest = minf(closest, await _walk(lv, 12.0, 1.3))
	check(not fol.visible, "after his hold he drops back out of the frame")
	check(closest >= 2.95, "he never comes closer than 3 m (closest %.2f m)" % closest)
	await _drop_street(lv)

	Game.debug_resume_cp = 0
	lv = await _street_with({"follower": {"appear": [{"x": 20.0, "hold": 8.0}]}})
	Game.debug_resume_cp = -1
	await _walk(lv, 1.0, 1.3)
	check(not lv.get_node("Follower").visible, "resuming past an appearance doesn't replay it")
	await _drop_street(lv)

	# Main Street: an open lot at 63.5-68.5, then awnings to 80.5.
	var wide_was: int = Game.run.upgrades[&"wide"]
	Game.run.upgrades[&"wide"] = 3
	lv = await _street_with({"follower": {"appear": [{"x": 64.0, "hold": 30.0}]}})
	p = lv.player
	fol = lv.get_node("Follower")
	p.position.x = 63.5
	await _walk(lv, 6.2, 1.3)
	var umb: Umbrella = fol.get("_umbrella")
	check(umb.current_radius() > Tun.f("umbrella_radius") - 0.05 and umb.current_radius() < Game.umbrella_radius() - 0.1,
		"in the rain (x %.1f) he opens a starter-size umbrella, whatever the walker bought (rim %.2f m)" % [fol.position.x, umb.current_radius()])
	var holder := umb.get_parent().get_parent() as BoneAttachment3D
	check(holder != null and holder.bone_name == &"LeftHand", "... held in his left hand (%s)" % (holder.bone_name if holder else "no bone"))
	await _walk(lv, 7.0, 1.3)
	check(umb.current_radius() < 0.2, "under the awnings (x %.1f) he furls it again (rim %.2f m)" % [fol.position.x, umb.current_radius()])
	await _drop_street(lv)
	Game.run.upgrades[&"wide"] = wide_was
	get_window().size = window_was


## A defeated walker trudges back toward the follower, who stays where he stopped.
func _test_follower_walker_defeated() -> void:
	var window_was := get_window().size
	get_window().size = Vector2i(1920, 1080)
	var lv := await _street_with({"follower": {"appear": [{"x": 20.0, "hold": 12.0}]}})
	var p: Player = lv.player
	var fol: Node3D = lv.get_node("Follower")
	_unhook_defeat(p)
	p.position.x = 19.0
	await _walk(lv, 3.5, 1.3)
	p.fail(&"wet")
	p.set_physics_process(true)   # _street_with holds him still; let him trudge off
	await get_tree().create_timer(1.5).timeout
	var x0 := fol.position.x
	var moved := 0.0
	var nearest := INF
	var t := 0.0
	while t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		moved = maxf(moved, absf(fol.position.x - x0))
		nearest = minf(nearest, p.position.x - fol.position.x)
	check(fol.visible and fol.get("speed") < 0.05 and nearest < 2.5 and moved < 0.01,
		"the defeated walker trudges back to %.1f m from him: he stands where he stopped (moved %.2f m)" % [nearest, moved])
	await _drop_street(lv)
	get_window().size = window_was


## Keeps the walker `gap` m behind the courier (0 = holding stop where he is) for `secs` of play, with
## the umbrella at `open` and `tilt`. Returns the seconds until `until` held, or -1.
func _tail(lv: Level, secs: float, gap: float, open := 0.0, tilt := 0.0, until := Callable()) -> float:
	var p: Player = lv.player
	var c: Node3D = lv.courier
	p.state = Player.State.STOPPED if gap == 0.0 else Player.State.WALK
	var t := 0.0
	while t < secs:
		if p.state == Player.State.WALK or p.state == Player.State.STOPPED:
			if gap > 0.0:
				p.position.x = c.position.x - gap
			p.open = open
			p.tilt = tilt
		await get_tree().process_frame
		t += get_process_delta_time()
		if until.is_valid() and until.call():
			return t
	return -1.0


const COURIER := {"courier": {"appear_x": 30.0, "door_x": 200.0, "stops": [{"x": 120.0, "dur": 2.0}, {"x": 70.0, "dur": 3.0}]}}


## Courier on Main Street: he steps out, glances when the walker is close, and ends the attempt as
## LOST, MADE or SHOT.
func _test_raincoat_figure() -> void:
	for facing: int in [1, -1]:
		var fig := RaincoatFigure.new()
		fig.facing = facing
		fig.pose = RaincoatFigure.Pose.WALK
		add_child(fig)
		await _idle_frames(3)
		var skel := fig.model.find_child("GeneralSkeleton", true, false) as Skeleton3D
		check(RaincoatFigure.PARTS.all(func(n: String) -> bool: return skel.find_child(n, false, false) is MeshInstance3D),
			"facing %d: the slicker's skirt, hood and buttons are skinned to his skeleton" % facing)
		var x0 := fig.position.x
		await get_tree().create_timer(1.0).timeout
		var moved := (fig.position.x - x0) * facing
		check(moved > 0.9 * fig.walk_speed and moved < 1.3 * fig.walk_speed, "facing %d: walking, he moves his way at walk_speed (%.2f m in 1 s)" % [facing, moved])
		var shaft := fig.umbrella.global_basis.y.normalized()
		check(shaft.x * facing > 0.8, "facing %d: the furled umbrella points forward, like a rifle (%s)" % [facing, shaft])
		check(fig.umbrella.global_position.z > fig.global_position.z + 0.1, "facing %d: carried in the camera-side hand (z %+.2f)" % [facing, fig.umbrella.global_position.z - fig.global_position.z])
		check(fig.umbrella.open == 0.0 and fig.umbrella._body.collision_layer == 0, "facing %d: furled, and no collider for the rain to hit" % facing)
		fig.smoking = true
		var cig_visible := fig._cig.visible
		fig.smoking = false
		check(cig_visible and not fig._cig.visible, "facing %d: smoking shows the cigarette, and hides it again" % facing)
		fig.queue_free()
	await _idle_frames(1)


func _test_courier() -> void:
	var lv := await _street_with(COURIER)
	var p: Player = lv.player
	var c: Node3D = lv.courier
	var max_tilt := Tun.f("umbrella_max_tilt")
	check(c != null and c.phase == c.Phase.WAIT and is_equal_approx(c.position.x, 30.0) and is_equal_approx(c.door_x, 200.0)
		and c.stops == [[70.0, 3.0], [120.0, 2.0]], "the courier field: he waits in his doorway at appear_x, stops sorted: %s" % [c.stops if c else null])
	p.position.x = 21.0
	await _tail(lv, 0.2, 0.0)
	check(c.phase == c.Phase.WAIT, "he stays in the doorway while the walker is far off")
	p.position.x = 23.0
	await _tail(lv, 3.5, 7.0)
	check(c.phase == c.Phase.WALK and is_equal_approx(c.position.z, c.LANE_Z) and lv._seen.has("courier"),
		"once the walker is near he steps out onto his lane, with the hint (phase %d)" % c.phase)
	var x0: float = c.position.x
	await _tail(lv, 2.0, 7.0)
	check(absf((c.position.x - x0) / 2.0 - c.PACE) < 0.05 and not c.glancing(), "he walks at %.2f m/s and doesn't glance at a walker 7 m back" % ((c.position.x - x0) / 2.0))

	# Glances: within GLANCE_DIST with his face showing, suspicion goes up when the turn completes.
	var began := await _tail(lv, 6.0, 3.5, 0.0, 0.0, func() -> bool: return c.glancing())
	check(began >= 0.0 and lv._seen.has("courier_glance"), "the walker 3.5 m behind: he starts a glance, with the hint")
	var done := await _tail(lv, 3.0, 3.5, 0.0, 0.0, func() -> bool: return c.suspicion > 0)
	check(c.suspicion == 1 and absf(done - (c.SLOW_S + c.TURN_S)) < 0.1,
		"the umbrella not tilted forward: +1 suspicion as the turn completes (%.2f s in)" % done)
	check(is_equal_approx(c.glance_dist(), c.GLANCE_DIST + c.GLANCE_DIST_UNEASY), "at suspicion 1 he glances from a metre further")
	var glanced := false
	var t := 0.0
	while t < 9.0:
		await _tail(lv, 0.1, 3.5, 1.0, max_tilt)
		t += 0.1
		glanced = glanced or c._glance_checked
	check(glanced and c.suspicion == 1, "the umbrella open and tilted fully forward: his next glance gains nothing (suspicion %d)" % c.suspicion)
	var hidden := Courier.face_hidden(p)
	p.tilt = max_tilt * 0.6
	check(hidden and not Courier.face_hidden(p), "only a full forward tilt hides the face")

	# The bots: hang back, and tilt forward while he glances.
	p.position.x = c.position.x - 3.0
	var ap: Array = c.steer_bot(p, [0.0, 0.5, 0.0, false])
	check(ap[3] and ap[1] == 0.0, "the bots hold stop when they're inside his glance distance")
	c._glance_t = 0.1
	ap = c.steer_bot(p, [0.0, 0.0, 0.0, false])
	check(ap[0] == 1.0 and ap[2] == 1.0, "... and open the umbrella tilted fully forward while he glances")
	c._glance_t = -1.0

	# LOST: off the right edge of the frame for 2 s.
	_unhook_defeat(p)
	var off_t := -1.0
	t = 0.0
	while t < 20.0 and p.state != Player.State.DEFEATED:
		await get_tree().process_frame
		t += get_process_delta_time()
		p.state = Player.State.STOPPED if p.state != Player.State.DEFEATED else p.state
		if off_t < 0.0 and c.position.x - 0.3 > c.frame_right():
			off_t = t
	check(p.fail_cause == &"lost" and off_t > 0.0 and absf(t - off_t - c.LOST_S) < 0.1,
		"the walker standing still: he walks out of frame, and %.2f s later the attempt fails as LOST" % (t - off_t))
	await _drop_street(lv)

	# MADE: the walker within 1.2 m of him.
	lv = await _street_with(COURIER)
	p = lv.player
	c = lv.courier
	_unhook_defeat(p)
	p.position.x = 23.0
	await _tail(lv, 3.5, 7.0)
	await _tail(lv, 0.3, 1.6)
	check(p.state != Player.State.DEFEATED, "1.6 m behind him is close, but not too close")
	await _tail(lv, 0.3, 1.0)
	check(p.state == Player.State.DEFEATED and p.fail_cause == &"made", "1 m behind him: YOU WERE MADE (%s)" % p.fail_cause)
	await _drop_street(lv)

	# SHOT: the 4th gain.
	lv = await _street_with(COURIER)
	p = lv.player
	c = lv.courier
	_unhook_defeat(p)
	p.position.x = 23.0
	await _tail(lv, 3.5, 7.0)
	c.suspicion = 3
	await _tail(lv, 8.0, 3.5, 0.0, 0.0, func() -> bool: return c.phase == c.Phase.AIM)
	check(c.phase == c.Phase.AIM and p.state != Player.State.DEFEATED, "the 4th gain: he turns to aim")
	p.wet = 0.0
	seed(13)
	await _tail(lv, 6.0, 0.0, 0.0, 0.0, func() -> bool: return p.state == Player.State.DEFEATED)
	check(p.fail_cause == &"shot" and p.wet >= 0.8 * Tun.f("wet_max"),
		"... and fires twice, each soaking like a car's splash (wet %.1f), then the attempt fails as SHOT (%s)" % [p.wet, p.fail_cause])
	await _drop_street(lv)

	# A checkpoint resume past his doorway puts him on his way just ahead, past the stops behind it.
	Game.debug_resume_cp = 0
	lv = await _street_with(COURIER)
	Game.debug_resume_cp = -1
	c = lv.courier
	check(c.phase == c.Phase.WALK and absf(c.position.x - lv.player.position.x - c.RESUME_GAP) < 0.5 and c._next_stop == 1,
		"resuming at x %.1f: he's already walking, %.1f m ahead, with the stop behind spent" % [lv.player.position.x, c.position.x - lv.player.position.x])
	await _drop_street(lv)


## The fatal look can come while he faces a shop window: he turns the short way to the walker and is
## facing him before the glint.
func _test_courier_aim_from_window() -> void:
	var lv := await _street_with({"courier": {"appear_x": 30.0, "door_x": 200.0, "stops": [{"x": 36.0, "dur": 3.0}]}})
	var p: Player = lv.player
	var c: Node3D = lv.courier
	_unhook_defeat(p)
	p.position.x = 23.0
	await _tail(lv, 3.5, 7.0)
	c.suspicion = 3
	await _tail(lv, 10.0, 7.0, 0.0, 0.0, func() -> bool: return c.phase == c.Phase.AIM)
	var at_window: bool = c.phase == c.Phase.AIM and c.global_basis.x.z < -0.9
	var turned := 0.0
	var facing_at_glint := NAN
	var was := c.rotation.y
	var t := 0.0
	while t < 1.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		turned += absf(angle_difference(was, c.rotation.y))
		was = c.rotation.y
		if is_nan(facing_at_glint) and lv.get_children().any(func(n: Node) -> bool: return n is WaterJet):
			facing_at_glint = c.global_basis.x.x
	check(at_window and turned < PI and facing_at_glint < -0.98,
		"made at a shop window: he turns %.0f degrees to the walker, and faces him as the glint starts (%.2f)" % [rad_to_deg(turned), facing_at_glint])
	await _drop_street(lv)


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

	# Checkpoint restarts: wetness capped at 80%, extra relief past the second resume of a segment.
	var wmax := Tun.f("wet_max")
	var soaked := {"id": "main_street", "index": 1, "x": x2, "wet": wmax * 0.96, "stamina": 61.0, "exhausted": false,
		"elapsed": 33.0, "stats": p.stats.duplicate(), "seen": {}, "car_hints": 0}
	for c in [[1, 0.8], [2, 0.8], [3, 0.75], [4, 0.7]]:
		Game.checkpoint = soaked.duplicate(true)
		Game.checkpoint["restarts"] = c[0]
		level._restore_checkpoint()
		check(is_equal_approx(p.wet, wmax * c[1]), "a 96%%-wet checkpoint on resume %d starts %d%% wet (got %.1f%%)"
			% [c[0], int(c[1] * 100.0), p.wet / wmax * 100.0])
	Game.checkpoint = soaked.duplicate(true)
	Game.checkpoint["wet"] = wmax * 0.06
	Game.checkpoint["restarts"] = 5
	level._restore_checkpoint()
	check(is_equal_approx(p.wet, 0.0), "relief never makes him less than dry (%.2f)" % p.wet)
	Game.checkpoint["wet"] = wmax * 0.3
	Game.checkpoint["restarts"] = 2
	level._restore_checkpoint()
	check(is_equal_approx(p.wet, wmax * 0.3), "a damp checkpoint resumes as it was until the third resume (%.2f)" % p.wet)
	p.position.x = float(cps[2]) + 0.2
	p.state = Player.State.WALK
	level._check_checkpoints()
	check(Game.checkpoint.get("index", -1) == 2 and not Game.checkpoint.has("restarts"),
		"reaching the next checkpoint starts its segment's restart count over")
	Game.checkpoint = {}


## The water in the umbrella's shot is part of the checkpoint; starting the street over fills it.
func _test_checkpoint_water() -> void:
	var p: Player = level.player
	var cps: Array = level.checkpoints
	p.gun.shots = 1.5
	p.state = Player.State.WALK
	level._next_cp = 1
	p.position.x = float(cps[1]) + 0.2
	level._check_checkpoints()
	p.gun.shots = 0.0
	Game.resuming = true
	level.queue_free()
	await _frames(2)
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	check(level.resumed and is_equal_approx(level.player.gun.shots, 1.5),
		"a checkpoint resume has the water the umbrella held at the checkpoint (%.2f of %d)" % [level.player.gun.shots, level.player.gun.capacity()])
	level.queue_free()
	await _frames(2)
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	check(not level.resumed and is_equal_approx(level.player.gun.shots, level.player.gun.capacity()),
		"starting the street over fills it (%.2f)" % level.player.gun.shots)
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
	# Car splash: real droplets. Near the crossing they soak him, a canopy tilted forward stops most of
	# them, and standing back out of the wave's reach he stays dry.
	var got: Array = []
	seed(42)   # droplet bursts are random: fix them so the check is stable
	for cfg in [[0.0, 0.0, 3.0], [1.0, 1.0, 3.0], [0.0, 0.0, 10.0]]:
		await _place(open_x, cfg[0], cfg[1] * Tun.f("umbrella_max_tilt"))
		var car := CarHazard.new()
		car.level = level
		car.crossing_x = p.position.x + cfg[2]
		level.add_child(car)
		var was: float = p.stats["wet_splash"]
		car._do_splash(p)
		await get_tree().create_timer(2.0).timeout
		got.append(p.stats["wet_splash"] - was)
		car.queue_free()
	check(got[0] >= 0.6 * Tun.f("wet_car_splash") and got[0] <= Tun.f("wet_car_splash") and got[1] < got[0] * 0.3 and got[2] == 0.0,
		"car splash from its droplets: 3 m from the crossing %.1f, tilted forward %.1f, 10 m back %.1f" % got)
	print("umbrella center ", p.umbrella.canopy_center(), " player ", p.global_position, " radius ", p.umbrella.current_radius())
	_test_sun_drying()
	_test_feedback_url()
	_test_street_text()
	_test_next_token()
	await _test_checkpoints()
	await _test_checkpoint_water()
	await _test_street_hints()
	await _test_pause_holds_hints()
	await _test_no_pause_while_building()
	await _test_pause_when_away()
	await _test_follower()
	await _test_follower_walker_defeated()
	await _test_courier()
	await _test_courier_aim_from_window()
	await _test_raincoat_figure()
	await _test_fail_cause()
	await _test_walk_off()
	await _test_trigger_ends()
	await _test_tilt_hand_off()
	await _test_touch_controls()
	await _test_umbrella_shot()
	await _test_viaduct()
	await _test_viaduct_road()
	await _test_rocket_row()
	await _test_the_bypass()
	_test_dynamic_resolution()
	await _test_menu_width()
	await _test_credits_scroll()
	await _test_slider_saves()
	await _test_shop_fits()
	await _test_small_screen_text()
	_run_tests()
	get_parent().finish(failures)


## Each attempt rolls its own train gaps within the street's range; a seed always rolls the same ones.
func _test_departures(data: Dictionary) -> void:
	var a := Track.parse(data["track"], [], 7)
	var b := Track.parse(data["track"], [], 7)
	var c := Track.parse(data["track"], [], 8)
	a.departure(900.0)
	var gaps := PackedFloat64Array()
	for i in range(1, a.departures.size()):
		gaps.append(a.departures[i] - a.departures[i - 1])
	var lo: float = Array(gaps).min()
	var hi: float = Array(gaps).max()
	check(lo >= a.gap_min and hi <= a.gap_max and hi - lo > (a.gap_max - a.gap_min) * 0.5,
		"%d train gaps all within %.0f-%.0f s and spread across it (%.1f-%.1f)" % [gaps.size(), a.gap_min, a.gap_max, lo, hi])
	var same := true
	var differs := false
	for t in range(0, 900, 7):
		same = same and a.wash_eta(100.0, t) == b.wash_eta(100.0, t)
		differs = differs or a.wash_eta(100.0, t) != c.wash_eta(100.0, t)
	check(same and differs, "a train seed always rolls the same trains, another seed different ones")
	check(a.noses(0.0).size() > 0, "trains are already on the track when the clock starts")


## When the next train's sheet starts falling at x, some way into the run.
func _next_sheet(x: float) -> float:
	var t0 := 40.0
	while level.wash_at(x, t0):
		t0 += 0.5
	return t0 + level.wash_eta(x, t0)


func _wash(x: float, open: float, tilt: float, t: float) -> float:
	await _place(x, open, tilt)
	level.elapsed = t
	return level.player._wash_exposure()


## Telstar Parade: a train's sheet of water is a pure function of the level clock and the attempt's
## rolled departures, and falls wherever the train is, from a deck where one hangs over him and from the train elsewhere. It falls straight
## down, so an upright umbrella or an awning stops it and a tilted umbrella doesn't.
func _test_viaduct() -> void:
	Game.current_level = "telstar_parade"
	if is_instance_valid(level):   # the street-hint test already freed it
		level.queue_free()
	await _frames(2)
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	await _frames(5)
	var p: Player = level.player
	p.set_physics_process(false)
	var tr: Track = level.track
	check(tr != null and not tr.decks.is_empty(), "telstar_parade has a track with deck spans")
	if tr == null or tr.decks.is_empty():
		return
	var deck: Array = tr.decks[0]
	var bare := -1.0       # open lot under the first deck
	var open_sky := -1.0   # open lot under bare beam
	var awning := -1.0     # awning under the first deck
	for lot in level.data["lots"]:
		var mid: float = lot["x"] + lot["w"] * 0.5
		var on_deck: bool = mid > deck[0] + 1.0 and mid < deck[1] - 1.0
		if lot["cover"] == "none" and lot["w"] >= 4.0 and mid > 20.0:
			if on_deck and bare < 0.0:
				bare = mid
			if not tr.deck_at(mid) and open_sky < 0.0:
				open_sky = mid
		if on_deck and lot["cover"] == "awning" and not lot.has("tears") and awning < 0.0:
			awning = mid
	var t_front := _next_sheet(bare)
	var t := t_front + 0.3
	check(level.wash_at(bare, t) and not level.wash_at(bare, t_front - 0.2) and not level.wash_at(bare, t_front + 1.2),
		"the sheet falls at x=%.1f for about a second after the train's nose passes" % bare)
	check(absf(level.wash_eta(bare, t_front - 1.5) - 1.5) < 0.01 and level.wash_eta(bare, t) == 0.0,
		"wash_eta counts down to the sheet and is 0 under it")
	var gap: float = level.wash_eta(bare, t_front + 1.0) + 1.0
	check(gap >= tr.gap_min - 0.01 and gap <= tr.gap_max + 0.01 and is_inf(level.wash_eta(tr.x1 + 5.0, t)),
		"the next sheet comes one train gap later (%.1f s); off the track there's none" % gap)
	_test_departures(level.data)
	var shut := await _wash(bare, 0.0, 0.0, t)
	check(shut > 0.95, "under the sheet with the umbrella shut: exposure %.2f ~ 1" % shut)
	var upright := await _wash(bare, 1.0, 0.0, t)
	check(upright < 0.1, "umbrella open and upright: exposure %.2f ~ 0" % upright)
	var tilted := await _wash(bare, 1.0, Tun.f("umbrella_max_tilt"), t)
	check(tilted > 0.3, "umbrella tilted fully forward: exposure %.2f, the sheet reaches him" % tilted)
	if awning > 0.0:
		var t_aw := _next_sheet(awning) + 0.3
		check(level.wash_at(awning, t_aw) and await _wash(awning, 0.0, 0.0, t_aw) == 0.0, "under an awning beneath the deck the sheet never reaches him")
	check(open_sky > 0.0, "telstar_parade has an open lot off the decks at x=%.1f" % open_sky)
	if open_sky > 0.0:
		var t_sky := _next_sheet(open_sky) + 0.3
		var sky_shut := await _wash(open_sky, 0.0, 0.0, t_sky)
		var sky_upright := await _wash(open_sky, 1.0, 0.0, t_sky)
		var sky_between := await _wash(open_sky, 0.0, 0.0, t_sky + 2.0)
		check(sky_shut > 0.95 and sky_upright < 0.1 and sky_between == 0.0,
			"off the decks the train's own sheet lands on him: shut %.2f, upright %.2f, between trains %.2f" % [sky_shut, sky_upright, sky_between])
	await _place(bare, 0.0, 0.0)
	level.elapsed = t
	check(level.player._wash_threat(1.8), "the bots see the sheet coming where he stands")
	level.elapsed = t_front - 5.0
	check(not level.player._wash_threat(1.8), "... and not while the next train is far off")

	var keep := -1
	var plain := -1
	for i in level.phones.size():
		if level.phones[i]["keep"]:
			keep = i
		elif plain < 0:
			plain = i
	check(keep >= 0 and level.phones[keep]["line"] != "", "the station phone keeps ringing and has a line")
	if keep < 0:
		return
	var kx: float = level.phones[keep]["x"]
	var px: float = level.phones[plain]["x"]
	check(level.phone_ringing(plain, px - 3.0) and not level.phone_ringing(plain, px + 1.0)
		and not level.phone_ringing(plain, px - Level.PHONE_HEAR - 1.0), "a plain payphone rings as he nears it and stops once he's past")
	check(level.phone_ringing(keep, kx + 6.0), "a `keep` phone rings on after he passes")
	p.position.x = kx + 0.5
	p.state = Player.State.STOPPED
	level._train_and_phone_hints(0.3)
	check(level.phone_ringing(keep, kx + 0.5), "a moment's stop beside it doesn't answer it")
	level._train_and_phone_hints(0.4)
	check(not level.phone_ringing(keep, kx + 0.5) and level._seen.has("phone@%d" % keep), "holding stop beside it answers it: the line shows and the ring stops")
	p.state = Player.State.WALK


## Fires one real WaterJet at the walker, standing at x with the umbrella open and tilted `tilt` of
## full, from where a pursuer 5.8 m behind holds his umbrella to fire (muzzle `muzzle_y` up). Returns
## what the pellets did.
func _shot(x: float, tilt: float, muzzle_y := 1.35) -> Dictionary:
	var p: Player = level.player
	for settle in 2:
		await _place(x, 1.0, tilt * Tun.f("umbrella_max_tilt"))
	p.jet_kick = 0.0
	var hit_was: float = p.stats["wet_hit"]
	var elev := PI * 0.5 - WaterJet.AIM_TILT
	var basis := Basis(Vector3(0, 0, 1), -(PI * 0.5 - elev))   # the shaft (local +Y) along +X, elev above level
	var from := p.global_position + Vector3(-5.8, muzzle_y, -0.35)
	var jet := WaterJet.fire(level, func() -> Transform3D: return Transform3D(basis, from), -1.0, 0.05)
	var blocked: bool = await jet.resolved
	return {"blocked": blocked, "landed": jet.burst.landed, "stopped": jet.burst.stopped,
		"wet": p.stats["wet_hit"] - hit_was, "kick": p.jet_kick}


## Viaduct Road: railway arches are cover from the rain and the sheet; jets from behind are blocked
## by a canopy tilted back toward them (and shove it, less with Sturdy Frame) or soak him as SHOT;
## the men who fire them hold fire under an arch and stay spent after a checkpoint resume.
func _test_viaduct_road() -> void:
	Game.current_level = "viaduct_road"
	if is_instance_valid(level):
		level.queue_free()
	await _frames(2)
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	await _frames(5)
	var p: Player = level.player
	p.set_physics_process(false)
	_unhook_defeat(p)
	var tr: Track = level.track
	check(tr != null and tr.railway() and not tr.decks.is_empty(), "viaduct_road has a railway with runs of arches")
	var arch: Array = tr.decks[1]
	var ax: float = (arch[0] + arch[1]) * 0.5
	check(tr.arch_at(ax) and not tr.arch_at(arch[1] + 3.0), "arch_at is true under the arches and false on the girders past them")
	var shut := await _place(ax, 0.0)
	check(shut < 0.05, "under a railway arch with the umbrella shut: rain exposure %.2f ~ 0" % shut)
	var t_sheet := _next_sheet(ax) + 0.3
	check(level.wash_at(ax, t_sheet) and await _wash(ax, 0.0, 0.0, t_sheet) == 0.0, "the train's sheet never reaches him under an arch")
	var open_x := -1.0
	for lot in level.data["lots"]:
		var mid: float = lot["x"] + lot["w"] * 0.5
		if lot["style"] == "vacant" and lot["w"] >= 4.0 and mid > 40.0 and not tr.deck_at(mid) and open_x < 0.0:
			open_x = mid
	var t_open := _next_sheet(open_x) + 0.3
	var bare := await _wash(open_x, 0.0, 0.0, t_open)
	check(bare > 0.95, "on an open girder span (x=%.1f) the sheet falls through onto him: exposure %.2f" % [open_x, bare])

	# Real shots from where a pursuer stands, umbrella down at his chest: what wets him is the pellets
	# that reach him. An upright canopy lets them by; one tilted back toward him stops them and is shoved.
	seed(12)
	var up := await _shot(open_x, 0.0)
	check(up["landed"] > 0 and up["wet"] > Tun.f("wet_jet_hit") * 0.6 and up["wet"] <= Tun.f("wet_jet_hit") + 0.01,
		"over an upright canopy the shot reaches him: %d pellets, wet %.1f (a full hit is %.0f)" % [up["landed"], up["wet"], Tun.f("wet_jet_hit")])
	var back := await _shot(open_x, -0.85)
	check(back["wet"] < up["wet"] * 0.35 and back["stopped"] > back["landed"] * 2 and back["kick"] > 0.5,
		"a canopy tilted well back toward him stops most of it (%d pellets stopped, %d through: wet %.1f) and is shoved (%.2f)" % [back["stopped"], back["landed"], back["wet"], back["kick"]])
	var sturdy_was: int = Game.run.upgrades[&"sturdy"]
	var kicks: Array = []
	for tier in [0, 3]:
		Game.run.upgrades[&"sturdy"] = tier
		kicks.append((await _shot(open_x, -0.85))["kick"])
	Game.run.upgrades[&"sturdy"] = sturdy_was
	check(kicks[1] < kicks[0] and absf(kicks[1] / kicks[0] - Game.jet_shove_mult(3)) < 0.15,
		"Sturdy Frame tier 3 takes about a quarter of the shove a bare frame does (%.2f vs %.2f)" % [kicks[1], kicks[0]])
	p.wet = Tun.f("wet_max") - 2.0
	await _shot(open_x, 0.0)
	p._physics_process(1.0 / 60.0)
	check(p.state == Player.State.DEFEATED and p.fail_cause == &"shot", "a shot that soaks him fails the attempt as SHOT: %s" % p.fail_cause)
	p.state = Player.State.WALK

	var att: Node = level.attackers
	check(att != null and att.phase == att.Phase.OFF and not att.visible, "nobody is behind him before the first attacker's x")
	att._begin(0)
	att._t = 2.0
	await _idle_frames(3)
	var edge: float = att._frame_edge()
	var tip: float = att._shadow.global_position.x + att._shadow.global_basis.x.length() * 0.5
	check(att.position.x < edge and att._shadow.visible and tip > edge + 4.0,
		"the warning: he is still out of shot (%.1f < %.1f) while his shadow already lies on the pavement in it" % [att.position.x, edge])
	att._set_phase(att.Phase.FIRE)
	att._shot_t = 0.0
	var shots: int = att.shots_left
	p.position.x = ax
	att._fire_control(0.016, p)
	check(att.jet == null and att.held == 1 and att.shots_left == shots - 1, "under an arch he holds his fire, and the held shot still counts")
	p.position.x = open_x
	att._shot_t = 0.0
	att._fire_control(0.016, p)
	check(att.incoming(), "out from under the arches he fires")
	att.jet.queue_free()
	att.jet = null
	# Outrun: once he has closed in he walks no faster than walking pace, and off the frame he gives up.
	att._set_phase(att.Phase.FIRE)
	att._closed = true
	att._out_t = 0.0
	att.position.x = att._frame_edge() - 3.0
	var shots_now: int = att.shots_left
	var t_out := 0.0
	var fastest := 0.0
	while t_out < 2.0 and att.phase == att.Phase.FIRE:
		await get_tree().process_frame
		t_out += get_process_delta_time()
		fastest = maxf(fastest, att.speed)
	check(att.phase != att.Phase.FIRE and absf(t_out - att.GIVE_UP_S) < 0.1 and fastest <= Tun.f("walk_speed") + 0.001 and att.shots_left == shots_now,
		"left behind out of the frame, he gives up after %.2f s (never faster than walking: %.2f m/s)" % [t_out, fastest])

	# Each man is a body the walker's shots can soak: two clean hits and he gives up on his own,
	# the attack ends, and the next man is a fresh one.
	att._begin(0)
	att._set_phase(att.Phase.FIRE)
	await _idle_frames(2)
	var first: NpcBody = att.man
	var half := first.wet_max() * 0.5
	first.soak(half, &"shot")
	await _frames(2)
	check(att.phase == att.Phase.FIRE and first.wet == half and first.get_parent() == att,
		"one hit leaves him half soaked (%.1f) and still on" % first.wet)
	first.soak(half, &"shot")
	await _frames(2)
	check(att.phase == att.Phase.OFF and not att.visible and att.man != first and att.man.wet == 0.0
		and first.get_parent() == level and first.visible and first._dropped_umbrella,
		"the second soaks him: he drops his umbrella and leaves on his own, and the next man is dry")
	first.queue_free()

	# A resume from the second checkpoint: the first two men are spent, the third still comes.
	var xs: Array = level.data["attackers"].map(func(a: Dictionary) -> float: return float(a["x"]))
	var cp_i := 0
	while cp_i < level.checkpoints.size() and float(level.checkpoints[cp_i]) < xs[1]:
		cp_i += 1
	check(cp_i < level.checkpoints.size() and float(level.checkpoints[cp_i]) < xs[2], "a checkpoint lies between the second and third men")
	level.queue_free()
	await _frames(2)
	Game.debug_resume_cp = cp_i
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	Game.debug_resume_cp = -1
	await _frames(3)
	p = level.player
	p.set_physics_process(false)
	att = level.attackers
	check(att._next == 2, "resuming past two men's x skips both (next is #%d)" % att._next)
	p.position.x = xs[1] + 2.0
	await _idle_frames(3)
	check(att.phase == att.Phase.OFF and att.index == -1, "... and walking back over one's x doesn't bring him")
	p.position.x = xs[2] + 0.5
	await _idle_frames(3)
	check(att.phase == att.Phase.WARN and att.index == 2, "the third still comes when the walker reaches his x")

	var r := Run.new("left", Game.start_node)
	r.completed = [Game.start_node, "canal_row", "mill_road", "kiln_street"]
	r.current_node = "kiln_street"
	var run_was := Game.run
	Game.run = r
	check(not Game.is_soon("viaduct_road") and Game.can_select("viaduct_road"), "the map opens Viaduct Road once Kiln Street is walked")
	r.completed = [Game.start_node, "canal_row", "mill_road"]
	r.current_node = "mill_road"
	check(not Game.can_select("viaduct_road"), "... and not before")
	Game.run = run_was


## Puts the walker at x with the camera caught up, and lets the street run `frames` frames.
func _walker_at(x: float, frames := 3) -> void:
	var p: Player = level.player
	p.position = Vector3(x, level.ground_y(x), Tun.f("player_z"))
	level._cam_x = x + Tun.f("camera_lead")
	level._update_camera(1.0)
	await _idle_frames(frames)


## Real seconds until `cond` holds (INF if it doesn't within `limit`).
func _until(cond: Callable, limit: float) -> float:
	var t := 0.0
	while not cond.call():
		if t > limit:
			return INF
		await get_tree().process_frame
		t += get_process_delta_time()
	return t


## Rocket Row: men who wait under the canopies and fire on a timer, the car that pulls out once one
## is dealt with, and the street on the map.
func _test_rocket_row() -> void:
	Game.current_level = "rocket_row"
	if is_instance_valid(level):
		level.queue_free()
	await _frames(2)
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	await _frames(5)
	var p: Player = level.player
	p.set_physics_process(false)
	p.speed = 0.0
	_unhook_defeat(p)
	check(p.gun.armed, "Rocket Row is armed")
	var hm: Node = level.henchmen
	check(hm != null and hm.men.size() == 5 and hm.men.all(func(m) -> bool:
		return m.body is NpcBody and m.body.umbrella.open == 0.0 and m.body.global_basis.x.x < -0.85),
		"five men wait at their x, umbrellas furled, facing back down the street")
	var m = hm.men[0]
	await _walker_at(m.x - hm.RANGE - 3.0, 30)
	check(m.phase == hm.Phase.WAIT and not hm.incoming() and not hm.armed(), "out of his range he only waits")
	var dealt: Array = []
	hm.dealt_with.connect(func(i: int) -> void: dealt.append(i))
	await _walker_at(m.x - 6.0)
	var first := await _until(func() -> bool: return m.incoming(), 4.0)
	check(m.phase == hm.Phase.FIRE and m.open == 1.0 and first < hm.OPEN_S + hm.FIRST_SHOT + 0.3 and level._seen.has("henchman"),
		"in range and in shot he opens up and his first glint comes %.2f s later, with the hint" % first)
	# The timer: each gap is the next of INTERVALS, nudged by up to JITTER, and runs only once the
	# last jet has landed.
	var gaps_ok := true
	for k in 6:
		hm._drop_jet(m)
		var i: int = m.next
		hm._fire(m)
		gaps_ok = gaps_ok and absf(m.shot_t - hm.INTERVALS[i]) <= hm.JITTER + 0.001 and m.next == (i + 1) % hm.INTERVALS.size()
	check(gaps_ok, "the gaps between shots cycle through %s, each within %.1f s" % [hm.INTERVALS, hm.JITTER])
	var held: float = m.shot_t
	await _idle_frames(10)
	check(m.incoming() and m.shot_t == held, "while his jet is glinting or in the air the next one waits")
	# Brought down to aim, his canopy stops the walker's shot; overhead between shots it lets it by.
	m.jet.glint_s = 100.0
	await get_tree().create_timer(0.5).timeout
	await _walker_at(m.x - 3.0)
	var shield := await _shots_at(m.body, 3)
	check(shield[0] > shield[1] * 8 and shield[2] < Tun.f("gun_hit") * 0.35,
		"aiming, his lowered canopy stops the shot (%d stopped, %d through, wet %.1f a shot)" % shield)
	check(not p._autopilot_fire(), "the bots hold their fire while his canopy is in the way")
	m.body.wet = 0.0
	m.body.visual.call("set_wetness", 0.0)
	hm._drop_jet(m)
	m.shot_t = 100.0
	await get_tree().create_timer(0.5).timeout
	check(p._autopilot_fire(), "... and fire once it is back over his head")
	await _fire()
	var one: float = m.body.wet
	await _fire()
	await _frames(2)
	check(one >= Tun.f("gun_hit") * 0.95 and m.phase == hm.Phase.DONE and not m.body.wettable() and dealt == [0] and not hm.armed(),
		"two clean hits between his shots soak him (%.1f after one): he gives up and is dealt with" % one)

	# Passed: he turns round, fires from behind while the walker is in range, and is dealt with.
	var m2 = hm.men[1]
	await _walker_at(m2.x - 5.0)
	await _until(func() -> bool: return m2.phase == hm.Phase.FIRE, 3.0)
	hm._drop_jet(m2)
	await _walker_at(m2.x + 2.5)
	m2.shot_t = 0.3
	var turned := await _until(func() -> bool: return absf(m2.body.rotation.y) < 0.01, 2.0)
	var behind := await _until(func() -> bool: return m2.incoming(), 2.0)
	check(dealt == [0, 1] and turned < 1.0 and behind < 1.0 and hm.brace_side() <= 0.0,
		"past him, he is dealt with, turns round in %.2f s and fires from behind %.2f s later" % [turned, behind])
	hm._drop_jet(m2)
	await _walker_at(m2.x + hm.RANGE + 1.0)
	m2.shot_t = 0.0
	await _idle_frames(20)
	check(not m2.incoming(), "out of his range behind, he stops")

	# The car: parked dark beside a man in a slicker until the third man is dealt with.
	var pk: PickupCar
	for c in level.cars:
		if c is PickupCar:
			pk = c
	var cx: float = pk.crossing_x
	var slicker := pk.man
	check(pk.phase == PickupCar.P.PARKED and not pk.is_threat_for(cx - 5.0) and pk._lights.all(func(l: SpotLight3D) -> bool: return l.light_energy == 0.0)
		and slicker is RaincoatFigure and not WetBody.of_level(level).has(slicker as Node) and slicker.smoking,
		"a car idles dark in the side street, the man in the slicker beside it, out of the shot's reach")
	await _walker_at(cx - 12.0)
	var early: bool = level._seen.has("slicker")
	await _walker_at(cx - 8.0)
	check(not early and level._seen.has("slicker"), "once he is in the frame, the line about his raincoat shows")
	check(level.camera_bias == pk.LOOK_AHEAD, "coming up to the crossing, the camera looks ahead to keep him in shot")
	var m3 = hm.men[pk.after]
	m3.body.soak(m3.body.wet_max(), &"shot")
	await _frames(2)
	check(pk.phase == PickupCar.P.BOARDING and pk.is_threat_for(cx - 5.0) and level.camera_bias == pk.LOOK_AHEAD,
		"once man #%d is soaked he heads for the car, in shot, and the engine turns over" % pk.after)
	var boarded := await _until(func() -> bool: return pk.phase == PickupCar.P.STARTING, 6.0)
	await _frames(2)
	check(not is_instance_valid(slicker) and boarded < 4.0 and level.camera_bias == 0.0, "he gets in (%.1f s) and the camera comes back" % boarded)
	await _walker_at(cx - 2.0)
	await get_tree().create_timer(pk.START_S + 0.3).timeout
	check(pk.phase == PickupCar.P.STARTING and pk._lights[0].light_energy > 7.0, "headlights on, it waits while the walker is at the kerb")
	await _walker_at(cx - 5.5)
	var was: float = p.stats["wet_splash"]
	var drove := await _until(func() -> bool: return pk._splashed, 3.0)
	await get_tree().create_timer(1.5).timeout
	check(drove < 2.0 and p.stats["wet_splash"] - was > 5.0, "5.5 m short of the crossing it pulls out through the puddle at him (+%.1f wet)" % (p.stats["wet_splash"] - was))

	# A resume from the middle checkpoint leaves out the men behind it, and the car with them.
	level.queue_free()
	await _frames(2)
	Game.debug_resume_cp = 1
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	Game.debug_resume_cp = -1
	await _frames(3)
	hm = level.henchmen
	var gone: Array = hm.men.filter(func(mm) -> bool: return mm.body == null).map(func(mm) -> int: return mm.index)
	check(gone == [0, 1, 2] and level.cars.filter(func(c) -> bool: return c is PickupCar).all(func(c) -> bool: return c.phase == PickupCar.P.GONE),
		"resuming at %.1f m skips the men behind it %s and the car" % [level.player.position.x, gone])
	level.player.set_physics_process(false)

	var r := Run.new("right", Game.start_node)
	r.completed = [Game.start_node, "arcade_lane", "neon_junction", "telstar_parade", "atomic_avenue"]
	r.current_node = "atomic_avenue"
	var run_was := Game.run
	Game.run = r
	check(not Game.is_soon("rocket_row") and Game.can_select("rocket_row"), "the map opens Rocket Row once Atomic Avenue is walked")
	r.completed.pop_back()
	r.current_node = "telstar_parade"
	check(not Game.can_select("rocket_row"), "... and not before")
	Game.run = run_was
	check(preload("res://src/ui/hud.gd").fail_line("rocket_row", &"shot") == "Right through the lapels.", "Rocket Row's SHOT line")
	level.queue_free()
	await _frames(2)
	Game.current_level = "main_street"


## One drive-by pass with the walker held at x, his canopy tilted `tilt` (of full) the whole time:
## the wetness its splash and its shot put on him, the order they came in, and the camera's pull.
func _drive_by_pass(x: float, tilt: float) -> Dictionary:
	var p: Player = level.player
	await _place(x, 1.0, tilt * Tun.f("umbrella_max_tilt"))
	p.jet_kick = 0.0
	var db: DriveBy = level.drive_bys
	var splash_was: float = p.stats["wet_splash"]
	var hit_was: float = p.stats["wet_hit"]
	var cam_z0: float = level.camera.global_position.z
	db._begin()
	await _idle_frames(2)
	var out := {"car_out_of_shot": db.position.x + 2.6 < level.camera.global_position.x - 8.0, "splash_t": -1.0,
		"glint_t": -1.0, "glint_s": 0.0, "pull": 0.0, "brace": []}
	var t := 0.0
	while db.phase != DriveBy.Phase.AWAY and t < 12.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		out["pull"] = maxf(out["pull"], level.camera.global_position.z - cam_z0)
		if out["splash_t"] < 0.0 and not db.splashes.is_empty():
			out["splash_t"] = t
		if out["glint_t"] < 0.0 and db.jet != null:
			out["glint_t"] = t
			out["glint_s"] = db.jet.glint_s
		var b := db.brace()
		if out["brace"].is_empty() or out["brace"][-1] != b:
			out["brace"].append(b)
	await get_tree().create_timer(1.2).timeout
	out["splash"] = p.stats["wet_splash"] - splash_was
	out["shot"] = p.stats["wet_hit"] - hit_was
	return out


## The Bypass: cars pass from behind on the near lane, the camera pulling out to show them; each
## splashes first (a canopy tilted back stops it), then its passenger glints and fires from ahead
## (tilted forward stops that), and a shot that soaks him fails as SHOT. A man waits posted under the
## petrol canopy, fires from ahead until passed, then follows at his own `gap`. A man in a slicker
## stands on the motel walkway, which is cover; the walker's shots don't wet him.
func _test_the_bypass() -> void:
	Game.current_level = "the_bypass"
	if is_instance_valid(level):
		level.queue_free()
	await _frames(2)
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	await _frames(5)
	var p: Player = level.player
	p.set_physics_process(false)
	_unhook_defeat(p)
	var db: DriveBy = level.drive_bys
	check(db != null and db._queue.size() == level.data["drive_bys"].size() and db.phase == DriveBy.Phase.OFF and not db.visible,
		"the_bypass has %d drive-bys, none on before the walker reaches one" % db._queue.size())
	var open_x := -1.0
	for lot in level.data["lots"]:
		if lot["style"] == "forecourt" and open_x < 0.0:
			open_x = float(lot["x"]) + float(lot["w"]) * 0.5
	seed(7)
	var up := await _drive_by_pass(open_x, 0.0)
	check(up["car_out_of_shot"] and up["pull"] > DriveBy.PULL * 0.6,
		"the warning starts with the car out of shot behind him, and the camera pulls out %.1f m to show the lane" % up["pull"])
	check(up["splash_t"] > 0.0 and up["glint_t"] > up["splash_t"] + 0.5 and absf(up["glint_s"] - 0.6) < 0.01,
		"the splash comes first (%.1f s), then a 0.6 s glint (%.1f s) and the shot" % [up["splash_t"], up["glint_t"]])
	check(up["splash"] > 6.0 and up["shot"] > Tun.f("wet_jet_hit") * 0.8,
		"upright, both reach him: splash %.1f, shot %.1f" % [up["splash"], up["shot"]])
	check(up["brace"].has(-1.0) and up["brace"].has(1.0) and up["brace"].find(-1.0) < up["brace"].find(1.0),
		"the bots are told back, then forward: %s" % [up["brace"]])
	var back := await _drive_by_pass(open_x, -0.7)
	check(back["splash"] < up["splash"] * 0.2 and back["shot"] > Tun.f("wet_jet_hit") * 0.8,
		"tilted back, the canopy stops the splash (%.1f) but not the shot from ahead (%.1f)" % [back["splash"], back["shot"]])
	var fwd := await _drive_by_pass(open_x, 1.0)
	# A droplet or two can skim the rim (2.6 each); a shot that misses the canopy costs a full hit.
	check(fwd["shot"] < Tun.f("wet_jet_hit") * 0.5 and fwd["splash"] > up["splash"] * 0.5,
		"tilted forward, it stops the shot (%.1f) but not the splash from behind (%.1f)" % [fwd["shot"], fwd["splash"]])
	await get_tree().create_timer(2.5).timeout
	check(level.camera_pull == 0.0 and absf(level.camera.global_position.z - Tun.f("player_z") - Tun.f("camera_distance")) < 0.6,
		"once the car has gone the camera eases back in (z %.1f)" % level.camera.global_position.z)
	p.wet = Tun.f("wet_max") - 3.0
	await _drive_by_pass(open_x, -0.7)
	p._physics_process(1.0 / 60.0)
	check(p.state == Player.State.DEFEATED and p.fail_cause == &"shot", "a passenger's shot that soaks him fails as SHOT: %s" % p.fail_cause)
	p.state = Player.State.WALK
	p.wet = 0.0

	# The man posted beside the drainpipe, then following at his own gap.
	var att: Node = level.attackers
	var posted_i := -1
	for i in att._queue.size():
		if float(att._queue[i][3]) >= 0.0:
			posted_i = i
	check(posted_i > 0 and absf(float(att._queue[posted_i][3]) - level.gutters[0]) < 3.0 and level.gutters.size() == 1,
		"one man is posted within 3 m of the street's only drainpipe")
	# A man soaked with his shot in the air: it still lands, from where he fired it, even once the
	# next man is standing at his post ahead (the bots keep bracing back for it).
	p.position.x = open_x
	p._prev_x = open_x
	att._next = posted_i
	att._begin(0)
	att._set_phase(att.Phase.FIRE)
	att.position.x = p.position.x - 3.5
	att._shot_t = 0.0
	att._fire_control(0.016, p)
	while att.jet != null and is_instance_valid(att.jet) and att.jet.phase == WaterJet.Phase.GLINT:
		await get_tree().process_frame
	att.man.soak(att.man.wet_max(), &"shot")
	await _idle_frames(3)
	check(att.posted and att.incoming() and att.side() < 0.0,
		"soaked mid-shot, his shot still comes from behind while the next man stands posted ahead")
	while att.incoming():
		await get_tree().process_frame
	await _idle_frames(2)
	check(att.posted and att.visible and absf(att.position.x - float(att._queue[posted_i][3])) < 0.01 and att.man.wettable(),
		"with nobody else on he stands at his post, in plain sight and soakable")
	p.position.x = float(att._queue[posted_i][0]) + 0.1
	await _idle_frames(3)
	check(att.phase == att.Phase.FIRE and att.posted and att.speed == 0.0 and att.side() > 0.0,
		"when the walker reaches his x he fires from his post, ahead of the walker, without the warning")
	p.position.x = att.position.x + 1.0
	await _idle_frames(3)
	check(not att.posted and att.side() < 0.0 and absf(att.hold_gap() - float(level.data["attackers"][posted_i]["gap"])) < 0.01,
		"once passed he turns and follows, holding %.1f m back" % att.hold_gap())
	check(att.hold_gap() <= Tun.f("gun_range"), "... inside the base range of the walker's shot (%.1f m)" % Tun.f("gun_range"))
	att._leave()

	# The slicker on the motel walkway: under cover, and no body for the shot to wet.
	var figs: Array = level.get_children().filter(func(n: Node) -> bool: return n is RaincoatFigure)
	check(figs.size() == 1 and figs[0].smoking and not WetBody.of_level(level).has(figs[0]),
		"one man in a slicker, smoking, who is no body the walker's shot can wet")
	var walk_x: float = figs[0].position.x
	var shut := await _place(walk_x, 0.0)
	check(shut < 0.05, "under the motel walkway with the umbrella shut: exposure %.2f" % shut)
	check(level.data["hints"].any(func(h: Dictionary) -> bool: return absf(float(h["x"]) - walk_x) < 4.0),
		"a hint shows as the walker reaches him")

	# A resume past the first drive-by's x skips it.
	var xs: Array = level.data["drive_bys"].map(func(d: Dictionary) -> float: return float(d["x"]))
	level.queue_free()
	await _frames(2)
	Game.debug_start_x = xs[0] + 1.0
	level = load("res://src/level/level.tscn").instantiate()
	add_child(level)
	Game.debug_start_x = -1.0
	await _frames(3)
	level.player.set_physics_process(false)
	check(level.drive_bys._next == 1, "starting past the first drive-by's x skips it")
	level.queue_free()
	await _frames(2)

	var r := Run.new("left", Game.start_node)
	r.completed = [Game.start_node, "canal_row", "mill_road", "kiln_street", "viaduct_road"]
	r.current_node = "viaduct_road"
	var run_was := Game.run
	Game.run = r
	check(not Game.is_soon("the_bypass") and Game.can_select("the_bypass") and Game.armed("the_bypass"),
		"the map opens The Bypass once Viaduct Road is walked, and it is armed")
	r.completed.erase("viaduct_road")
	r.current_node = "kiln_street"
	check(not Game.can_select("the_bypass"), "... and not before")
	Game.run = run_was


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


# --- title screen -----------------------------------------------------------------------------

func _open_menu() -> Control:
	var m: Control = load("res://src/ui/main_menu.tscn").instantiate()
	add_child(m)
	await _idle_frames(3)
	return m


func _menu_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text and (n as Control).is_visible_in_tree():
		return n
	for c in n.get_children():
		var b := _menu_button(c, text)
		if b != null:
			return b
	return null


func _press(m: Control, text: String) -> void:
	_menu_button(m, text).pressed.emit()
	await _idle_frames(3)


func _test_menu_width() -> void:
	var m := await _open_menu()
	var before := _menu_button(m, "Quit").size.x
	for page in ["Credits", "Settings"]:
		await _press(m, page)
		await _press(m, "Back")
	check(_menu_button(m, "Quit").size.x == before,
		"main menu buttons keep their width after Credits and back: %d -> %d" % [before, _menu_button(m, "Quit").size.x])
	m.free()


func _test_credits_scroll() -> void:
	var m := await _open_menu()
	await _press(m, "Credits")
	var text: RichTextLabel = m.find_children("*", "RichTextLabel", true, false)[0]
	var back := _menu_button(m, "Back")
	back.grab_focus()
	var push := InputEventJoypadMotion.new()
	push.axis = JOY_AXIS_RIGHT_Y
	push.axis_value = 1.0
	Input.parse_input_event(push)
	await get_tree().create_timer(0.3).timeout
	push.axis_value = 0.0
	Input.parse_input_event(push)
	await _idle_frames(2)
	var scrolled := text.get_v_scroll_bar().value
	check(scrolled > 50.0, "pushing a stick down scrolls the credits: %d px" % scrolled)
	var up := InputEventAction.new()
	up.action = &"ui_up"
	up.pressed = true
	Input.parse_input_event(up)
	await _idle_frames(2)
	up.pressed = false
	Input.parse_input_event(up)
	await _idle_frames(1)
	check(back.has_focus() and text.get_v_scroll_bar().value < scrolled,
		"up on the credits scrolls back while Back keeps focus")
	m.free()

func _test_slider_saves() -> void:
	var real_path := Game.save_path
	Game.save_path = OS.get_temp_dir().path_join("dgw_slider_%d.json" % OS.get_process_id())
	Game.autopilot = false
	Game.settings["music"] = 0.5
	Game.save_game()
	var m := await _open_menu()
	await _press(m, "Settings")
	var music: HSlider = m.find_children("*", "HSlider", true, false)[0]
	music.grab_focus()
	await _idle_frames(1)
	var step := InputEventAction.new()
	step.action = &"ui_left"
	step.pressed = true
	Input.parse_input_event(step)
	await _idle_frames(2)
	step.pressed = false
	Input.parse_input_event(step)
	await _idle_frames(1)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(is_equal_approx(float(saved["settings"]["music"]), music.value) and music.value < 0.5,
		"a music slider step is saved while you're still in Settings: %.2f" % music.value)
	m.free()
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = real_path
	Game.autopilot = true


func _test_small_screen_text() -> void:
	check(Game.is_small_screen(Vector2(1280, 800)) and Game.is_small_screen(Vector2(1366, 768))
		and not Game.is_small_screen(Vector2(1920, 1080)) and not Game.is_small_screen(Vector2(3440, 1440)),
		"a Steam Deck or small laptop screen counts as small; 1080p and wider monitors don't")
	var theme := ThemeDB.get_project_theme()
	var sizes := {}
	for type in theme.get_type_list():
		if theme.has_font_size("font_size", type):
			sizes[type] = theme.get_font_size("font_size", type)
	UIStyle.use_small_screen_text()
	var window := get_tree().root.size
	get_tree().root.size = Vector2i(1366, 768)   # 16:9 leaves the least height
	var m: Control = load("res://src/ui/map_screen.tscn").instantiate()
	add_child(m)
	await _idle_frames(3)
	check(m._shop_panel.get_global_rect().end.y <= m._map.get_global_rect().end.y,
		"the shop still fits beside the map with small-screen text")
	var smallest := 999
	for l: Label in m.find_children("*", "Label", true, false):
		if l.is_visible_in_tree() and l.text != "":
			smallest = mini(smallest, l.get_theme_font_size("font_size"))
	check(smallest >= UIStyle.SMALL_SCREEN_TEXT, "on a small screen no map or shop text is under %d: smallest %d" % [UIStyle.SMALL_SCREEN_TEXT, smallest])
	m.free()
	get_tree().root.size = window
	UIStyle.min_text = 0
	for type: StringName in sizes:
		theme.set_font_size("font_size", type, sizes[type])

func _test_shop_fits() -> void:
	var was := Game.run
	var r := Run.new("left", Game.start_node)
	r.completed = Game.map_order().filter(func(id: String) -> bool: return Game.branch[id] != "right" and not Game.is_soon(id))
	r.current_node = r.completed[0]
	r.tokens = 40
	r.upgrades[&"light"] = 3
	Game.run = r
	var window := get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)   # headless starts at 64x64
	var m: Control = load("res://src/ui/map_screen.tscn").instantiate()
	add_child(m)
	await _idle_frames(4)
	var shop: Rect2 = m._shop_panel.get_global_rect()
	var frame: Rect2 = m._map.get_global_rect()
	var screen := get_viewport().get_visible_rect()
	check(m._shop_buttons.size() == 5 and shop.end.y <= frame.end.y and shop.end.x <= screen.end.x - m.MARGIN + 0.5,
		"the shop with all five upgrades ends level with the map (%d / %d) and keeps its margin (%d / %d)" \
		% [shop.end.y, frame.end.y, shop.end.x, screen.end.x - m.MARGIN])
	m.free()
	get_tree().root.size = window
	Game.run = was

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

	# Each checkpoint restart takes 5% off the level score, additively; a full restart clears the count.
	Game.reset_progress()
	Game.new_run("")
	Game.checkpoint_restarts = 3
	var pen := Game.finish_level(start, 0.0, 10.0, 10.0)
	check(int(pen["score"]) == 850 and int(pen["penalty"]) == 150 and int(pen["restarts"]) == 3,
		"three checkpoint restarts score 85%% of a perfect run: %s" % [pen])
	Game.checkpoint_restarts = 0

	# Walking the map moves you; replaying an earlier street from the main menu doesn't.
	Game.reset_progress()
	Game.new_run("")
	Game.finish_level(start, 0.0, 10.0, 10.0)
	var lnb2: String = Game.neighbors(lnb).filter(func(id: String) -> bool: return id != start)[0]
	for id: String in [lnb, lnb2]:
		Game.choose(id)
		Game.finish_level(id, 0.0, 10.0, 10.0)
	check(Game.run.current_node == lnb2, "finishing streets picked on the map walks you to them: %s" % Game.run.current_node)
	Game.finish_level(lnb, 0.0, 10.0, 10.0)
	check(Game.run.current_node == lnb2, "a street replayed from the menu leaves you where you were: %s" % Game.run.current_node)

	# The replay list offers both runs' streets; each replays under the run that walked it.
	Game.reset_progress()
	Game.new_run("left")
	Game.run.completed = [start, lnb]
	Game.run.current_node = lnb
	Game.new_run("right")
	Game.run.completed = [start, rnb]
	check(Game.replay_run(lnb) == Game.runs["left"] and Game.replay_run(rnb) == Game.runs["right"],
		"each side's street replays under its own run, whichever run is active")
	check(Game.replay_run(start) == Game.run and Game.replay_run(lnb2) == null,
		"the start street replays under the active run; an unwalked street isn't offered")
	Game.resume_run(Game.replay_run(lnb).direction)
	Game.finish_level(lnb, 0.0, 10.0, 10.0)
	check(Game.runs["left"].best.has(lnb) and Game.runs["right"].best.is_empty(),
		"a replay scores on its own run and leaves the other alone")
	Game.resume_run("right")
	Game.run.completed = []
	check(Game.replay_run(start) == Game.runs["left"], "the start street stays on offer when only the other run has walked it")

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
	check(right_upg == [0, 1, 0, 0, 0], "undecided run's upgrade commits with it to the right: %s" % [right_upg])
	Game.new_run("left")
	check(upg.call(Game.run) == [0, 0, 0, 0, 0] and Game.run.tokens == 0, "a new left run starts with no upgrades or tokens")
	Game.run.tokens = 20
	Game.buy_upgrade(&"sturdy")
	Game.buy_upgrade(&"light")
	Game.finish_level(start, 0.0, 10.0, 10.0)
	Game.choose(lnb)
	reload.call()
	check(Game.run.direction == "left" and upg.call(Game.run) == [1, 0, 1, 0, 0], "left run keeps its own upgrades: %s" % [upg.call(Game.run)])
	check(upg.call(Game.runs["right"]) == right_upg and Game.runs["right"].tokens == right_tokens,
		"buying and scoring on the left leaves the right run untouched: %s" % [upg.call(Game.runs["right"])])
	Game.resume_run("right")
	Game.run.tokens += 20
	Game.buy_upgrade(&"wide")
	reload.call()
	check(Game.run.direction == "right" and upg.call(Game.run) == [0, 2, 0, 0, 0], "right run upgrades on top of its own: %s" % [upg.call(Game.run)])
	check(upg.call(Game.runs["left"]) == [1, 0, 1, 0, 0], "and the left run still has only its own: %s" % [upg.call(Game.runs["left"])])
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

	# Atomic Avenue opens on the right once Telstar Parade is walked.
	var job := Run.new("right", start)
	job.completed = [start, "arcade_lane", "neon_junction"]
	job.current_node = "neon_junction"
	Game.run = job
	check(Game.branch["atomic_avenue"] == "right" and not Game.is_soon("atomic_avenue") and not Game.can_select("atomic_avenue"),
		"atomic_avenue is built, on the right, and locked before Telstar Parade")
	job.completed.append("telstar_parade")
	job.current_node = "telstar_parade"
	check(Game.can_select("atomic_avenue"), "... and selectable once Telstar Parade is walked")

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	Game.autopilot = true
	Game.runs = {}
	Game.run = Run.new("", start)
