extends Node3D
## Neutral turntable evidence for the retained provider assets; not gameplay.
var out_dir := "../docs/wave-02/assets"
var asset: Node3D
var cam: Camera3D
var report: Array = []
var asset_files := ["sedan_clean.glb", "coupe_clean.glb", "van_clean.glb", "helicopter_clean.glb", "player_clean.glb", "officer_clean.glb", "shophouse_clean.glb", "hdb_slab_clean.glb", "hawker_counter_clean.glb", "hawker_table_clean.glb", "food_trolley_clean.glb", "ac_unit_clean.glb", "street_lamp_clean.glb", "service_clutter_clean.glb", "planter_clean.glb", "pistol_clean.glb", "smg_clean.glb", "airfield_clutter_clean.glb"]
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): out_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.15,.18,.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.7,.8,1)
	env.ambient_light_energy = .5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	var we := WorldEnvironment.new(); we.environment=env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); sun.light_energy=1.3; sun.shadow_enabled=true; add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees=Vector3(-30,135,0); fill.light_energy=.35; add_child(fill)
	cam=Camera3D.new(); cam.fov=45; cam.current=true; add_child(cam)
	_run.call_deferred()
func _bounds(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform := parent_transform
	if node is Node3D: transform=parent_transform*node.transform
	var bounds := AABB()
	if node is MeshInstance3D: bounds=transform*node.get_aabb()
	for child in node.get_children():
		var child_bounds := _bounds(child,transform)
		if child_bounds.size.length() > 0:
			bounds = child_bounds if bounds.size.length()==0 else bounds.merge(child_bounds)
	return bounds
func _run() -> void:
	for file in asset_files:
		asset=AssetLibrary.instantiate(file,self)
		if asset==null: continue
		var bounds := _bounds(asset)
		var centre := bounds.get_center()
		var radius := maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		cam.far=maxf(200,radius*10)
		cam.near=.01
		for angle in 2:
			var direction := Vector3(1,.55,1) if angle==0 else Vector3(-1,.45,-1)
			cam.position=centre+direction.normalized()*radius*2.0
			cam.look_at(centre)
			await get_tree().create_timer(.3).timeout
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%d.png" % [out_dir,file.trim_suffix(".glb"),angle]
			get_viewport().get_texture().get_image().save_png(path)
			print("[asset-review] ",path)
		report.append({"asset":file,"size_m":[bounds.size.x,bounds.size.y,bounds.size.z],"note":"Neutral two-angle rendered inspection; per-asset rights verdict requires reviewer."})
		asset.queue_free()
		await get_tree().process_frame
	var f:=FileAccess.open(out_dir+"/asset-review.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t")); f.close()
	get_tree().quit()
