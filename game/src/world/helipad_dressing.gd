class_name HelipadDressing
extends RefCounted
## Helipad set dressing (opus55 helicopter piece). Called from
## WorldBuilder._helipad(). Visual only: nothing here has collision, so the
## driving, walking and landing routes are unaffected. Repeated parts are
## batched with MultiMesh to keep draw calls low.

const PAD_TOP := 0.33

static func build(root: Node3D, pos: Vector3, radius: float, primary: bool) -> void:
	var holder := Node3D.new()
	holder.name = "HelipadDressing"
	holder.position = pos
	root.add_child(holder)
	_deck_surface(holder, radius)
	_markings(holder, radius)
	_edge_lights(holder, radius)
	_safety_apron(holder, radius)
	_flood_masts(holder, radius)
	_windsock(holder, Vector3(-radius - 5.0, 0.0, -radius * 0.6))
	if primary:
		_ground_ops(holder, radius)

static func _mm(holder: Node3D, mesh: Mesh, mat: Material, xforms: Array[Transform3D], shadows: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(inst)
	return inst

static func _mesh(holder: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot_deg
	holder.add_child(mi)
	return mi

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _cyl(radius: float, height: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c

## Painted aiming-point circle, dashed TLOF edge, touchdown/positioning marks.
## Weathered deck surface over the dark touchdown disc: cast-in panel
## joints, aggregate grain, rubber scuffs from skids, oil stains and the
## yellow shoulder bars, so the pad is no longer a flat black slab.
const DECK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float pad_r = 10.0;
varying vec2 p;
float h21(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 q) {
	vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 q) { return vn(q) * 0.5 + vn(q * 2.1) * 0.25 + vn(q * 4.3) * 0.125 + vn(q * 8.7) * 0.0625; }
void vertex() { p = VERTEX.xz; }
void fragment() {
	float r = length(p);
	if (r > pad_r) { discard; }
	vec3 base = vec3(0.235, 0.245, 0.235);
	float large = fbm(p * 0.18);
	float grain = vn(p * 9.0) * 0.6 + h21(floor(p * 40.0)) * 0.4;
	vec3 col = base * (0.82 + 0.30 * large) * (0.92 + 0.14 * grain);
	// cast-in deck panel joints every 3 m
	vec2 g = abs(fract(p / 3.0 + 0.5) - 0.5) * 3.0;
	float joint = 1.0 - smoothstep(0.015, 0.045, min(g.x, g.y));
	col *= 1.0 - 0.45 * joint;
	// rubber scuffs where skids touch down: dark arcs around the centre
	float ang = atan(p.y, p.x);
	float scuff = smoothstep(0.55, 0.85, fbm(vec2(ang * 3.0, r * 0.7) + 7.0)) * smoothstep(pad_r * 0.12, pad_r * 0.3, r) * (1.0 - smoothstep(pad_r * 0.45, pad_r * 0.7, r));
	col *= 1.0 - 0.38 * scuff;
	// oil / fuel stains
	float stain = smoothstep(0.64, 0.80, fbm(p * 0.16 + 3.0)) * smoothstep(0.3, 0.7, vn(p * 1.3));
	col = mix(col, vec3(0.10, 0.095, 0.09), stain * 0.45);
	// sun-bleached, dusty outer band
	col = mix(col, vec3(0.40, 0.39, 0.35), smoothstep(pad_r * 0.80, pad_r, r) * 0.45 * (0.6 + 0.4 * large));
	// yellow shoulder bars either side of the H, paint worn by fbm
	vec2 b = vec2(abs(abs(p.x) - pad_r * 0.60), abs(p.y));
	float bar = (1.0 - step(0.30, b.x)) * (1.0 - step(pad_r * 0.33, b.y));
	float wear = smoothstep(0.25, 0.55, fbm(p * 2.3));
	col = mix(col, vec3(0.80, 0.60, 0.12), bar * (0.55 + 0.45 * wear));
	ALBEDO = col;
	ROUGHNESS = mix(0.86, 0.55, stain * 0.8);
	SPECULAR = 0.35;
}
"""

static func _deck_surface(holder: Node3D, radius: float) -> void:
	var plane := PlaneMesh.new()
	var pad_r := radius * 0.75
	plane.size = Vector2(pad_r * 2.0, pad_r * 2.0)
	var shader := Shader.new()
	shader.code = DECK_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("pad_r", pad_r)
	var mi := _mesh(holder, plane, m, Vector3(0.0, PAD_TOP + 0.034, 0.0))
	mi.name = "DeckSurface"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _markings(holder: Node3D, radius: float) -> void:
	var yellow := Palette.mat(Color(0.86, 0.66, 0.14), 0.7)
	var white := Palette.mat(Color(0.86, 0.85, 0.80), 0.75)
	var dashes: Array[Transform3D] = []
	var n := int(radius * 2.2)
	for i in n:
		var a := TAU * float(i) / float(n)
		var r := radius * 0.755
		var t := Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * r, PAD_TOP + 0.005, sin(a) * r))
		dashes.append(t)
	_mm(holder, _box(Vector3(0.35, 0.012, radius * 0.11)), yellow, dashes, false)
	# outer white edge band on the concrete deck
	var band := TorusMesh.new()
	band.inner_radius = radius * 0.93
	band.outer_radius = radius * 0.975
	band.rings = 48
	band.ring_segments = 6
	var ring := _mesh(holder, band, white, Vector3(0.0, PAD_TOP - 0.03, 0.0))
	ring.scale = Vector3(1.0, 0.03, 1.0)
	# shoulder-line bars either side of the H
	var bars: Array[Transform3D] = []
	for sx in [-1.0, 1.0]:
		bars.append(Transform3D(Basis(), Vector3(sx * radius * 0.45, PAD_TOP + 0.006, 0.0)))
	_mm(holder, _box(Vector3(0.4, 0.012, radius * 0.5)), yellow, bars, false)
	# "MAX 5T" style load box, original text
	var label := Label3D.new()
	label.text = "5.0 t  D16"
	label.font_size = 64
	label.pixel_size = 0.03
	label.modulate = Color(0.88, 0.86, 0.80)
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = Vector3(0.0, PAD_TOP + 0.02, radius * 0.56)
	label.shaded = true
	holder.add_child(label)

## Inset perimeter lights (green) and floodlit touchdown ring lights (amber).
static func _edge_lights(holder: Node3D, radius: float) -> void:
	var lamps: Array[Transform3D] = []
	var n := int(radius * 1.5)
	for i in n:
		var a := TAU * (float(i) + 0.5) / float(n)
		lamps.append(Transform3D(Basis(), Vector3(cos(a) * radius * 0.985, PAD_TOP + 0.04, sin(a) * radius * 0.985)))
	_mm(holder, _cyl(0.16, 0.1, 8), Palette.emissive(Color(0.45, 1.0, 0.5), 2.2), lamps, false)
	var amber: Array[Transform3D] = []
	var m := int(radius * 1.1)
	for i in m:
		var a := TAU * float(i) / float(m)
		amber.append(Transform3D(Basis(), Vector3(cos(a) * radius * 0.70, PAD_TOP + 0.02, sin(a) * radius * 0.70)))
	_mm(holder, _cyl(0.11, 0.06, 8), Palette.emissive(Color(1.0, 0.72, 0.25), 1.6), amber, false)

## Safety area around the deck: a lighter apron ring, red/white bollards with
## drooping chains and hazard chevrons at the edge.
static func _safety_apron(holder: Node3D, radius: float) -> void:
	var apron := TorusMesh.new()
	apron.inner_radius = radius
	apron.outer_radius = radius + 4.5
	apron.rings = 48
	apron.ring_segments = 4
	var apron_mesh := _mesh(holder, apron, Palette.mat_textured(Color(0.50, 0.49, 0.46), "concrete", Vector3.ONE, 0.92), Vector3(0.0, 0.03, 0.0))
	apron_mesh.scale = Vector3(1.0, 0.012, 1.0)
	apron_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var chev: Array[Transform3D] = []
	var n := int(radius * 2.4)
	for i in n:
		var a := TAU * float(i) / float(n)
		var r := radius + 0.6
		chev.append(Transform3D(Basis(Vector3.UP, -a + 0.6), Vector3(cos(a) * r, 0.05, sin(a) * r)))
	_mm(holder, _box(Vector3(0.28, 0.01, 1.3)), Palette.mat(Color(0.85, 0.66, 0.12), 0.75), chev, false)
	# bollards (gaps left on the east and south-west for access paths)
	var white: Array[Transform3D] = []
	var red: Array[Transform3D] = []
	var count := int((radius + 4.5) * 1.1)
	for i in count:
		var a := TAU * float(i) / float(count)
		if absf(wrapf(a, -PI, PI)) < 0.45 or absf(wrapf(a - 2.4, -PI, PI)) < 0.35:
			continue
		var p := Vector3(cos(a) * (radius + 4.4), 0.0, sin(a) * (radius + 4.4))
		white.append(Transform3D(Basis(), p + Vector3(0.0, 0.45, 0.0)))
		red.append(Transform3D(Basis(), p + Vector3(0.0, 0.82, 0.0)))
	_mm(holder, _cyl(0.09, 0.9, 8), Palette.mat(Color(0.86, 0.85, 0.80), 0.6), white)
	_mm(holder, _cyl(0.095, 0.12, 8), Palette.mat(Color(0.70, 0.10, 0.08), 0.55), red, false)

## Floodlight masts on the diagonals; lamp heads are emissive panels only (no
## omni lights, so no blown halo in daylight shots).
static func _flood_masts(holder: Node3D, radius: float) -> void:
	var metal := Palette.mat(Color(0.42, 0.43, 0.44), 0.5, 0.6)
	var dark := Palette.mat(Color(0.12, 0.12, 0.13), 0.6, 0.4)
	var lamp := Palette.emissive(Color(1.0, 0.93, 0.78), 1.1)
	var poles: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var faces: Array[Transform3D] = []
	for i in 4:
		# Rotated 22.5 deg off the diagonals so no mast stands between the fixed
		# photo_09 airfield camera (pad + (-20, 3, 24)) and the pad centre.
		var a := TAU * (float(i) + 0.5) / 4.0 + TAU / 16.0
		var p := Vector3(cos(a), 0.0, sin(a)) * (radius + 7.0)
		poles.append(Transform3D(Basis(), p + Vector3(0.0, 4.0, 0.0)))
		var face_basis := Basis.looking_at((-p).normalized() + Vector3(0.0, -0.6, 0.0), Vector3.UP)
		heads.append(Transform3D(face_basis, p + Vector3(0.0, 8.1, 0.0)))
		faces.append(Transform3D(face_basis, p + Vector3(0.0, 8.1, 0.0) + face_basis * Vector3(0.0, 0.0, -0.21)))
	_mm(holder, _cyl(0.13, 8.0, 10), metal, poles)
	_mm(holder, _box(Vector3(1.4, 0.7, 0.4)), dark, heads)
	_mm(holder, _box(Vector3(1.25, 0.55, 0.02)), lamp, faces, false)

static func _windsock(holder: Node3D, at: Vector3) -> void:
	_mesh(holder, _cyl(0.07, 6.0, 8), Palette.mat(Color(0.42, 0.43, 0.44), 0.5, 0.6), at + Vector3(0.0, 3.0, 0.0))
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.38
	hoop.outer_radius = 0.43
	_mesh(holder, hoop, Palette.mat(Color(0.3, 0.3, 0.3), 0.5, 0.6), at + Vector3(0.0, 5.85, 0.35), Vector3(90.0, 0.0, 0.0))
	var colors := [Color(0.92, 0.38, 0.10), Color(0.90, 0.88, 0.84), Color(0.92, 0.38, 0.10), Color(0.90, 0.88, 0.84)]
	for i in 4:
		var seg := CylinderMesh.new()
		seg.top_radius = 0.40 - i * 0.065
		seg.bottom_radius = 0.40 - (i + 1) * 0.065
		seg.height = 0.6
		seg.radial_segments = 12
		var s := _mesh(holder, seg, Palette.mat(colors[i], 0.9), at + Vector3(0.0, 5.85 - i * 0.07, 0.35 + 0.3 + i * 0.6), Vector3(-83.0, 0.0, 0.0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Primary pad only: a working heliport edge - fuel bowser, ground power
## cart, fire trolley, a parked second aircraft on its stand and taxi lines.
static func _ground_ops(holder: Node3D, radius: float) -> void:
	var yellow := Palette.mat(Color(0.86, 0.66, 0.14), 0.7)
	# taxi line from the pad edge to the parking stand (north-east)
	var stand := Vector3(radius + 15.0, 0.0, -radius - 8.0)
	var dir := (stand - Vector3.ZERO).normalized()
	var start := dir * (radius + 4.6)
	var length := start.distance_to(stand) - 5.0
	var line := _mesh(holder, _box(Vector3(0.22, 0.012, length)), yellow, start.lerp(stand - dir * 5.0, 0.5) + Vector3(0.0, 0.05, 0.0))
	line.rotation.y = atan2(dir.x, dir.z)
	var stand_ring := TorusMesh.new()
	stand_ring.inner_radius = 5.2
	stand_ring.outer_radius = 5.45
	stand_ring.rings = 36
	stand_ring.ring_segments = 4
	var sr := _mesh(holder, stand_ring, yellow, stand + Vector3(0.0, 0.05, 0.0))
	sr.scale = Vector3(1.0, 0.012, 1.0)
	sr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if AssetLibrary.has_asset("helicopter_clean.glb"):
		var parked := AssetLibrary.instantiate("helicopter_clean.glb", holder)
		if parked != null:
			parked.position = stand + Vector3(0.0, 0.0, 0.0)
			parked.rotation.y = -2.3
			AssetLibrary.tint(parked, Color(0.92, 0.90, 0.86))
	# fuel bowser
	_vehicle_bowser(holder, Vector3(-radius - 9.0, 0.0, -radius - 4.0), 0.5)
	# ground power unit + fire trolley + cones near the north-west quadrant
	var gpu_at := Vector3(-radius * 0.55, 0.0, -radius - 7.5)
	_mesh(holder, _box(Vector3(1.4, 1.1, 2.2)), Palette.mat(Color(0.86, 0.66, 0.14), 0.55, 0.3), gpu_at + Vector3(0.0, 0.85, 0.0), Vector3(0.0, 20.0, 0.0))
	_mesh(holder, _box(Vector3(1.45, 0.08, 2.25)), Palette.mat(Color(0.15, 0.15, 0.16), 0.6, 0.4), gpu_at + Vector3(0.0, 1.44, 0.0), Vector3(0.0, 20.0, 0.0))
	var wheels: Array[Transform3D] = []
	for wx in [-0.6, 0.6]:
		for wz in [-0.8, 0.8]:
			var off := Basis(Vector3.UP, deg_to_rad(20.0)) * Vector3(wx, 0.0, wz)
			wheels.append(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), gpu_at + off + Vector3(0.0, 0.28, 0.0)))
	_mm(holder, _cyl(0.28, 0.18, 10), Palette.mat(Color(0.07, 0.07, 0.08), 0.9), wheels)
	var fire_at := Vector3(radius + 6.5, 0.0, 3.0)
	_mesh(holder, _cyl(0.32, 1.25, 12), Palette.mat(Color(0.72, 0.08, 0.06), 0.4, 0.2), fire_at + Vector3(0.0, 0.85, 0.0))
	_mesh(holder, _box(Vector3(0.9, 0.06, 0.7)), Palette.mat(Color(0.2, 0.2, 0.21), 0.6, 0.5), fire_at + Vector3(0.0, 0.2, 0.0))
	var cones: Array[Transform3D] = []
	for i in 6:
		cones.append(Transform3D(Basis(), Vector3(-radius - 3.0 + i * 1.6, 0.36, radius + 7.0)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = 0.2
	cone.height = 0.7
	cone.radial_segments = 10
	_mm(holder, cone, Palette.mat(Color(0.95, 0.40, 0.08), 0.7), cones)

static func _vehicle_bowser(holder: Node3D, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var cab := Palette.mat(Color(0.88, 0.87, 0.83), 0.4, 0.3)
	var tank := Palette.mat(Color(0.80, 0.80, 0.78), 0.3, 0.7)
	var dark := Palette.mat(Color(0.10, 0.10, 0.11), 0.7, 0.3)
	var glass := Palette.mat(Color(0.12, 0.16, 0.19), 0.1, 0.5)
	var parts := [
		[_box(Vector3(2.3, 1.9, 1.9)), cab, Vector3(0.0, 1.55, -3.0)],
		[_box(Vector3(2.32, 0.7, 0.05)), glass, Vector3(0.0, 1.95, -3.96)],
		[_box(Vector3(2.2, 0.35, 7.6)), dark, Vector3(0.0, 0.75, 0.0)],
		[_box(Vector3(2.4, 0.2, 0.25)), Palette.mat(Color(0.8, 0.1, 0.06), 0.5), Vector3(0.0, 0.85, 3.85)],
	]
	for p in parts:
		var mi := _mesh(holder, p[0], p[1], at + b * (p[2] as Vector3))
		mi.rotation.y = yaw
	var tank_mesh := _cyl(1.05, 5.0, 16)
	var t := _mesh(holder, tank_mesh, tank, at + b * Vector3(0.0, 1.95, 1.0))
	t.basis = b * Basis(Vector3.RIGHT, PI * 0.5)
	var stripe := _mesh(holder, _cyl(1.07, 0.35, 16), Palette.mat(Color(0.85, 0.12, 0.08), 0.5), at + b * Vector3(0.0, 1.95, 1.0))
	stripe.basis = b * Basis(Vector3.RIGHT, PI * 0.5)
	var wheels: Array[Transform3D] = []
	for wz in [-3.0, 1.4, 2.6]:
		for wx in [-1.05, 1.05]:
			wheels.append(Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), at + b * Vector3(wx, 0.5, wz)))
	_mm(holder, _cyl(0.5, 0.35, 14), Palette.mat(Color(0.07, 0.07, 0.08), 0.9), wheels)
	var sign := Label3D.new()
	sign.text = "AVTUR JET A-1"
	sign.font_size = 48
	sign.pixel_size = 0.02
	sign.modulate = Color(0.75, 0.12, 0.08)
	sign.shaded = true
	sign.basis = b * Basis(Vector3.UP, PI * 0.5)
	sign.position = at + b * Vector3(1.07, 1.95, 1.0)
	holder.add_child(sign)
