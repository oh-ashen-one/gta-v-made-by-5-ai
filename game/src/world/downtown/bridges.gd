extends RefCounted
## downtown-map: vehicular and pedestrian bridges (DOWNTOWN_PLAN section 6).
##
## Every bridge has a smooth cosine vertical profile from ground level (0) up to
## its plan deck_y at mid-span and back, over RAMP_L metres either side of the
## centre. Roads and walks that run onto a bridge sample height_at(), so the
## approaches, the deck and any side street joining a ramp (Connaught Drive,
## the river walks under Elgin / Coleman) meet without steps. The structure
## over the water (deck slab, arches or girders, piers, parapets, lamps) is
## generated here; collision covers the deck, parapets and piers.

## Lateral distance over which a crossing road or walk blends back to ground.
const FALLOFF := 15.0
## Cosine profile half-lengths. Vehicle ramps stay at or under the plan's 6 %
## grade (3.6 m * PI / (2 * 99 m) = 5.7 %). Pedestrian ramps are 6.2-6.3 %
## (plan 5 %, deviation logged in loop/DOWNTOWN_PLAN.md): a 5 % Jubilee ramp
## would run into the Esplanade landmark site.
const RAMP_L := {"esplanade_bridge": 99.0, "bayfront_bridge": 99.0, "jubilee_bridge": 66.0,
	"cavenagh_bridge": 60.0, "elgin_bridge": 71.0, "coleman_bridge": 71.0}
const MINE := ["esplanade_bridge", "bayfront_bridge", "jubilee_bridge", "cavenagh_bridge", "elgin_bridge", "coleman_bridge"]

static var _profiles: Array = []

static func profiles() -> Array:
	if _profiles.is_empty():
		for key: String in MINE:
			var b: Dictionary = DowntownPlan.BRIDGES[key]
			var a: Vector3 = b["from"]
			var c: Vector3 = b["to"]
			var d := c - a
			d.y = 0.0
			_profiles.append({"name": key, "c": (a + c) * 0.5, "d": d.normalized(), "span": d.length() * 0.5,
				"L": float(RAMP_L[key]), "w": float(b["width"]) * 0.5, "h": float(b["deck_y"]),
				"soffit": float(b["soffit_y"]), "kind": String(b["kind"]), "lanes": int(b["lanes"])})
	return _profiles

static func profile(name: String) -> Dictionary:
	for p: Dictionary in profiles():
		if p["name"] == name:
			return p
	return {}

static func profile_h(p: Dictionary, t: float) -> float:
	var l: float = p["L"]
	if absf(t) >= l:
		return 0.0
	return float(p["h"]) * 0.5 * (1.0 + cos(PI * t / l))

## Finished surface height of roads / walks at (x, z): 0 on flat land, the
## bridge profile on and beside a bridge axis.
static func height_at(x: float, z: float) -> float:
	var best := 0.0
	for p: Dictionary in profiles():
		var c: Vector3 = p["c"]
		var d: Vector3 = p["d"]
		var rx := x - c.x
		var rz := z - c.z
		var t := rx * d.x + rz * d.z
		if absf(t) >= float(p["L"]):
			continue
		var excess := absf(-rx * d.z + rz * d.x) - float(p["w"])
		var k := 1.0
		if excess > 0.0:
			# downtown-fill (wave T): the Jubilee footbridge lands on the
			# Esplanade waterfront without lifting the paving beside it (the
			# lateral blend twisted the promenade setts into a warped hump)
			if excess >= FALLOFF or p["name"] == "jubilee_bridge":
				continue
			k = 0.5 * (1.0 + cos(PI * excess / FALLOFF))
		best = maxf(best, profile_h(p, t) * k)
	return best

## True when (x, z) is on a bridge deck footprint over or beside the water.
static func on_deck(x: float, z: float, margin: float = 0.0) -> bool:
	for p: Dictionary in profiles():
		var c: Vector3 = p["c"]
		var d: Vector3 = p["d"]
		var rx := x - c.x
		var rz := z - c.z
		var t := rx * d.x + rz * d.z
		var lat := absf(-rx * d.z + rz * d.x)
		if absf(t) <= float(p["span"]) + margin and lat <= float(p["w"]) + margin:
			return true
	return false

static func deck_point(p: Dictionary, t: float, lat: float, dy: float = 0.0) -> Vector3:
	var c: Vector3 = p["c"]
	var d: Vector3 = p["d"]
	var left := Vector3(d.z, 0.0, -d.x)
	var q := c + d * t + left * lat
	q.y = profile_h(p, t) + dy
	return q

