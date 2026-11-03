extends Control
## North-up cartography of the actual playable world's colliders and road plan.
const Shoreline := preload("res://src/world/downtown/shoreline.gd")
const LAND:=Color("172321")
const WATER:=Color("102d39")
const PARK:=Color("254235")
const ROAD_EDGE:=Color("71827b")
const ROAD:=Color("3e514c")
const ROOF:=Color("2b3733")
const ACCENT:=Color("a3e2ba")
var world: WorldBuilder
var player: Player
var mission: Mission
var footprints: Array[Dictionary]=[]
var tree_points: Array[Vector3]=[]
var _cached_trees:=false
var _centre:=Vector3.ZERO
var _scale:=0.5
var _view:=Rect2()
func setup(w: WorldBuilder,p: Player,m: Mission) -> void:
	world=w;player=p;mission=m
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true
	cache_footprints()
func cache_footprints() -> void:
	footprints.clear()
	if world==null:return
	for node in world.find_children("*","CollisionShape3D",true,false):
		var shape: Shape3D=node.shape
		if not shape is BoxShape3D:continue
		var dims: Vector3=(shape as BoxShape3D).size
		if dims.y<3.0 or dims.x<3.0 or dims.z<3.0 or maxf(dims.x,dims.z)>240.0:continue
		var xf: Transform3D=node.global_transform
		if xf.origin.y-dims.y*.5>12.0:continue
		var poly:=PackedVector3Array()
		for corner in [Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(1,0,1),Vector3(-1,0,1)]:
			poly.append(xf*(corner*dims*.5))
		var bounds:=Rect2(Vector2(poly[0].x,poly[0].z),Vector2.ZERO)
		for point in poly:bounds=bounds.expand(Vector2(point.x,point.z))
		footprints.append({"points":poly,"bounds":bounds,"height":dims.y})
	footprints.sort_custom(func(a,b):return a.bounds.get_area()>b.bounds.get_area())
func point(p: Vector3) -> Vector2:
	# DowntownPlan.NORTH=-X, EAST=-Z. This is geographic north-up, not a fake N.
	return Vector2(-(p.z-_centre.z),p.x-_centre.x)*_scale+size*.5
func _rect(r: Rect2,color: Color) -> void:
	var pts:=PackedVector2Array()
	for v in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:pts.append(point(Vector3(v.x,0,v.y)))
	draw_colored_polygon(pts,color)
func _road(points: Array,width: float,arterial: bool=false) -> void:
	for i in points.size()-1:
		var a:=point(points[i]);var b:=point(points[i+1]);var thickness:=maxf(2.0,width*_scale)
		draw_line(a,b,ROAD_EDGE,thickness+1.5,true)
		draw_line(a,b,ROAD,thickness,true)
		if arterial:draw_line(a,b,Color(.72,.77,.65,.45),.8,true)
