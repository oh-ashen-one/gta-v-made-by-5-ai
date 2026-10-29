extends RefCounted
## Existing Orchard Reach art on exact source geometry. Window/facade layout
## remains an explicit game treatment, never a current facade survey.
var _materials: Dictionary = {}

func _surface(name: String, tint: Color, metres_per_texture: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = .88
	var base := "res://assets/authored/surfaces/" + name
	if ResourceLoader.exists(base + "_albedo.png"):
		material.albedo_texture = load(base + "_albedo.png")
	if ResourceLoader.exists(base + "_normal.png"):
		material.normal_enabled = true
		material.normal_texture = load(base + "_normal.png")
		material.normal_scale = .55
	material.uv1_scale = Vector3.ONE / metres_per_texture
	return material

func material_for(feature: String, role: String) -> Material:
	var bucket: int = posmod(feature.hash(), 8)
	var key := role + "/" + str(bucket)
	if _materials.has(key): return _materials[key]
	var material: StandardMaterial3D
	if role == "road":
		material = _surface("asphalt", Color(.50,.53,.54), 1.0)
	elif role == "terrain":
		material = _surface("soil", Color(.47,.53,.40), 5.0)
	elif role in ["roof", "underside"]:
		material = _surface("concrete", Color(.61,.64,.63), 2.0)
	else:
		var colors := [Color(.86,.83,.75),Color(.74,.78,.78),Color(.81,.77,.67),Color(.71,.74,.71),Color(.88,.86,.79),Color(.70,.77,.79),Color(.77,.74,.69),Color(.81,.82,.78)]
		material = _surface("plaster", colors[bucket], 1.0)
	_materials[key] = material
	return material