# ------------------------------------------------------------------ build
static func build(m) -> void:
	for p: Dictionary in profiles():
		match String(p["name"]):
			"esplanade_bridge":
				_bridge(m, p, "granite_light", 5, true)
			"bayfront_bridge":
				_bridge(m, p, "concrete_bridge", 5, false)
			"elgin_bridge", "coleman_bridge":
				_bridge(m, p, "cream_render", 1, true)
			"jubilee_bridge":
				_bridge(m, p, "concrete_bridge", 4, false)
			"cavenagh_bridge":
				_bridge(m, p, "steel_white", 1, false)
				_cavenagh_towers(m, p)
	_sheares(m)

## One bridge over the water: deck slab (asphalt or paving on top), side
## fascias with arch soffits or a flat girder line, piers, parapets with
## collision and lamp standards. `spans` arches / girder bays over the water.
static func _bridge(m, p: Dictionary, struct_mat: String, spans: int, arched: bool) -> void:
	var span: float = p["span"]
	var w: float = p["w"]
	var vehicle: bool = p["kind"] == "vehicle"
	var t0 := -span - 4.0
	var t1 := span + 4.0
	if not vehicle:
		t0 = -float(p["L"])
		t1 = float(p["L"])
	var top_mat := "asphalt" if vehicle else ("timber" if p["name"] == "jubilee_bridge" else "pavers_bridge")
	var thick := maxf(float(p["h"]) - float(p["soffit"]), 0.6)
	var walk_w := 3.2 if vehicle else 0.0
	var steps := maxi(8, int((t1 - t0) / 3.0))
	# deck top surfaces (+ raised footways on the vehicle bridges)
	for i in steps:
		var ta := t0 + (t1 - t0) * float(i) / steps
		var tb := t0 + (t1 - t0) * float(i + 1) / steps
		var cw := w - walk_w
		m.quad_up(top_mat, deck_point(p, ta, cw, 0.065), deck_point(p, tb, cw, 0.065), deck_point(p, tb, -cw, 0.065), deck_point(p, ta, -cw, 0.065))
		m.drive_quad(deck_point(p, ta, w, 0.065), deck_point(p, tb, w, 0.065), deck_point(p, tb, -w, 0.065), deck_point(p, ta, -w, 0.065))
		if vehicle:
			for side: float in [-1.0, 1.0]:
				var a0 := deck_point(p, ta, side * cw, 0.165)
				var b0 := deck_point(p, tb, side * cw, 0.165)
				var a1 := deck_point(p, ta, side * w, 0.165)
				var b1 := deck_point(p, tb, side * w, 0.165)
				m.quad_up("pavers_bridge", a0, b0, b1, a1)
				# kerb face
				m.quad_side("kerb", a0, b0, deck_point(p, tb, side * cw, 0.065), deck_point(p, ta, side * cw, 0.065), -side)
	# deck collision, pitched boxes along the profile
	var seg := 5.0
	var n_seg := maxi(1, int(ceil((t1 - t0) / seg)))
	for i in n_seg:
		var ta2 := t0 + (t1 - t0) * float(i) / n_seg
		var tb2 := t0 + (t1 - t0) * float(i + 1) / n_seg
		var a := deck_point(p, ta2, 0.0, 0.065)
		var b := deck_point(p, tb2, 0.0, 0.065)
		m.pitched_box(a, b, w * 2.0, 0.6, Vector3(0, -0.55, 0))
		if vehicle:
			for side: float in [-1.0, 1.0]:
				m.pitched_box(deck_point(p, ta2, side * (w - walk_w * 0.5), 0.165), deck_point(p, tb2, side * (w - walk_w * 0.5), 0.165), walk_w, 0.3, Vector3(0, -0.15, 0))
	# side fascias + soffit: arches or a straight girder over the water
	var water_top := DowntownPlan.WATER_LEVEL + 0.25
	var bays := spans
	var bay_len := span * 2.0 / bays
	for k in bays:
		var s0 := -span + k * bay_len
		var s1 := s0 + bay_len
		var n := 14
		for j in n:
			var u0 := float(j) / n
			var u1 := float(j + 1) / n
			var ta3 := lerpf(s0, s1, u0)
			var tb3 := lerpf(s0, s1, u1)
			var ya := _under(p, ta3, thick, arched, u0, water_top)
			var yb := _under(p, tb3, thick, arched, u1, water_top)
			for side: float in [-1.0, 1.0]:
				var lat := side * (w + 0.05)
				var top_a := deck_point(p, ta3, lat, 0.0)
				var top_b := deck_point(p, tb3, lat, 0.0)
				var bot_a := Vector3(top_a.x, ya, top_a.z)
				var bot_b := Vector3(top_b.x, yb, top_b.z)
				m.quad_side(struct_mat, top_a, top_b, bot_b, bot_a, side)
			# soffit (underside, facing down)
			var sa0 := deck_point(p, ta3, w + 0.05, 0.0)
			var sa1 := deck_point(p, ta3, -w - 0.05, 0.0)
			var sb0 := deck_point(p, tb3, w + 0.05, 0.0)
			var sb1 := deck_point(p, tb3, -w - 0.05, 0.0)
			sa0.y = ya; sa1.y = ya; sb0.y = yb; sb1.y = yb
			m.quad_dir(struct_mat + "_soffit", sa0, sb0, sb1, sa1, Vector3.DOWN)
		# pier at the start of each bay (and the far abutment)
		_pier(m, p, s0, struct_mat, arched)
	_pier(m, p, span, struct_mat, arched)
	# parapets / railings (with collision) and lamp standards
	var par_h := 1.1
	# vehicle-bridge parapets start just past the banks, so a car turning onto
	# the deck from a diagonal approach (Fullerton Road) never meets their ends
	var pt0 := -span + 1.5 if vehicle else t0
	var pt1 := span - 1.5 if vehicle else t1
	var np := maxi(1, int(ceil((pt1 - pt0) / seg)))
	for side: float in [-1.0, 1.0]:
		var lat2 := side * (w - 0.2)
		for i in np:
			var ta4 := pt0 + (pt1 - pt0) * float(i) / np
			var tb4 := pt0 + (pt1 - pt0) * float(i + 1) / np
			var a4 := deck_point(p, ta4, lat2, 0.165)
			var b4 := deck_point(p, tb4, lat2, 0.165)
			if arched:
				m.pitched_box_visual(struct_mat, a4, b4, 0.4, par_h, Vector3(0, par_h * 0.5, 0))
				m.pitched_box_visual("granite_coping", a4, b4, 0.5, 0.08, Vector3(0, par_h + 0.04, 0))
			else:
				m.pitched_box_visual("steel_rail", a4, b4, 0.08, 0.08, Vector3(0, par_h, 0))
				m.pitched_box_visual("steel_rail", a4, b4, 0.05, 0.05, Vector3(0, par_h * 0.5, 0))
				m.pitched_box_visual(struct_mat, a4, b4, 0.3, 0.25, Vector3(0, 0.12, 0))
				if p["name"] == "jubilee_bridge":
					m.pitched_box_visual("glass_rail", a4, b4, 0.03, 0.9, Vector3(0, 0.62, 0))
			m.pitched_box(a4, b4, 0.4, par_h + 0.1, Vector3(0, (par_h + 0.1) * 0.5, 0), true)
		var lamp_step := 24.0
		var t := -span + 6.0
		while t < span - 2.0:
			m.lamp(deck_point(p, t, side * (w - 0.6), 0.165), "heritage" if arched else "modern")
			t += lamp_step
		if not arched:
			var tp := t0
			while tp < t1:
				m.post(deck_point(p, tp, lat2, 0.165), par_h)
				tp += 2.5
	m.label_name(p)

