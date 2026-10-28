#!/usr/bin/env python3
"""Audit MBS source footprints and roads before placing real resort interiors.

This consumes the integrator's attributed SVY21 tiles. It does not geocode a
POI and call that point a building centroid, invent untagged building identity,
or claim that an OSM outline proves a hotel floor plan. No network/engine work.
"""
import argparse
import hashlib
import itertools
import json
import math
import re
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

from shapely.geometry import LineString, Polygon, shape, mapping
from shapely.ops import nearest_points, unary_union
from georeference import to_wgs84, from_wgs84

DRIVABLE = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
            "residential", "living_street", "service", "road", "motorway_link",
            "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
NAME_KEYS = ("name", "name:en", "name:zh", "alt_name")
LANDMARK_ALIASES = {
    "artscience_museum": {"artscience museum", "art science museum"},
    "singapore_flyer": {"singapore flyer"},
    "merlion_landmark": {"merlion", "merlion statue"},
    "esplanade": {"esplanade theatres on the bay", "esplanade the theatres on the bay"},
    "fullerton": {"the fullerton hotel", "fullerton hotel"},
}

class AuditError(ValueError):
    pass

class SnapshotNotReady(AuditError):
    pass

def normalized(value):
    text = unicodedata.normalize("NFKC", str(value)).casefold()
    return " ".join(re.sub(r"[^\w]+", " ", text).split())

def names_of(feature):
    tags = feature.get("tags", {})
    return {normalized(part) for key in NAME_KEYS for part in str(tags.get(key, "")).split(";") if part.strip()}

def _validate_frame(manifest):
    frame = manifest.get("georeference", {})
    if frame.get("survey_crs") != "EPSG:3414" or frame.get("metres_per_unit") != 1.0:
        raise AuditError("Expected uncompressed SVY21 metre tiles")
    if frame.get("distance_compression") is not False:
        raise AuditError("Compressed or unspecified geometry cannot establish the requested scale")
    if frame.get("world_axes") != {"x": "south", "y": "up", "z": "west"}:
        raise AuditError("Unexpected coordinate axes")
    if frame.get("origin_easting") != 30000.0 or frame.get("origin_northing") != 30000.0:
        raise AuditError("Origin differs from this audit's georeference converter")

def read_snapshot(folder):
    folder = Path(folder)
    if not (folder / "manifest.json").is_file():
        raise SnapshotNotReady("Snapshot manifest is not present; extraction is not established complete")
    manifest = json.loads((folder / "manifest.json").read_text())
    _validate_frame(manifest)
    features, seen = [], set()
    for tile in manifest.get("tiles", []):
        path = (folder / tile["file"]).resolve()
        if not path.is_relative_to(folder.resolve()):
            raise AuditError("Tile path escapes the snapshot")
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != tile["sha256"]:
            raise AuditError("Tile checksum mismatch: " + tile["file"])
        payload = json.loads(data)
        if len(payload.get("features", [])) != tile["features"]:
            raise AuditError("Tile feature count mismatch: " + tile["file"])
        for feature in payload["features"]:
            key = (feature["kind"], feature["id"])
            if key in seen:
                raise AuditError("Duplicate feature identity: " + repr(key))
            seen.add(key)
            features.append(feature)
    return manifest, features

def candidate_roles(feature):
    """Semantic candidate labels only. Geometry alone does not name a building."""
    if feature.get("kind") != "building":
        return []
    tags, names = feature.get("tags", {}), names_of(feature)
    mbs = any("marina bay sands" in name for name in names)
    if not mbs:
        return []
    roles = []
    if any("shoppes" in name for name in names):
        roles.append("retail")
    if tags.get("building") == "hotel" or tags.get("tourism") == "hotel" or any("hotel" in name for name in names):
        roles.append("hotel")
    if tags.get("amenity") == "casino" or any("casino" in name for name in names):
        roles.append("casino")
    if any("skypark" in name or "sky park" in name for name in names):
        roles.append("roof_program")
    return roles or ["unclassified_mbs_name"]

