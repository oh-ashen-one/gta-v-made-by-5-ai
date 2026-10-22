class_name RoofKit
extends RefCounted
## Rooftop dressing for the mid-block infill and HDB slabs (wave A, Opus 5.5).
##
## The wave-5 critic found the aerial views "dominated by untextured beige box
## roofs". Every flat roof now gets: a deck in one of several weathered
## membranes (grey concrete tiles, dark bitumen, green or red waterproofing,
## ribbed metal sheet) with a world-space stain/ponding shader; a parapet; and
## a seeded mix of roof equipment (condenser banks with fan grilles, water
## tanks on stands, stair/lift housings, solar arrays, ducts, skylights,
## rooftop planters). Everything is collected first and emitted as one
## MultiMesh per part type, so a few hundred roofs cost about a dozen draws.

const DECK_SHADER := "res://assets/authored/shaders/roof_deck.gdshader"

## Membrane colours (alpha < 0.5 = ribbed metal sheet).
const MEMBRANES := [
	Color(0.47, 0.46, 0.43, 1.0),   # grey concrete tiles
	Color(0.23, 0.23, 0.24, 1.0),   # bitumen
	Color(0.34, 0.42, 0.36, 1.0),   # green waterproofing
	Color(0.50, 0.30, 0.24, 1.0),   # red waterproofing
	Color(0.56, 0.55, 0.52, 1.0),   # pale concrete
	Color(0.44, 0.46, 0.48, 0.0),   # ribbed metal
]

var _deck: Array = []        # [Transform3D, Color]
var _parts := {}             # part name -> Array[Transform3D]
var _rng := RandomNumberGenerator.new()
var roofs := 0

func _init(seed_value: int = 5501) -> void:
	_rng.seed = seed_value

func _put(part: String, xf: Transform3D) -> void:
	if not _parts.has(part):
		_parts[part] = []
	_parts[part].append(xf)

static func _box_xf(size: Vector3, pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), pos)

