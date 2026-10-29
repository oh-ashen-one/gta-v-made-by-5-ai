"""Operator-catalogue reconstruction proposal. Never overwrites legacy inventory.
Active1,844 keys /775 suites are source-grounded; unknown type counts, variant
mix and room-ID assignment are explicit reconstruction, pending critique/adoption.
"""
from pathlib import Path
import json,hashlib,datetime,collections,copy
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
OLD=ROOT/'game/data/mbs-interior/inventory.json'
BASE='https://www.marinabaysands.com/hotel/rooms-suites/'
TOTAL_SOURCE='https://s28.q4cdn.com/640198178/files/content_files/LVS-3Q-2026-Presentation-Deck.pdf'
PAIZA_SOURCE='https://www.marinabaysands.com/expo-and-convention/gallery/event-highlights/2025/06/hotel-room-renovations-and-jin-ting-wan.html'


def category(id,label,collection,count,area,bedrooms,url,program,is_suite=True,towers=None,variant=None,royal=False,kids=False,extra=None):
 r={'id':id,'label':label,'collection':collection,'is_suite':is_suite,'reconstructed_count':count,'count_status':'RECONSTRUCTED_MIX_NOT_OPERATOR_PER_TYPE_INVENTORY','published_average_area_m2':area,'advertised_bedrooms':bedrooms,'separate_kids_room':kids,'sleeping_spaces_for_game':bedrooms+int(kids),'bedroom_count_interpretation':'Advertised adult bedroom count plus separately described kids room' if kids else 'Published bedroom count','source_url':BASE+url,'required_programs':program,'programme_provenance_note':'Distinctive listed amenities follow the linked category page; common architectural basics remain explicit full-function reconstruction. External resort amenities are not duplicated inside each unit.','variant':variant,'paiza_royal':royal,'tower_restriction_from_current_category_page':towers or [],'zoning_status':'CURRENT_CATEGORY_PAGE_TOWER_FACT' if towers else 'NO_EXACT_TOWER_ASSIGNMENT_CLAIMED','actual_room_sizes_and_layouts_vary':True,'individual_room_positions_asbuilt_verified':False}
 if royal:r['required_programs']=list(dict.fromkeys(program+['powder_room']))
 if 'family' in id:r['secondary_source_urls']=['https://www.marinabaysands.com/hotel/the-sands-collection.html'] if collection=='Sands' else ['https://www.marinabaysands.com/hotel/the-paiza-collection.html']
 if extra:r.update(extra)
 return r