def named_tower_group(candidates):
    """Use three explicit source labels, never an inferred row of polygons.

    This union is ONLY the three tower footprints. It does not fill the shared
    ground atrium, infer a roof, or turn those shapes into a hotel floor plan.
    """
    towers = {}
    for f in candidates:
        if "hotel" not in candidate_roles(f): continue
        numbers = {int(m.group(1)) for n in names_of(f) for m in [re.fullmatch(r"marina bay sands (?:hotel )?tower ([123])", n)] if m}
        if len(numbers) != 1: continue
        number = next(iter(numbers))
        towers.setdefault(number, []).append(f)
    if set(towers) != {1,2,3} or any(len(v) != 1 for v in towers.values()):
        return None
    chosen = [towers[n][0] for n in [1,2,3]]
    geometries = [shape(f["geometry"]) for f in chosen]
    if any(g.is_empty or not g.is_valid or g.geom_type not in {"Polygon","MultiPolygon"} for g in geometries): return None
    return {"id": None, "kind": "derived_tower_group", "tags": {},
            "geometry": mapping(unary_union(geometries)),
            "source_ids": [f["id"] for f in chosen],
            "tower_components": {"T"+str(i+1): f for i,f in enumerate(chosen)},
            "scope": "Only three explicitly named OSM tower footprints; shared atrium, circulation and roof geometry are not established by this union"}

def _point_info(point):
    x, z = float(point.x), float(point.y)
    lon, lat = to_wgs84(x, 0, z)
    return {"world_xz_m": [round(x, 4), round(z, 4)], "wgs84_lon_lat": [round(lon, 9), round(lat, 9)]}

def geometry_metrics(geometry):
    if geometry.is_empty or not geometry.is_valid or geometry.geom_type not in {"Polygon", "MultiPolygon"}:
        raise AuditError("MBS footprint must be nonempty, valid polygon geometry")
    rectangle = geometry.minimum_rotated_rectangle
    corners = list(rectangle.exterior.coords)[:-1]
    edges = [(math.dist(corners[i], corners[(i+1) % 4]), corners[i], corners[(i+1) % 4]) for i in range(4)]
    length, a, b = max(edges, key=lambda item: item[0])
    width = min(item[0] for item in edges)
    ux, uz = ((b[0]-a[0])/length, (b[1]-a[1])/length)
    # Undirected major axis; this is GRID north, not a surveyed façade bearing.
    bearing = math.degrees(math.atan2(-uz, -ux)) % 180.0
    center = rectangle.centroid
    from shapely.geometry import Point
    ends = sorted([Point(center.x-ux*length/2, center.y-uz*length/2),
                   Point(center.x+ux*length/2, center.y+uz*length/2)], key=lambda p: (p.x, p.y))
    return {"area_m2": round(geometry.area, 3), "bounds_world_xz_m": [round(v,4) for v in geometry.bounds],
            "footprint_centroid": _point_info(geometry.centroid),
            "inside_representative_point": _point_info(geometry.representative_point()),
            "oriented_envelope": {"long_m": round(length,3), "short_m": round(width,3),
                "major_axis_grid_bearing_deg_mod180": round(bearing,5),
                "corners_world_xz_m": [[round(v,4) for v in p] for p in corners],
                "axis_endpoints_north_to_south": [_point_info(p) for p in ends],
                "not_tower_or_door_positions": True}}

