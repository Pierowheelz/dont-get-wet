@tool
extends "res://assets/buildings/kit_import.gd"
## Post-import script for the generated vehicles (tools/blender/vehicles.py), set as
## `import_script/path` by tools/blender/configure_imports.py. On top of the kit's material swap:
##
## 1. The empties named in LAMPS become lights of the same name, directly under the scene root
##    (docs/CONTRACTS.md §8: the game flashes "Flash" with the beacons).
## 2. Rotor smears, lamps and lit windows cast no shadow.

# name -> [colour, energy, range, attenuation, volumetric fog energy]
const LAMPS := {
	"Flash": [Color(1.0, 0.15, 0.1), 0.0, 12.0, 1.3, 0.6],          # the game sets its energy
	"CockpitGlow": [Color(0.4, 1.0, 0.7), 0.6, 1.5, 1.0, 0.0],
	"BellyLight": [Color(0.75, 0.85, 1.0), 2.0, 12.0, 1.0, 1.2],    # the wash shows in it
}
const NO_SHADOW := ["rotor_blur", "nav_red", "nav_green", "nav_white", "heli_window", "panel_glow"]


func _post_import(scene: Node) -> Object:
	super(scene)
	for lamp: String in LAMPS:
		var marker := scene.get_node_or_null(lamp) as Node3D
		if marker == null:
			continue
		var cfg: Array = LAMPS[lamp]
		var l := OmniLight3D.new()
		l.transform = marker.transform
		l.light_color = cfg[0]
		l.light_energy = cfg[1]
		l.omni_range = cfg[2]
		l.omni_attenuation = cfg[3]
		l.light_volumetric_fog_energy = cfg[4]
		l.shadow_enabled = false
		scene.remove_child(marker)
		marker.free()
		l.name = lamp
		scene.add_child(l)
		l.owner = scene
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var only_glow := mi.mesh != null and mi.mesh.get_surface_count() > 0
		for i in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var m := mi.mesh.surface_get_material(i)
			only_glow = only_glow and m != null and NO_SHADOW.has(m.resource_name)
		if only_glow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return scene
