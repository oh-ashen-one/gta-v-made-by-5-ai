class_name Palette
extends RefCounted
## Shared look-development palette (END_GOAL ART-01 / ART-04).
## One warm late-afternoon tropical look, applied consistently.

static func mat(color: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

static func emissive(color: Color, energy: float = 1.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m

static func glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.55, 0.62, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.35
	m.roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

const ROOF_TILE := Color(0.42, 0.20, 0.15)
const ROOF_TILE_2 := Color(0.50, 0.26, 0.18)
const PLASTER := Color(0.85, 0.81, 0.73)
const PLASTER_2 := Color(0.78, 0.74, 0.66)
const CONCRETE := Color(0.66, 0.65, 0.62)
const CONCRETE_LIGHT := Color(0.74, 0.73, 0.70)
const ASPHALT := Color(0.11, 0.11, 0.12)
const ASPHALT_EDGE := Color(0.20, 0.20, 0.21)
const PAINT_LINE := Color(0.85, 0.83, 0.72)
const GLASS := Color(0.44, 0.56, 0.62)
const METAL := Color(0.35, 0.36, 0.38)
const METAL_DARK := Color(0.16, 0.17, 0.18)
const FOLIAGE := Color(0.16, 0.32, 0.17)
const FOLIAGE_LIGHT := Color(0.26, 0.42, 0.20)
const TRUNK := Color(0.24, 0.18, 0.13)
const SHOP_WARM := Color(1.0, 0.76, 0.42)
const SKIN := Color(0.72, 0.55, 0.44)
const WATER := Color(0.16, 0.31, 0.36)

## Muted pastel shophouse frontages, kept in one family so the street reads as
## one place rather than an asset collage (ART-01 / ART-04).
const FRONTAGES := [
	Color(0.62, 0.71, 0.68),
	Color(0.78, 0.66, 0.62),
	Color(0.80, 0.70, 0.47),
	Color(0.67, 0.72, 0.60),
	Color(0.72, 0.68, 0.76),
	Color(0.74, 0.62, 0.55),
	Color(0.60, 0.67, 0.72),
]

const SIGN_TEXT := [
	"Kopitiam", "Hardware", "Barber", "Money Changer", "Bakery", "Repair Shop",
	"Phone Repair", "Sari Textiles", "Rice Shop", "Clinic", "Laundry", "Stationery",
]