def feature_record(feature):
    g = shape(feature["geometry"])
    return {"source_id": feature["id"], "source_kind": feature["kind"],
            "identity_evidence": {key: feature.get("tags", {}).get(key) for key in (*NAME_KEYS, "building", "building:part", "tourism", "amenity") if key in feature.get("tags", {})},
            "candidate_roles": candidate_roles(feature), "source_tags": feature.get("tags", {}), "source_geometry_valid": bool(g.is_valid),
            "source_height_m": feature.get("height_m"), "source_height_status": feature.get("height_status", "not_supplied"),
            "raw_levels_tag": feature.get("tags", {}).get("building:levels"),
            "metrics": geometry_metrics(g) if g.is_valid and g.geom_type in {"Polygon", "MultiPolygon"} and not g.is_empty else None,
            "architectural_identity_verified": False}

def select_candidate(role, candidates, explicit_id=None):
    available = [f for f in candidates if role in candidate_roles(f)]
    if explicit_id:
        matches = [f for f in available if f["id"] == explicit_id]
        if len(matches) != 1:
            raise AuditError(f"Explicit {role} ID is not a unique semantic source candidate")
        return matches[0], "explicit_source_id_requires_architectural_review"
    if len(available) == 1:
        return available[0], "unique_semantic_source_match_requires_architectural_review"
    return None, "missing" if not available else "ambiguous"

def legacy_plan(path):
    text = Path(path).read_text()
    if "const ANCHORS :=" not in text: raise AuditError("Legacy plan has no expected ANCHORS section")
    section = text.split("const ANCHORS :=",1)[1].split("## ---------------------------------------------------------------- roads",1)[0]
    pattern = r'"(?P<id>[\w]+)"\s*:\s*\{\s*"pos"\s*:\s*Vector3\((?P<x>[-\d.]+),\s*(?P<y>[-\d.]+),\s*(?P<z>[-\d.]+)\)'
    anchors = {m["id"]: [float(m["x"]),float(m["y"]),float(m["z"])] for m in re.finditer(pattern,section)}
    scales = {}
    for axis in ["EAST_WEST", "NORTH_SOUTH"]:
        match = re.search(r'DISTANCE_SCALE_'+axis+r'\s*:=\s*([\d.]+)',text)
        scales[axis.lower()] = float(match.group(1)) if match else None
    version = re.search(r'PLAN_VERSION\s*:=\s*"([^"]+)"',text)
    return {"path":str(path),"sha256":hashlib.sha256(text.encode()).hexdigest(),"plan_version":version.group(1) if version else None,
            "declared_distance_scales":scales,"anchors_world_xyz_m":anchors,
            "frame_registration_to_survey": "NOT_ESTABLISHED; direct absolute point deltas would be misleading"}

