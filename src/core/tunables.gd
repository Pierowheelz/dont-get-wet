extends Node
## Global gameplay tunables, loaded from res://data/tunables.json.
## Access with Tun.f("walk_speed") or Tun.arr("upgrade_costs").

const PATH := "res://data/tunables.json"
var values: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("tunables: cannot open %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		values = parsed
	else:
		push_error("tunables: invalid JSON")


func f(key: String) -> float:
	if not values.has(key):
		push_error("tunables: missing key '%s'" % key)
		return 0.0
	return float(values[key])


func arr(key: String) -> Array:
	return values.get(key, [])
