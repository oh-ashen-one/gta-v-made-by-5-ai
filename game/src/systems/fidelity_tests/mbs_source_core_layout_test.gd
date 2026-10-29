extends Node3D
## Native geometry-construction fixture. No actor motion, integration or render proof.
const CoreLayout=preload("res://src/world/mbs_interior/source_core_layout.gd")
const Exterior=preload("res://src/world/mbs_interior/exterior_shell.gd")
const Cabin=preload("res://src/world/mbs_interior/cabins.gd")
var checks:int=0
var failures:Array[String]=[]
var metrics:Dictionary={}

func check(label:String,condition:bool,detail:Variant="")->void:
	checks+=1
	print("[mbs-source-core] ","PASS " if condition else "FAIL ",label," ",str(detail))
	if not condition:failures.append(label)

func _ready()->void:
	run.call_deferred()

func _closed_receiver(_id:String)->Dictionary:
	return {"ready":false,"reason":"Isolated packing fixture has no receiving floor installed."}

func _inside(point:Vector3,polygon:Array)->bool:
	var vertices:=PackedVector2Array()
	for p:Array in polygon:vertices.append(Vector2(p[0],p[1]))
	return Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),vertices)

func _shapes(node:Node)->Array[CollisionShape3D]:
	var result:Array[CollisionShape3D]=[]
	for child:Node in node.get_children():
		if child is CollisionShape3D and not child.disabled and child.get_parent() is PhysicsBody3D:result.append(child)
		result.append_array(_shapes(child))
	return result

func run()->void:
	var plan:Dictionary=Exterior.reference_plan()
	check("reference shell and complete core contract parse",plan.get("valid",false),plan.get("error",""))
	if not plan.get("valid",false):finish();return
	check("physical shell remains disabled before caller integration",not plan.collision_enabled and not plan.interior_factory_alignment_verified)
	check("unknown tower fails closed",not CoreLayout.for_tower("T4").get("valid",true))
	for tower:Dictionary in plan.towers:
		var layout:Dictionary=CoreLayout.for_tower(tower.tower)
		check(tower.tower+" retains all six cores",layout.components.size()==6 and layout.required_core_aliases_preserved)
		var parent:=Node3D.new();parent.name=tower.tower+"PackingFixture";add_child(parent)
		# Real tower orientation; origin stays local to this isolated fixture.
		var u:Array=tower.axis_south
		parent.basis=Basis(Vector3.UP,atan2(-float(u[1]),float(u[0])))
		var bindings:Array=[]
		for component:Dictionary in layout.components:
			if component.kind!="lift":continue
			var lift:=Cabin.new();parent.add_child(lift)
			var kind:String="service_lift" if component.legacy_core_alias.ends_with("service_lift") else "guest_lift"
			var stops:Array=[]
			for level:int in 2:stops.append({"floor_id":tower.tower+"-fixture-"+str(level),"elevation_m":float(level)*3.45,"label":"Packing fixture "+str(level),"portal_id":component.id+"-"+str(level),"kind":kind,"height_status":"EXPLICIT_ISOLATED_FIXTURE_NOT_ACTUAL_FLOOR"})
			var descriptor:Dictionary={"schema":Cabin.SCHEMA,"shaft_id":component.id,"center_xz":component.own_cabin_center_xz,"entry_sign":component.entry_sign,"initial_floor_id":stops[0].floor_id,"stops":stops,"speed_mps":2.0,"acceleration_mps2":1.25}
			var built:Dictionary=lift.build(descriptor,_closed_receiver)
			check(component.id+" actual production shaft builds",built.get("built",false),built.get("error",""))
			bindings.append({"lift":lift,"component":component})
		for tick in 4:await get_tree().physics_frame
		var shape_count:int=0
		for binding:Dictionary in bindings:
			var lift:Node3D=binding.lift;var component:Dictionary=binding.component
			var native_fit:bool=true;var detail:Array=[]
			for shape:CollisionShape3D in _shapes(lift):
				if not shape.shape is BoxShape3D:continue
				shape_count+=1
				var body:PhysicsBody3D=shape.get_parent()
				var actual:Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
				actual=parent.global_transform.affine_inverse()*actual*shape.transform
				var half:Vector3=(shape.shape as BoxShape3D).size*.5
				for x:float in [-half.x,half.x]:
					for y:float in [-half.y,half.y]:
						for z:float in [-half.z,half.z]:
							var point:Vector3=actual*Vector3(x,y,z)
							if not _inside(point,component.own_operational_polygon):native_fit=false;detail.append({"body":body.name,"shape":shape.name,"point":point})
			check(component.id+" real native collision fits reserved operational polygon",native_fit,detail)
		var capsule:=CapsuleShape3D.new();capsule.radius=.36;capsule.height=1.75
		var clear:bool=true;var obstructions:Array=[]
		for index in 56:
			var x:float=-13.75+index*.5
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=1;query.margin=.02
			query.transform=parent.global_transform*Transform3D(Basis.IDENTITY,Vector3(x,1.0,float(layout.own_center_xz[1])-2.20))
			var hits:Array=get_world_3d().direct_space_state.intersect_shape(query,16)
			if not hits.is_empty():clear=false;obstructions.append({"x":x,"hit_count":hits.size()})
		check(tower.tower+" full production-size capsule clear along shared hall",clear,obstructions)
		metrics[tower.tower]={"actual_native_box_shapes":shape_count,"hall_capsule_samples":56,"native_lifts_built":bindings.size(),"stairs_installed":false,"receiving_floors_installed":false}
		parent.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame
	finish()

func finish()->void:
	var report:Dictionary={"checks":checks,"failures":failures,"metrics":metrics,"scope":"Production cabin closed-pose native shape containment and hall capsule clearance for three source-oriented core banks. Stairs/receiving floors/moving gates/room layout/traversal/source installation/rendering remain unverified."}
	print("[mbs-source-core] RESULT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
