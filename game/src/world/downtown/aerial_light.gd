extends Node
## downtown-polish (wave S): altitude-aware sun shadows and froxel fog for the
## downtown aerial views (original; the idea follows the parked opus55/aerial
## AerialAtmosphere, re-written small and self-contained for the downtown).
##
## Critic standing gaps: "crisp tower shadows from one sun" and "aerial depth /
## haze layering". On the street the sun's shadow map covers 280 m and the
## 140 m volumetric-fog volume gives the five-foot-way sun shafts; from the
## helicopter that means towers beyond the first block cast nothing and a warm
## froxel veil flattens every pixel. As the active camera climbs from 30 to
## 80 m this blends the shadow range out to 1100 m (tighter first splits so
## the helicopter keeps a crisp shadow) and thins the froxel fog to a quarter,
## leaving the exponential fog / aerial perspective to grade the distance.
## The tower ground-shadow overlay (tower_shadows.gd) is pushed out past the
## real shadow range at the same time, so the two never stack. Street-level
## frames are untouched (blend 0 below 30 m).

const BLEND_LOW := 30.0
const BLEND_HIGH := 80.0
const AIR_SHADOW := 1100.0
const AIR_SPLITS := Vector3(0.025, 0.09, 0.32)
const AIR_VFOG_SCALE := 0.25
const OVERLAY_STRENGTH := 0.62

var env: Environment
var sun: DirectionalLight3D
var overlay: Array[ShaderMaterial] = []
var _g_dist := 280.0
var _g_splits := Vector3(0.05, 0.15, 0.4)
var _g_vfog := 0.0
var blend := -1.0

static func attach(w: WorldBuilder, overlay_mats: Array[ShaderMaterial]) -> Node:
	if "--aerial-light-off" in OS.get_cmdline_user_args():
		return null
	var we := w.find_child("GoldenHourEnvironment", true, false) as WorldEnvironment
	var sun_node := w.find_child("Sun", true, false) as DirectionalLight3D
	if we == null or we.environment == null or sun_node == null:
		return null
	var n: Node = load("res://src/world/downtown/aerial_light.gd").new()
	n.name = "DowntownAerialLight"
	n.env = we.environment
	n.sun = sun_node
	n.overlay = overlay_mats
	n._g_dist = sun_node.directional_shadow_max_distance
	n._g_splits = Vector3(sun_node.directional_shadow_split_1, sun_node.directional_shadow_split_2, sun_node.directional_shadow_split_3)
	n._g_vfog = we.environment.volumetric_fog_density
	w.add_child(n)
	return n

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or sun == null:
		return
	var b := smoothstep(BLEND_LOW, BLEND_HIGH, cam.global_position.y)
	if blend >= 0.0 and absf(b - blend) < 0.004:
		return
	blend = b
	sun.directional_shadow_max_distance = lerpf(_g_dist, AIR_SHADOW, b)
	sun.directional_shadow_split_1 = lerpf(_g_splits.x, AIR_SPLITS.x, b)
	sun.directional_shadow_split_2 = lerpf(_g_splits.y, AIR_SPLITS.y, b)
	sun.directional_shadow_split_3 = lerpf(_g_splits.z, AIR_SPLITS.z, b)
	env.volumetric_fog_density = lerpf(_g_vfog, _g_vfog * AIR_VFOG_SCALE, b)
	var reach := sun.directional_shadow_max_distance
	for m in overlay:
		m.set_shader_parameter("near_start", reach * 0.75)
		m.set_shader_parameter("near_end", reach * 1.07)
		# Integrator (wave S): from the air the real shadow map reaches 1.1 km
		# and the swept-footprint overlay beyond it only showed as torn dark
		# fragments between the CBD blocks and dark bands under the MBFC
		# podiums (critic downtown-polish-S1, photo_29 / dtx_heli_bayfront);
		# it fades out as the camera climbs and keeps the street-level views.
		m.set_shader_parameter("strength", OVERLAY_STRENGTH * (1.0 - b))