def catalogue():
 basic=['sleeping','bath_with_two_person_tub','separate_vanities','rain_shower','walk_in_wardrobe','armoire_minibar','television']
 suite=basic+['separate_living','dining']
 paiza=suite+['dressing_table','night_fridge']
 cats=[
 category('sands_premier','Sands Premier Room','Sands',894,45,1,'sands-premier-room.html',basic,False,extra={'bed_options':['king','two_queen'],'bed_dimensions_status':'No dimension inferred from the generic king label'}),
 category('sands_studio','Sands Premier Studio','Sands',125,70,1,'sands-premier-studio.html',basic+['two_seat_sofa'],False,extra={'bed_options':['king','two_queen']}),
 category('paiza_club','Paiza Club Room','Paiza',50,55,1,'paiza-club-room.html',basic+['concealed_bath_tv'],False,extra={'bed_options':['king','two_queen']}),
 category('sands_bay','Sands Bay Suite','Sands',90,80,1,'sands-bay-suite.html',suite+['two_seat_dining'],towers=['T3']),
 category('sands_premier_1b','Sands Premier Suite -1bedroom','Sands',165,95,1,'sands-premier-suite.html',suite+['four_seat_dining','dressing_table'],towers=['T1','T2']),
 category('sands_premier_2b','Sands Premier Suite -2bedroom','Sands',45,130,2,'sands-premier-suite.html',suite+['dressing_table','dining'],towers=['T3'],extra={'source_variant_note':'Gardens-view2-bedroom page specifies a2-seat dining table;4-seat belongs to other listed configurations.'}),
 category('sands_family_1b','Sands Family Suite -1bedroom plus kids room','Sands',25,85,1,'sands-family-suite.html',suite+['kids_bunk_room','child_friendly_kitchenette','washer','banquette_dining','highchair','kids_bookshelf'],kids=True),
 category('sands_family_2b','Sands Family Suite -2bedrooms plus kids room','Sands',30,145,2,'sands-family-suite.html',suite+['kids_bunk_room','child_friendly_kitchenette','washer','banquette_dining','highchair','kids_bookshelf'],kids=True),
 category('sands_signature','Sands Signature Suite','Sands',100,140,1,'sands-signature-suite.html',suite+['six_seat_dining','social_bar','selected_entertainment_room'],variant=['media_room','pool_table_room','entertainment_den']),
 category('paiza_bay','Paiza Bay Suite','Paiza',29,75,1,'paiza-bay-suite.html',paiza+['two_seat_dining','jetted_tub'],towers=['T3']),
 category('paiza_premier_1b','Paiza Premier Suite -1bedroom','Paiza',80,110,1,'paiza-premier-suite.html',paiza+['jetted_tub','enhanced_shower']),
 category('paiza_premier_2b','Paiza Premier Suite -2bedroom','Paiza',25,160,2,'paiza-premier-suite.html',paiza+['jetted_tub','enhanced_shower']),
 category('paiza_grand_1b','Paiza Grand Suite -1bedroom','Paiza',40,140,1,'paiza-grand-suite.html',paiza+['six_seat_dining','powder_room','selected_social_or_media_room'],variant=['social_kitchen_island','social_bar_island','media_room']),
 category('paiza_grand_2b','Paiza Grand Suite -2bedroom','Paiza',10,210,2,'paiza-grand-suite.html',paiza+['six_seat_dining','powder_room','selected_social_or_media_room'],variant=['social_kitchen_island','social_bar_island','media_room']),
 category('paiza_signature_1b','Paiza Signature Suite -1bedroom','Paiza',50,140,1,'paiza-signature-suite.html',paiza+['powder_room','selected_social_or_entertainment_room'],variant=['social_kitchen_island','social_bar_island','entertainment_den_foosball']),
 category('paiza_signature_2b','Paiza Signature Suite -2bedroom','Paiza',15,210,2,'paiza-signature-suite.html',paiza+['powder_room','selected_social_room'],variant=['social_kitchen_island','social_bar_island']),
 category('paiza_family','Paiza Family Suite','Paiza',15,175,1,'paiza-family-suite.html',paiza+['kids_bunk_room','social_kitchen_island','child_friendly_dining','working_den','working_desk','massage_chair','pullout_sofa_bed','kids_bookshelf'],towers=['T3'],kids=True),
 category('harbour','The Harbour Suite','Paiza',6,160,1,'paiza-harbour-suite.html',paiza+['jacuzzi_bath'],royal=True),
 category('marina','The Marina Suite','Paiza',10,160,1,'paiza-marina-suite.html',paiza+['eight_seat_dining','jacuzzi_bath','selected_social_or_media_room'],variant=['social_bar','media_room_with_pool_table'],royal=True,extra={'published_mattress_width_m':2.20,'pool_reference_note':'Official Marina PDF page2 labels POOL TABLE(8\u0027)1500x2620; overall-object interpretation is an inference, not a verified playing-bed dimension.'}),
 category('skyline','The Skyline Suite','Paiza',8,200,1,'paiza-skyline-suite.html',paiza+['jacuzzi_bath','selected_entertainment_room'],variant=['private_karaoke','golf_simulator'],royal=True),
 category('merlion','The Merlion Suite','Paiza',6,260,2,'paiza-merlion-suite.html',paiza+['social_kitchen','karaoke_room'],royal=True),
 category('straits','The Straits Suite','Paiza',5,300,2,'paiza-straits-suite.html',paiza+['ensuite_and_wardrobe_each_bedroom','eight_seat_dining','social_bar','selected_entertainment_room'],variant=['karaoke_room','pool_table_room'],royal=True,extra={'published_bed_widths_m':{'super_king':2.4,'queen':1.6}}),
 category('horizon','The Horizon Suite','Paiza',4,330,1,'paiza-horizon-suite.html',paiza+['ten_seat_dining','hammam','salt_wall','heated_loungers','massage_room_two_tables','sauna','ice_well','private_gym','jacuzzi_bath'],royal=True,extra={'published_mattress_width_m':2.4}),
 category('presidential','The Presidential Suite','Paiza',13,360,2,'paiza-presidential-suite.html',paiza+['six_seat_dining','jacuzzi_bath','selected_entertainment_room'],variant=['golf_simulator','media_room','pool_table_room','entertainment_show_kitchen','social_kitchen_and_media'],royal=True,extra={'published_bed_widths_m':{'super_king':2.4,'queen':1.6}}),
 category('chairman_3b','The Chairman Suite -3bedroom','Paiza',2,520,3,'paiza-chairman-suite.html',paiza+['two_living_rooms','eight_seat_dining','private_gym','massage_room_two_tables','sauna','ice_well','butler_pantry','grand_piano','humidor','jacuzzi_bath'],royal=True,extra={'published_bed_width_options_m':{'super_king':[2.4,2.6],'queen':[1.4,1.6]}}),
 category('chairman_4b','The Chairman Suite -4bedroom','Paiza',2,630,4,'paiza-chairman-suite.html',paiza+['two_living_rooms','eight_seat_dining','private_gym','massage_room_two_tables','sauna','ice_well','butler_pantry','grand_piano','humidor','jacuzzi_bath'],royal=True,extra={'published_bed_width_options_m':{'super_king':[2.4,2.6],'queen':[1.4,1.6]}}),
 ]
 return cats


