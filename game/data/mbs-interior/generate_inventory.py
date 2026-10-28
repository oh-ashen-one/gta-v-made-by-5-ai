#!/usr/bin/env python3
"""Deterministic game reconstruction; allocations are not hotel as-built records."""
from pathlib import Path
import json, hashlib, math
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
SOURCE=ROOT/'src/world/mbs_interior/site_reference.gd'
SEED='orchard-mbs-private-reconstruction-v1-2026-10-28'

def allocate(total, keys, weights, minimum=0, caps=None):
    result={k:minimum for k in keys}
    caps=caps or {k:10**6 for k in keys}
    for _ in range(total-minimum*len(keys)):
        # Largest weighted deficit, with stable keys as deterministic tie-break.
        active=[k for k in keys if result[k]<caps[k]]
        assert active, ('insufficient allocation capacity',total)
        target=sum(weights[k] for k in active)
        remaining=total-sum(result.values())
        k=max(active,key=lambda k:(weights[k]/target*remaining/(result[k]-minimum+1),str(k)))
        result[k]+=1
    return result

def elevation(level):
    if level=='L1':return 0.0
    if level.startswith('L'):return round(5.0+(int(level[1:])-2)*3.45,3)
    return {'B1':-5.0,'B2M':-7.5,'B2':-10.0,'B3':-14.5,'B4':-18.5,'B5':-22.5}[level]

