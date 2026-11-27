class_name TreeCover
extends RefCounted
## A tree's crown over a lot with `cover: "trees"`, on any street. A crown is partial cover: it keeps
## off all but `tree_leak` (tunable) of the rain, so a walker under it with the umbrella shut gets a
## little wet, and the open umbrella keeps all of it off.
##
## Gameplay (the same whatever the street looks like):
##   - a box on physics layer 6 `trees` (LAYER) over the lot, from UNDERSIDE to TOP and Z0 to Z1:
##     Player._rain_exposure lets tree_leak of the rain through to a body sample whose ray to the sky
##     only this stops;
##   - the rain's cover map (cover_map, called by LevelBuilder.cover_map for every such lot): only
##     tree_leak of the drops fall on through the crown, out to the camera as under a deck;
##   - drips falling from the leaves all over the ground beneath (node group &"tree_drips").
## The look is the caller's: build() draws a crown in code, or places a model, or draws nothing and
## leaves it to the lot's style. Every leafy node is in the group &"foliage" with its own material on
## src/fx/foliage.gdshader, whose `gust` and `gust_dir` the squalls drive, and has metas "x0" / "x1",
## the street x it spans.
## Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const LAYER := 1 << 5          # physics layer 6, `trees`
const UNDERSIDE := 3.6         # the crown's collider: underside over the walker's lane (an open umbrella tops out near 2.5)
const TOP := 8.0
const Z0 := -1.5
const Z1 := 3.7                # to about the edge of the road
const SPAN := 11.0             # a code crown or a model every this much of the lot
const FOLIAGE_GROUP := &"foliage"
const DRIPS_GROUP := &"tree_drips"
const COUNTRY_MODELS := "res://assets/country/%s.glb"
const LEAF_DARK := Color(0.07, 0.12, 0.05)
const LEAF_LIGHT := Color(0.3, 0.38, 0.13)


## Puts a tree's crown over the lot from x to x + w: its collider, drips and, by `look`, what it looks
## like. Returns the node holding them (added to the street). `look`:
##   "crown": false       gameplay only: draw nothing (the caller draws its own tree around it)
##   "models": [names]    a model per SPAN of the lot, picked by a hash of its x: a name is
##                        res://assets/country/<name>.glb, or give a full res:// path; scaled along x
##                        to its share of the lot; materials named for leaves become the foliage shader
##   "leaf_dark", "leaf_light": Color   the code crown's greens (else LEAF_DARK / LEAF_LIGHT)
##   "trunk": false       the code crown without its trunk and limbs
## With no model (or a missing file) it draws a broadleaf in code: a short trunk in the lot line,
## limbs out over the path and a crown of leaf clumps from z -3 to about Z1, its underside well above
## UNDERSIDE over the path. LevelBuilder calls build() itself for a `cover: "trees"` lot whose style
## didn't, so such a lot is never without its crown.
static func build(b: LevelBuilder, x: float, w: float, look: Dictionary = {}) -> Node3D:
	var node := Node3D.new()
	node.name = "Tree_%d" % roundi(x * 10.0)
	node.set_meta("x0", x)
	node.set_meta("x1", x + w)
	b.root.add_child(node)
	b.tree_covers[snappedf(x, 0.01)] = node
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, TOP - UNDERSIDE, Z1 - Z0)
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(x + w * 0.5, (UNDERSIDE + TOP) * 0.5, (Z0 + Z1) * 0.5)
	node.add_child(body)
	drips(node, x, w)
	if not bool(look.get("crown", true)):
		return node
	var n := maxi(1, roundi(w / SPAN))
	var span := w / n
	var models: Array = look.get("models", [])
	for i in n:
		var tx := x + span * (i + 0.5)
		var seed := b._lot_hash(tx, "tree")
		var m: Node3D = null
		if not models.is_empty():
			m = model(b, String(models[seed % models.size()]), Vector3(tx, 0.0, -0.2), node)
		if m:
			m.scale.x = clampf(span / 10.0, 0.75, 1.35)
			tag_foliage(m, tx - span * 0.5, tx + span * 0.5)
		else:
			_broadleaf(b, node, tx, span, seed, look)
	return node