def floor_number(u):return int(u['floor_id'].split('-L')[1])

def propose():
 old=json.loads(OLD.read_text());all_units=[u for f in old['hotel_floors'] for u in f['units']];cats=catalogue();assert sum(c['reconstructed_count'] for c in cats)==1844;assert sum(c['reconstructed_count'] for c in cats if c['is_suite'])==775
 # These were invented game IDs, never operator room numbers. Keep every full
 # old record; mark two non-suite normalization slots per old tower superseded.
 superseded=[]
 for tower in ['T1','T2','T3']:
  candidates=[u for u in all_units if not u['is_suite'] and u['floor_id'].startswith(tower+'-')];candidates.sort(key=lambda u:(floor_number(u),u['id']),reverse=True);superseded.extend(u['id'] for u in candidates[:2])
 active=[u for u in all_units if u['id'] not in superseded];available={u['id']:u for u in active};mapped=[]
 # Allocate scarce/large/explicitly zoned types first, preserving semantic IDs
 # where possible, but never interpreting the old invented floor as surveyed.
 order=sorted(cats,key=lambda c:(not c['is_suite'],not c['paiza_royal'],-c['published_average_area_m2'],c['id']))
 for c in order:
  pool=[u for u in available.values() if bool(u['is_suite'])==c['is_suite']]
  def score(u):
   tower=u['floor_id'].split('-')[0];restricted=c['tower_restriction_from_current_category_page'];old_kind=u['kind'];semantic=0 if (c['id'].startswith('chairman') and old_kind=='chairman_residence') or (c['id']=='presidential' and old_kind=='presidential_suite') or ('family' in c['id'] and old_kind=='family_suite') else 1
   return (bool(restricted) and tower not in restricted,semantic,-floor_number(u) if c['collection']=='Paiza' else floor_number(u),u['id'])
  pool.sort(key=score)
  chosen=pool[:c['reconstructed_count']]
  if len(chosen)!=c['reconstructed_count']:raise RuntimeError('Lost inventory capacity')
  for i,u in enumerate(chosen):
   available.pop(u['id']);variants=c.get('variant');variant=variants[i%len(variants)] if variants else None
   programmes=list(c['required_programs'])
   if variant:programmes.append(variant)
   mapped.append({'id':u['id'],'status':'ACTIVE_CATALOGUE_RECONSTRUCTION','legacy_record':u,'catalogue_category_id':c['id'],'operator_category_label':c['label'],'collection':c['collection'],'is_suite':c['is_suite'],'published_average_area_target_m2':c['published_average_area_m2'],'advertised_bedrooms':c['advertised_bedrooms'],'sleeping_spaces_for_game':c['sleeping_spaces_for_game'],'kids_room_separate':c['separate_kids_room'],'selected_variant':variant,'required_programs':programmes,'source_url':c['source_url'],'allowed_towers_from_current_page':c['tower_restriction_from_current_category_page'],'prefer_highest_guest_levels':c['collection']=='Paiza','paiza_royal':c['paiza_royal'],'physical_floor_assignment':None,'physical_room_number_verified':False,'source_category_not_legacy_kind_controls_fitout':True})
 assert not available
 lookup={r['id']:r for r in mapped};legacy=[]
 for u in all_units:
  if u['id'] in superseded:legacy.append({'id':u['id'],'status':'SUPERSEDED_ROUNDING_PLACEHOLDER','legacy_record':u,'reason':'Old game normalized approximate1850 marketing to1850 arbitrary IDs; current Oct21 2026 LVS disclosure gives1844 actual keys. This ID was never verified as an operator room number. History retained; not counted as an active key.'})
  else:legacy.append({'id':u['id'],'status':'ACTIVE','catalogue_category_id':lookup[u['id']]['catalogue_category_id'],'legacy_record':u})
 return {'schema':'mbs_operator_catalogue_inventory_proposal_v9','recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'adoption_state':'PROPOSAL_PENDING_INDEPENDENT_SOURCE_AND_COVERAGE_CRITIQUE','legacy_inventory_sha256':hashlib.sha256(OLD.read_bytes()).hexdigest(),'source_grounded_totals':{'active_keys':1844,'suites':775,'source_url':TOTAL_SOURCE,'published_date':'2026-10-21','pdf_page_index':24,'slide_number':25,'marketing1850_is_rounded':True},'source_collection_guidance':{'paiza_about370':True,'source_url':PAIZA_SOURCE,'date_context':'June2025 completed-renovation article','proposal_exact_paiza370_is_reconstruction_of_approximate_count':True},'legacy_mapping_count':len(legacy),'superseded_ids':superseded,'active_key_count':len(mapped),'active_suite_count':sum(u['is_suite'] for u in mapped),'catalogue':cats,'active_units':mapped,'legacy_mapping':legacy,'reconstructed_mix_rationale':['Represent all currently listed Sands and Paiza/Royal families, not a single Signature template.','Paiza proposal370 keys includes50 Club rooms and320 varied suites, consistent with the operator description mostly suites; per-type counts remain unknown.','Sands proposal1474 keys includes1019 Premier/Studio rooms and455 varied suites.','All larger residences remain represented, including both current Chairman bedroom/area variants; no all-small-suite packing substitution.','Current explicit Tower3 Bay/Family and Premier2-bedroom facts govern future allocation; Royal/Paiza upper-level preference comes from operator collection wording, exact levels remain reconstruction.'],'unknowns':['Actual per-type counts and per-floor/per-key positions are not public evidence.','Historical2024 phase counts are not asserted as a current exact tower schedule.','Bed configurations, variant distribution and generated room labels remain reconstruction unless explicitly tied to current category facts.'],'full_physical_coverage_verified':False,'actual_source_envelope_allocation_verified':False,'native_or_visual_acceptance':False}

if __name__=='__main__':
 p=propose();(HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V9.json').write_text(json.dumps(p,indent=2)+'\n');print('active',p['active_key_count'],'suites',p['active_suite_count'],'legacy',p['legacy_mapping_count'],'superseded',p['superseded_ids']);print('collections',dict(collections.Counter(u['collection'] for u in p['active_units'])));print('area',sum(u['published_average_area_target_m2'] for u in p['active_units']))