def main():
    data=json.JSONDecoder().raw_decode(SOURCE.read_text().split('const DATA := ',1)[1])[0]
    src={t['tower']:t for t in data['towers']}
    widths={'T3':10.,'T2':20.,'T1':40.}; roofs={'T3':27.,'T2':47.,'T1':76.}
    anchors=[dict(x=t['centroid_local_xz'][0],z=t['centroid_local_xz'][1],w=widths[t['tower']],h=roofs[t['tower']]) for t in data['towers']]
    north=dict(anchors[0],x=anchors[0]['x']-src['T3']['source_long_extent_m']*.78*.5)
    south=dict(anchors[-1],x=anchors[-1]['x']+src['T1']['source_long_extent_m']*.78*.5)
    profile=[north]+anchors+[south]
    def sample(x):
        for a,b in zip(profile,profile[1:]):
            if x<=b['x']:
                u=max(0,min(1,(x-a['x'])/(b['x']-a['x'])))
                return {k:a[k]+u*(b[k]-a[k]) for k in ['x','z','w','h']}
        return profile[-1]
    facts=[
      dict(id='MBS-FACTS',url='https://www.marinabaysands.com/content/dam/singapore/marinabaysands/master/main/home/company-information/media-centre/factsheets/amenities/marina-bay-sands-hotel.pdf',facts={'approx_units':1850,'suites':775,'hotel_floors':55,'towers':3,'legs_connected_level':23},scope='Current operator totals/program, not unit numbering/floor assignment'),
      dict(id='MBS-PREMIER',url='https://www.marinabaysands.com/hotel/rooms-suites/sands-premier-room.html',facts={'average_area_m2':45,'beds':'king or twin queen','program':['sleep','bath','vanities','minibar','TV']},scope='Published example; actual layouts vary'),
      dict(id='MBS-SIGNATURE',url='https://www.marinabaysands.com/hotel/rooms-suites/sands-signature-suite.html',facts={'average_area_m2':140,'bedrooms':1,'program':['separate_living','dining_six','bar','bedroom','wardrobe','bath']},scope='Published example, not every suite'),
      dict(id='MBS-PAIZA',url='https://www.marinabaysands.com/content/dam/singapore/marinabaysands/master/main/home/company-information/media-centre/factsheets/restaurants/paiza-sky-residence.pdf',facts={'tower':'T2','level':'L55','program':['private_checkin','dining','tea','lounge']},scope='Current program identity; exact floorplate reconstructed'),
      dict(id='MBS-JIN',url='https://www.marinabaysands.com/restaurants/jin-ting-wan.html',facts={'tower':'T1','level':'L55'},scope='Current operator restaurant location; private layout reconstructed'),
      dict(id='MBS-SPA',url='https://www.marinabaysands.com/hotel/amenities/banyan-tree-spa.html',facts={'tower':'T2','level':'L5'},scope='Current operator page supersedes historical L55 spa location'),
      dict(id='MBS-FITNESS',url='https://www.marinabaysands.com/hotel/amenities/fitness-centre.html',facts={'building':'EXPO','level':'L3'},scope='Current operator page supersedes historical T2L55 gym location'),
      dict(id='MBS-DECK',url='https://www.marinabaysands.com/attractions/skypark-observation-deck.html',facts={'tower':'T3','level':'L56'},scope='Public observation deck'),
      dict(id='MBS-FAQ',url='https://www.marinabaysands.com/faq.html',facts={'pool_restaurants_level':'L57','deck_mezzanine':'part of L57','box_office':'T3-B1'},scope='Public program facts; exact shafts/landings not surveyed'),
      dict(id='MBS-KIOSK',url='https://www.marinabaysands.com/content/dam/singapore/marinabaysands/master/main/home/sands-lifestyle/SandsLifeStyle_KioskMap.pdf',facts={'retail_levels':['L1','B1','B2'],'casino_entry':'B2M','coach':'B2M','hotel_public':'L1'},scope='Public schematic topology; unscaled'),
    ]
    guest_levels={t:[n for n in range(2,56) if not (t in ['T1','T2'] and n==55) and not(t=='T2' and n==5)] for t in ['T1','T2','T3']}
    tower_targets={'T1':(625,260),'T2':(600,290),'T3':(625,225)}
    counts={};suites={}
    for t,levels in guest_levels.items():
        weights={n:(.70 if n<9 else 1.13 if n<23 else 1.0 if n<45 else .88 if n<51 else .60) for n in levels}
        counts[t]=allocate(tower_targets[t][0],levels,weights,6,{n:16 for n in levels})
        suites[t]=allocate(tower_targets[t][1],levels,{n:.06+((n-2)/53)**2.0 for n in levels},caps=counts[t])
    floors=[];units=[];graph=[]
    for t in ['T1','T2','T3']:
        source=src[t];cx,cz=source['centroid_local_xz']
        length=round(source['source_long_extent_m']-2.0,5);cross=round(source['source_cross_extent_m']-1.0,5)
        for level in ['B5','B4','B3','B2','B2M','B1']+[f'L{n}' for n in range(1,58)]:
            number=int(level[1:]) if level.startswith('L') else None
            key=f'{t}-{level}'
            kind='guest_floor' if number in guest_levels[t] else 'hotel_service_basement' if number is None else 'public_l1' if number==1 else 'paiza_residence' if t=='T2' and number==55 else 'spa' if t=='T2' and number==5 else 'jin_ting_wan_dining' if t=='T1' and number==55 else 'roof_pool_dining' if number==57 else 'public_observation' if t=='T3' and number==56 else 'roof_service_mezzanine'
            y=elevation(level)
            xs=[max(profile[0]['x'],cx-length/2),min(profile[-1]['x'],cx+length/2)]+[a['x'] for a in profile if cx-length/2<a['x']<cx+length/2]
            samples=[sample(x) for x in xs]
            active=y<max(q['h'] for q in samples)+.30 and number is not None and number>1
            void_min=min(q['z']-q['w']/2 for q in samples)-cz-.15 if active else 0.0
            void_max=max(q['z']+q['w']/2 for q in samples)-cz+.15 if active else 0.0
            floor=dict(id=key,tower=t,level=level,level_number=number,elevation_m=y,factory='guest_floor_v1' if kind=='guest_floor' else 'program_module',program=kind,source_status='RECONSTRUCTED_ASSIGNMENT_UNLESS_SOURCE_FACT_LISTED',geometry=dict(length_m=length,cross_m=cross,clear_height_m=3.08,storey_height_m=3.45,core_bay_m=6.2,corridor_width_m=2.6,atrium_void_active=active,void_min_z_m=round(void_min,5),void_max_z_m=round(void_max,5),all_dimensions_reconstructed=True),units=[],cores=[dict(id=f'{key}-{wing}-{k}',wing=wing,kind=k,x_side=-1 if k=='stair' else 1) for wing in ['east','west'] for k in ['stair','guest_lift','service_lift']],source_facts=[])
            for core in floor['cores']:
                side=-1 if core['wing']=='east' else 1
                core['local_x_m']=round(-length*.5+1.80 if core['kind']=='stair' else length*.5-3.10+(-1.30 if core['kind']=='guest_lift' else 1.30),5)
                core['threshold_z_m']=round(side*(cross*.5-5.60),5)
                core['status']='RECONSTRUCTED_FIXED_VERTICAL_AXIS_ALL_LEVELS'
            program_spaces={
                'guest_floor':['east_guest_corridor','west_guest_corridor','two_physical_stairs','two_guest_lift_landings','two_service_lift_landings','two_linen_service_rooms'],
                'public_l1':['connected_grand_atrium','arrival_concierge','checkin','luggage_store','guest_lifts','public_toilets','restaurant_lounge','service_corridor','public_stairs'],
                'paiza_residence':['private_checkin','dining_room','tea_lounge','residence_bar','private_dining','kitchen','pantry','toilets','guest_service_lifts','stairs'],
                'spa':['reception','water_garden','treatment_rooms','changing','wet_treatment','relaxation_lounge','linen_store','staff_pantry','guest_service_lifts','stairs'],
                'jin_ting_wan_dining':['reception','main_dining','private_dining','show_kitchen','service_kitchen','pantry','toilets','lifts','stairs'],
                'public_observation':['public_observation_promenade','viewing_rail','ticket_lift_arrival','public_toilets','public_mezzanine_stair','staff_store','egress_stairs'],
                'roof_pool_dining':['shared_infinity_pool_segment','pool_deck','tropical_garden','guest_changing','restaurant','bar_lounge','kitchen','plant_service','guest_service_lifts','stairs'],
                'roof_service_mezzanine':['plant_rooms','roof_service_corridor','restaurant_back_of_house','mezzanine_lift_landing','stairs'],
                'hotel_service_basement':['service_corridor','linen_laundry_transfer','engineering_store','staff_changing','staff_pantry','plant','service_lifts','stairs'],
            }[kind]
            if level=='B1' and t=='T3':program_spaces+=['observation_deck_box_office']
            if level=='B3':program_spaces+=['loading_transfer','bulk_stores','staff_arrival']
            if level in ['B4','B5']:program_spaces+=['parking','water_tanks','electrical_mechanical_plant']
            if number==57:program_spaces += [{'T1':'LAVO_dining','T2':'Spago_dining','T3':'CE_LA_VI_dining'}[t]]
            floor['program_spaces']=[dict(id=key+'-'+space,program=space,status='RECONSTRUCTED_ROOM_OR_LAYOUT_UNLESS_OPERATOR_PROGRAM_FACT',geometry_required=True,permanent_empty_fallback=False) for space in program_spaces]
            if kind=='paiza_residence':floor['source_facts']=['MBS-PAIZA']
            if kind=='spa':floor['source_facts']=['MBS-SPA']
            if kind=='jin_ting_wan_dining':floor['source_facts']=['MBS-JIN']
            if kind=='public_observation':floor['source_facts']=['MBS-DECK']
            if number==57:floor['source_facts']=['MBS-FAQ','MBS-FACTS']
            if kind=='guest_floor':
                count=counts[t][number];sn=suites[t][number]
                order=sorted(range(count),key=lambda i:hashlib.sha256(f'{SEED}-{key}-{i}'.encode()).hexdigest())
                suite_indices=set(order[:sn])
                for i in range(count):
                    suite=i in suite_indices
                    digest=int(hashlib.sha256(f'{key}-{i}'.encode()).hexdigest()[:8],16)
                    typ='premier'
                    if suite:typ='family_suite' if digest%7==0 else 'signature_suite' if number<40 else 'paiza_suite' if digest%3 else 'signature_suite'
                    # Unique reconstructed flagship residences remain explicitly
                    # gameplay allocations, never published room numbers.
                    if suite and number>=52 and i==next(j for j in order if j in suite_indices and j%2==i%2):typ='chairman_residence' if number==max(guest_levels[t]) else 'presidential_suite'
                    unit=dict(id=f'R-{key}-{i+1:02d}',floor_id=key,label=f'{t[1:]}{number:02d}-{i+1:02d}',label_is_reconstructed=True,kind=typ,is_suite=suite,wing='west' if i%2 else 'east',frontage_weight=3.6 if typ=='chairman_residence' else 2.7 if typ=='presidential_suite' else 1.85 if suite else 1.0,bedrooms=3 if typ=='chairman_residence' else 2 if typ in ['family_suite','presidential_suite'] else 1,bed_variant='twin_queen' if not suite and digest%4==0 else 'king',entertainment=['media','billiards','lounge'][digest%3] if suite else 'lounge',fitout='RECONSTRUCTED_CURRENT_COLLECTION_INSPIRED',reference='MBS-PREMIER' if not suite else 'MBS-SIGNATURE')
                    floor['units'].append(unit);units.append(unit)
            # Assign twin queens only where the reconstructed cell can retain a
            # proper bed/door/side aisle; this is our allocation, not a real SKU map.
            for wing in ['east','west']:
                row=[u for u in floor['units'] if u['wing']==wing]
                total_weight=sum(u['frontage_weight'] for u in row)
                for u in row:
                    frontage=(length-12.4)*u['frontage_weight']/total_weight
                    if frontage<6.8:u['bed_variant']='king'
                    if u['is_suite']:
                        living=max(3.2,min(5.4,frontage*.36))
                        requested=u['bedrooms']
                        supported=max(1,int((frontage-living)/3.8))
                        u['bedrooms']=min(requested,supported)
                        u['requested_reconstructed_bedrooms']=requested
                        u['bedroom_allocation_status']='RECONSTRUCTED_TO_PRESERVE_FULL_KING_BED_AND_WINDOW_AISLE'
                        if u['kind']=='family_suite' and u['bedrooms']==1:u['kind']='signature_suite'
                        if u['kind']=='chairman_residence' and u['bedrooms']<3:u['kind']='presidential_suite' if u['bedrooms']==2 else 'paiza_suite'
                        if u['kind']=='presidential_suite' and u['bedrooms']==1:u['kind']='paiza_suite'
            floors.append(floor)
        ordered=sorted([f for f in floors if f['tower']==t],key=lambda f:f['elevation_m'])
        for a,b in zip(ordered,ordered[1:]):
            for wing in ['east','west']:
                for kind in ['stair','guest_lift','service_lift']:
                    graph.append(dict(id=f'{a["id"]}--{b["id"]}-{wing}-{kind}',from_floor=a['id'],to_floor=b['id'],wing=wing,kind=kind,height_m=round(b['elevation_m']-a['elevation_m'],3),status='RECONSTRUCTED_VERTICAL_ALIGNMENT',actor_teleport=False,loaded_collision_required_before_transition=True))
    for a,b in [('T1-L1','T2-L1'),('T2-L1','T3-L1')]:graph.append(dict(id=a+'--'+b,from_floor=a,to_floor=b,kind='continuous_atrium',status='PUBLIC_TOPOLOGY_SOURCE_EXACT_METRICS_STAGED',actor_teleport=False))
    program_floors=[]
    for building,levels in {'SHOPPES':['B5','B4','B3','B2','B2M','B1','L1'],'EXPO':['B2','B1','L1','L2','L3','L4','L5'],'CASINO':['B2M','L1','L2','L3','L4'],'THEATRE':['B1','L1','L2'],'MUSEUM':['B2','B1','L1','L2','L3']}.items():
        for level in levels:
            program='retail_galleria' if building=='SHOPPES' and level in ['L1','B1','B2'] else 'coach_entry' if building=='SHOPPES' and level=='B2M' else 'fitness_centre' if building=='EXPO' and level=='L3' else 'casino_gaming' if building=='CASINO' and level!='L4' else 'back_of_house_parking_loading' if level.startswith('B') else building.lower()+'_public_program'
            f=dict(id=building+'-'+level,building=building,level=level,elevation_m=elevation(level),program=program,factory='program_module',permanent_empty_fallback=False,source_status='PUBLIC_PROGRAM_WITH_RECONSTRUCTED_PRIVATE_LAYOUT',rooms_required=['public_circulation','service_circulation','toilets','staff_lift_landing','public_stairs_lift_landing'],source_facts=['MBS-KIOSK'] if building=='SHOPPES' and level in ['L1','B1','B2','B2M'] else ['MBS-FITNESS'] if program=='fitness_centre' else [])
            if building=='SHOPPES' and program=='retail_galleria':f['rooms_required']+=['retail_units','restaurant_seating','retail_service_stores']
            program_floors.append(f)
        ordered=sorted([f for f in program_floors if f['building']==building],key=lambda f:f['elevation_m'])
        for a,b in zip(ordered,ordered[1:]):graph.append(dict(id=a['id']+'--'+b['id'],from_floor=a['id'],to_floor=b['id'],kind='public_stair_lift',status='RECONSTRUCTED_METRIC_ALIGNMENT',actor_teleport=False,loaded_collision_required_before_transition=True))
    for a,b,kind in [('T2-B2','SHOPPES-B2','under_Bayfront_public_link'),('T3-B1','SHOPPES-B1','observation_ticketing_reconstructed_link'),('SHOPPES-B2M','CASINO-B2M','casino_entry'),('SHOPPES-L1','THEATRE-L1','public_galleria'),('SHOPPES-L1','EXPO-L1','public_galleria'),('SHOPPES-B2','MUSEUM-B2','public_walkway'),('T1-B3','SHOPPES-B3','service_loading_link'),('T2-L57','T1-L57','continuous_skypark'),('T2-L57','T3-L57','continuous_skypark'),('T3-L56','T3-L57','public_mezzanine_stair')]:
        graph.append(dict(id=a+'--'+b,from_floor=a,to_floor=b,kind=kind,status='RECONSTRUCTED_ROUTE_ON_PUBLIC_PROGRAM_TOPOLOGY',actor_teleport=False,loaded_collision_required_before_transition=True))
    inv=dict(schema='orchard_mbs_interior_inventory_v1',deterministic_seed=SEED,target_epoch='2026-10-28',authorization='Owner delegated full explorable recreation; undocumented private layouts reconstructed without further questions.',facts=facts,source_geography=dict(source=data['source'],tower_ids={k:v['id'] for k,v in src.items()}),inventory_scope=dict(operator_approx_units=1850,game_normalized_exact_units=1850,game_normalized_exact_suites=775,operator_floors=55,numbered_roof_levels=[56,57],reconstructed_distribution=True,reconstructed_unit_numbers=True,current_private_asbuilt_verified=False),tower_totals={t:{'units':tower_targets[t][0],'suites':tower_targets[t][1]} for t in tower_targets},hotel_floors=floors,resort_program_floors=program_floors,connections=graph,streaming=dict(max_full_guest_floors_recommended=3,retain_adjacent_stair_destinations=True,collision_before_door_open=True,elevator_cabin_is_physical=True,events_are_requests_not_actor_relocations=True,persistent_keys=['floor_id','unit_door_states','lift_cabin_id','cabin_transform','actor_floor_and_position']),coverage=dict(all_1850_units_have_factory_recipe=True,all_named_programs_have_inventory=True,all_hotel_levels_have_guest_or_nonempty_program=True,program_geometry_integrated=False,global_building_tested=False,all_rooms_visually_reviewed=False,full_building_completed=False))
    assert len(units)==1850 and sum(u['is_suite'] for u in units)==775
    assert len({u['id'] for u in units})==1850
    ids={f['id'] for f in floors+program_floors};assert len(ids)==len(floors)+len(program_floors)
    assert all(e['from_floor'] in ids and e['to_floor'] in ids for e in graph)
    # Graph connectivity: no orphaned service, guest, basement or roof program.
    reached={'T1-L1'}
    while True:
        old=len(reached)
        for e in graph:
            if e['from_floor'] in reached or e['to_floor'] in reached:reached.update([e['from_floor'],e['to_floor']])
        if len(reached)==old:break
    assert reached==ids,ids-reached
    text=json.dumps(inv,indent=2,sort_keys=True)+'\n'
    (OUT/'inventory.json').write_text(text)
    report=dict(units=len(units),suites=sum(u['is_suite'] for u in units),standard_units=sum(not u['is_suite'] for u in units),guest_floors=sum(f['factory']=='guest_floor_v1' for f in floors),hotel_floor_records=len(floors),resort_program_floor_records=len(program_floors),physical_connection_records=len(graph),orphaned_floor_ids=sorted(ids-reached),inventory_sha256=hashlib.sha256(text.encode()).hexdigest(),scope='Deterministic inventory/data checks only; no engine or complete-building claim')
    (OUT/'inventory-check.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
