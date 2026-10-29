extends Node
## Capture-only startup health. A completed GPU viewport readback proves the
## first frame returned; it is not gameplay, visual-quality or FPS acceptance.
var nonce := ""

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name()=="headless" or nonce.is_empty():queue_free();return
	_confirm_frame.call_deferred()

func _confirm_frame() -> void:
	for attempt in 3:
		await RenderingServer.frame_post_draw
		var texture:ViewportTexture=get_viewport().get_texture()
		if texture==null:continue
		# This readback deliberately waits for the rendered pixels. If the GPU
		# wedges here, the separate bounded driver times out and pauses launches.
		var pixels:Image=texture.get_image()
		if pixels==null or pixels.is_empty() or Engine.get_frames_drawn()<=0:continue
		print("SINGAPORE_RENDER_FIRST_FRAME ",JSON.stringify({"pid":OS.get_process_id(),"nonce":nonce,"width":pixels.get_width(),"height":pixels.get_height(),"frames_drawn":Engine.get_frames_drawn(),"display_server":DisplayServer.get_name(),"gpu_readback_completed":true}))
		queue_free();return
	push_error("Rendered startup produced no readable frame after three draw signals")
	queue_free()
