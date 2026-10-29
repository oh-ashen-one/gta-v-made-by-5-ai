extends "res://src/systems/fidelity_tests/source_road_batch_test.gd"
## Five retained real-source precision failures. Actual native shapes/rays,
## not a CPU reproduction or country/terrain acceptance.
const ANCHOR_SHA := "fdd79d76c995496b1e7acfa7c7d6e64d7b5c48ebf7f1ab7b786f1e8cfec26d75"

func _directory()->String:
	return ProjectSettings.globalize_path("res://").path_join("../loop/singapore-fidelity/source-roads/typed-physical-fixtures/native-anchor-failures-r2").simplify_path()

func _vec(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _one_case(row:Dictionary,index:int,manifest:Dictionary,snapshot_sha:String)->bool:
	var frame:=Frame.new();var roads:=Roads.new()
	if not check("recorded exact source origin "+str(index),frame.configure(manifest.georeference,row.origin_source_xyz,snapshot_sha)):return false
	if not check("pinned unchanged real geometry fixture "+str(index),roads.configure(_directory(),ANCHOR_SHA,frame),roads.last_error):return false
	var prepared:Dictionary=roads.prepare_physical(row.part)
	if not check("exact failed source part prepares "+str(index),prepared.ok):return false
	var built:Dictionary=roads.build_physical(prepared.plan,self,null,{"collision_mode":"static_batches"})
	if not check("actual anchored source part commits without relaxed cap "+str(index),built.ok,str(built)):return false
	await frames(5)
	var native:Dictionary={};var expected_local:=PackedVector3Array()
	for point:Array in row.encoded_local_triangle:expected_local.append(_vec(point))
	var registry:Dictionary=roads.get("_collision_batches")
	for body:StaticBody3D in _bodies(built.node):
		var descriptor:Dictionary=registry[body.get_instance_id()]
		for range_row:Dictionary in descriptor.ranges:
			if range_row.source_way!=row.source_way:continue
			var source_index:int=row.worst_original_face_index
			if source_index<int(range_row.source_first_face) or source_index>=int(range_row.source_first_face)+int(range_row.face_count):continue
			var index_in_shape:int=int(range_row.first_face)+source_index-int(range_row.source_first_face)
			var shape_rid:RID=PhysicsServer3D.body_get_shape(body.get_rid(),0)
			var data:Variant=PhysicsServer3D.shape_get_data(shape_rid)
			if not check("server owns unmodified one-sided concave triangles "+str(index),data is Dictionary and data.get("faces") is PackedVector3Array and not data.get("backface_collision",true)):
				built.node.queue_free();await frames(5);return false
			var faces:PackedVector3Array=data.faces
			var local:=PackedVector3Array([faces[index_in_shape*3],faces[index_in_shape*3+1],faces[index_in_shape*3+2]])
			var pose:Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			var shape_pose:Transform3D=PhysicsServer3D.body_get_shape_transform(body.get_rid(),0)
			var projected:Dictionary=frame.to_local(row.encoded_anchor_source_xyz)
			check("native body translates exact projected anchor with unit basis "+str(index),pose==Transform3D(Basis.IDENTITY,projected.position) and shape_pose==Transform3D.IDENTITY,str(pose))
			check("actual server local worst triangle retains exact encoded bytes "+str(index),local.to_byte_array()==expected_local.to_byte_array())
			var cross:Vector3=(local[1]-local[0]).cross(local[2]-local[0])
			var normal:Vector3=-cross.normalized()
			var slope:float=INF if normal.y<=0 else Vector2(normal.x,normal.z).length()/normal.y
			check("native local worst face respects fixed class cap "+str(index),cross.y<0 and slope<=float(row.cap),str({"slope":slope,"cap":row.cap}))
			var world:=PackedVector3Array([pose*local[0],pose*local[1],pose*local[2]])
			var max_error:=0.0
			for vertex in 3:
				var canonical:Dictionary=frame.to_source_current_live(world[vertex])
				for axis in 3:max_error=maxf(max_error,absf(float(canonical.source_xyz[axis])-float(row.canonical_triangle[vertex][axis])))
			check("actual native transformed vertices retain source position within1mm encoding bound "+str(index),max_error<=.001,str(max_error))
			var recross:Vector3=(world[1]-world[0]).cross(world[2]-world[0])
			native={"body":body,"local":local,"pose":pose,"normal":normal,"native_local_slope":slope,"native_world_vertices":world,"source_position_error_m":max_error,"reflattened_world_slope_diagnostic_only":Vector2(recross.x,recross.z).length()/-recross.y if recross.y<0 else INF,"native_face_index":index_in_shape,"source_face_index":source_index}
	if not check("recorded actual source face found "+str(index),not native.is_empty()):built.node.queue_free();await frames(5);return false
	var ray_attempts:Array[Dictionary]=[];var confirmed:Dictionary={}
	for weights:Vector3 in [Vector3(1.0/3,1.0/3,1.0/3),Vector3(.50,.25,.25),Vector3(.25,.50,.25),Vector3(.25,.25,.50)]:
		var local:PackedVector3Array=native.local
		var at:Vector3=native.pose*(local[0]*weights.x+local[1]*weights.y+local[2]*weights.z)
		var hit:Dictionary=ray(at+Vector3.UP*.50,at-Vector3.UP*.50)
		var source:Dictionary=roads.resolve_source_hit(hit)
		var attempt:Dictionary={"barycentric_weights":weights,"ray_at":at,"native_hit_position":hit.get("position"),"native_hit_normal":hit.get("normal"),"source":source}
		ray_attempts.append(attempt)
		if source.get("ok",false) and source.source_way==row.source_way and source.source_face_index==row.worst_original_face_index and source.anchor_source_xyz==row.encoded_anchor_source_xyz:
			var slope:float=INF if hit.normal.y<=0 else Vector2(hit.normal.x,hit.normal.z).length()/hit.normal.y
			if slope<=float(row.cap) and (hit.normal as Vector3).dot(native.normal)>.99999:
				confirmed={"native_normal":hit.normal,"slope":slope,"source":source};break
	check("actual ray hits retained worst source face with correct native normal "+str(index),not confirmed.is_empty(),str(ray_attempts))
	var record:Dictionary={"case":index,"source_way":row.source_way,"part":row.part,"original_failure":row.duplicate(true),"native":native.duplicate(true),"ray_attempts":ray_attempts,"confirmed":confirmed}
	record.native.erase("body");metrics["precision_case_"+str(index)]=record
	built.node.queue_free();await frames(5)
	return failures.is_empty()

func run()->void:
	var raw:PackedByteArray=FileAccess.get_file_as_bytes(SNAPSHOT);var manifest:Dictionary=JSON.parse_string(raw.get_string_from_utf8())
	var document:Variant=JSON.parse_string(FileAccess.get_file_as_string(_directory().path_join("cases.json")))
	if not check("all five retained original failures are present",document is Dictionary and document.get("cases") is Array and document.cases.size()==5):finish();return
	for index in document.cases.size():
		await _one_case(document.cases[index],index,manifest,_sha(raw))
	metrics["scope"]="Five exact source-face precision fixtures; no altered caps, source geometry, global origin, native animation or complete source city claim. Reflattened world-triangle cross products are diagnostic, not a replacement for actual native ray normals."
	finish()