def audit(manifest, features, legacy=None, hotel_id=None, retail_id=None):
    _validate_frame(manifest)
    candidates = [f for f in features if candidate_roles(f)]
    hotel, hotel_status = select_candidate("hotel", candidates, hotel_id)
    if hotel is None and hotel_status == "ambiguous" and hotel_id is None:
        group = named_tower_group(candidates)
        if group:
            hotel, hotel_status = group, "three_explicitly_named_tower_footprints_grouped_not_full_hotel"
    retail, retail_status = select_candidate("retail", candidates, retail_id)
    roads = [f for f in features if f.get("kind")=="road" and "bayfront avenue" in names_of(f)]
    drivable = [f for f in roads if f.get("tags",{}).get("highway") in DRIVABLE]
    result = {"audit_kind":"source geometry and legacy-layout audit, not interior completion", "created_utc":datetime.now(timezone.utc).isoformat(),
        "source":{k:manifest.get(k) for k in ["source_url","pbf_sha256","source_snapshot_utc","data_license","license_url","attribution","parse_errors"]},
        "georeference":manifest["georeference"],"candidate_buildings":[feature_record(f) for f in sorted(candidates,key=lambda f:f["id"])],
        "hotel_selection":{"status":hotel_status,"source_id":hotel["id"] if hotel else None,
            "source_ids":hotel.get("source_ids",[hotel["id"]]) if hotel else [],
            "geometry_scope":hotel.get("scope","Selected source polygon only, not an entire resort or interior") if hotel else None},
        "retail_selection":{"status":retail_status,"source_id":retail["id"] if retail else None},
        "bayfront_avenue":{"all_named_source_ids":[f["id"] for f in roads],"drivable_source_ids":[f["id"] for f in drivable],
            "names":sorted({f.get("tags",{}).get("name","") for f in roads}),"widths_only_as_tagged":{f["id"]:f.get("tags",{}).get("width") for f in drivable}},
        "hotel_retail_separation":None,"landmarks":{},"legacy_comparison":None,
        "selected_hotel_geometry":hotel["geometry"] if hotel else None,
        "selected_hotel_metrics":geometry_metrics(shape(hotel["geometry"])) if hotel else None,
        "tower_footprints":{label:feature_record(f) for label,f in hotel.get("tower_components",{}).items()} if hotel else {},
        "full_interior_acceptance":False,"one_to_one_city_acceptance":False,
        "unverified":["Every interior level, room, doorway and vertical circulation assignment",
                      "Architectural identity/extent of source footprint versus resort/site or building-part geometry",
                      "Actual Tower3/L56 public-deck footprint and elevation: a north endpoint is not that deck",
                      "OSM height/name/completeness and physical-world survey accuracy",
                      "Runtime replacement of legacy compressed geometry"]}
    if hotel and hotel.get("tower_components"):
        order=sorted(hotel["tower_components"],key=lambda key: shape(hotel["tower_components"][key]["geometry"]).centroid.x)
        result["tower_order_north_to_south"]={"observed_source_labels":order,"operator_reference_order":["T3","T2","T1"],
            "order_matches":order==["T3","T2","T1"],"does_not_locate_public_deck_or_door":True}
    if hotel and retail:
        h, r = shape(hotel["geometry"]), shape(retail["geometry"])
        if h.is_valid and r.is_valid and not h.is_empty and not r.is_empty:
            p,q = nearest_points(h,r);link=LineString([p,q]);distance=h.distance(r)
            between=[f["id"] for f in drivable if shape(f["geometry"]).intersects(link)] if distance>0 else []
            result["hotel_retail_separation"]={"minimum_surface_gap_m":round(distance,4),"nearest_points":[_point_info(p),_point_info(q)],
                "named_drivable_road_intersects_gap_connector":between,
                "evidence_status":"source_geometry_supports_separate_footprints_and_named_road_between" if distance>0 and between else "inconclusive",
                "hotel_geometry_scope":hotel.get("scope","Single source footprint only"),
                "does_not_prove_interior_or_door_connections":True}
    for name,aliases in LANDMARK_ALIASES.items():
        compact_aliases={n.replace(" ","") for n in aliases}
        matches=[f for f in features if f.get("kind")=="building" and {n.replace(" ","") for n in names_of(f)} & compact_aliases]
        result["landmarks"][name]={"status":"unique_semantic_match" if len(matches)==1 else "ambiguous" if matches else "missing_from_extracted_building_features",
                                  "source_ids":[f["id"] for f in matches],"candidates":[feature_record(f) for f in matches],"metrics":geometry_metrics(shape(matches[0]["geometry"])) if len(matches)==1 and shape(matches[0]["geometry"]).is_valid else None}
    if legacy:
        old=legacy.get("anchors_world_xyz_m",{});comparisons=[]
        legacy_ids={"fullerton":"fullerton_hotel", "merlion_landmark":"merlion"}
        chosen={legacy_ids.get(name,name):entry["metrics"]["footprint_centroid"]["world_xz_m"] for name,entry in result["landmarks"].items() if entry["status"]=="unique_semantic_match" and entry["metrics"]}
        if hotel:chosen["marina_bay_sands"]=geometry_metrics(shape(hotel["geometry"]))["footprint_centroid"]["world_xz_m"]
        for a,b in itertools.combinations(sorted(set(old)&set(chosen)),2):
            real=math.dist(chosen[a],chosen[b]);previous=math.dist([old[a][0],old[a][2]],[old[b][0],old[b][2]])
            comparisons.append({"anchors":[a,b],"legacy_anchor_distance_m":round(previous,3),"source_footprint_centroid_distance_m":round(real,3),
                "legacy_to_source_ratio":round(previous/real,6) if real else None,
                "not_identical_reference_points":True})
        result["legacy_comparison"]={**legacy,"pairwise_distance_comparisons":comparisons,
            "interpretation":"Pair distances avoid an arbitrary origin translation, but authored anchors and source polygon centroids are not established equivalent points. Do not apply these ratios as a runtime warp."}
    return result