func _draw() -> void:
	if world==null or player==null:return
	_centre=player.controlled_actor().global_position
	_scale=.36 if Game.mode==Game.MODE_CAR else (.12 if Game.mode==Game.MODE_HELI else .5)
	var radius:=size.x*.5/_scale
	_view=Rect2(Vector2(_centre.x-radius,_centre.z-radius),Vector2.ONE*radius*2)
	draw_rect(Rect2(Vector2.ZERO,size),LAND)
	for water: Rect2 in Shoreline.water_rects():_rect(water,WATER)
	for key in DowntownPlan.ISLANDS:_rect(DowntownPlan.ISLANDS[key],LAND)
	for key in DowntownPlan.BLOCKS:
		var block: Dictionary=DowntownPlan.BLOCKS[key]
		if block.kind=="park" or key in ["gardens_site","civic_padang"]:_rect(block.rect,PARK)
	for building in footprints:
		if not _view.intersects(building.bounds):continue
		var polygon:=PackedVector2Array();var shadow:=PackedVector2Array()
		for v in building.points:
			var p:=point(v);polygon.append(p);shadow.append(p+Vector2(1.3,1.3))
		draw_colored_polygon(shadow,Color(0,0,0,.42))
		draw_colored_polygon(polygon,Color("39443f") if building.height>35 else ROOF)
		polygon.append(polygon[0]);draw_polyline(polygon,Color("536158"),.7,true)
	for x in WorldBuilder.X_LINES:_road([Vector3(x,0,-340),Vector3(x,0,340)],16.0)
	for z in WorldBuilder.Z_LINES:_road([Vector3(-340,0,z),Vector3(340,0,z)],16.0)
	for key in DowntownPlan.ROADS:
		var road: Dictionary=DowntownPlan.ROADS[key];_road(road.pts,road.width,road.kind=="arterial")
	for key in DowntownPlan.BRIDGES:
		var bridge: Dictionary=DowntownPlan.BRIDGES[key];_road([bridge.from,bridge.to],bridge.width,bridge.kind=="vehicle")
	for key in DowntownPlan.PROMENADES:
		var path: Dictionary=DowntownPlan.PROMENADES[key]
		for i in path.pts.size()-1:draw_line(point(path.pts[i]),point(path.pts[i+1]),Color("697364"),maxf(1.0,path.width*_scale*.4),true)
	if not _cached_trees:
		var traffic: Node=get_tree().get_first_node_in_group("traffic_manager")
		if traffic and traffic.dressing and not traffic.dressing.trees.is_empty():
			for xf: Transform3D in traffic.dressing.trees:tree_points.append(traffic.dressing.global_transform*xf.origin)
			_cached_trees=true
	for tree in tree_points:
		var pos:=point(tree)
		if Rect2(Vector2.ZERO,size).has_point(pos):draw_circle(pos,maxf(1.1,2.6*_scale),Color("416a50"))
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if vehicle==player.current_vehicle or not vehicle.visible:continue
		var pos:=point(vehicle.global_position)
		if Rect2(Vector2.ONE*8,size-Vector2.ONE*16).has_point(pos):draw_circle(pos,1.6,Color(.74,.81,.77,.8))
	_draw_labels()
	var objective: Vector3=mission.get_meta("marker",Vector3.ZERO) if mission else Vector3.ZERO
	var pin:=point(objective).clamp(Vector2.ONE*12,size-Vector2.ONE*12)
	draw_circle(pin,6.0,Color("091a13"));draw_arc(pin,5.0,0,TAU,24,ACCENT,1.5,true);draw_circle(pin,2.0,ACCENT)
	var centre:=size*.5
	var forward: Vector3=-player.controlled_actor().global_transform.basis.z
	var dir:=Vector2(-forward.z,forward.x).normalized();var side:=Vector2(-dir.y,dir.x)
	var arrow:=PackedVector2Array([centre+dir*8,centre-dir*5+side*4.5,centre-dir*2,centre-dir*5-side*4.5])
	draw_circle(centre,10,Color(0,0,0,.35));draw_colored_polygon(arrow,Color("fff6de"))
	draw_string(ThemeDB.fallback_font,Vector2(size.x*.5-4,14),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("e4eadc"))
	var bar:=minf(100*_scale,size.x*.3)
	draw_line(Vector2(10,size.y-13),Vector2(10+bar,size.y-13),Color("d1d9ce"),2,true)
	draw_string(ThemeDB.fallback_font,Vector2(10,size.y-19),"100 m",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("d1d9ce"))
func _draw_labels() -> void:
	var font:=ThemeDB.fallback_font
	for pair in [["hawker","HAWKER"],["helipad_primary","AIRFIELD"],["delivery","WATERFRONT"]]:
		if not world.locations.has(pair[0]):continue
		var pos:=point(world.locations[pair[0]])
		if Rect2(Vector2(25,25),size-Vector2(80,50)).has_point(pos):
			draw_circle(pos,3,Color("d9c897"));draw_string(font,pos+Vector2(7,3),pair[1],HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("c4d0bf"))
	# At most two named nearby roads; actual plan names, never invented GPS routes.
	var labels:=0
	for key in DowntownPlan.ROADS:
		var pts: Array=DowntownPlan.ROADS[key].pts
		var mid: Vector3=(pts[0]+pts[-1])*.5;var pos:=point(mid)
		if Rect2(Vector2(24,30),size-Vector2(100,60)).has_point(pos):
			draw_string(font,pos+Vector2(4,-4),String(key).replace("_"," ").to_upper(),HORIZONTAL_ALIGNMENT_LEFT,130,8,Color(.7,.77,.71,.85))
			labels+=1
			if labels>=2:break
