extends "res://src/systems/fidelity_tests/source_roads_test.gd"
## Typed native component fixture. No country/terrain/route acceptance.
const TYPED_SHA := "db2ba665dc60d9cf3f839f9dc1f8b1191cbf6d13bcb3573b172a9979cdf1477b"

func _directory() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../loop/singapore-fidelity/source-roads/typed-physical-fixtures/native-contract-r1").simplify_path()

func _reject(roads:RefCounted,plan:Dictionary,label:String)->void:
	_resign(plan)
	var count:int=get_child_count()
	var result:Dictionary=roads.build_physical(plan,self,null,{"collision_mode":"static_batches"})
	check(label,not result.get("ok",false) and get_child_count()==count,str(result))

func _manifest_fixture(label:String,base:Dictionary,rows:Array)->Dictionary:
	var folder:String=qa_session.path_join("manifest-"+label)
	if DirAccess.make_dir_absolute(folder)!=OK:return {}
	var manifest:Dictionary=base.duplicate(true);manifest.physical_tiles=rows
	var raw:PackedByteArray=JSON.stringify(manifest,"",true,true).to_utf8_buffer()
	var file:=FileAccess.open(folder.path_join("manifest.json"),FileAccess.WRITE)
	if file==null:return {}
	file.store_buffer(raw);file.close()
	var identity:Dictionary={"schema":Roads.IDENTITY,"version":6,"snapshot_manifest_sha256":manifest.snapshot_manifest_sha256,"manifest":{"file":"manifest.json","bytes":raw.size(),"sha256":_sha(raw)}}
	var iraw:PackedByteArray=JSON.stringify(identity,"",true,true).to_utf8_buffer()
	file=FileAccess.open(folder.path_join("identity.json"),FileAccess.WRITE)
	if file==null:return {}
	file.store_buffer(iraw);file.close()
	return {"folder":folder,"sha256":_sha(iraw)}

func _parts(frame:RefCounted)->bool:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(_directory().path_join("manifest.json")))
	var row:Dictionary=manifest.physical_tiles[0]
	var valid:Array=[]
	for part in 2:
		var one:Dictionary=row.duplicate(true);one.tile="0_0.p%03d"%part;one.spatial_tile_key="0_0";valid.append(one)
	var cases:Dictionary={"gap":[0,2],"missing_zero":[1],"malformed":[0],"signed_zero":[0],"mixed":[0,1],"missing_cell":[0]}
	for label:String in cases:
		var rows:Array=[]
		for part:int in cases[label]:
			var one:Dictionary=row.duplicate(true);one.tile="0_0.p%03d"%part;one.spatial_tile_key="0_0";rows.append(one)
		if label=="malformed":rows[0].tile="0_0.pbad"
		if label=="signed_zero":rows[0].tile="0_0.p+00"
		if label=="mixed":rows[0].tile="0_0"
		if label=="missing_cell":rows[0].erase("spatial_tile_key")
		var fixture:Dictionary=_manifest_fixture(label,manifest,rows)
		if not check("private manifest-negative fixture writes "+label,not fixture.is_empty()):return false
		check("part contract refuses "+label,not Roads.new().configure(fixture.folder,fixture.sha256,frame))
	var fixture:Dictionary=_manifest_fixture("contiguous",manifest,valid)
	if not check("private contiguous manifest fixture writes",not fixture.is_empty()):return false
	var loader:=Roads.new()
	if not check("contiguous explicit parts configure",loader.configure(fixture.folder,fixture.sha256,frame)):return false
	check("cell accessor returns EVERY sorted part",loader.physical_parts_for_cell(0,0)==["0_0.p000","0_0.p001"])
	check("manifest alone does not prove physical part availability",not loader.prepare_physical("0_0.p000").ok)
	metrics["part_scope"]="Manifest structural rejection/accessor only; no SourceWorld residency or full-cell acceptance inferred"
	return failures.is_empty()

