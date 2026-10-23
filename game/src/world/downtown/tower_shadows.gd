extends RefCounted
## downtown-polish (wave S): crisp ground shadows of the downtown towers from
## the one sun, beyond the reach of the real shadow map.
##
## Critic standing gap: "crisp tower shadows from one sun". The sun's shadow
## map covers 280 m (lighting.gd), so in every helicopter / across-the-bay
## view the CBD, Marina Centre and MBS stood on evenly lit ground. Each
## building collision box of the blocks piece (and the three MBS towers) is
## swept along the sun's horizontal direction by height / tan(elevation),
## capped so neighbouring shadows stay separate shapes; only the footprint
## edges facing away from the sun are swept (no overlap with the footprint).
## The shader (dt_ground_shadow.gdshader) fades them in from 210-300 m, so the
## real shadow map owns the near field. One mesh, one draw, no shadow casting.

const SHADER := "res://assets/authored/shaders/dt_ground_shadow.gdshader"
const LightingScript := preload("res://src/world/lighting.gd")
const MIN_H := 8.0
const LEN_FACTOR_MAX := 2.3
const LEN_MAX := 330.0

static func sun_dir() -> Vector3:
	var e: Vector3 = LightingScript.SUN_ROTATION_DEG
	var b := Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
	return -b.z

## boxes: Array of [size: Vector3, centre: Vector3] (axis-aligned, as the
## blocks MeshKit records them). Returns the number of shadows built.
static func build(root: Node3D, boxes: Array, y: float = 0.27) -> int:
	if boxes.is_empty() or "--tower-shadows-off" in OS.get_cmdline_user_args():
		return 0
	var ld := sun_dir()
	var sd := Vector2(ld.x, ld.z)
	var len_per_h := sd.length() / maxf(-ld.y, 0.05)
	sd = sd.normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := 0
	for bx: Array in boxes:
		var size: Vector3 = bx[0]
		var c: Vector3 = bx[1]
		var top := c.y + size.y * 0.5
		if top < MIN_H:
			continue
		var sweep := Vector3(sd.x, 0.0, sd.y) * minf(top * minf(len_per_h, LEN_FACTOR_MAX), LEN_MAX)
		var o := Vector3(c.x, y, c.z)
		var hx := Vector3(size.x * 0.5, 0.0, 0.0)
		var hz := Vector3(0.0, 0.0, size.z * 0.5)
		var cs := [o - hx - hz, o + hx - hz, o + hx + hz, o - hx + hz]
		for e in 4:
			var p0: Vector3 = cs[e]
			var p1: Vector3 = cs[(e + 1) % 4]
			var mid := (p0 + p1) * 0.5 - o
			if Vector2(mid.x, mid.z).dot(sd) <= 0.0:
				continue
			for v: Vector3 in [p0, p1, p1 + sweep, p0, p1 + sweep, p0 + sweep]:
				st.add_vertex(v)
		n += 1
	if n == 0:
		return 0
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "DowntownTowerShadows"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("tower_shadows", n)
	root.add_child(mi)
	return n

## The three MBS hotel towers (landmarks piece, mbs.gd constants) as boxes.
static func mbs_boxes() -> Array:
	var m: Vector3 = DowntownPlan.ANCHORS["marina_bay_sands"]["pos"]
	var out: Array = []
	for dx: float in [-98.0, 0.0, 98.0]:
		out.append([Vector3(35.0, 200.0, 50.0), Vector3(m.x + dx, 100.0, m.z - 18.0)])
	return out
