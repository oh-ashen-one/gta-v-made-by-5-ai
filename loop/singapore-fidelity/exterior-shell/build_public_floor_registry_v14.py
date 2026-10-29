"""Versioned physical-floor/programme proposal derived from the independent
current-source audit. No existing game schedule is overwritten or certified.
"""
from pathlib import Path
import json,copy,hashlib,datetime
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
REVIEW=HERE/'catalogue-review/PUBLIC_FLOOR_CONSTRAINTS.json'


def build():
 old=json.loads((ROOT/'game/data/mbs-interior/inventory.json').read_text());review=json.loads(REVIEW.read_text());floors={}
 for record in old['hotel_floors']+old['resort_program_floors']:
  id=record['id'];hotel=record.get('tower') in ['T1','T2','T3'];level=str(record['level']);guest_possible=hotel and level.startswith('L') and level[1:].isdigit() and 2<=int(level[1:])<=55
  floors[id]={'id':id,'building':record.get('tower',record.get('building')),'level':level,'legacy_record':record,'physical_floor_must_remain_built':True,'metric_elevation_m':record.get('elevation_m'),'metric_elevation_status':'LEGACY_RECONSTRUCTION_NOT_OPERATOR_SURVEY','documented_uses':[],'legacy_programme_status':'UNVERIFIED_RECONSTRUCTION_UNLESS_CURRENT_SOURCE_CONFIRMS','guest_allocation_possible':guest_possible,'guest_assignment_status':'DO_NOT_INFER_FROM_OLD_FACTORY_TYPE','public_reservation_polygons':[],'public_reservation_geometry_verified':False,'current_floor_use_exclusivity_verified':False}
 floors['MUSEUM-L4']={'id':'MUSEUM-L4','building':'MUSEUM','level':'L4','legacy_record':None,'physical_floor_must_remain_built':True,'metric_elevation_m':None,'metric_elevation_status':'NEW_SOURCE_SUPPORTED_LEVEL_NEEDS_METRIC_ARCHITECTURAL_PLAN','documented_uses':[],'legacy_programme_status':'MISSING_FROM_OLD_SCHEDULE','guest_allocation_possible':False,'guest_assignment_status':'MUSEUM_NOT_HOTEL_KEYS','public_reservation_polygons':[],'public_reservation_geometry_verified':False,'current_floor_use_exclusivity_verified':False}
 bindings={'Banyan Tree Spa':['T2-L5'],'Paiza Sky Residence':['T2-L55'],'Jin Ting Wan':['T1-L55'],'Fitness Centre':['EXPO-L3'],'Expo Level3 ballrooms and meeting rooms':['EXPO-L3'],'SkyPark Observation Deck':['T3-L56','T3-L57'],'SkyPark rooftop facilities':['T1-L57','T2-L57','T3-L57'],'LAVO':['T1-L57'],'Spago Dining Room':['T2-L57'],'CE LA VI':['T3-L57','T3-L1'],'The Club':['T1-L1'],'SkyPark Box Office':['T3-B1'],'ArtScience Museum Basement2':['MUSEUM-B2'],'ArtScience Museum Level4':['MUSEUM-L4'],'ArtScience Museum Basement1':['MUSEUM-B1']}
 for row in review['rows']:
  for id in bindings.get(row['facility'],[]):
   data=copy.deepcopy(row);data['source_fact_not_entire_floor_claim']=True
   if row['facility']=='CE LA VI' and id=='T3-L1':data['in_game_zone_role']='Reception only; restaurant/lounge remainsT3L57'
   if row['facility']=='SkyPark Observation Deck' and id=='T3-L57':data['in_game_zone_role']='Only the documented partial mezzanine relation, not the wholeLevel57'
   floors[id]['documented_uses'].append(data)
 for id,f in floors.items():
  mandatory=[r for r in f['documented_uses'] if 'UNRESOLVED' not in r['status']]
  f['guest_placement_requires_completed_public_reservations']=f['guest_allocation_possible'] and bool(mandatory)
  f['metric_allocation_ready']=False
 floors['EXPO-L3']['programme_policy']='Mixed fitness+convention level: preserve all named main/junior/meeting venues plus gym/changing/sauna; no whole-floor fitness-only fallback.'
 floors['MUSEUM-B2']['programme_policy']='Public galleries/boxoffice/ArtScience Laboratory320sqm are required; supersede parking/loading-only assignment while retaining old record as history.'
 floors['MUSEUM-L4']['programme_policy']='Construct cinema236sqm, lift lobby166sqm and VRgallery184sqm zones; these published areas do not define the whole level envelope.'
 floors['MUSEUM-B1']['programme_policy']='Build a coherent labelled reconstruction; current2026use remains unresolved. Do not move the newB2laboratory here or call oldparking-only verified.'
 return {'schema':'mbs_current_public_mixed_use_floor_registry_proposal_v14','recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_review_sha256':hashlib.sha256(REVIEW.read_bytes()).hexdigest(),'legacy_inventory_sha256':hashlib.sha256((ROOT/'game/data/mbs-interior/inventory.json').read_bytes()).hexdigest(),'floor_records':floors,'floor_count':len(floors),'new_documented_level_ids':['MUSEUM-L4'],'legacy_floor_ids_retained':len(old['hotel_floors'])+len(old['resort_program_floors']),'source_venue_location_does_not_prove_whole_floor_exclusivity':True,'next_required_work':'Actual source envelopes, explicit public-use reservation polygons, service/private reconstruction and coupled guest-room allocation; independent/native/rendered verification remains required.','adopted_into_game':False}

if __name__=='__main__':
 d=build();p=HERE/'PUBLIC_MIXED_USE_FLOOR_REGISTRY_PROPOSAL_V14.json';p.write_text(json.dumps(d,indent=2)+'\n');print('floors',d['floor_count'],'legacy',d['legacy_floor_ids_retained'],'new',d['new_documented_level_ids']);print('mixed guest/public',[id for id,f in d['floor_records'].items() if f['guest_placement_requires_completed_public_reservations']])
