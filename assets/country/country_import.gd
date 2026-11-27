@tool
extends EditorScenePostImport
## Post-import script for the country models (docs/CONTRACTS.md §10), set as `import_script/path`
## in each assets/country/*.glb.import by tools/blender/configure_imports.py.
##
## These models are painted in their vertex colours and every material is white. Godot's glTF
## importer turns "vertex colour as albedo" on for some of a mesh's materials and not others, so
## this turns it on for all of them: without it the first surface of each mesh comes out white.


func _post_import(scene: Node) -> Object:
	_walk(scene)
	return scene


func _walk(n: Node) -> void:
	for c in n.get_children():
		_walk(c)
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if m:
			m.vertex_color_use_as_albedo = true
