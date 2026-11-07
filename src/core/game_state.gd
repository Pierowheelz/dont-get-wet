extends Node
## Persistent progression (scores, tokens, upgrades, map position) and scene flow.

const SAVE_PATH := "user://save.json"
const INDEX_PATH := "res://levels/index.json"
const UPGRADES := [&"sturdy", &"wide", &"light"]

signal tokens_changed(tokens: int)

var nodes: Dictionary = {}          # id -> node dict from levels/index.json
var start_node := ""
var current_node := ""              # where the player is on the map (last completed / start)
var current_level := ""             # level being played
var best: Dictionary = {}           # id -> {score, wet, time, grade}
var tokens := 0
var upgrades := {&"sturdy": 0, &"wide": 0, &"light": 0}
var completed: Array = []
var autopilot := false              # bot plays (testing)
var debug_start_x := -1.0           # --start-x=NN spawns the player further along (testing)
var debug_lazy := false             # --lazy: autopilot never opens the umbrella (testing defeat)
var trace_path := ""                # --trace=PATH: autopilot writes a JSON-lines run trace
var debug_human := false            # --human: autopilot with reaction delay & sloppier timing
var debug_auto_continue := false    # --auto-continue: result screen presses Continue (testing)
var debug_start_wet := 0.0          # --wet=NN starts the level already damp (testing)
var last_result: Dictionary = {}
var settings := {"painterly": true, "music": 0.7, "sfx": 1.0, "touch_controls": false, "low_quality": false}


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
		if a.begins_with("--upgrades="):   # testing: set every upgrade tier
			for k in UPGRADES:
				upgrades[k] = clampi(int(a.substr(11)), 0, 3)
		if a.begins_with("--wet="):
			debug_start_wet = float(a.substr(6))
		if a.begins_with("--shots="):
			for t in a.substr(8).split(","):
				_shots.append(float(t))
		if a.begins_with("--shot-dir="):
			_shot_dir = a.substr(11)
	load_game()   # after args: the autopilot must never read or write the player's save
	if current_level != "":
		get_tree().process_frame.connect(_jump_to_level, CONNECT_ONE_SHOT)


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


func can_select(id: String) -> bool:
	if not completed.has(current_node):
		return id == current_node     # finish where you are before moving on
	return id == current_node or neighbors(current_node).has(id)


# --- upgrades -----------------------------------------------------------------

func upgrade_level(u: StringName) -> int:
	return int(upgrades.get(u, 0))


func upgrade_cost(u: StringName) -> int:
	var lvl := upgrade_level(u)
	var costs := Tun.arr("upgrade_costs")
	return int(costs[lvl]) if lvl < costs.size() else -1


func buy_upgrade(u: StringName) -> bool:
	var c := upgrade_cost(u)
	if c < 0 or tokens < c:
		return false
	tokens -= c
	upgrades[u] = upgrade_level(u) + 1
	tokens_changed.emit(tokens)
	save_game()
	return true


func umbrella_drain_mult() -> float:
	return float(Tun.arr("upgrade_sturdy_drain_mult")[upgrade_level(&"sturdy")])


func umbrella_radius() -> float:
	return Tun.f("umbrella_radius") + float(Tun.arr("upgrade_wide_radius_add")[upgrade_level(&"wide")])


func umbrella_open_time() -> float:
	return Tun.f("umbrella_open_time") * float(Tun.arr("upgrade_light_time_mult")[upgrade_level(&"light")])


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
	var prev: Dictionary = best.get(id, {})
	var prev_score: int = int(prev.get("score", 0))
	# Tokens scale with score, paid only for improving on your best score for this street.
	var k := Tun.f("tokens_per_point")
	var earned := maxi(0, int(floor(score * k)) - int(floor(prev_score * k)))
	tokens += earned
	var is_best := score > prev_score
	if is_best:
		best[id] = {"score": score, "wet": wet_pct, "time": time, "grade": grade_for(score)}
	if not completed.has(id):
		completed.append(id)
	current_node = id
	last_result = {"id": id, "score": score, "wet": wet_pct, "time": time, "par": par,
		"grade": grade_for(score), "tokens": earned, "best": is_best, "prev_score": prev_score}
	save_game()
	tokens_changed.emit(tokens)
	return last_result


# --- persistence --------------------------------------------------------------

func save_game() -> void:
	if autopilot:
		return
	var d := {"current_node": current_node, "best": best, "tokens": tokens,
		"upgrades": {"sturdy": upgrades[&"sturdy"], "wide": upgrades[&"wide"], "light": upgrades[&"light"]},
		"completed": completed, "settings": settings}
	# Write to a temp file then swap it in, so a crash mid-write can't corrupt the save.
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("save: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))


func load_game() -> void:
	current_node = start_node
	if autopilot or not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if not d is Dictionary:
		# Keep the unreadable file for recovery instead of silently overwriting it.
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".bak"))
		push_warning("save: unreadable save backed up to save.json.bak")
		return
	var cn: Variant = d.get("current_node")
	if cn is String and nodes.has(cn):
		current_node = cn
	var b: Variant = d.get("best")
	if b is Dictionary:
		for id in b:
			if nodes.has(id) and b[id] is Dictionary:
				best[id] = b[id]
	var t: Variant = d.get("tokens")
	if t is float or t is int:
		tokens = maxi(0, int(t))
	var u: Variant = d.get("upgrades")
	if u is Dictionary:
		for k in UPGRADES:
			var v: Variant = u.get(String(k), 0)
			upgrades[k] = clampi(int(v), 0, 3) if (v is float or v is int) else 0
	var c: Variant = d.get("completed")
	if c is Array:
		completed = c.filter(func(e: Variant) -> bool: return e is String and nodes.has(e))
	var st: Variant = d.get("settings")
	if st is Dictionary:
		for k in settings:
			if st.has(k) and typeof(st[k]) == typeof(settings[k]):
				settings[k] = st[k]


func reset_progress() -> void:
	current_node = start_node
	best = {}
	tokens = 0
	upgrades = {&"sturdy": 0, &"wide": 0, &"light": 0}
	completed = []
	save_game()


# --- scene flow ---------------------------------------------------------------

func play_level(id: String) -> void:
	if _building:
		return
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
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/map_screen.tscn")


func goto_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