## A flat roof of a box building: size = building size, pos = base centre.
func add_flat_roof(size: Vector3, pos: Vector3, kind: String) -> void:
	roofs += 1
	var top := pos.y + size.y
	var k := int(absf(pos.x) * 3.1 + absf(pos.z) * 7.3 + size.y * 11.0)
	_rng.seed = k
	var membrane: Color = MEMBRANES[5] if kind == "workshop" else MEMBRANES[k % 5]
	membrane = Color(membrane.r * _rng.randf_range(0.9, 1.1), membrane.g * _rng.randf_range(0.9, 1.1), membrane.b * _rng.randf_range(0.9, 1.1), membrane.a)
	# Deck slab (its side faces render as a parapet band in the shader).
	_deck.append([_box_xf(Vector3(size.x + 0.5, 0.42, size.z + 0.5), Vector3(pos.x, top + 0.17, pos.z)), membrane])
	var deck_top := top + 0.38
	# Parapet upstands on all four edges.
	var ph := 0.7 if size.y > 6.0 else 0.45
	for sx in [-1.0, 1.0]:
		_put("parapet", _box_xf(Vector3(0.28, ph, size.z + 0.5), Vector3(pos.x + sx * (size.x * 0.5 + 0.11), deck_top + ph * 0.5, pos.z)))
	for sz in [-1.0, 1.0]:
		_put("parapet", _box_xf(Vector3(size.x + 0.5, ph, 0.28), Vector3(pos.x, deck_top + ph * 0.5, pos.z + sz * (size.z * 0.5 + 0.11))))
	var area := size.x * size.z
	var hx := size.x * 0.5 - 1.6
	var hz := size.z * 0.5 - 1.6
	if hx < 1.0 or hz < 1.0:
		return
	var long_x := size.x >= size.z
	# Condenser banks: one or two rows of chunky units with dark fan grilles.
	var units := clampi(int(area / 45.0), 2, 12)
	var banks := 1 if area < 300.0 else 2
	for bank in banks:
		var row_z := _rng.randf_range(-hz, hz) * 0.7
		var start := -minf(hx, units * 0.85) + _rng.randf_range(0.0, 1.0)
		for u in units:
			var along := start + u * 1.7
			if absf(along) > (hx if long_x else hz):
				break
			var p := Vector3(pos.x + along, deck_top, pos.z + row_z) if long_x else Vector3(pos.x + row_z, deck_top, pos.z + along)
			var yaw := 0.0 if long_x else PI * 0.5
			_put("condenser", _box_xf(Vector3(1.55, 1.15, 1.15), p + Vector3(0, 0.58, 0), yaw))
			_put("fan", Transform3D(Basis.from_scale(Vector3(0.95, 0.04, 0.95)), p + Vector3(0, 1.17, 0)))
	# Big cooling tower on large roofs.
	if area > 450.0 and _rng.randf() < 0.6:
		var cp := Vector3(pos.x + _rng.randf_range(-hx, hx) * 0.5, deck_top, pos.z + _rng.randf_range(-hz, hz) * 0.5)
		_put("stand", _box_xf(Vector3(5.0, 1.2, 5.0), cp + Vector3(0, 0.6, 0)))
		_put("cooling", Transform3D(Basis.from_scale(Vector3(4.4, 3.0, 4.4)), cp + Vector3(0, 2.7, 0)))
		_put("fan", Transform3D(Basis.from_scale(Vector3(3.4, 0.05, 3.4)), cp + Vector3(0, 4.22, 0)))
	# Vent stacks.
	for v in _rng.randi_range(0, 3):
		var vp := Vector3(pos.x + _rng.randf_range(-hx, hx), deck_top, pos.z + _rng.randf_range(-hz, hz))
		_put("vent", Transform3D(Basis.from_scale(Vector3(0.45, 1.6, 0.45)), vp + Vector3(0, 0.8, 0)))
	# Stair / lift housing on most mid-size roofs.
	if area > 70.0 and _rng.randf() < 0.9:
		var hp := Vector3(pos.x + _rng.randf_range(-hx, hx) * 0.6, deck_top, pos.z + _rng.randf_range(-hz, hz) * 0.6)
		var hs := Vector3(_rng.randf_range(2.8, 4.2), _rng.randf_range(2.4, 3.2), _rng.randf_range(2.6, 3.6))
		_put("housing", _box_xf(hs, hp + Vector3(0, hs.y * 0.5, 0)))
		_put("housing_roof", _box_xf(Vector3(hs.x + 0.3, 0.18, hs.z + 0.3), hp + Vector3(0, hs.y + 0.09, 0)))
		_put("door", _box_xf(Vector3(0.95, 2.0, 0.06), hp + Vector3(0, 1.0, hs.z * 0.5 + 0.03)))
	# Water tank on a steel stand (taller buildings).
	if size.y > 6.5 and _rng.randf() < 0.7:
		var tp := Vector3(pos.x + _rng.randf_range(-hx, hx) * 0.7, deck_top, pos.z + _rng.randf_range(-hz, hz) * 0.7)
		var r := _rng.randf_range(0.9, 1.4)
		_put("stand", _box_xf(Vector3(r * 2.1, 1.0, r * 2.1), tp + Vector3(0, 0.5, 0)))
		_put("tank", Transform3D(Basis.from_scale(Vector3(r * 2.0, 2.2, r * 2.0)), tp + Vector3(0, 2.1, 0)))
	# Solar array: tilted dark panels in rows.
	if area > 220.0 and _rng.randf() < 0.4:
		var rows := clampi(int(hz / 1.6), 1, 6)
		var cols := clampi(int(hx / 1.1), 1, 10)
		var sp := Vector3(pos.x - hx * 0.45, deck_top + 0.45, pos.z - hz * 0.4)
		for rr in rows:
			for cc in cols:
				var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18.0)) * Basis.from_scale(Vector3(1.0, 0.05, 1.5)), sp + Vector3(cc * 1.05, 0.0, rr * 2.0))
				_put("solar", xf)
	# Duct run along the long axis.
	if _rng.randf() < 0.6:
		var dl := (hx if long_x else hz) * 1.5
		var off := _rng.randf_range(-1.0, 1.0) * (hz if long_x else hx) * 0.7
		var dp := Vector3(pos.x, deck_top + 0.35, pos.z + off) if long_x else Vector3(pos.x + off, deck_top + 0.35, pos.z)
		_put("duct", _box_xf(Vector3(dl, 0.55, 0.6) if long_x else Vector3(0.6, 0.55, dl), dp))
	# Skylights or a rooftop planter bed.
	if _rng.randf() < 0.35:
		for s in 2:
			var lp := Vector3(pos.x + _rng.randf_range(-hx, hx) * 0.5, deck_top + 0.3, pos.z + _rng.randf_range(-hz, hz) * 0.5)
			_put("skylight", _box_xf(Vector3(2.2, 0.6, 1.4), lp))
	elif area > 160.0 and _rng.randf() < 0.45:
		var gp := Vector3(pos.x + _rng.randf_range(-hx, hx) * 0.5, deck_top, pos.z + _rng.randf_range(-hz, hz) * 0.5)
		_put("planter", _box_xf(Vector3(4.0, 0.5, 1.4), gp + Vector3(0, 0.25, 0)))
		for b in 3:
			_put("shrub", Transform3D(Basis.from_scale(Vector3(1.2, 0.9, 1.1)), gp + Vector3(-1.3 + b * 1.3, 0.85, 0)))

