extends SceneTree
# Offline motion-only retarget. No provider geometry is exported.
const SOURCE := "res://assets/animations/quaternius/UAL1_Standard.glb"
const TARGET := "res://assets/providers/player_rigged.glb"
const MAP := {"root":"root","pelvis":"pelvis","spine":"spine_01","chest":"spine_03","neck":"neck_01","head":"Head","clavicle.l":"clavicle_l","upper_arm.l":"upperarm_l","forearm.l":"lowerarm_l","hand.l":"hand_l","clavicle.r":"clavicle_r","upper_arm.r":"upperarm_r","forearm.r":"lowerarm_r","hand.r":"hand_r","thigh.l":"thigh_l","shin.l":"calf_l","foot.l":"foot_l","toe.l":"ball_l","thigh.r":"thigh_r","shin.r":"calf_r","foot.r":"foot_r","toe.r":"ball_r"}
func find_kind(node: Node, kind: String) -> Node:
	if node.is_class(kind): return node
	for child in node.get_children():
		var found:=find_kind(child,kind)
		if found: return found
	return null
const CHILD := {"pelvis":"spine","spine":"chest","chest":"neck","neck":"head","clavicle.l":"upper_arm.l","upper_arm.l":"forearm.l","forearm.l":"hand.l","clavicle.r":"upper_arm.r","upper_arm.r":"forearm.r","forearm.r":"hand.r","thigh.l":"shin.l","shin.l":"foot.l","foot.l":"toe.l","thigh.r":"shin.r","shin.r":"foot.r","foot.r":"toe.r"}
func body_frame(sk: Skeleton3D, left: String, right: String, head: String, hip: String) -> Basis:
	var x: Vector3=(sk.get_bone_global_rest(sk.find_bone(right)).origin-sk.get_bone_global_rest(sk.find_bone(left)).origin).normalized()
	var y: Vector3=(sk.get_bone_global_rest(sk.find_bone(head)).origin-sk.get_bone_global_rest(sk.find_bone(hip)).origin).normalized()
	var z:=x.cross(y).normalized()
	return Basis(x,z.cross(x).normalized(),z).orthonormalized()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var source: Node=load(SOURCE).instantiate(); root.add_child(source)
	var target: Node=load(TARGET).instantiate(); root.add_child(target)
	var ss:=find_kind(source,"Skeleton3D") as Skeleton3D
	var ts:=find_kind(target,"Skeleton3D") as Skeleton3D
	var sa:=find_kind(source,"AnimationPlayer") as AnimationPlayer
	var ta:=find_kind(target,"AnimationPlayer") as AnimationPlayer
	var path: String=String(ta.get_node(ta.root_node).get_path_to(ts))
	var library:=AnimationLibrary.new()
	var source_frame:=body_frame(ss,"upperarm_l","upperarm_r","Head","pelvis")
	var target_frame:=body_frame(ts,"upper_arm.l","upper_arm.r","head","pelvis")
	var frame_rotation: Quaternion=(target_frame*source_frame.inverse()).get_rotation_quaternion()
	var alignments: Dictionary={}
	for bone in CHILD:
		var target_dir:=ts.get_bone_global_rest(ts.find_bone(CHILD[bone])).origin-ts.get_bone_global_rest(ts.find_bone(bone)).origin
		var source_dir:=ss.get_bone_global_rest(ss.find_bone(MAP[CHILD[bone]])).origin-ss.get_bone_global_rest(ss.find_bone(MAP[bone])).origin
		alignments[bone]=Quaternion(target_dir.normalized(),(frame_rotation*source_dir).normalized())
		if bone.begins_with("upper_arm"):print("REST_ALIGNMENT ",bone," degrees=",rad_to_deg(alignments[bone].get_angle()))
	var scale_ratio: float=(ts.get_bone_global_rest(ts.find_bone("head")).origin-ts.get_bone_global_rest(ts.find_bone("pelvis")).origin).length()/(ss.get_bone_global_rest(ss.find_bone("Head")).origin-ss.get_bone_global_rest(ss.find_bone("pelvis")).origin).length()
	var bone_order: Array[int]=[]
	# Parent-first order is not guaranteed by file indices.
	while bone_order.size()<ts.get_bone_count():
		for b in ts.get_bone_count():
			if b not in bone_order and (ts.get_bone_parent(b)<0 or ts.get_bone_parent(b) in bone_order):bone_order.append(b)
	for pair in [["walk","Walk_Loop"],["run","Jog_Fwd_Loop"],["sprint","Sprint_Loop"]]:
		var clip_name: String=""
		for name in sa.get_animation_list():
			if String(name).to_lower().trim_suffix("_loop")==String(pair[1]).to_lower().trim_suffix("_loop"):clip_name=name
		if clip_name.is_empty():
			print("MISSING_CLIP ",pair[1]," available=",sa.get_animation_list());quit(1);return
		var original:=sa.get_animation(clip_name)
		var baked:=Animation.new(); baked.length=original.length; baked.loop_mode=Animation.LOOP_LINEAR
		var tracks: Dictionary={}
		var positions: Dictionary={}
		for b in bone_order:
			var name:=ts.get_bone_name(b)
			if not MAP.has(name) or name=="root":continue
			var track:=baked.add_track(Animation.TYPE_ROTATION_3D)
			baked.track_set_path(track,NodePath(path+":"+name));tracks[b]=track
			var position_track:=baked.add_track(Animation.TYPE_POSITION_3D)
			baked.track_set_path(position_track,NodePath(path+":"+name));positions[b]=position_track
		var samples:=int(ceil(original.length*30))
		sa.play(clip_name)
		for frame in samples+1:
			var t:=minf(float(frame)/30.0,original.length)
			sa.seek(0.0 if frame==samples else t,true)
			ss.force_update_all_bone_transforms()
			var world_rot: Dictionary={}
			for b in bone_order:
				var name:=ts.get_bone_name(b)
				var rest:=ts.get_bone_global_rest(b).basis.get_rotation_quaternion()
				var desired:=rest
				if tracks.has(b):
					var sb:=ss.find_bone(MAP[name]);assert(sb>=0)
					var source_rest:=ss.get_bone_global_rest(sb).basis.get_rotation_quaternion()
					var source_pose:=ss.get_bone_global_pose(sb).basis.get_rotation_quaternion()
					var delta: Quaternion=frame_rotation*source_pose*source_rest.inverse()*frame_rotation.inverse()
					desired=delta*(alignments.get(name,Quaternion.IDENTITY) as Quaternion)*rest
				world_rot[b]=desired
				if tracks.has(b):
					var parent:=ts.get_bone_parent(b)
					var local: Quaternion=(world_rot[parent].inverse()*desired if parent>=0 else desired).normalized()
					baked.rotation_track_insert_key(tracks[b],t,local)
					var position: Vector3=ts.get_bone_rest(b).origin
					if name=="pelvis":
						var hip:=ss.find_bone("pelvis")
						var shift: Vector3=frame_rotation*(ss.get_bone_global_pose(hip).origin-ss.get_bone_global_rest(hip).origin)*scale_ratio
						# Retain vertical bob, never source root travel or lateral drift.
						var delta_y:=Vector3(0,shift.y,0)
						position+=ts.get_bone_global_rest(parent).basis.inverse()*delta_y if parent>=0 else delta_y
					baked.position_track_insert_key(positions[b],t,position)
		library.add_animation(pair[0],baked)
		print("RETARGET ",pair[0]," source=",clip_name," seconds=",baked.length," samples=",samples+1," bones=",tracks.size())
	var result:=ResourceSaver.save(library,"res://assets/animations/quaternius/player_locomotion.tres")
	print("RETARGET_RESULT ",result)
	source.queue_free();target.queue_free();quit(result)
