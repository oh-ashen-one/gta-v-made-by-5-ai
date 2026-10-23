class_name AerialAtmosphere
extends Node
## Altitude-aware atmosphere for the aerial views (aerial piece, Opus 5.5 wave D).
##
## Critics helicopter-C2 / lighting-A4 / skyline-1: from the air the district
## was flat and milky. Two street-tuned settings caused most of it:
##  - the sun's shadow map ended at 280 m, so from 100 m up nothing beyond the
##    first block cast a shadow and every tower stood unshadowed in flat light;
##  - the 140 m volumetric-fog froxel volume, tuned for sun shafts in the five-foot
##    ways, laid a warm ~12 % veil over every aerial pixel.
## This node watches the active camera's height every frame and blends both
## toward an aerial setting (long cascaded shadows, almost no froxel fog) as
## the camera climbs, and back again on the ground. Street-level frames are
## untouched (blend 0 below ~28 m).
##
## It also owns the procedural 3D noise volumes the cumulus sky marches
## through (generated once at startup, original, no external data).

const GROUND_SHADOW_RANGE := 280.0
const AIR_SHADOW_RANGE := 1300.0
const AIR_VFOG_DENSITY := 0.00012
const BLEND_LOW := 28.0
const BLEND_HIGH := 75.0

## Aerial perspective shared by every skyline-piece shader (pushed through
## SkylineHorizon.sync; the shader defaults match so the self-test can read them).
## Aerial R2: darker, thinner haze (critic aerial-R1: far band p5 193 / std 14
## read as a milky wash; GTA V far towers sit at p5 ~133 / std 26). A deeper
## blue-grey in-scatter capped lower keeps the 0.8-3 km towers as graded
## silhouettes instead of fading them into the horizon.
const HAZE := {
	"haze_col": Color(0.47, 0.54, 0.64),
	"haze_sun_col": Color(0.92, 0.76, 0.58),
	"haze_start": 220.0,
	"haze_density": 0.0015,
	"haze_max": 0.62,
}

## Fake ground-shadow materials of the background towers: they fade out
## inside the real shadow range so the two never stack.
static var fake_shadow_materials: Array[ShaderMaterial] = []
## Background towers / low-rise that cast real shadows only while the camera
## is airborne (aerial R2): on the street their real shadows darkened the
## heritage road, and the parent never had them there.
static var aerial_casters: Array[GeometryInstance3D] = []
const CASTER_BLEND := 0.05

var env: Environment
var sun: DirectionalLight3D
var ground_vfog := 0.0009
var blend := -1.0
static var _noise_cache: Array = []

static func attach(parent: Node, environment: Environment, sun_light: DirectionalLight3D) -> AerialAtmosphere:
	var a := AerialAtmosphere.new()
	a.name = "AerialAtmosphere"
	a.env = environment
	a.sun = sun_light
	a.ground_vfog = environment.volumetric_fog_density
	parent.add_child(a)
	return a

## Blend for a camera height (0 = street tuning, 1 = aerial tuning).
static func blend_for_height(y: float) -> float:
	var t := clampf((y - BLEND_LOW) / (BLEND_HIGH - BLEND_LOW), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp == null or env == null or sun == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	apply_blend(blend_for_height(cam.global_position.y))

func apply_blend(k: float) -> void:
	if absf(k - blend) < 0.004:
		return
	blend = k
	sun.directional_shadow_max_distance = lerpf(GROUND_SHADOW_RANGE, AIR_SHADOW_RANGE, k)
	# Keep ~the same near-cascade size on the ground; from the air the first
	# split still covers the helicopter and the block under it.
	sun.directional_shadow_split_1 = lerpf(0.05, 0.035, k)
	sun.directional_shadow_split_2 = lerpf(0.15, 0.11, k)
	sun.directional_shadow_split_3 = lerpf(0.40, 0.33, k)
	env.volumetric_fog_density = lerpf(ground_vfog, AIR_VFOG_DENSITY, k)
	var airborne := k > CASTER_BLEND
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if airborne else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for g in aerial_casters:
		if is_instance_valid(g):
			g.cast_shadow = mode
	# The fake ground shadows step aside only where real tower shadows exist.
	for m in fake_shadow_materials:
		if is_instance_valid(m):
			m.set_shader_parameter("real_shadow_range", sun.directional_shadow_max_distance if airborne else 0.0)

const GLASS_TEX := "res://assets/providers/higgsfield/tower_glass_bluegreen_albedo.png"
static var glass_materials := 0

## Aerial R1: give the background-city curtain walls (skyline facade
## materials with per-instance data) the generated `tower_glass_bluegreen`
## sheet when the private library is linked in; procedural glass otherwise.
static func apply_glass_library() -> int:
	glass_materials = 0
	if not ResourceLoader.exists(GLASS_TEX):
		return 0
	var tex := load(GLASS_TEX) as Texture2D
	if tex == null:
		return 0
	for m: ShaderMaterial in SkylineHorizon._materials:
		if m == null or m.shader == null or not m.shader.resource_path.ends_with("skyline_facade.gdshader"):
			continue
		if m.get_shader_parameter("use_instance_custom") != true:
			continue
		m.set_shader_parameter("glass_tex", tex)
		m.set_shader_parameter("glass_tex_amount", 0.8)
		glass_materials += 1
	return glass_materials

## Two tiling 64^3 noise volumes for the cumulus sky: Perlin fbm (cloud
## fields and billows) and inverted cellular fbm (round cumulus lobes).
static func cloud_noise() -> Array:
	if not _noise_cache.is_empty():
		return _noise_cache
	var per := FastNoiseLite.new()
	per.seed = 4127
	per.noise_type = FastNoiseLite.TYPE_PERLIN
	per.frequency = 1.0 / 16.0
	per.fractal_type = FastNoiseLite.FRACTAL_FBM
	per.fractal_octaves = 4
	var cel := FastNoiseLite.new()
	cel.seed = 9203
	cel.noise_type = FastNoiseLite.TYPE_CELLULAR
	cel.frequency = 1.0 / 12.0
	cel.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cel.fractal_type = FastNoiseLite.FRACTAL_FBM
	cel.fractal_octaves = 3
	for n: FastNoiseLite in [per, cel]:
		var imgs := n.get_seamless_image_3d(64, 64, 64, n == cel, 0.1, true)
		var tex := ImageTexture3D.new()
		tex.create(imgs[0].get_format(), 64, 64, 64, false, imgs)
		_noise_cache.append(tex)
	return _noise_cache