static func _under(p: Dictionary, t: float, thick: float, arched: bool, u: float, water_top: float) -> float:
	var deck_bottom := profile_h(p, t) - thick
	if not arched:
		return deck_bottom
	var spring := water_top + 0.35
	var crown := float(p["soffit"])
	return minf(deck_bottom, spring + (crown - spring) * sin(PI * u))

static func _pier(m, p: Dictionary, t: float, struct_mat: String, arched: bool) -> void:
	var w: float = p["w"]
	var top := profile_h(p, t) - (0.0 if arched else maxf(float(p["h"]) - float(p["soffit"]), 0.6))
	if arched:
		top = DowntownPlan.WATER_LEVEL + 0.6
	var base := DowntownPlan.WATER_LEVEL - 2.5
	var c := deck_point(p, t, 0.0, 0.0)
	var d: Vector3 = p["d"]
	var basis := Basis(Vector3.UP, atan2(d.x, d.z))
	if arched:
		# full-width pier with cutwaters
		var size := Vector3(w * 2.0 + 1.2, top - base, 2.6)
		m.box_basis(struct_mat, Vector3(c.x, (top + base) * 0.5, c.z), size, basis)
		m.col_box(size, Vector3(c.x, (top + base) * 0.5, c.z), basis)
	else:
		# twin round-cornered column pairs under the girders
		for lat: float in [-w * 0.6, 0.0, w * 0.6] if w > 8.0 else [0.0]:
			var q := deck_point(p, t, lat, 0.0)
			var size2 := Vector3(1.4, top - base, 1.4)
			m.box_basis(struct_mat, Vector3(q.x, (top + base) * 0.5, q.z), size2, basis)
			m.col_box(size2, Vector3(q.x, (top + base) * 0.5, q.z), basis)
		m.box_basis(struct_mat, Vector3(c.x, top - 0.4, c.z), Vector3(w * 2.0 - 1.0, 0.8, 1.8), basis)

