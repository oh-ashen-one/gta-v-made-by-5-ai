class_name AssetLibrary
extends RefCounted
## Loader for provider-generated assets.
##
## Provider GLBs are not committed to the repository (their terms are not MIT);
## they live in `game/assets/providers/` and are re-fetched with
## `game/tools/fetch_provider_assets.sh`. Everything here degrades gracefully:
## when a provider asset is absent the procedural stand-in is used instead.

const PROVIDER_DIR := "res://assets/providers/"

static func has_asset(file_name: String) -> bool:
	return ResourceLoader.exists(PROVIDER_DIR + file_name)

static func instantiate(file_name: String, parent: Node) -> Node3D:
	if not has_asset(file_name):
		return null
	var packed: PackedScene = load(PROVIDER_DIR + file_name)
	if packed == null:
		return null
	var node := packed.instantiate()
	if node is Node3D:
		parent.add_child(node)
		return node
	if parent:
		parent.add_child(node)
	return null

## Depth-first search for a named node inside an imported asset.
static func find_named(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	for child in root.get_children():
		if String(child.name).to_lower() == node_name.to_lower():
			return child
		var found := find_named(child, node_name)
		if found != null:
			return found
	return null

## Spin a separated part (wheel, rotor) about an axis of the owning body.
## The part origin sits at its own geometry centre, so this reads as a real
## wheel or rotor turning in place.
static func spin_part(node: Node3D, owner_body: Node3D, world_axis: Vector3, angle: float) -> void:
	if node == null or owner_body == null:
		return
	var axis_global: Vector3 = owner_body.global_transform.basis * world_axis.normalized()
	var axis_local: Vector3 = node.global_transform.basis.inverse() * axis_global
	if axis_local.length() < 0.0001:
		return
	node.rotate_object_local(axis_local.normalized(), angle)

## Recolor a provider asset so a shared mesh can stand in for several vehicles.
static func tint(root: Node, color: Color) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh: Mesh = child.mesh
			if mesh == null:
				continue
			var surface: int = mesh.get_surface_count()
			for i in surface:
				var mat: Material = mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var copy: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
					copy.albedo_color = copy.albedo_color.lerp(color, 0.55)
					# Preserve provider PBR response; fabric and plaster must not
					# inherit car paint merely because this helper tints them.
					copy.metallic = mat.metallic
					copy.roughness = mat.roughness
					child.set_surface_override_material(i, copy)
		tint(child, color)