def compare_overpass(report, features, document, raw_sha256):
    """Separately dated consistency check, never an architectural identity oracle."""
    by_id={f["id"]:f for f in features if f.get("kind")=="building"}
    elements={e["type"]+"/"+str(e["id"]):e for e in document.get("elements",[])}
    ids=report["hotel_selection"].get("source_ids",[]) + ([report["retail_selection"]["source_id"]] if report["retail_selection"]["source_id"] else [])
    rows=[]
    def line_points(geometry):
        return [[from_wgs84(p["lon"],p["lat"])[0],from_wgs84(p["lon"],p["lat"])[2]] for p in geometry]
    for identifier in ids:
        record={"source_id":identifier,"comparison":"unavailable"}
        source=by_id.get(identifier);element=elements.get(identifier)
        if not source or not element:
            record["reason"]="Feature is absent from one source snapshot";rows.append(record);continue
        existing=shape(source["geometry"])
        try:
            if element["type"]=="way":
                points=line_points(element.get("geometry",[]))
                if len(points)<4 or points[0]!=points[-1]:raise AuditError("Expected closed way geometry")
                boundary=Polygon(points).boundary
            elif element["type"]=="relation":
                lines=[]
                for member in element.get("members",[]):
                    if member.get("role") not in {"outer","inner"}:continue
                    points=line_points(member.get("geometry",[]))
                    if len(points)<2:raise AuditError("Relation boundary member geometry missing")
                    lines.append(LineString(points))
                if not lines:raise AuditError("No relation boundary geometry")
                boundary=unary_union(lines)
            else:raise AuditError("POI/node positions are not footprint geometry")
            distance=existing.boundary.hausdorff_distance(boundary)
            record.update(comparison="boundary_consistent_within_1cm" if distance<=0.01 else "geometry_differs",boundary_hausdorff_m=round(distance,6))
        except (AuditError,ValueError,KeyError) as e:record["reason"]=str(e)
        rows.append(record)
    return {"source_kind":"Separately dated parent-provided Overpass geometry snapshot","sha256":raw_sha256,
        "source_snapshot_utc":document.get("osm3s",{}).get("timestamp_osm_base"),"national_snapshot_utc":report["source"].get("source_snapshot_utc"),
        "feature_comparisons":rows,"not_a_survey_or_full_interior_verification":True}