## Cavenagh Bridge: a pair of white portal frames at each bank with chain
## hangers down to the deck edge (an 1869 suspension footbridge silhouette).
static func _cavenagh_towers(m, p: Dictionary) -> void:
	var span: float = p["span"]
	var w: float = p["w"]
	for end: float in [-1.0, 1.0]:
		var t := end * (span - 2.0)
		for side: float in [-1.0, 1.0]:
			var base := deck_point(p, t, side * (w + 0.3), 0.0)
			m.box_basis("steel_white", base + Vector3(0, 3.5, 0), Vector3(0.5, 7.0, 0.5), Basis.IDENTITY)
			m.col_box(Vector3(0.5, 7.0, 0.5), base + Vector3(0, 3.5, 0), Basis.IDENTITY)
		var top_c := deck_point(p, t, 0.0, 6.9)
		var d: Vector3 = p["d"]
		m.box_basis("steel_white", top_c, Vector3(w * 2.0 + 1.1, 0.4, 0.4), Basis(Vector3.UP, atan2(d.x, d.z) + PI * 0.5))
	for side: float in [-1.0, 1.0]:
		var n := 16
		for i in n:
			var u0 := float(i) / n
			var u1 := float(i + 1) / n
			var sag := func(u: float) -> float: return 6.9 - 5.2 * (1.0 - pow(2.0 * u - 1.0, 2.0))
			var a := deck_point(p, lerpf(-span + 2.0, span - 2.0, u0), side * (w + 0.3), 0.0)
			var b := deck_point(p, lerpf(-span + 2.0, span - 2.0, u1), side * (w + 0.3), 0.0)
			a.y += sag.call(u0)
			b.y += sag.call(u1)
			m.pitched_box_visual("steel_white", a, b, 0.14, 0.14, Vector3.ZERO)
			if i > 0:
				var h := a.y - (profile_h(p, lerpf(-span + 2.0, span - 2.0, u0)) + 1.1)
				m.box_basis("steel_white", a - Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.05), Basis.IDENTITY)

## Sheares Bridge: elevated expressway on the eastern horizon beyond the
## Gardens (scenery; collision only so aircraft cannot fly through it).
static func _sheares(m) -> void:
	var a: Dictionary = DowntownPlan.ANCHORS["sheares_bridge"]
	var pos: Vector3 = a["pos"]
	var size: Vector3 = a["size"]
	var deck_y := pos.y
	var x0 := pos.x - size.x * 0.5
	var x1 := pos.x + size.x * 0.5
	var n := 26
	for i in n:
		var xa := lerpf(x0, x1, float(i) / n)
		var xb := lerpf(x0, x1, float(i + 1) / n)
		# gentle hog: highest over the channel
		var ya := deck_y - 0.0006 * pow(xa - (-400.0), 2.0) / 100.0
		var yb := deck_y - 0.0006 * pow(xb - (-400.0), 2.0) / 100.0
		var pa := Vector3(xa, maxf(ya, 8.0), pos.z)
		var pb := Vector3(xb, maxf(yb, 8.0), pos.z)
		m.pitched_box_visual("concrete_bridge", pa, pb, size.z, 2.4, Vector3.ZERO)
		m.pitched_box_visual("steel_rail", pa, pb, size.z + 0.6, 1.0, Vector3(0, 1.4, 0))
		var mid := (pa + pb) * 0.5
		var h := mid.y - 1.2 - DowntownPlan.WATER_LEVEL + 2.0
		m.box_basis("concrete_bridge", Vector3(mid.x, mid.y - 1.2 - h * 0.5, mid.z), Vector3(4.0, h, 8.0), Basis.IDENTITY)
		m.col_box(Vector3(xb - xa, 3.0, size.z), Vector3(mid.x, mid.y, mid.z), Basis.IDENTITY)
