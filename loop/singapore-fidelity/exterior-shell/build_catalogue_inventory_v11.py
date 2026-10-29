"""Apply independently confirmed source corrections without mutating frozenv9."""
from pathlib import Path
import json,copy,hashlib,datetime
HERE=Path(__file__).resolve().parent
V9=HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V9.json'

def build():
 doc=json.loads(V9.read_text());doc['schema']='mbs_operator_catalogue_inventory_proposal_v11';doc['predecessor_v9_sha256']=hashlib.sha256(V9.read_bytes()).hexdigest();doc['recorded_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();cats={c['id']:c for c in doc['catalogue']};changes=[]
 def patch(id,field,value,reason):
  old=copy.deepcopy(cats[id].get(field));cats[id][field]=value;changes.append({'category':id,'field':field,'before':old,'after':value,'source_url':cats[id]['source_url'],'confirmation':'Independent source_dataset_recovery review; current detailed operator page takes precedence.','reason':reason})
 patch('paiza_club','bed_options',['king'],'Current detail page says1king; generic collection summary two-queen option is not used.')
 patch('paiza_club','source_conflict_note','Collection summary offers king/two-queen; current category detail lists onlyking. Detail controls proposal.','Preserve conflict rather than silently merge inconsistent options.')
 patch('harbour','variant',['social_kitchen','social_kitchen_and_media_room'],'Current Harbour detail provides both named configurations.')
 patch('harbour','required_programs',cats['harbour']['required_programs']+['selected_social_kitchen_or_kitchen_and_media'],'Retain kitchen in both variants and media in the combined variant.')
 for id in ['harbour','skyline']:patch(id,'published_mattress_width_m',2.4,'Current detail explicitly gives240cm mattress.')
 patch('merlion','published_bed_widths_m',{'super_king':2.4,'queen':1.4},'Current detail gives240cm superking and140cm double-queen.')
 patch('skyline','variant',['private_karaoke','golf_and_media_room'],'Golf is paired with a Media Room; a golf-only identifier lost programme coverage.')
 for id in ['chairman_3b','chairman_4b']:
  patch(id,'required_programs',cats[id]['required_programs']+['146_inch_karaoke_display','massage_chair'],'Distinctive current amenities retained without inventing an additional enclosed media room.')
 for id in ['sands_premier','sands_studio','paiza_club']:
  patch(id,'advertised_bedrooms',None,'Current page gives bed options, not a published separated-bedroom count.')
  patch(id,'bedroom_count_interpretation','One sleeping space is a reconstruction from the offered beds; no separate bedroom is asserted.','Distinguish room/studio planning from a published suite bedroom count.')
 patch('sands_premier_2b','required_programs',list(dict.fromkeys(cats['sands_premier_2b']['required_programs'])),'Remove duplicate dining entry without deleting any programme.')
 patch('sands_premier_2b','dining_seat_rules',{'gardens_by_the_bay':2,'other_listed_configurations':4},'Current detail page makes dining seats dependent on the actual view/configuration.')
 patch('sands_premier_2b','selected_dining_seats',None,'Physical view is not yet assigned; no dining variant can be selected silently.')
 patch('presidential','source_variant_wording_issue','Current page says four types while naming Golf, Media Room, Pool Table, Entertainment Show Kitchen, and Social Kitchen and Media Room. Named options retained; exact layout-count wording is inconsistent.','Do not turn the textual inconsistency into a verified five-layout claim.')
 for cat in doc['catalogue']:
  cat['review_status']='CONFIRMED_CORRECTIONS_APPLIED_PENDING_COMPLETE_REVIEW'
 for unit in doc['active_units']:
  c=cats[unit['catalogue_category_id']];siblings=[u for u in doc['active_units'] if u['catalogue_category_id']==c['id']];index=next(i for i,u in enumerate(siblings) if u['id']==unit['id']);variants=c.get('variant');variant=variants[index%len(variants)] if variants else None;unit['selected_variant']=variant;unit['required_programs']=list(dict.fromkeys(list(c['required_programs'])+([variant] if variant else [])));unit['advertised_bedrooms']=c['advertised_bedrooms'];unit['sleeping_spaces_for_game']=c['sleeping_spaces_for_game'];unit['bedroom_count_interpretation']=c['bedroom_count_interpretation']
  if c.get('dining_seat_rules'):unit['dining_seat_rules']=c['dining_seat_rules'];unit['selected_dining_seats']=None
  if c.get('published_mattress_width_m') is not None:unit['published_mattress_width_m']=c['published_mattress_width_m']
  if c.get('published_bed_widths_m') is not None:unit['published_bed_widths_m']=c['published_bed_widths_m']
  if c.get('bed_options'):unit['allowed_bed_options']=c['bed_options']
 doc['independent_review_corrections']=changes;doc['adoption_state']='PROPOSAL_CONFIRMED_CORRECTIONS_APPLIED_FULL_REVIEW_AND_GEOMETRY_PENDING';doc['physical_floor_programme_assignment_status']='Waiting for current public/mixed-use floor review; legacy159guest-floor schedule is not an operator fact.'
 return doc

if __name__=='__main__':
 doc=build();p=HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V11.json';p.write_text(json.dumps(doc,indent=2)+'\n');print('corrections',len(doc['independent_review_corrections']),'active',len(doc['active_units']),'suites',sum(u['is_suite'] for u in doc['active_units']),'sha256',hashlib.sha256(p.read_bytes()).hexdigest())
