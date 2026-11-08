extends Node
## Persistent progression (settings and one run per direction) and scene flow.

const SAVE_VERSION := 2
const FEEDBACK_URL := "https://github.com/Pierowheelz/dont-get-wet/issues/new?template=feedback.yml"
const INDEX_PATH := "res://levels/index.json"

signal tokens_changed(tokens: int)

var nodes: Dictionary = {}          # id -> node dict from levels/index.json
var start_node := ""
var branch: Dictionary = {}         # id -> "" (the start node) / "left" / "right"
var runs: Dictionary = {}           # direction ("" while undecided) -> Run, every run in the save
var run: Run                        # the active run; a fresh unsaved one when there are no runs
var current_level := ""             # level being played
var save_path := "user://save.json"
var autopilot := false              # bot plays (testing)
var debug_start_x := -1.0           # --start-x=NN spawns the player further along (testing)
var debug_lazy := false             # --lazy: autopilot never opens the umbrella (testing defeat)
var trace_path := ""                # --trace=PATH: autopilot writes a JSON-lines run trace
var debug_human := false            # --human: autopilot with reaction delay & sloppier timing
var debug_auto_continue := false    # --auto-continue: result screen presses Continue (testing)
var debug_confirm_upgrade := &""    # --confirm-upgrade=light opens the map with that buy prompt up (testing)
var debug_tilt := NAN              # --tilt=-1..1 holds the umbrella open at that tilt (testing)
var debug_start_wet := 0.0          # --wet=NN starts the level already damp (testing)
var debug_resume_cp := -1          # --resume-checkpoint=N starts the level resumed from its checkpoint N (testing; --wet= sets the wetness)
var last_result: Dictionary = {}
var checkpoint: Dictionary = {}     # latest checkpoint of the level being played (Level._take_checkpoint); memory only, never saved
var resuming := false               # play_level(id, true) asked the next Level to restore `checkpoint`
var settings := {"painterly": true, "music": 0.7, "sfx": 1.0, "touch_controls": false, "low_quality": false, "fullscreen": true}


func _ready() -> void:
	_load_index()
	var args := OS.get_cmdline_user_args()
	_fps_log = args.has("--fps-log")
	autopilot = args.has("--autopilot")
	debug_lazy = args.has("--lazy")
	debug_human = args.has("--human")
	debug_auto_continue = args.has("--auto-continue")
	if args.has("--low"):
		settings["low_quality"] = true
	for a in args:
		if a.begins_with("--trace="):
			trace_path = a.substr(8)
		if a.begins_with("--level="):
			current_level = a.substr(8)
		if a.begins_with("--start-x="):
			debug_start_x = float(a.substr(10))
		if a.begins_with("--save="):
			save_path = a.substr(7)
		if a.begins_with("--confirm-upgrade="):
			debug_confirm_upgrade = StringName(a.substr(18))
		if a.begins_with("--tilt="):
			debug_tilt = float(a.substr(7))
		if a.begins_with("--resume-checkpoint="):
			debug_resume_cp = int(a.substr(20))
		if a.begins_with("--wet="):
			debug_start_wet = float(a.substr(6))
		if a.begins_with("--shots="):
			for t in a.substr(8).split(","):
				_shots.append(float(t))
		if a.begins_with("--shot-dir="):
			_shot_dir = a.substr(11)
		if a.begins_with("--profile="):
			add_child(preload("res://src/core/perf_probe.gd").new())
	load_game()   # after args: the autopilot must never read or write the player's save
	# Exported builds follow the setting; editor runs (screenshots, bots) stay windowed.
	if OS.has_feature("template"):
		apply_fullscreen(bool(settings["fullscreen"]))
	for a in args:
		if a.begins_with("--upgrades="):   # testing: set every upgrade tier
			for k in Run.UPGRADES:
				run.upgrades[k] = clampi(int(a.substr(11)), 0, 3)
	if current_level != "":
		get_tree().process_frame.connect(_jump_to_level, CONNECT_ONE_SHOT)


