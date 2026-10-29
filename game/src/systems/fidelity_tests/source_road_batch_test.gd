extends "res://src/systems/fidelity_tests/source_roads_test.gd"
## Exact representation parity and native original-way lookup, synthetic fixture.
func _bodies(holder: Node3D) -> Array[StaticBody3D]:
	var result:Array[StaticBody3D]=[]
	for child:Node in holder.get_children():
		if child is StaticBody3D:result.append(child)
	return result

func _snapshot(holder:Node3D,roads:RefCounted)->Dictionary:
	# Read the installed PhysicsServer shapes AND their real native transforms.
	# Per-source face identity survives differing anchors and split bodies.
	var result:Dictionary={};var registry:Dictionary=roads.get("_collision_batches")
	for body:StaticBody3D in _bodies(holder):
		var pose:Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		for shape_index in PhysicsServer3D.body_get_shape_count(body.get_rid()):
			var rid:RID=PhysicsServer3D.body_get_shape(body.get_rid(),shape_index)
			var raw:Variant=PhysicsServer3D.shape_get_data(rid)
			if not check("actual server concave face data available",raw is Dictionary and raw.get("faces") is PackedVector3Array and not raw.get("backface_collision",true)):return {}
			var faces:PackedVector3Array=raw.faces
			var shape_pose:Transform3D=PhysicsServer3D.body_get_shape_transform(body.get_rid(),shape_index)
			var native:Transform3D=pose*shape_pose
			var ranges:Array=[];var anchor:Array=[]
			if body.has_meta("source_way"):
				ranges=[{"source_way":body.get_meta("source_way"),"first_face":0,"face_count":faces.size()/3,"source_first_face":0}]
				anchor=body.get_meta("source_anchor_xyz")
			else:
				if not check("batch has exact owned source ranges",registry.has(body.get_instance_id())):return {}
				ranges=registry[body.get_instance_id()].ranges
				anchor=registry[body.get_instance_id()].anchor_source_xyz
			for row:Dictionary in ranges:
				for index in int(row.face_count):
					var first:int=(int(row.first_face)+index)*3
					var local:=PackedVector3Array([faces[first],faces[first+1],faces[first+2]])
					var world:=PackedVector3Array([native*local[0],native*local[1],native*local[2]])
					var key:String=String(row.source_way)+"/"+str(int(row.source_first_face)+index)
					if result.has(key):check("source face is unique in installed part",false,key);return {}
					result[key]={"local_bytes":local.to_byte_array(),"transformed_bytes":world.to_byte_array(),"native_transform":native,"anchor":anchor.duplicate()}
	return result

func _visual(holder:Node3D)->Dictionary:
	var result:Dictionary={}
	for child:Node in holder.get_children():
		if child is MeshInstance3D:
			var key:String=JSON.stringify(child.get_meta("source_anchor_xyz"),"",true,true)
			var arrays:Array=child.mesh.surface_get_arrays(0)
			result[key]={"transform":child.global_transform,"vertices":arrays[Mesh.ARRAY_VERTEX],"normals":arrays[Mesh.ARRAY_NORMAL],"uv":arrays[Mesh.ARRAY_TEX_UV],"indices":arrays[Mesh.ARRAY_INDEX],"source_names":child.get_meta("actual_source_way_names").duplicate()}
	return result

func _distinct_anchor_case(roads:RefCounted,original:Dictionary)->bool:
	# Explicit SYNTHETIC alternate encoding. Canonical fixture points stay the
	# same; default and batched paths receive the identical new local encoding.
	var plan:Dictionary=original.duplicate(true)
	var offsets:Array=[-64.0,0.0,64.0,16.0,128.0]
	var canonical_unchanged:=true
	for index in plan.data.features.size():
		var feature:Dictionary=plan.data.features[index];var shift:float=offsets[index]
		var old_anchor:float=feature.anchor_source_xyz[0]
		feature.anchor_source_xyz[0]=old_anchor+shift
		for vertex:Array in feature.mesh.vertices_local_xyz:
			var canonical:float=old_anchor+float(vertex[0])
			vertex[0]=float(vertex[0])-shift
			canonical_unchanged=canonical_unchanged and canonical==float(feature.anchor_source_xyz[0])+float(vertex[0])
	if not check("synthetic anchor recoding preserves exact canonical XZ/Y",canonical_unchanged):return false
	_resign(plan)
	var baseline:Dictionary=roads.build_physical(plan,self)
	if not check("distinct synthetic anchors build default bodies",baseline.ok and baseline.anchor_groups==5 and baseline.collision_body_count==5):return false
	await frames(5)
	var expected:Dictionary=_snapshot(baseline.node,roads);var visuals:Dictionary=_visual(baseline.node)
	baseline.node.queue_free();await frames(5)
	var batch:Dictionary=roads.build_physical(plan,self,null,{"collision_mode":"static_batches"})
	if not check("different anchors are never flattened into one body",batch.ok and batch.anchor_groups==5 and batch.collision_body_count==5):return false
	await frames(5)
	var actual:Dictionary=_snapshot(batch.node,roads)
	check("distinct-anchor per-source native faces and transforms exactly match",not expected.is_empty() and actual==expected)
	check("distinct-anchor visual arrays and transforms exactly match",visuals.size()==5 and _visual(batch.node)==visuals)
	metrics["distinct_anchor_representation"]={"anchor_groups":batch.anchor_groups,"bodies":batch.collision_body_count,"per_source_native_faces":actual.size(),"synthetic_reencoding_only":true,"original_production_artifacts_changed":false}
	batch.node.queue_free();await frames(5)
	return failures.is_empty()

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
	var original_faces:Dictionary=_snapshot(before.node,roads);var original_visual:Dictionary=_visual(before.node)
	var probes:Array[Dictionary]=[]
	for pair:Array in [[Vector3(25,20,0),Vector3(25,-2,0)],[Vector3(25,5,0),Vector3(25,-2,0)],[Vector3(-80,15,0),Vector3(-80,-5,0)],[Vector3(130,15,0),Vector3(130,-5,0)],[Vector3(200,15,220),Vector3(200,-5,220)]]:
		var hit:=ray(pair[0],pair[1])
		if not check("default native original-way probe hits",not hit.is_empty()):finish();return
		probes.append({"from":pair[0],"to":pair[1],"way":hit.collider.get_meta("source_way"),"position":hit.position,"normal":hit.normal})
	before.node.queue_free();await frames(5)
	var batched:Dictionary=roads.build_physical(plan.plan,self,null,{"collision_mode":"static_batches"})
	if not check("bounded aggregate representation commits",batched.ok and batched.collision_body_count<5):finish();return
	await frames(5)
	var actual_faces:Dictionary=_snapshot(batched.node,roads)
	check("per-source native local/transformed triangles and anchors are exact",not original_faces.is_empty() and actual_faces==original_faces)
	check("all anchor visual arrays and transforms unchanged",not original_visual.is_empty() and _visual(batched.node)==original_visual)
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
	check("split representation preserves each exact source face and native transform",_snapshot(split.node,roads)==original_faces)
	for probe:Dictionary in probes:
		var hit:=ray(probe.from,probe.to);var source:=roads.resolve_source_hit(hit)
		check("split shape native face retains source way",source.get("ok",false) and source.source_way==probe.way,str(source))
	metrics["representations"]={"default_bodies":before.collision_body_count,"batch_bodies":batched.collision_body_count,"split_bodies":split.collision_body_count,"faces":original_faces.size(),"native_probes":probes.size(),"actual_country_route":false}
	split.node.queue_free();await frames(5)
	if not await _distinct_anchor_case(roads,plan.plan):finish();return
	finish()
