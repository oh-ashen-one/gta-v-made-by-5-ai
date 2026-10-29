"""Contiguous type-average expansion after area-first placement; v1/v2 immutable."""
from pathlib import Path
import json,hashlib
import expand_luxury_rooms_v2 as grow
HERE=Path(__file__).resolve().parent
if __name__=='__main__':
 grow.BASE=HERE/'SOURCE_FLOOR_LUXURY_AREA_FIRST_V3.json'
 d=grow.expand();d['schema']='mbs_source_floor_luxury_expansion_v3';d['seed_type_target_policy']='Signature/Paiza placement seeds85percent of their published average; the unchanged full category-average target remains mandatory and is measured explicitly after growth. No omitted room or final acceptance from a seed.'
 p=HERE/'SOURCE_FLOOR_LUXURY_EXPANSION_V3.json';p.write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d['area_progress'],indent=2))
