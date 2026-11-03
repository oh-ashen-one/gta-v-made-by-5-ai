extends Node
# Asset-only CPU validation. Does not instantiate main.tscn or a game window.
var failures: Array[String]=[]
func check(label: String, passed: bool) -> void:
	print("HUMAN_CHECK ",label," ",passed)
	if not passed:failures.append(label)
func _ready() -> void:call_deferred("run")
func run() -> void:
	var holder:=Node3D.new();add_child(holder)
	var visual:=CharacterVisual.new();holder.add_child(visual)
	check("native_configure",visual.configure("player"))
	check("native_path_selected",visual.native_human)
	check("original_65_bone_rig",visual.skeleton.get_bone_count()==65)
	check("no_rebuilt_look_mesh",visual.look_mesh==null)
	check("no_custom_body_or_foot_modifier",visual.motion==null and visual.foot_lock==null and visual.hands==null)
	for gait in ["idle","walk","run","sprint","jump","aim","aim_walk","aim_run","aim_back","seated","drive","reload","hit"]:
		check("clip_"+gait,visual._clips.has(gait))
		if not visual._clips.has(gait):continue
		var anim:=visual.animator.get_animation(visual._clips[gait])
		check("duration_"+gait,anim.length>0.2 and anim.length<20.0)
		for phase in [0.0,.25,.5,.75,.99]:
			visual.hold_pose(gait,phase)
			visual.skeleton.force_update_all_bone_transforms()
			var finite:=true
			for b in visual.skeleton.get_bone_count():
				var pose:=visual.skeleton.get_bone_global_pose(b)
				finite=finite and pose.origin.is_finite() and pose.basis.is_finite()
			check("finite_"+gait+"_"+str(phase),finite)
	visual.release_pose()
	visual.set_motion(3.6,false,true,false)
	check("controller_chooses_run",visual.current_clip()=="run")
	visual.set_motion(6.8,false,true,false)
	check("controller_chooses_sprint",visual.current_clip()=="sprint")
	var gun:=Node3D.new();holder.add_child(gun);visual.attach_weapon(gun,"pistol")
	check("no_old_aim_deformer",visual.skeleton.get_node_or_null("AimIkLayer")==null)
	check("weapon_scale_preserved",gun.global_transform.basis.get_scale().distance_to(Vector3.ONE)<.01)
	print("HUMAN_RESULT failures=",JSON.stringify(failures))
	holder.queue_free();get_tree().quit(0 if failures.is_empty() else 1)