## The rain's cover map over a tree lot: LevelBuilder.COVER_TREE from the back of the map out to the
## camera, its R the crown's underside, below which only tree_leak of the drops carry on.
static func cover_map(b: LevelBuilder, img: Image, x0: float, x: float, w: float) -> void:
	b._cover_fill(img, x0, x, x + w, LevelBuilder.COVER_Z0, LevelBuilder.COVER_Z1, func(_z): return UNDERSIDE, LevelBuilder.COVER_TREE)


## Drips falling from the leaves all over the ground beneath the crown, heavier than the rain that
## gets through.
static func drips(parent: Node3D, x: float, w: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(8, int(w * 9.0))
	p.lifetime = 0.9
	p.randomness = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.5, 0.1, (Z1 - 0.2) * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.022, 0.14)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.72, 0.8, 0.9, 0.5)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mesh.material = dm
	p.draw_pass_1 = mesh
	p.position = Vector3(x + w * 0.5, UNDERSIDE + 0.1, (Z1 - 0.2) * 0.5)
	p.visibility_aabb = AABB(Vector3(-w * 0.5 - 0.5, -UNDERSIDE - 0.5, -Z1), Vector3(w + 1.0, UNDERSIDE + 1.0, Z1 * 2.0))
	p.add_to_group(DRIPS_GROUP)
	parent.add_child(p)
	return p