def component_input(report, features):
    """Original selected source polygons/lines with lineage, never a floor plan."""
    hotel_ids=report["hotel_selection"].get("source_ids",[])
    retail_id=report["retail_selection"].get("source_id")
    if not hotel_ids or not retail_id:raise AuditError("Cannot export metric components while hotel/retail source identity is unresolved")
    required=set(hotel_ids+[retail_id]);roads=set(report["bayfront_avenue"]["drivable_source_ids"])
    selected=[f for f in features if (f.get("kind")=="building" and f["id"] in required) or (f.get("kind")=="road" and f["id"] in roads)]
    found={f["id"] for f in selected if f.get("kind")=="building"}
    if found!=required:raise AuditError("Selected source component is missing")
    return {"schema":"mbs_source_site_components_v1","source":report["source"],"coordinate_frame":report["georeference"],
        "geometry_coordinates":"[world X south, world Z west] metres; not RFC7946 WGS84 GeoJSON",
        "ground_elevation_status":"Not provided; terrain, basement and floor elevations are not inferred",
        "hotel_source_ids":hotel_ids,"retail_source_id":retail_id,"bayfront_avenue_source_ids":sorted(roads),
        "features":selected,"complete_hotel_interior":False,"architectural_identity_and_fitout_verified":False,
        "missing_metric_geometry":["Shared hotel atrium envelope/circulation beyond tagged tower footprints","Actual doorway, lift, stair and underpass landing coordinates/elevations","Roof-program polygons and floor levels","Current upper-floor room and service layouts"]}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("snapshot",type=Path);p.add_argument("--output",type=Path,required=True)
    p.add_argument("--legacy-plan",type=Path);p.add_argument("--hotel-id");p.add_argument("--retail-id");p.add_argument("--expected-pbf-sha256")
    p.add_argument("--circulation-contract",type=Path);p.add_argument("--legacy-access",type=Path)
    p.add_argument("--site-overpass",type=Path);p.add_argument("--expected-overpass-sha256")
    p.add_argument("--components-output",type=Path)
    a=p.parse_args()
    if a.output.exists() or (a.components_output and a.components_output.exists()):raise SystemExit("Refusing to overwrite an audit/component file; choose new output paths")
    try:
        m,features=read_snapshot(a.snapshot)
        if a.expected_pbf_sha256 and m.get("pbf_sha256")!=a.expected_pbf_sha256:raise AuditError("Snapshot PBF identity differs from expected input")
        report=audit(m,features,legacy_plan(a.legacy_plan) if a.legacy_plan else None,a.hotel_id,a.retail_id)
        if a.site_overpass:
            raw=a.site_overpass.read_bytes();digest=hashlib.sha256(raw).hexdigest()
            if a.expected_overpass_sha256 and digest!=a.expected_overpass_sha256:raise AuditError("Site-query identity differs from expected input")
            report["overpass_consistency"]=compare_overpass(report,features,json.loads(raw),digest)
        report["auditor_source_sha256"]=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        if a.circulation_contract:
            raw=a.circulation_contract.read_bytes();contract=json.loads(raw)
            node=next((n for n in contract.get("nodes",[]) if n.get("id")=="public_deck_T3_L56"),None)
            report["operator_circulation_reference"]={"path":str(a.circulation_contract),"sha256":hashlib.sha256(raw).hexdigest(),
                "target_epoch":contract.get("target_epoch"),"tower_order":contract.get("tower_axis_order_north_to_south"),
                "public_deck_node":node,"metric_deck_position_proven":False}
        if a.legacy_access:
            raw=a.legacy_access.read_bytes();text=raw.decode()
            match=re.search(r'const TERRACE := Rect2\(([^)]+)\)',text)
            values=[float(v.strip()) for v in match.group(1).split(',')] if match else None
            report["legacy_public_terrace"]={"path":str(a.legacy_access),"sha256":hashlib.sha256(raw).hexdigest(),"rect_x_z_w_d":values,
                "relative_center_x":values[0]+values[2]/2 if values else None,
                "side_under_legacy_compass":"south" if values and values[0]>0 else "not_established",
                "public_deck_north_tower_reference_conflict":bool(values and values[0]>0 and a.circulation_contract),
                "not_a_metric_deck_polygon_comparison":True}
    except (AuditError,OSError,json.JSONDecodeError) as e:raise SystemExit(str(e))
    components=component_input(report,features) if a.components_output else None
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n")
    if a.components_output:
        a.components_output.parent.mkdir(parents=True,exist_ok=True);a.components_output.write_text(json.dumps(components,indent=2,ensure_ascii=False)+"\n")
    print(json.dumps({"output":str(a.output),"hotel":report["hotel_selection"],"retail":report["retail_selection"],"separation":report["hotel_retail_separation"]},ensure_ascii=False))
if __name__=="__main__":main()
