extends RefCounted
## Material set of the downtown blocks piece (original work). One shared
## facade ShaderMaterial for every building shell plus a small set of
## frontage materials keyed by name for the detail batcher. The generated
## Higgsfield textures (loop/GENERATED_ASSETS.md: rooftop_flat, sign_*) are
## used when present in the git-ignored provider folder; without them every
## material falls back to procedural colour.

const FACADE_SHADER := "res://assets/authored/shaders/dt_facade.gdshader"
const HF := "res://assets/providers/higgsfield/"
const SIGN_FILES := ["sign_teck_huat_kopitiam", "sign_sin_leong_hardware", "sign_mei_ling_tailor", "sign_joo_heng_medical_hall",
	"sign_ah_kow_prawn_noodle", "sign_kim_seng_provision", "sign_golden_lotus_money_changer", "sign_happy_cycles"]

var facade: ShaderMaterial
var mats := {}
var sign_keys: Array[String] = []

func _init() -> void:
	facade = ShaderMaterial.new()
	facade.shader = load(FACADE_SHADER)
	if ResourceLoader.exists(HF + "rooftop_flat_albedo.png"):
		facade.set_shader_parameter("roof_tex", load(HF + "rooftop_flat_albedo.png"))
		facade.set_shader_parameter("has_roof_tex", 1.0)
	# `--blocks-emit=K` scales glass reflection / interior emission (look A/B only).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--blocks-emit="):
			var k := float(arg.trim_prefix("--blocks-emit="))
			facade.set_shader_parameter("reflect_strength", k)
			facade.set_shader_parameter("interior_energy", 0.20 * k)
			facade.set_shader_parameter("lobby_energy", 0.42 * k)
	mats["paving"] = Palette.mat_textured(Color(0.66, 0.63, 0.58), "pavers", Vector3.ONE, 0.88)
	mats["paving_dark"] = Palette.mat_textured(Color(0.46, 0.45, 0.43), "pavers", Vector3.ONE, 0.85)
	mats["granite"] = Palette.mat(Color(0.30, 0.29, 0.28), 0.42)
	mats["granite_light"] = Palette.mat(Color(0.62, 0.60, 0.56), 0.55)
	mats["metal_dark"] = Palette.mat(Color(0.13, 0.135, 0.14), 0.42, 0.6)
	mats["metal_light"] = Palette.mat(Color(0.70, 0.71, 0.72), 0.35, 0.7)
	mats["metal_white"] = Palette.mat(Color(0.86, 0.86, 0.84), 0.45, 0.2)
	mats["canopy_glass"] = _glass(Color(0.62, 0.70, 0.72, 0.55))
	mats["shelter_glass"] = _glass(Color(0.70, 0.78, 0.80, 0.35))
	mats["light_strip"] = Palette.emissive(Color(1.0, 0.88, 0.70), 2.2)
	mats["light_cool"] = Palette.emissive(Color(0.85, 0.92, 1.0), 1.8)
	mats["lantern"] = Palette.emissive(Color(0.95, 0.22, 0.12), 1.6)
	mats["ad_panel"] = Palette.emissive(Color(0.95, 0.92, 0.86), 1.1)
	mats["planter"] = Palette.mat_textured(Color(0.58, 0.56, 0.52), "concrete", Vector3.ONE, 0.9)
	mats["soil"] = Palette.mat(Color(0.20, 0.15, 0.10), 0.95)
	mats["shrub"] = Palette.mat(Color(0.17, 0.30, 0.14), 0.92)
	mats["shrub_light"] = Palette.mat(Color(0.26, 0.40, 0.18), 0.92)
	mats["turf"] = Palette.mat_textured(Color(0.27, 0.38, 0.17), "soil", Vector3.ONE, 0.95)
	mats["plaster_white"] = Palette.mat_textured(Color(0.90, 0.88, 0.82), "plaster", Vector3.ONE, 0.88)
	mats["plaster_cream"] = Palette.mat_textured(Color(0.86, 0.80, 0.68), "plaster", Vector3.ONE, 0.88)
	mats["timber"] = Palette.mat(Color(0.36, 0.22, 0.13), 0.75)
	mats["shutter_green"] = Palette.mat(Color(0.16, 0.34, 0.27), 0.7)
	mats["shutter_blue"] = Palette.mat(Color(0.20, 0.30, 0.42), 0.7)
	mats["roof_tile"] = Palette.mat(Color(0.48, 0.22, 0.15), 0.8)
	mats["awning_red"] = Palette.mat(Color(0.62, 0.16, 0.12), 0.85)
	mats["awning_cream"] = Palette.mat(Color(0.86, 0.80, 0.66), 0.85)
	mats["awning_green"] = Palette.mat(Color(0.16, 0.36, 0.26), 0.85)
	mats["awning_navy"] = Palette.mat(Color(0.12, 0.17, 0.30), 0.85)
	mats["umbrella_white"] = Palette.mat(Color(0.92, 0.90, 0.85), 0.85)
	mats["table"] = Palette.mat(Color(0.20, 0.17, 0.14), 0.6, 0.3)
	mats["chair"] = Palette.mat(Color(0.55, 0.45, 0.32), 0.7)
	mats["sign_dark"] = Palette.mat(Color(0.07, 0.08, 0.09), 0.5, 0.3)
	mats["sign_red"] = Palette.emissive(Color(0.80, 0.10, 0.10), 0.8)
	mats["mrt_red"] = Palette.mat(Color(0.72, 0.10, 0.12), 0.5)
	mats["bus_sign"] = Palette.mat(Color(0.10, 0.36, 0.22), 0.5)
	mats["bronze"] = Palette.mat(Color(0.42, 0.28, 0.16), 0.35, 0.8)
	mats["water_feature"] = Palette.mat(Color(0.10, 0.20, 0.24), 0.04, 0.2)
	for i in SIGN_FILES.size():
		var f: String = HF + SIGN_FILES[i] + ".png"
		var key := "shopsign_%d" % i
		if ResourceLoader.exists(f):
			var m := StandardMaterial3D.new()
			m.albedo_texture = load(f)
			m.emission_enabled = true
			m.emission_texture = m.albedo_texture
			m.emission_energy_multiplier = 0.25
			m.roughness = 0.6
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mats[key] = m
			sign_keys.append(key)

static func _glass(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