## A broadleaf grown from the lot line: a short trunk that leans and kinks, limbs spreading along the
## street, out over the path and up, and a crown in three parts: a high ceiling of clumps over the
## path, lower ones behind the trunk, and the bulk above.
static func _broadleaf(b: LevelBuilder, parent: Node3D, tx: float, span: float, seed: int, look: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var half := span * 0.5
	if bool(look.get("trunk", true)):
		var sts := {}
		var bark := b._mat("bark", Color(0.2, 0.18, 0.15), 0.9)
		var lean := r.randf_range(-0.35, 0.35)
		var pts := [Vector3(tx, -0.1, -0.35), Vector3(tx + lean * 0.3, 1.3, -0.3), Vector3(tx + lean * 0.8, 2.7, -0.2),
			Vector3(tx + lean, 3.7, -0.1)]
		var radii := [0.62, 0.42, 0.38, 0.33]
		for i in pts.size() - 1:
			ModernBuilder.cyl(sts, bark, pts[i], pts[i + 1] + Vector3(0, 0.05, 0), radii[i], radii[i + 1], 12)
		for k in 4:   # root flare
			var ang := TAU * k / 4.0 + 0.4
			ModernBuilder.cyl(sts, bark, pts[0] + Vector3(0, 0.6, 0), pts[0] + Vector3(cos(ang) * 0.9, 0.05, sin(ang) * 0.5), 0.28, 0.08, 7)
		var fork: Vector3 = pts[-1]
		var limbs := [Vector3(tx - half * 0.62, 5.6, -1.2), Vector3(tx + half * 0.66, 5.4, -0.6),
			Vector3(tx + r.randf_range(-0.8, 0.8), 5.3, 2.7), Vector3(tx + r.randf_range(-1.2, 1.2), 7.8, -0.8),
			Vector3(tx - half * 0.3, 6.6, -2.2)]
		for l: Vector3 in limbs:
			var mid := fork.lerp(l, 0.45) + Vector3(0, 0.45, 0)
			ModernBuilder.cyl(sts, bark, fork, mid, 0.27, 0.18, 9)
			ModernBuilder.cyl(sts, bark, mid, l, 0.18, 0.07, 7)
			for k in 2:
				var tip := l + Vector3(r.randf_range(-1.6, 1.6), r.randf_range(0.3, 1.4), r.randf_range(-0.9, 0.9))
				if tip.z > 0.4:
					tip.y = maxf(tip.y, UNDERSIDE + 0.8)
				ModernBuilder.cyl(sts, bark, mid.lerp(l, 0.6), tip, 0.09, 0.03, 5)
		commit(sts, parent)
	var o := Vector3(tx, 0.0, 0.0)
	var pivot := Vector3(tx, 6.2, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in int(span * 0.9):   # over the path, their undersides above UNDERSIDE
		var rad := r.randf_range(0.9, 1.4)
		var px := tx + (r.randf() * 2.0 - 1.0) * half * 0.92
		var pz := r.randf_range(0.6, Z1 - 0.6)
		var py := UNDERSIDE + 0.45 + rad * 0.8 + r.randf() * 0.5 + absf(px - tx) / half * 0.4
		puff(st, Vector3(px, py, pz) - o, rad, 0.8, pivot - o, r.randi(), 11, 6)
	for i in int(span * 0.8):   # behind, hanging lower over the lot line
		var rad := r.randf_range(1.1, 1.7)
		var px := tx + (r.randf() * 2.0 - 1.0) * half * 0.95
		var pz := r.randf_range(-2.8, -0.2)
		var py := r.randf_range(3.3, 5.0) + absf(px - tx) / half * 0.6
		puff(st, Vector3(px, py, pz) - o, rad, 0.8, pivot - o, r.randi(), 11, 6)
	for i in 14 + int(span):   # the bulk
		var rad := r.randf_range(1.4, 2.1)
		var px := tx + (r.randf() * 2.0 - 1.0) * half * 0.8
		var pz := r.randf_range(-2.5, 2.6)
		var top := 10.4 - pow(absf(px - tx) / half, 2.0) * 3.0 - absf(pz) * 0.3
		var py := lerpf(6.0, top, sqrt(r.randf()))
		puff(st, Vector3(px, py, pz) - o, rad, 0.8, pivot - o, r.randi(), 12, 7)
	var mi := foliage_node(b, st, o, tx - half, tx + half, look.get("leaf_dark", LEAF_DARK), look.get("leaf_light", LEAF_LIGHT),
		0.12, 3.5, 7.0, true, parent)
	mi.material_override.set_shader_parameter("leaf_scale", 1.6)


# --- models ----------------------------------------------------------------------------------------

## A model as a PackedScene, or null if there is none: `name` is res://assets/country/<name>.glb, or a
## full res:// path.
static func model_scene(b: LevelBuilder, name: String) -> PackedScene:
	var path := name if name.begins_with("res://") else COUNTRY_MODELS % name
	if not ResourceLoader.exists(path):
		return null
	if not b._scene_cache.has(path):
		b._scene_cache[path] = load(path)
	return b._scene_cache[path]


## An instance of the model `name` (see model_scene) at pos under parent (the street if null), its
## leaves swapped for the foliage shader; null if there is no such model (draw a stand-in).
static func model(b: LevelBuilder, name: String, pos: Vector3, parent: Node3D = null) -> Node3D:
	var ps := model_scene(b, name)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	if n == null:
		return null
	n.position = pos
	(parent if parent else b.root).add_child(n)
	_swap_foliage(b, n, pos.y)
	tag_foliage(n, pos.x - 0.5, pos.x + 0.5)   # a lot piece's caller tags its real span over this
	return n


## Every surface of a model whose material is named for leaves ("foliage", "leaf", "leaves") gets its
## own foliage material, painted from the model's vertex colours (docs/CONTRACTS.md §10: COLOR.a is how
## far each leaf may move) or coloured and textured from its material, and its node joins &"foliage".
static func _swap_foliage(b: LevelBuilder, n: Node, base_y: float) -> void:
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			var nm := (src.resource_name if src else "").to_lower()
			if not (nm.contains("foliage") or nm.contains("leaf") or nm.contains("leaves")):
				continue
			var low := nm.contains("hedge") or nm.contains("grass")
			var fm := foliage_material(b, LEAF_DARK, LEAF_LIGHT, 0.03 if low else 0.12, base_y + (0.2 if low else 3.0), 1.6 if low else 6.0)
			var sm := src as BaseMaterial3D
			if sm and sm.vertex_color_use_as_albedo:
				fm.set_shader_parameter("vertex_paint", true)
				fm.set_shader_parameter("wet", 0.5)
			elif sm:
				fm.set_shader_parameter("leaf_dark", sm.albedo_color.darkened(0.45))
				fm.set_shader_parameter("leaf_light", sm.albedo_color.lightened(0.1))
				if sm.albedo_texture:
					fm.set_shader_parameter("leaf_tex", sm.albedo_texture)
					fm.set_shader_parameter("use_tex", true)
			if mi.mesh.get_surface_count() == 1:
				mi.material_override = fm   # a model's Foliage and Grass nodes are one surface each
			else:
				mi.set_surface_override_material(i, fm)
			if not mi.is_in_group(FOLIAGE_GROUP):
				mi.add_to_group(FOLIAGE_GROUP)
	for ch in n.get_children():
		_swap_foliage(b, ch, base_y)


## Records the street span x0..x1 on each foliage node under n.
static func tag_foliage(n: Node, x0: float, x1: float) -> void:
	if n.is_in_group(FOLIAGE_GROUP):
		n.set_meta("x0", x0)
		n.set_meta("x1", x1)
	for ch in n.get_children():
		tag_foliage(ch, x0, x1)


# --- foliage ---------------------------------------------------------------------------------------

## A new material on src/fx/foliage.gdshader (one per node, so a gust can shake each on its own):
## greens dark to light, `sway` metres of breeze at the top of `reach` above `base_y`. Its `gust_dir`
## starts as the street's wind.
static func foliage_material(b: LevelBuilder, dark: Color, light: Color, sway: float, base_y: float, reach: float) -> ShaderMaterial:
	if not b._mats.has("_foliage_shader"):
		b._mats["_foliage_shader"] = load("res://src/fx/foliage.gdshader")
	var m := ShaderMaterial.new()
	m.shader = b._mats["_foliage_shader"]
	m.set_shader_parameter("leaf_dark", dark)
	m.set_shader_parameter("leaf_light", light)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("base_y", base_y)
	m.set_shader_parameter("reach", reach)
	var wind: Array = b.data.get("wind", [[0, 0]])
	m.set_shader_parameter("gust_dir", -1.0 if float(wind[0][1]) < 0.0 else 1.0)
	return m


## st's leaves as a node at o (vertices relative to it), in &"foliage" with metas x0 / x1.
static func foliage_node(b: LevelBuilder, st: SurfaceTool, o: Vector3, x0: float, x1: float, dark: Color, light: Color,
		sway: float, base_y: float, reach: float, shadows := true, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = foliage_material(b, dark, light, sway, base_y, reach)
	mi.position = o
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("x0", x0)
	mi.set_meta("x1", x1)
	mi.add_to_group(FOLIAGE_GROUP)
	(parent if parent else b.root).add_child(mi)
	return mi


## A lumpy ball of leaves into st: centre c, radius r, `squash` its height. Its normals lean
## `pivot_w` toward out from `pivot` (the crown's or hedge's middle), so a whole crown shades as one
## soft mass of clumps.
static func puff(st: SurfaceTool, c: Vector3, r: float, squash: float, pivot: Vector3, seed: int, n := 10, rings := 6,
		pivot_w := 0.5) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed
	var lumps: Array[Vector3] = []
	for k in 4:
		lumps.append(Vector3(rr.randf_range(-1, 1), rr.randf_range(-0.5, 1), rr.randf_range(-1, 1)).normalized())
	var spin := rr.randf() * TAU
	var pts: Array = []
	for j in rings + 1:
		var row: Array = []
		var t := PI * j / rings
		for i in n:
			var a := TAU * i / n + spin
			var d := Vector3(sin(t) * cos(a), cos(t), sin(t) * sin(a))
			var k := 1.0
			for l in lumps:
				k += 0.22 * pow(maxf(d.dot(l), 0.0), 3.0)
			row.append(c + Vector3(d.x * r * k, d.y * r * k * squash, d.z * r * k))
		pts.append(row)
	for j in rings:
		for i in n:
			var q: Array = [pts[j][i], pts[j][(i + 1) % n], pts[j + 1][(i + 1) % n], pts[j + 1][i]]
			tri_out(st, q[0], q[1], q[2], c, pivot, pivot_w)
			tri_out(st, q[0], q[2], q[3], c, pivot, pivot_w)


## One triangle facing away from c, each vertex's normal out from c leaning pivot_w toward out from pivot.
static func tri_out(st: SurfaceTool, a: Vector3, p: Vector3, q: Vector3, c: Vector3, pivot: Vector3, pivot_w := 0.5) -> void:
	var out := (a + p + q) / 3.0 - c
	if (p - a).cross(q - a).dot(out) > 0.0:   # front faces wind clockwise seen from outside
		var t := p
		p = q
		q = t
	for v: Vector3 in [a, p, q]:
		st.set_normal((v - c).normalized().lerp((v - pivot).normalized(), pivot_w).normalized())
		st.add_vertex(v)


## A batch of meshes (material -> SurfaceTool) under parent, one mesh a material.
static func commit(sts: Dictionary, parent: Node3D) -> void:
	for mat: Material in sts:
		var mi := MeshInstance3D.new()
		mi.mesh = (sts[mat] as SurfaceTool).commit()
		mi.material_override = mat
		parent.add_child(mi)
