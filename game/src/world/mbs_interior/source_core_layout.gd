extends RefCounted
## Source-conforming RECONSTRUCTION. This is the complete operational packing
## contract; Root's existing floor/cabin/stair consumers must adopt each pose.
## Geometry packing is not native traversal or surveyed private lift placement.
const SCHEMA := "mbs_source_core_layout_v2"
const BANK_CENTRES := {"T3":[0.0,12.2],"T2":[0.0,21.0],"T1":[0.0,21.8]}
const BANK_SIZE := [28.0,7.2]
const OWN_ATRIUM_INTERVALS := {"T3":[-5.0,5.0],"T2":[-10.0,10.0],"T1":[-20.35,18.0]}
const LIFT_X := [-4.5,-1.5,1.5,4.5]
const LIFT_ALIASES := ["east-guest_lift","east-service_lift","west-guest_lift","west-service_lift"]
const STAIR_EDGE_X := 8.3
const STAIR_CROSS_Z := 1.0
const HINGE_FRAME_CLEARANCE := .1175
const STAIR_APPROACH_Z := .45-HINGE_FRAME_CLEARANCE-(1.30+.75)
const SHAFT_HALF_WIDTH := 1.32 # 2.20/2 + .14 + .16/2
const OPEN_GRILLE_HALF_WIDTH := 1.37 # 1.30/4 + .72 + 1.30/4
const SHAFT_MIN_Z := -.225 # Side wall: -(2.80+.45)/2 + cabin offset1.40
const SHAFT_BACK_Z := 3.04 # 1.40 + 2.80/2 + .16 + .16/2
const STAIR_LOCAL_BOUNDS := [-1.84,-2.20,1.84,5.30]

static func _rect(center: Array,bounds: Array) -> Array:
	return [[center[0]+bounds[0],center[1]+bounds[1]],[center[0]+bounds[2],center[1]+bounds[1]],[center[0]+bounds[2],center[1]+bounds[3]],[center[0]+bounds[0],center[1]+bounds[3]]]

static func _rotate_stair(point: Array,outward: float,bank: Array) -> Array:
	# Godot right-handed Y rotation: +90 maps local +Z to own +X.
	return [float(bank[0])+outward*(STAIR_EDGE_X+float(point[1])),float(bank[1])+STAIR_CROSS_Z-outward*float(point[0])]

static func for_tower(tower: String) -> Dictionary:
	if not BANK_CENTRES.has(tower):return {"valid":false,"error":"Unknown source tower."}
	var bank: Array=BANK_CENTRES[tower].duplicate()
	var components: Array=[]
	for index in LIFT_X.size():
		var cx: float=float(bank[0])+float(LIFT_X[index])
		var threshold: Array=[cx,float(bank[1])]
		components.append({"id":tower+"-"+LIFT_ALIASES[index],"legacy_core_alias":LIFT_ALIASES[index],"kind":"lift","own_cabin_center_xz":[cx,float(bank[1])+1.4],"own_threshold_xz":threshold,"entry_sign":-1.0,"rotation_y_rad":0.0,"own_operational_polygon":_rect(threshold,[-1.40,-.90,1.40,3.10]),"own_static_and_grille_envelope":_rect(threshold,[-OPEN_GRILLE_HALF_WIDTH,SHAFT_MIN_Z,OPEN_GRILLE_HALF_WIDTH,SHAFT_BACK_Z]),"own_approach_path":[[cx,float(bank[1])-2.20],[cx,float(bank[1])-.60],[cx,float(bank[1])+1.40]],"inner_cabin_xz_m":[2.20,2.80],"hall_clear_width_m":2.60,"opened_grille_width_m":2.74,"source_lift_xy_surveyed":false})
	for outward: float in [-1.0,1.0]:
		var alias: String="east-stair" if outward<0 else "west-stair"
		var polygon: Array=[]
		for p: Array in [[-1.84,-2.20],[1.84,-2.20],[1.84,5.30],[-1.84,5.30]]:polygon.append(_rotate_stair(p,outward,bank))
		var approaches: Array=[]
		for lane: float in [-.78,.78]:
			var approach: Array=_rotate_stair([lane,STAIR_APPROACH_Z],outward,bank)
			approaches.append({"lane":"lower_departure" if lane<0 else "upper_return","own_path":[[approach[0],float(bank[1])-2.20],approach,_rotate_stair([lane,.60],outward,bank),_rotate_stair([lane,1.20],outward,bank)],"unchanged_capsule_radius_m":.36,"gate_opening_width_m":1.30})
		components.append({"id":tower+"-"+alias,"legacy_core_alias":alias,"kind":"rotated_u_stair","own_origin_xz":[float(bank[0])+outward*STAIR_EDGE_X,float(bank[1])+STAIR_CROSS_Z],"rotation_y_rad":outward*PI*.5,"original_local_side":1.0,"own_operational_polygon":polygon,"local_operational_bounds_xz":STAIR_LOCAL_BOUNDS.duplicate(),"own_approaches":approaches,"physical_u_stair_width_depth_m":[3.20,5.20],"occupancy_query_cross_extent_m":3.68,"gate_edge_setback_m":.45,"hinge_frame_clearance_m":HINGE_FRAME_CLEARANCE,"two_independent_1_30m_leaves":true,"source_stair_xy_surveyed":false})
	var result: Dictionary={"valid":true,"schema":SCHEMA,"tower":tower,"own_center_xz":bank,"own_size_xz":BANK_SIZE.duplicate(),"own_bank_polygon":_rect(bank,[-14.0,-3.60,14.0,3.60]),"shared_hall":{"own_polygon":_rect(bank,[-13.75,-3.50,13.75,-.90]),"clear_width_m":2.60,"support_owner":"floor_factory","no_furnishing_or_door_swing_in_clear_hall":true},"components":components,"own_atrium_interval":OWN_ATRIUM_INTERVALS[tower].duplicate(),"complete_operational_geometry_defined":true,"native_fit_verified":false,"production_consumers_integrated":false,"required_core_aliases_preserved":true,"private_asbuilt_verified":false,"status":"GEOMETRIC_CONTRACT_REQUIRES_NATIVE_CONSUMER_INTEGRATION"}
	return result
