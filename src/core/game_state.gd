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
var debug_human := false            # --human: autopilot with reaction delay & sloppier timing
var debug_start_wet := 0.0          # --wet=NN starts the level already damp (testing)
var last_result: Dictionary = {}
var settings := {"painterly": true, "music": 0.7, "sfx": 1.0, "touch_controls": false}


func _ready() -> void:
	_load_index()
	load_game()
	var args := OS.get_cmdline_user_args()
	autopilot = args.has("--autopilot")
	debug_lazy = args.has("--lazy")
	debug_human = args.has("--human")
	for a in args:
		if a.begins_with("--level="):
			current_level = a.substr(8)
		if a.begins_with("--start-x="):
			debug_start_x = float(a.substr(10))
		if a.begins_with("--wet="):
			debug_start_wet = float(a.substr(6))
		if a.begins_with("--shots="):
			for t in a.substr(8).split(","):
				_shots.append(float(t))
		if a.begins_with("--shot-dir="):
			_shot_dir = a.substr(11)


# --- debug screenshots: --shots=1.0,2.5 --shot-dir=/abs/path (quits after the last) ----------

var _shots: Array = []
var _shot_dir := ""
var _shot_t := 0.0
var _shot_i := 0


var _fps_t := 0.0


func _process(delta: float) -> void:
	if OS.get_cmdline_user_args().has("--fps-log"):
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
	if score >= 900: return "S"
	if score >= 750: return "A"
	if score >= 500: return "B"
	return "C"


## Returns the result dictionary, updates bests and tokens.
func finish_level(id: String, wetness: float, time: float, par: float) -> Dictionary:
	var dry := clampf(1.0 - wetness / Tun.f("wet_max"), 0.0, 1.0)
	var time_ratio := clampf(par / maxf(time, 0.01), 0.0, 1.0)
	var score := int(round(Tun.f("score_dry_weight") * dry + Tun.f("score_time_weight") * time_ratio))
	var prev: Dictionary = best.get(id, {})
	var prev_score: int = int(prev.get("score", 0))
	var earned := maxi(0, score / 100 - prev_score / 100)
	tokens += earned
	var is_best := score > prev_score
	if is_best:
		best[id] = {"score": score, "wet": wetness, "time": time, "grade": grade_for(score)}
	if not completed.has(id):
		completed.append(id)
	current_node = id
	last_result = {"id": id, "score": score, "wet": wetness, "time": time, "par": par,
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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "  "))


func load_game() -> void:
	current_node = start_node
	if autopilot or not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	current_node = d.get("current_node", start_node)
	if not nodes.has(current_node):
		current_node = start_node
	best = d.get("best", {})
	tokens = int(d.get("tokens", 0))
	var u: Dictionary = d.get("upgrades", {})
	for k in UPGRADES:
		upgrades[k] = int(u.get(String(k), 0))
	completed = d.get("completed", [])
	settings.merge(d.get("settings", {}), true)


func reset_progress() -> void:
	current_node = start_node
	best = {}
	tokens = 0
	upgrades = {&"sturdy": 0, &"wide": 0, &"light": 0}
	completed = []
	save_game()


# --- scene flow ---------------------------------------------------------------

func play_level(id: String) -> void:
	current_level = id
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/level/level.tscn")


func goto_map() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/map_screen.tscn")


func goto_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
