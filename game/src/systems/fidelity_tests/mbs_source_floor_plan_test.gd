extends Node
## Bounded source allocation validation. No native room/world construction claim.
const Planner=preload("res://src/world/mbs_interior/source_floor_plan.gd")
const Inventory=preload("res://src/world/mbs_interior/inventory.gd")
var checks:int=0
var failures:Array[String]=[]
var result:Dictionary={}

func check(label:String,condition:bool,detail:Variant="")->void:
	checks+=1;print("[mbs-source-floor-plan] ","PASS " if condition else "FAIL ",label," ",str(detail))
	if not condition:failures.append(label)

func _ready()->void:run.call_deferred()

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var at:int=args.find("--allocation-plan")
	if at<0 or at+1>=args.size():check("explicit allocation artifact supplied",false);finish();return
	var path:String=args[at+1]
	if not path.is_absolute_path() or not FileAccess.file_exists(path):check("owned explicit allocation file exists",false);finish();return
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:check("allocation JSON parses",false);finish();return
	var document:Dictionary=parsed
	var planner=Planner.new();result=planner.configure(document)
	check("complete actual source-envelope allocation validates",result.get("configured",false),result)
	if not result.get("configured",false):finish();return
	check("all1850 rooms and775 suites retained",result.rooms==1850 and result.suites==775)
	check("every original159 guest floor remains occupied",result.guest_floor_count==159 and result.all_original_guest_floors_occupied)
	check("no cross-tower shuffle required",result.cross_tower_reconstructed_relocations==0)
	check("documented same-tower relocations match",result.explicit_relocated_rooms==176)
	check("all57 program records retained without geometry claim",result.program_floor_records_retained==57 and not result.program_floor_geometry_planned)
	var unique:Dictionary={};var billiards:int=0;var media:int=0;var resized:int=0
	for id:String in Inventory.guest_floor_ids():
		var plan:Dictionary=planner.floor_plan(id)
		check("real floor plan "+id,plan.get("valid",false) and plan.source_own_axes_required and plan.exterior_face_owner=="persistent_shell" and plan.core_support_owner=="source_core_geometry")
		for room:Dictionary in plan.rooms:
			unique[room.id]=true
			billiards+=int(room.unit.entertainment=="billiards");media+=int(room.unit.entertainment=="media")
			resized+=int(room.explicit_relayout_not_legacy_dimensions and room.has("old_prototype_dimensions"))
	check("all private program identities retrievable",unique.size()==1850 and billiards==268 and media==267 and resized==1850)
	check("roof program cannot be relabelled a finished guest plan",not planner.floor_plan("T1-L57").get("valid",true))
	check("same planner cannot silently replace owned allocation",not planner.configure(document).get("configured",true))
	var first:String=Inventory.guest_floor_ids()[0]
	var bad:Dictionary=document.duplicate(true);bad.floors[first].rooms.pop_back()
	check("removed room rejected",not Planner.new().configure(bad).get("configured",true))
	bad=document.duplicate(true);bad.floors[first].rooms.append(bad.floors[first].rooms[0].duplicate(true))
	check("duplicate room rejected",not Planner.new().configure(bad).get("configured",true))
	bad=document.duplicate(true);bad.floors[first].rooms[0].footprint_own_xz=bad.floors[first].core_bank_polygon.duplicate(true)
	check("room crossing physical core rejected",not Planner.new().configure(bad).get("configured",true))
	bad=document.duplicate(true);bad.floors[first].rooms[0].unit.bedrooms=3
	check("changed original private inventory rejected",not Planner.new().configure(bad).get("configured",true))
	bad=document.duplicate(true);bad.floors[first].source_ceiling_polygon[0][0]+=.2
	check("stale or altered source profile rejected",not Planner.new().configure(bad).get("configured",true))
	bad=document.duplicate(true);bad.floors[first].rooms[0].frontage_own_axis=[2.0,0.0];bad.floors[first].rooms[0].into_room_own_axis=[0.0,.5]
	check("determinant-one anisotropic compression rejected",not Planner.new().configure(bad).get("configured",true))
	bad=document.duplicate(true);bad.program_records_retained_for_separate_source_polygon_planning.pop_back()
	check("missing public service or resort program rejected",not Planner.new().configure(bad).get("configured",true))
	bad=document.duplicate(true)
	var changed:bool=false
	for id:String in bad.floors:
		for room:Dictionary in bad.floors[id].rooms:
			if room.unit.entertainment=="billiards" and not changed:
				room.profile.depth_m=8.0;changed=true
	check("full-size billiards program cannot be shrunk away",changed and not Planner.new().configure(bad).get("configured",true))
	finish()

func finish()->void:
	print("[mbs-source-floor-plan] RESULT ",JSON.stringify({"checks":checks,"failures":failures,"allocation":result,"scope":"Actual Godot planner parsing, source polygon operations and complete room/program allocation validation. No floor geometry installation, native room/corridor/door traversal, furniture interaction, rendered or whole-building acceptance."}))
	get_tree().quit(0 if failures.is_empty() else 1)
