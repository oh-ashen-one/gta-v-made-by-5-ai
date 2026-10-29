extends "res://src/systems/fidelity_tests/source_roads_test.gd"
## Exact representation parity and native original-way lookup, synthetic fixture.
func _bodies(holder: Node3D) -> Array[StaticBody3D]:
	var result:Array[StaticBody3D]=[]
	for child:Node in holder.get_children():
		if child is StaticBody3D:result.append(child)
	return result

func _faces(holder:Node3D)->PackedVector3Array:
	var result:=PackedVector3Array()
	for body:StaticBody3D in _bodies(holder):
		for child:Node in body.get_children():
			if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:result.append_array(child.shape.get_faces())
	return result

func _visual(holder:Node3D)->Array:
	for child:Node in holder.get_children():
		if child is MeshInstance3D:return child.mesh.surface_get_arrays(0)
	return []

func run()->void:
	var raw:=FileAccess.get_file_as_bytes(SNAPSHOT);var manifest:Dictionary=JSON.parse_string(raw.get_string_from_utf8())
	var frame:=Frame.new();var roads:=Roads.new()
	if not check("canonical native frame",frame.configure(manifest.georeference,[0,0,0],_sha(raw))):finish();return
	if not check("pinned synthetic five-road fixture",roads.configure(FIXTURE,FIXTURE_SHA,frame)):finish();return
	var plan:Dictionary=roads.prepare_physical("fixture")
	if not check("fixture prepares",plan.ok):finish();return
	var child_count:=get_child_count()
	for options:Dictionary in [{"collision_mode":"unknown"},{"faces_per_body":1},{"faces_per_body":8.5},{"unknown":true}]:
		check("invalid options refuse without scene mutation",not roads.build_physical(plan.plan,self,null,options).ok and get_child_count()==child_count,str(options))
	var before:Dictionary=roads.build_physical(plan.plan,self)
	if not check("default representation retained",before.ok and before.collision_mode=="per_feature" and before.collision_body_count==5):finish();return
	await frames(5)
	var original_faces:=_faces(before.node);var original_visual:=_visual(before.node)
	var probes:Array[Dictionary]=[]
	for pair:Array in [[Vector3(25,20,0),Vector3(25,-2,0)],[Vector3(25,5,0),Vector3(25,-2,0)],[Vector3(-80,15,0),Vector3(-80,-5,0)],[Vector3(130,15,0),Vector3(130,-5,0)],[Vector3(200,15,220),Vector3(200,-5,220)]]:
		var hit:=ray(pair[0],pair[1])
		if not check("default native original-way probe hits",not hit.is_empty()):finish();return
		probes.append({"from":pair[0],"to":pair[1],"way":hit.collider.get_meta("source_way"),"position":hit.position,"normal":hit.normal})
	before.node.queue_free();await frames(5)
	var batched:Dictionary=roads.build_physical(plan.plan,self,null,{"collision_mode":"static_batches"})
	if not check("bounded aggregate representation commits",batched.ok and batched.collision_body_count<5):finish();return
	await frames(5)
	var actual_faces:=_faces(batched.node)
	if actual_faces.to_byte_array()!=original_faces.to_byte_array():
		var mismatches:Array=[]
		for i in mini(actual_faces.size(),original_faces.size()):
			if actual_faces[i]!=original_faces[i]:mismatches.append({"index":i,"default":original_faces[i],"batch":actual_faces[i]})
			if mismatches.size()>=12:break
		metrics["face_mismatches"]={"default_count":original_faces.size(),"actual_count":actual_faces.size(),"first":mismatches}
	check("every native triangle triple is byte-for-byte equal",actual_faces.to_byte_array()==original_faces.to_byte_array())
	var current_visual:=_visual(batched.node)
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX]:
		check("render array unchanged channel "+str(channel),current_visual[channel]==original_visual[channel])
	for probe:Dictionary in probes:
		var hit:=ray(probe.from,probe.to);var source:=roads.resolve_source_hit(hit)
		check("fresh native aggregate face resolves original way "+str(probe.way),source.get("ok",false) and source.source_way==probe.way and hit.position.is_equal_approx(probe.position) and hit.normal.is_equal_approx(probe.normal),str(source))
	check("real loop opening remains empty",ray(Vector3(220,15,220),Vector3(220,-5,220)).is_empty())
	var native_hit:=ray(probes[0].from,probes[0].to)
	var tampered:Dictionary=native_hit.duplicate();tampered.erase("face_index")
	check("missing native face never guesses original identity",not roads.resolve_source_hit(tampered).ok)
	tampered=native_hit.duplicate();tampered.face_index=999999
	check("out of range face rejected",not roads.resolve_source_hit(tampered).ok)
	tampered=native_hit.duplicate();tampered.shape=999
	check("foreign shape index rejected",not roads.resolve_source_hit(tampered).ok)
	var collider:StaticBody3D=native_hit.collider
	collider.collision_layer=0
	check("disabled body invalidates old hit immediately",not roads.resolve_source_hit(native_hit).ok)
	collider.collision_layer=1
	var shape:CollisionShape3D=collider.get_child(0);var original_shape:Shape3D=shape.shape
	shape.shape=original_shape.duplicate()
	check("replacement shape invalidates source mapping",not roads.resolve_source_hit(native_hit).ok)
	shape.shape=original_shape
	var changed_faces:PackedVector3Array=original_shape.get_faces();changed_faces[0].x+=.025
	original_shape.set_faces(changed_faces);await frames(2)
	check("same-resource topology mutation invalidates original-way mapping",not roads.resolve_source_hit(native_hit).ok)
	batched.node.queue_free();await frames(5)
	check("freed native body cannot resolve stale source",not roads.resolve_source_hit(native_hit).ok)
	var split:Dictionary=roads.build_physical(plan.plan,self,null,{"collision_mode":"static_batches","faces_per_body":8})
	if not check("one original road splits across bounded bodies",split.ok and split.collision_body_count>5):finish();return
	await frames(5)
	check("split representation still preserves every exact triangle",_faces(split.node).to_byte_array()==original_faces.to_byte_array())
	for probe:Dictionary in probes:
		var hit:=ray(probe.from,probe.to);var source:=roads.resolve_source_hit(hit)
		check("split shape native face retains source way",source.get("ok",false) and source.source_way==probe.way,str(source))
	metrics["representations"]={"default_bodies":before.collision_body_count,"batch_bodies":batched.collision_body_count,"split_bodies":split.collision_body_count,"faces":original_faces.size()/3,"native_probes":probes.size(),"actual_country_route":false}
	finish()
