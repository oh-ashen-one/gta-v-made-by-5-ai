class_name SingaporeGeoReference
extends RefCounted
## Exact affine mapping of projected SVY21 metres to the new geography frame.
## Existing fictional/compressed DowntownPlan is not yet migrated by this file.
const ORIGIN_EASTING := 30000.0
const ORIGIN_NORTHING := 30000.0
static func from_svy21(easting: float, northing: float, elevation: float = 0.0) -> Vector3:
	return Vector3(ORIGIN_NORTHING - northing, elevation, ORIGIN_EASTING - easting)
static func to_svy21(world_position: Vector3) -> Vector2:
	return Vector2(ORIGIN_EASTING - world_position.z, ORIGIN_NORTHING - world_position.x)
