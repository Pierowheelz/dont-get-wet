class_name Run
extends RefCounted
## One playthrough of the city: where the walker is, the streets he's walked, his tokens and
## umbrella upgrades. Each direction out of the start street is its own run.

const DIRECTIONS := ["left", "right"]
const UPGRADES := [&"sturdy", &"wide", &"light"]

var direction := ""            # "" until the first street off the start, then "left" / "right"
var current_node := ""         # where the player is on the map (last completed / start)
var best: Dictionary = {}      # id -> {score, wet, time, grade}
var tokens := 0
var upgrades := {&"sturdy": 0, &"wide": 0, &"light": 0}
var completed: Array = []


func _init(dir := "", start := "") -> void:
	direction = dir
	current_node = start


func to_dict() -> Dictionary:
	return {"direction": direction, "current_node": current_node, "best": best, "tokens": tokens,
		"upgrades": {"sturdy": upgrades[&"sturdy"], "wide": upgrades[&"wide"], "light": upgrades[&"light"]},
		"completed": completed}


## Parses saved run data, dropping anything that no longer fits the map. Null if the direction is unknown.
static func from_dict(d: Dictionary, nodes: Dictionary, start: String) -> Run:
	var dir: Variant = d.get("direction", "")
	if not dir is String or not (dir == "" or DIRECTIONS.has(dir)):
		return null
	var r := Run.new(dir, start)
	var cn: Variant = d.get("current_node")
	if cn is String and nodes.has(cn):
		r.current_node = cn
	var b: Variant = d.get("best")
	if b is Dictionary:
		for id in b:
			if nodes.has(id) and b[id] is Dictionary:
				r.best[id] = b[id]
	var t: Variant = d.get("tokens")
	if t is float or t is int:
		r.tokens = maxi(0, int(t))
	var u: Variant = d.get("upgrades")
	if u is Dictionary:
		for k in UPGRADES:
			var v: Variant = u.get(String(k), 0)
			r.upgrades[k] = clampi(int(v), 0, 3) if (v is float or v is int) else 0
	var c: Variant = d.get("completed")
	if c is Array:
		r.completed = c.filter(func(e: Variant) -> bool: return e is String and nodes.has(e))
	return r
