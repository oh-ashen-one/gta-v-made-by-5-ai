"""WGS84 -> Singapore SVY21 -> uncompressed Godot metres.

Runtime axes retain the established compass: -X north, -Z east, +Y up.
The surveying origin is arbitrary, not a claim about a building centroid.
"""
from pyproj import Transformer

ORIGIN_EASTING = 30000.0
ORIGIN_NORTHING = 30000.0
_FORWARD = Transformer.from_crs('EPSG:4326', 'EPSG:3414', always_xy=True)
_INVERSE = Transformer.from_crs('EPSG:3414', 'EPSG:4326', always_xy=True)

def from_svy21(easting, northing, elevation=0.0):
    return [ORIGIN_NORTHING-float(northing), float(elevation), ORIGIN_EASTING-float(easting)]

def to_svy21(x, y, z):
    return [ORIGIN_EASTING-float(z), ORIGIN_NORTHING-float(x)]

def from_wgs84(lon, lat, elevation=0.0):
    if not (-180<=lon<=180 and -90<=lat<=90):
        raise ValueError('Invalid longitude/latitude')
    return from_svy21(*_FORWARD.transform(lon, lat), elevation)

def to_wgs84(x, y, z):
    return list(_INVERSE.transform(*to_svy21(x,y,z)))

def manifest():
    return {'source_crs':'EPSG:4326','survey_crs':'EPSG:3414',
            'origin_easting':ORIGIN_EASTING,'origin_northing':ORIGIN_NORTHING,
            'world_axes':{'x':'south','y':'up','z':'west'},'metres_per_unit':1.0,
            'distance_compression':False,'legacy_plan_alignment_applied':False}