## Roof plant on a provider HDB slab (roof at pos.y + h, footprint ~fx x fz).
func add_hdb_roof(pos: Vector3, h: float, rot90: bool) -> void:
	var top := pos.y + h + 0.1
	var along := Vector3(1, 0, 0) if not rot90 else Vector3(0, 0, 1)
	var across := Vector3(0, 0, 1) if not rot90 else Vector3(1, 0, 0)
	var span := h * 0.28
	# Two lift motor rooms and a raised water-tank frame per slab.
	for s in [-1.0, 1.0]:
		var mp: Vector3 = pos + along * s * span + Vector3(0, top - pos.y, 0)
		_put("housing", _box_xf(Vector3(4.6, 3.2, 4.6), mp + Vector3(0, 1.6, 0)))
		_put("housing_roof", _box_xf(Vector3(5.0, 0.2, 5.0), mp + Vector3(0, 3.3, 0)))
	var tp: Vector3 = pos + Vector3(0, top - pos.y, 0) + across * 1.5
	_put("stand", _box_xf(Vector3(6.4, 2.4, 3.6), tp + Vector3(0, 1.2, 0)))
	for t in 2:
		_put("tank", Transform3D(Basis.from_scale(Vector3(2.8, 2.6, 2.8)), tp + along * (-1.6 + t * 3.2) + Vector3(0, 3.7, 0)))
	_put("mast", _box_xf(Vector3(0.18, 6.0, 0.18), pos + along * span * 1.4 + Vector3(0, top - pos.y + 3.0, 0)))

func build(parent: Node3D) -> void:
	if not _deck.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var unit := BoxMesh.new()
		unit.size = Vector3.ONE
		mm.mesh = unit
		mm.instance_count = _deck.size()
		for i in _deck.size():
			mm.set_instance_transform(i, _deck[i][0])
			mm.set_instance_color(i, _deck[i][1])
		var mat := ShaderMaterial.new()
		mat.shader = load(DECK_SHADER)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "RoofKit_deck"
		mmi.multimesh = mm
		mmi.material_override = mat
		parent.add_child(mmi)
	var looks := {
		"parapet": [_box(), Palette.mat_textured(Color(0.66, 0.64, 0.60), "concrete", Vector3.ONE, 0.9)],
		"condenser": [_box(), Palette.mat_textured(Color(0.70, 0.71, 0.70), "metal", Vector3.ONE, 0.5, 0.3)],
		"fan": [_cyl(), Palette.mat(Color(0.10, 0.11, 0.12), 0.6, 0.5)],
		"cooling": [_cyl(), Palette.mat(Color(0.56, 0.60, 0.60), 0.5, 0.4)],
		"vent": [_cyl(), Palette.mat(Color(0.42, 0.43, 0.44), 0.45, 0.6)],
		"housing": [_box(), Palette.mat_textured(Color(0.58, 0.57, 0.54), "concrete", Vector3.ONE, 0.9)],
		"housing_roof": [_box(), Palette.mat(Color(0.30, 0.30, 0.31), 0.9)],
		"door": [_box(), Palette.mat(Color(0.30, 0.22, 0.16), 0.7, 0.2)],
		"stand": [_box(), Palette.mat(Color(0.28, 0.30, 0.33), 0.6, 0.6)],
		"tank": [_cyl(), Palette.mat(Color(0.62, 0.66, 0.68), 0.45, 0.55)],
		"solar": [_box(), Palette.mat(Color(0.07, 0.10, 0.18), 0.18, 0.6)],
		"duct": [_box(), Palette.mat(Color(0.66, 0.67, 0.68), 0.4, 0.7)],
		"skylight": [_box(), Palette.mat(Color(0.35, 0.47, 0.52), 0.12, 0.4)],
		"planter": [_box(), Palette.mat_textured(Color(0.46, 0.44, 0.40), "concrete", Vector3.ONE, 0.9)],
		"shrub": [_sphere(), Palette.mat(Palette.FOLIAGE_LIGHT, 0.95)],
		"mast": [_box(), Palette.mat(Color(0.55, 0.56, 0.58), 0.5, 0.6)],
	}
	for part in _parts:
		var xforms: Array = _parts[part]
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = looks[part][0]
		mm2.instance_count = xforms.size()
		for i in xforms.size():
			mm2.set_instance_transform(i, xforms[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "RoofKit_%s" % part
		inst.multimesh = mm2
		inst.material_override = looks[part][1]
		if part in ["fan", "door", "solar", "skylight", "shrub", "mast"]:
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(inst)

## Tinted copies of a Palette facade sheet, so a block of mid-block buildings
## does not read as one white estate from the air. A handful of shared
## variants keeps static batching effective (one draw per variant).
const FACADE_TINTS := [
	Color(1.0, 0.96, 0.88), Color(0.80, 0.81, 0.82), Color(0.93, 0.85, 0.74), Color(0.84, 0.91, 0.85),
	Color(0.82, 0.87, 0.94), Color(0.95, 0.84, 0.82), Color(0.70, 0.68, 0.64),
]
static var _facade_variants := {}

static func facade_variant(kind: String, pos: Vector3) -> StandardMaterial3D:
	var k := int(absf(pos.x) * 0.37 + absf(pos.z) * 0.91) % FACADE_TINTS.size()
	var key := "%s|%d" % [kind, k]
	if not _facade_variants.has(key):
		var m := Palette.facade(kind).duplicate() as StandardMaterial3D
		m.albedo_color = FACADE_TINTS[k]
		_facade_variants[key] = m
	return _facade_variants[key]

func part_count(part: String) -> int:
	return (_parts.get(part, []) as Array).size()

static func _box() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b

static func _cyl() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = 12
	c.rings = 1
	return c

static func _sphere() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 8
	s.rings = 4
	return s
