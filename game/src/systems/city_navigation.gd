extends RefCounted
## GPS graph follows the game's existing roads, splitting real intersections.
var graph := AStar3D.new()
var points: Array[Dictionary] = []
var route := PackedVector3Array()
var walking_route := PackedVector3Array()
var destination := Vector3.ZERO
var title := ""
var active := false
var _ids := {}
var _last_start := Vector3.INF
func setup(world: WorldBuilder) -> void:
	var segments: Array = []
	for x in WorldBuilder.X_LINES: segments.append([Vector3(x,0,-340),Vector3(x,0,340)])
	for z in WorldBuilder.Z_LINES: segments.append([Vector3(-340,0,z),Vector3(340,0,z)])
	for key in DowntownPlan.ROADS:
		var pts: Array = DowntownPlan.ROADS[key].pts
		for i in pts.size()-1: segments.append([pts[i],pts[i+1]])
	for key in DowntownPlan.BRIDGES:
		var bridge: Dictionary=DowntownPlan.BRIDGES[key]
		if bridge.kind=="vehicle": segments.append([bridge.from,bridge.to])
	for segment in segments:
		var a: Vector3=segment[0]; var b: Vector3=segment[1]
		var cuts: Array[Vector3]=[a,b]
		for other in segments:
			var hit=Geometry2D.segment_intersects_segment(Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(other[0].x,other[0].z),Vector2(other[1].x,other[1].z))
			if hit != null: cuts.append(Vector3(hit.x,0,hit.y))
		cuts.sort_custom(func(u:Vector3,v:Vector3):return a.distance_squared_to(u)<a.distance_squared_to(v))
		for i in cuts.size()-1:
			var first:=_node(cuts[i]);var second:=_node(cuts[i+1])
			if first!=second and not graph.are_points_connected(first,second):graph.connect_points(first,second)
	points.append({"name":"MBS · Hotel entrance","position":preload("res://src/world/mbs_interior/city_access_layout.gd").entrance()})
	for pair in [["helipad_secondary","Helicopter · Waterfront"],["helipad_primary","Helicopter · Airfield"],["hawker","Hawker Centre"]]:
		if world.locations.has(pair[0]):points.append({"name":pair[1],"position":world.locations[pair[0]]})
	for pair in [["mbs_event_plaza","MBS · Event Plaza"],["merlion","Merlion"],["singapore_flyer","Singapore Flyer"],["gardens_supertree_grove","Gardens by the Bay"],["artscience_museum","ArtScience Museum"],["esplanade_concert_hall","Esplanade"]]:
		var offset:Vector3={"mbs_event_plaza":Vector3(0,.1,10),"merlion":Vector3(0,0,16),"singapore_flyer":Vector3(80,0,0),"artscience_museum":Vector3(0,0,-45),"esplanade_concert_hall":Vector3(0,0,58)}.get(pair[0],Vector3.ZERO)
		points.append({"name":pair[1],"position":DowntownPlan.anchor(pair[0])+offset})
func _node(p:Vector3)->int:
	p.y=0; var key:=Vector2i(roundi(p.x*10),roundi(p.z*10))
	if _ids.has(key):return _ids[key]
	var id:=graph.get_available_point_id();graph.add_point(id,p);_ids[key]=id;return id
func select(at:Vector3,label:String)->void:
	destination=at;title=label;active=true;_last_start=Vector3.INF
func clear()->void:
	active=false;route.clear();walking_route.clear();title=""
func update(at:Vector3)->void:
	if not active:return
	if at.distance_to(destination)<9.0:clear();return
	if at.distance_squared_to(_last_start)<100:return
	_last_start=at
	var approach:=destination
	walking_route=PackedVector3Array()
	# Event Plaza is behind the solid Shoppes podium. Route around its north
	# end on the plan's channel promenade, never through the building wall.
	if title.begins_with("MBS · Event") or (destination.distance_to(DowntownPlan.anchor("mbs_event_plaza"))<20):
		approach=Vector3(-324,0,-780)
		walking_route=PackedVector3Array([approach,Vector3(-324,.1,-646),Vector3(-318,.36,-632),destination])
	var start:=graph.get_closest_point(at);var finish:=graph.get_closest_point(approach)
	route=graph.get_point_path(start,finish)
	if not route.is_empty():
		if walking_route.is_empty():walking_route=PackedVector3Array([route[-1],destination])
		else:walking_route.insert(0,route[-1])
func distance_remaining(at:Vector3)->float:
	if route.is_empty():return at.distance_to(destination)
	var length:=at.distance_to(route[0])
	for i in route.size()-1:length+=route[i].distance_to(route[i+1])
	for i in walking_route.size()-1:length+=walking_route[i].distance_to(walking_route[i+1])
	return length
