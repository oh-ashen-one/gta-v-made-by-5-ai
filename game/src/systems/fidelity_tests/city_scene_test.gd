extends "res://src/systems/fidelity_tests/city_tiles_test.gd"
const Scene = preload("res://src/world/geography/city_scene.gd")
var city: Node3D
var may_remove := false
var material := StandardMaterial3D.new()

func _material(_feature: String, _role: String) -> Material:
	return material

func _retire(_key: String, _receipt: Dictionary) -> bool:
	return may_remove

func _run() -> void:
	var provider := Tiles.new()
	var policy := {"mode": Tiles.YMODE, "offset_m": 0.0}
	if not check("fixture source provider configures", provider.configure(FIXTURE, FIXTURE_ID, "a".repeat(64), "b".repeat(64), policy, 2)): _finish(); return
	var frame := Frame.new()
	check("source frame configured at actual fixture origin", frame.configure(Frame.EXPECTED_FRAME, [80000, 0, 80000], "a".repeat(64)))
	city = Scene.new(); add_child(city)
	var identity := {"geometry_identity_sha256": provider.metadata().identity_sha256, "snapshot_manifest_sha256": provider.metadata().bindings.snapshot_sha}
	var wrong := identity.duplicate(true); wrong.snapshot_manifest_sha256 = "c".repeat(64)
	check("different source snapshot refuses before geometry construction", not city.configure(frame, _material, _retire, 2, 1, wrong) and city.get_child_count() == 0)
	check("world supplies explicit materials and geometry identity", city.configure(frame, _material, _retire, 2, 1, identity))
	var foreign: Dictionary = provider.tile(80, 80); foreign.identity_sha256 = "d".repeat(64)
	var rejected: Dictionary = await city.install_tile(foreign)
	check("foreign geometry tile refuses before construction", not rejected.ok and city.get_child_count() == 0)
	for x in [80, 81]:
		var result: Dictionary = await city.install_tile(provider.tile(x, 80))
		if not check("production city scene commits native tile " + str(x), result.get("ok", false), str(result)): _finish(); return
	var roof := _ray(Vector3(3, 25, 3), Vector3(3, -5, 3))
	check("production renderer collision supports the actual roof", not roof.is_empty() and absf(roof.position.y - 12) < .001 and roof.normal.y > .95, str(roof))
	check("production renderer retains actual open courtyard", _ray(Vector3(7, 25, 7), Vector3(7, -5, 7)).is_empty())
	check("source fragment metadata belongs to actual collider", not roof.is_empty() and roof.collider.has_meta("source_feature_id") and roof.collider.has_meta("source_geometry_identity"))
	var denied: Dictionary = await city.retire_tile("80_80")
	check("world retirement refusal retains actual support", not denied.ok and not _ray(Vector3(3, 25, 3), Vector3(3, -5, 3)).is_empty())
	may_remove = true
	var retired: Dictionary = await city.retire_tile("80_80")
	check("approved tile retirement removes only its owned support", retired.ok and retired.owned_geometry_reaped and _ray(Vector3(3, 25, 3), Vector3(3, -5, 3)).is_empty())
	check("neighbor tile stays physically present", not _ray(Vector3(1005, 25, 30), Vector3(1005, -5, 30)).is_empty())
	metrics["scene_receipt"] = city.tile_receipt("81_80")
	metrics["scope"] = "Production scene installer/native fixture only; no city material fidelity, terrain, actors, world streaming or full game acceptance."
	_finish()