func apply_fullscreen(on: bool) -> void:
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# KDE keeps its panel above a fullscreen window that isn't focused (e.g. after focus-stealing
		# prevention on launch).
		DisplayServer.window_move_to_foreground()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Leaving fullscreen, the window manager keeps it screen-sized (KDE reports it maximized), so
	# give it a real window.
	var screen := DisplayServer.screen_get_usable_rect()
	var size := Vector2i(Vector2(screen.size) * 0.75)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## `--level=ID` launches straight into a level (exported builds can't override the main scene).
func _jump_to_level() -> void:
	var cs := get_tree().current_scene
	if cs and cs.scene_file_path == "res://src/ui/main_menu.tscn":
		play_level(current_level)


# --- debug screenshots: --shots=1.0,2.5 --shot-dir=/abs/path (quits after the last) ----------

var _shots: Array = []
var _shot_dir := ""
var _shot_t := 0.0
var _shot_i := 0


var _fps_t := 0.0
var _fps_log := false


func _process(delta: float) -> void:
	if _fps_log and delta > 0.05:
		var lvl := get_tree().current_scene
		var px: float = lvl.player.position.x if lvl and lvl.get("player") else -1.0
		print("HITCH %.0f ms at t=%.1f x=%.1f" % [delta * 1000.0, Time.get_ticks_msec() / 1000.0, px])
	if _fps_log:
		_fps_t += delta
		if _fps_t > 2.0:
			_fps_t = 0.0
			print("FPS %d  draw_calls %d  objects %d  vram %.0fMB" % [Engine.get_frames_per_second(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	if _shots.is_empty():
		return
	_shot_t += delta
	if _shot_i < _shots.size() and _shot_t >= float(_shots[_shot_i]):
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%02d.png" % [_shot_dir, _shot_i])
		_shot_i += 1
		if _shot_i >= _shots.size():
			get_tree().quit()


func _load_index() -> void:
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null:
		push_error("missing %s" % INDEX_PATH)
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	start_node = d.get("start", "")
	for n in d.get("nodes", []):
		nodes[n["id"]] = n
	branch = derive_branches(nodes, start_node)


## Which side of the start each node lies on: the start's neighbour it's reached through, labelled
## left/right by that neighbour's map x against the start's.
static func derive_branches(graph: Dictionary, start: String) -> Dictionary:
	var out := {start: ""}
	if not graph.has(start):
		return out
	var sx := float(graph[start]["map_pos"][0])
	var queue: Array = []
	for nb: String in graph[start].get("neighbors", []):
		if graph.has(nb) and not out.has(nb):
			out[nb] = "left" if float(graph[nb]["map_pos"][0]) < sx else "right"
			queue.append(nb)
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for nb: String in graph[id].get("neighbors", []):
			if graph.has(nb) and not out.has(nb):
				out[nb] = out[id]
				queue.append(nb)
	return out


func level_data(id: String) -> Dictionary:
	var node: Dictionary = nodes.get(id, {})
	var path: String = node.get("file", "res://levels/%s.json" % id)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing level file %s" % path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func neighbors(id: String) -> Array:
	return nodes.get(id, {}).get("neighbors", [])


## True for a street on the other side of the start from the active run's direction.
func other_way(id: String) -> bool:
	var side: String = branch.get(id, "")
	return run.direction != "" and side != "" and side != run.direction


## A street on the map that isn't built yet: shown, never playable.
func is_soon(id: String) -> bool:
	return bool(nodes.get(id, {}).get("soon", false))


func can_select(id: String) -> bool:
	if other_way(id) or is_soon(id):
		return false
	if not run.completed.has(run.current_node):
		return id == run.current_node     # finish where you are before moving on
	return id == run.current_node or neighbors(run.current_node).has(id)


## Streets a run can walk now: the start plus its direction's built side (all of them while undecided).
func reachable_count(r: Run) -> int:
	return nodes.keys().filter(func(id: String) -> bool:
		return not is_soon(id) and (r.direction == "" or branch.get(id, "") in ["", r.direction])).size()


## Every street in walking order along the map: the left side from its far end, the start, then the
## right side outward. Each side is a chain, so walking it from the start's neighbour gives its order.
func map_order() -> Array:
	var out: Array = []
	for nb: String in neighbors(start_node):
		var chain: Array = []
		var prev := start_node
		var id := nb
		while id != "":
			chain.append(id)
			var next := ""
			for n: String in neighbors(id):
				if n != prev and nodes.has(n) and not chain.has(n):
					next = n
			prev = id
			id = next
		if branch.get(nb, "") == "left":
			chain.reverse()
			out = chain + [start_node] + out
		else:
			out.append_array(chain)
	if not out.has(start_node):
		out.push_front(start_node)
	return out


# --- runs ---------------------------------------------------------------------

## Starts a fresh run in `dir` ("" = undecided), replacing any saved run there, and makes it active.
func new_run(dir: String) -> void:
	run = Run.new(dir, start_node)
	runs[dir] = run
	save_game()


func resume_run(dir: String) -> void:
	run = runs[dir]
	save_game()


## The player picked a street on the map: an undecided run commits to that street's side.
func choose(id: String) -> void:
	var side: String = branch.get(id, "")
	if run.direction != "" or side == "":
		return
	runs.erase("")
	run.direction = side
	runs[side] = run
	save_game()


# --- upgrades -----------------------------------------------------------------

func upgrade_level(u: StringName) -> int:
	return int(run.upgrades.get(u, 0))


func upgrade_cost(u: StringName) -> int:
	var lvl := upgrade_level(u)
	var costs := Tun.arr("upgrade_costs")
	return int(costs[lvl]) if lvl < costs.size() else -1


func buy_upgrade(u: StringName) -> bool:
	var c := upgrade_cost(u)
	if c < 0 or run.tokens < c:
		return false
	run.tokens -= c
	run.upgrades[u] = upgrade_level(u) + 1
	tokens_changed.emit(run.tokens)
	save_game()
	return true


## Each takes an upgrade level (default: the current one) so the shop can preview the next tier.
func umbrella_drain_mult(level := -1) -> float:
	return float(Tun.arr("upgrade_sturdy_drain_mult")[_lvl(&"sturdy", level)])


func umbrella_radius(level := -1) -> float:
	return Tun.f("umbrella_radius") + float(Tun.arr("upgrade_wide_radius_add")[_lvl(&"wide", level)])


func umbrella_open_time(level := -1) -> float:
	return Tun.f("umbrella_open_time") * float(Tun.arr("upgrade_light_time_mult")[_lvl(&"light", level)])


func _lvl(u: StringName, level: int) -> int:
	return upgrade_level(u) if level < 0 else level


# --- scoring ------------------------------------------------------------------

static func grade_for(score: int) -> String:
	if score >= 950: return "S"
	if score >= 880: return "A"
	if score >= 780: return "B"
	if score >= 650: return "C"
	return "D"


## Returns the result dictionary, updates bests and tokens.
func finish_level(id: String, wetness: float, time: float, par: float) -> Dictionary:
	var wet_pct := clampf(wetness / Tun.f("wet_max") * 100.0, 0.0, 100.0)   # stored/displayed as %
	var dry := 1.0 - wet_pct / 100.0
	var time_ratio := clampf(par / maxf(time, 0.01), 0.0, 1.0)
	var score := int(round(Tun.f("score_dry_weight") * dry + Tun.f("score_time_weight") * time_ratio))
	var prev: Dictionary = run.best.get(id, {})
	var prev_score: int = int(prev.get("score", 0))
	# Tokens scale with score, paid only for improving on your best score for this street.
	var k := Tun.f("tokens_per_point")
	var earned := maxi(0, int(floor(score * k)) - int(floor(prev_score * k)))
	run.tokens += earned
	var is_best := score > prev_score
	if is_best:
		run.best[id] = {"score": score, "wet": wet_pct, "time": time, "grade": grade_for(score)}
	if not run.completed.has(id):
		run.completed.append(id)
	run.current_node = id
	checkpoint = {}
	last_result = {"id": id, "score": score, "wet": wet_pct, "time": time, "par": par,
		"grade": grade_for(score), "tokens": earned, "best": is_best, "prev_score": prev_score}
	save_game()
	tokens_changed.emit(run.tokens)
	return last_result


# --- persistence --------------------------------------------------------------

func save_game() -> void:
	if autopilot:
		return
	var d := {"version": SAVE_VERSION, "settings": settings, "active": run.direction,
		"runs": runs.values().map(func(r: Run) -> Dictionary: return r.to_dict())}
	# Write to a temp file then swap it in, so a crash mid-write can't corrupt the save.
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("save: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path))


func load_game() -> void:
	runs = {}
	run = Run.new("", start_node)
	if autopilot or not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if not d is Dictionary:
		# Keep the unreadable file for recovery instead of silently overwriting it.
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bak"))
		push_warning("save: unreadable save backed up to %s.bak" % save_path.get_file())
		return
	var st: Variant = d.get("settings")
	if st is Dictionary:
		for k in settings:
			if st.has(k) and typeof(st[k]) == typeof(settings[k]):
				settings[k] = st[k]
	var saved: Variant = d.get("runs") if d.has("version") else _legacy_runs(d)
	for rd: Variant in (saved if saved is Array else []):
		var r: Run = Run.from_dict(rd, nodes, start_node) if rd is Dictionary else null
		if r != null and not runs.has(r.direction):
			runs[r.direction] = r
	if runs.size() > 1:
		runs.erase("")    # an undecided run only exists before any direction does
	var active: Variant = d.get("active", "")
	if active is String and runs.has(active):
		run = runs[active]
	elif not runs.is_empty():
		run = runs.values()[0]


## The pre-runs save held one run's fields at the top level; it becomes the run for the side it was on.
func _legacy_runs(d: Dictionary) -> Array:
	var walked: Variant = d.get("completed")
	if not walked is Array or walked.is_empty():
		return []
	var r := d.duplicate()
	r["direction"] = legacy_side(str(d.get("current_node", "")), walked, branch)
	return [r]


## The side an old single-run save played on: current_node's side, else the side with more walked
## streets (right on a tie), else undecided.
static func legacy_side(current: String, walked: Array, sides: Dictionary) -> String:
	if sides.get(current, "") != "":
		return sides[current]
	var left := walked.filter(func(id: Variant) -> bool: return sides.get(id, "") == "left").size()
	var right := walked.filter(func(id: Variant) -> bool: return sides.get(id, "") == "right").size()
	if left + right == 0:
		return ""
	return "left" if left > right else "right"


func reset_progress() -> void:
	runs = {}
	run = Run.new("", start_node)
	save_game()


# --- scene flow ---------------------------------------------------------------

## Loads a level. With `from_checkpoint` it keeps `checkpoint` for the new Level to restore; any other
## way in (restart, the map, the menu) starts the street over and forgets it.
func play_level(id: String, from_checkpoint := false) -> void:
	if _building:
		return
	resuming = from_checkpoint and checkpoint.get("id", "") == id
	if not resuming:
		checkpoint = {}
	_building = true
	# Closing the window mid-build must wait: shutting the engine down under the build / loader
	# threads crashes or deadlocks it. _notification defers the quit until they finish.
	get_tree().auto_accept_quit = false
	current_level = id
	_show_loading(String(nodes.get(id, {}).get("name", "")))
	# Freeze whatever is behind the card (e.g. the level being restarted) while we build.
	get_tree().paused = true
	await get_tree().process_frame
	# Build the street on a worker thread (off-tree node construction is thread-safe) so the
	# loading card keeps animating; the level picks the finished world up in its _ready.
	Tun.reload()
	var data := level_data(id)
	var world := Node3D.new()
	world.name = "World"
	var builder := LevelBuilder.new()
	var scenes := _level_scenes()
	for path in scenes:
		ResourceLoader.load_threaded_request(path)
	var fps_was := Engine.max_fps
	Engine.max_fps = LOADING_FPS     # leave the build thread the renderer most of the time
	var task := WorkerThreadPool.add_task(builder.build.bind(world, data), true, "build level")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	Engine.max_fps = fps_was
	# Character scenes loaded on loader threads meanwhile; hold them until the level has used
	# them (its load() calls hit the cache instead of blocking).
	_held = []
	for path in scenes:
		_held.append(ResourceLoader.load_threaded_get(path))
	var scene := _held[0] as PackedScene     # level.tscn is first in _level_scenes()
	get_tree().auto_accept_quit = true
	if _quit_pending:
		_held = []
		world.free()
		get_tree().quit()
		return
	prebuilt = {"id": id, "data": data, "world": world, "builder": builder}
	get_tree().paused = false
	_building = false
	get_tree().change_scene_to_packed(scene)


## A street built in the background by play_level, consumed by Level._ready.
var prebuilt := {}
var _held: Array = []
const LOADING_FPS := 20
var _building := false
var _quit_pending := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _building:
		_quit_pending = true      # play_level quits once the background build is done
var _loading: CanvasLayer


## A black card with the street name, shown while a level builds; the level's HUD fades in over it.
func _show_loading(street: String) -> void:
	if _loading == null:
		_loading = CanvasLayer.new()
		_loading.layer = 100
		_loading.process_mode = Node.PROCESS_MODE_ALWAYS
		var bg := ColorRect.new()
		bg.name = "ColorRect"
		bg.color = Color(0.02, 0.022, 0.03)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading.add_child(bg)
		var lbl := Label.new()
		lbl.name = "Label"
		lbl.set_anchors_preset(Control.PRESET_CENTER)
		lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 40)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82, 0.85))
		bg.add_child(lbl)
		# The little walker from the map, strolling along above the street name.
		var walker := preload("res://src/ui/loading_walker.gd").new()
		walker.name = "Walker"
		walker.set_anchors_preset(Control.PRESET_CENTER)
		walker.position.y -= 70.0
		bg.add_child(walker)
		add_child(_loading)
	(_loading.get_node("ColorRect/Label") as Label).text = ("Walking to %s…" % street) if street != "" else "Loading…"
	_loading.visible = true


func hide_loading() -> void:
	if _loading:
		_loading.visible = false
	_held = []


## Scenes a level needs at startup: loaded on threads by play_level while the street builds.
func _level_scenes() -> PackedStringArray:
	var out := PackedStringArray(["res://src/level/level.tscn", Player.CHARACTER_SCENE])
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/pedestrians/peds.json"))
	if d is Array:
		for p in d:
			if ResourceLoader.exists(String(p.get("scene", ""))):
				out.append(String(p["scene"]))
	return out


func goto_map() -> void:
	checkpoint = {}
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/map_screen.tscn")


## The feedback issue form, with the game version prefilled into its `version` field.
func feedback_url() -> String:
	return FEEDBACK_URL + "&version=" + String(ProjectSettings.get_setting("application/config/version", "")).uri_encode()


## Returns what the button should say: with no browser (Steam Deck Game Mode) the link is copied instead.
func open_feedback() -> String:
	if OS.shell_open(feedback_url()) == OK:
		return "Opened in browser"
	DisplayServer.clipboard_set(feedback_url())
	return "Link copied"


func goto_menu() -> void:
	checkpoint = {}
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