func run()->void:
	var raw:PackedByteArray=FileAccess.get_file_as_bytes(SNAPSHOT);var manifest:Dictionary=JSON.parse_string(raw.get_string_from_utf8())
	var frame:=Frame.new();var roads:=Roads.new()
	if not check("actual uncompressed frame",frame.configure(manifest.georeference,[0.0,0.0,0.0],_sha(raw))):finish();return
	if not check("pinned synthetic typed artifact",roads.configure(_directory(),TYPED_SHA,frame),roads.last_error):finish();return
	var prepared:Dictionary=roads.prepare_physical("fixture")
	if not check("typed fixture prepares",prepared.ok):finish();return
	var plan:Dictionary=prepared.plan;var changed:Dictionary
	changed=plan.duplicate(true);changed.data.features[0].physical_contract.required_native_slope_cap=.702
	_reject(roads,changed,"file cannot grant car the step slope cap")
	changed=plan.duplicate(true);changed.data.features[0].physical_contract.maximum_emitted_slope=.701
	_reject(roads,changed,"file cannot enlarge emitted car slope contract")
	changed=plan.duplicate(true);changed.data.features[0].physical_contract.surface_class="foot_ribbon";changed.data.features[0].physical_contract.maximum_emitted_slope=.251;changed.data.features[0].physical_contract.required_native_slope_cap=.252
	_reject(roads,changed,"car-permitted source cannot masquerade as foot-only geometry")
	changed=plan.duplicate(true);changed.data.features[1].physical_contract.surface_class="car_ribbon";changed.data.features[1].physical_contract.maximum_emitted_slope=.121;changed.data.features[1].physical_contract.required_native_slope_cap=.122
	_reject(roads,changed,"foot-only source cannot masquerade as a car ribbon")
	changed=plan.duplicate(true);changed.data.features[1].physical_contract.source_foot_direction_bits=0
	_reject(roads,changed,"contract mode bits must equal actual source policy")
	changed=plan.duplicate(true);changed.data.features[3].source_tags.highway="footway"
	_reject(roads,changed,"visible steps require original steps source type")
	changed=plan.duplicate(true);changed.data.features[3].erase("visual_mesh")
	_reject(roads,changed,"steps without actual visible tread geometry refuse")
	changed=plan.duplicate(true);changed.data.features[0].visual_mesh=changed.data.features[0].mesh.duplicate(true)
	_reject(roads,changed,"ordinary car cannot substitute a separate visual mesh")
	changed=plan.duplicate(true);changed.data.features[0].mesh.vertices_local_xyz[0][1]+=20.0
	_reject(roads,changed,"actual car triangle slope cannot hide behind valid shader normals")
	changed=plan.duplicate(true);var first:int=changed.data.features[3].visual_mesh.indices[0];changed.data.features[3].visual_mesh.indices[0]=changed.data.features[3].visual_mesh.indices[1];changed.data.features[3].visual_mesh.indices[1]=first
	_reject(roads,changed,"reversed visible riser or tread winding refuses")
	if not _parts(frame):finish();return
	var built:Dictionary=roads.build_physical(plan,self,null,{"collision_mode":"static_batches"})
	if not check("all fixed surface classes commit at shared unchanged anchor",built.ok and built.features==5 and built.anchor_groups==1 and built.collision_body_count==1,str(built)):finish();return
	await frames(5)
	var above:Dictionary=ray(Vector3(0,7,0),Vector3(0,5,0));var below:Dictionary=ray(Vector3(0,1,0),Vector3(0,-1,0))
	check("actual footbridge remains6m above crossing car surface",not above.is_empty() and not below.is_empty() and absf(above.position.y-6.0)<.005 and absf(below.position.y)<.005)
	for entry:Dictionary in [{"hit":above,"id":"fixture/foot_crossing","class":"foot_ribbon","cap":.252},{"hit":below,"id":"fixture/car_flat","class":"car_ribbon","cap":.122},{"hit":ray(Vector3(0,3,20),Vector3(0,0,20)),"id":"fixture/foot_slope","class":"foot_ribbon","cap":.252},{"hit":ray(Vector3(-7.5,3,-20),Vector3(-7.5,-1,-20)),"id":"fixture/steps_up","class":"foot_steps","cap":.702},{"hit":ray(Vector3(7.5,3,-20),Vector3(7.5,-1,-20)),"id":"fixture/steps_down","class":"foot_steps","cap":.702}]:
		var hit:Dictionary=entry.hit;var source:Dictionary=roads.resolve_source_hit(hit)
		var slope:float=INF if hit.is_empty() or hit.normal.y<=0 else Vector2(hit.normal.x,hit.normal.z).length()/hit.normal.y
		check("native face retains original source class "+entry.id,source.get("ok",false) and source.source_way==entry.id and source.surface_class==entry["class"] and slope<=entry.cap,str(source))
		metrics[entry.id]={"source":source,"actual_ray_normal":hit.get("normal"),"actual_ray_slope":slope}
	var visual_faces:=0;var collision_faces:=0;var vertical_faces:=0
	for child:Node in built.node.get_children():
		if child is MeshInstance3D:
			var faces:PackedVector3Array=child.mesh.get_faces();visual_faces+=faces.size()/3
			for i in range(0,faces.size(),3):
				var n:Vector3=(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).normalized()
				if absf(n.y)<.0001:vertical_faces+=1
		if child is StaticBody3D:
			for i in PhysicsServer3D.body_get_shape_count(child.get_rid()):
				var data:Variant=PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(child.get_rid(),i))
				if data is Dictionary and data.get("faces") is PackedVector3Array:collision_faces+=data.faces.size()/3
	check("both ten-step fixtures have actual separate visible risers",vertical_faces==40 and visual_faces==built.visible_faces and collision_faces==built.collision_faces and visual_faces>collision_faces,str({"visual":visual_faces,"collision":collision_faces,"vertical":vertical_faces}))
	metrics["scope"]="Synthetic native types/crossing/visible steps and manifest guards; not original country meshes, terrain or walking/animation proof"
	finish()
