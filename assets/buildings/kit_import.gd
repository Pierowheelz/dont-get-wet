@tool
extends EditorScenePostImport
## Post-import script for the generated kit .glb files (buildings + props).
## Set as `import_script/path` in each .glb.import by tools/blender/configure_imports.py.
##
## 1. Every imported material whose name matches res://assets/materials/<name>.tres is replaced by
##    that shared material (textures are not embedded in the .glb files).
## 2. Marker nodes named omni_* become OmniLight3D children (warm shop spill, lamps, fire...).
##    Lights are added without shadows; gameplay code may tweak or remove them (group "kit_light").
## 3. Kit meshes are put in group "kit_mesh".

const MAT_DIR := "res://assets/materials/"

# name prefix -> [colour, energy, range, attenuation]
const LIGHTS := {
	"omni_warm": [Color(1.0, 0.66, 0.36), 2.4, 7.5, 1.4],
	"omni_lamp": [Color(1.0, 0.72, 0.42), 1.4, 4.5, 1.6],
	"omni_window": [Color(1.0, 0.62, 0.32), 0.7, 3.5, 1.8],
	"omni_sodium": [Color(1.0, 0.56, 0.2), 3.0, 9.0, 1.3],
	"omni_fire": [Color(1.0, 0.42, 0.12), 2.2, 5.5, 1.6],
}

var _cache := {}


func _post_import(scene: Node) -> Object:
	_walk(scene, scene)
	return scene


func _material(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var path := MAT_DIR + name + ".tres"
	var m: Material = null
	if ResourceLoader.exists(path):
		m = load(path)
	_cache[name] = m
	return m


func _walk(n: Node, root: Node) -> void:
	for c in n.get_children():
		_walk(c, root)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.add_to_group(&"kit_mesh", true)
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var cur := mesh.surface_get_material(i)
				if cur == null:
					continue
				var nm := cur.resource_name
				var rep := _material(nm)
				if rep:
					mesh.surface_set_material(i, rep)
	else:
		for key in LIGHTS:
			if String(n.name).begins_with(key):
				var cfg: Array = LIGHTS[key]
				var l := OmniLight3D.new()
				l.name = "Light"
				l.light_color = cfg[0]
				l.light_energy = cfg[1]
				l.omni_range = cfg[2]
				l.omni_attenuation = cfg[3]
				l.shadow_enabled = false
				l.light_bake_mode = Light3D.BAKE_DYNAMIC
				l.add_to_group(&"kit_light", true)
				n.add_child(l)
				l.owner = root
				break
