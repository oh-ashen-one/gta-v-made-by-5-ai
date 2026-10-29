"""Private operator PDF -> compact factual zone references, never world slabs.
Requires pdfplumber from bundled Codex Python. Raw PDF/renders remain ignored.
"""
from pathlib import Path
import json,hashlib
import pdfplumber
HERE=Path(__file__).resolve().parent
PDF=HERE/'private/unique-spaces.pdf'
EXPECTED='8f88a3e22fd560c202ea1dfbfa29beb5f50c461c381b1cc44092ac18f72bba0c'
assert hashlib.sha256(PDF.read_bytes()).hexdigest()==EXPECTED
with pdfplumber.open(PDF) as doc:
    p=doc.pages[4]; obs=[]
    # Bounding coordinates locate semantic groups in the actual operator drawing;
    # they are explicitly NOT filled reservation rectangles or world geometry.
    for name,cy in zip(['Jasmine','Hibiscus','Heliconia','Cassia','Begonia'],[250,317,383,450,517]):
        for kind,color in [('main',(0.967,0.728,0.752)),('junior',(0.401,0.084,0.068))]:
            rs=[r for r in p.rects+p.curves if r.get('non_stroking_color')==color and r['width']>6 and r['height']>6 and 750<r['x0']<975 and abs((r['top']+r['bottom'])/2-cy)<32]
            if not rs:raise ValueError('Missing source drawing group '+name+kind)
            obs.append({'name':name+(' Junior' if kind=='junior' else ''),'group':kind,'drawing_reference_bounds_pt':[min(r['x0'] for r in rs),min(r['top'] for r in rs),max(r['x1'] for r in rs),max(r['bottom'] for r in rs)],'reference_kind':'LOCATOR_NOT_RESERVATION_GEOMETRY'})
    p=doc.pages[10]; museum=[]
    for name,code,color in [('ArtScience Cinema','A.04.06.00',(0.784,0.725,0.727)),('Level4 Lift Lobby','A.04.05.00',(0.605,0.734,0.742)),('VR Gallery','A.04.02.00',(0.022,0.208,0.198))]:
        curves=[c for c in p.curves if c.get('non_stroking_color')==color and c.get('fill') and c['x0']<400 and c['width']>50 and c['height']>50]
        assert len(curves)==1
        c=curves[0]
        museum.append({'name':name,'source_plan_zone_code':code,'drawing_reference_bounds_pt':[c[k] for k in ['x0','top','x1','bottom']],'drawing_boundary_commands_pt':c['path'],'reference_kind':'SOURCE_SCHEMATIC_CURVED_ZONE_NOT_WORLD_POLYGON','possible_exclusions':'Lobby drawing includes L-A01/02 lift cores. Outer coloured boundary must not be treated as net clear area or filled solid slab.'})
result={'schema':'mbs_public_operator_plan_observations_v2','source_url':'https://www.marinabaysands.com/content/dam/marinabaysands/mice/brochures/unique-spaces.pdf','source_pdf_sha256':EXPECTED,'source_footer_date':'2025.7','raw_reference_redistribution_licensed':False,'private_pdf_path':'private/unique-spaces.pdf','source_reference_coordinate_system':{'units':'PDF points','origin':'top left of landscape spread','width':1190.55,'height':841.89,'metric_scale_verified':False,'world_registration':None},'expo':{'page_1_based':5,'source_group_locators':obs,'source_topological_constraints':['Main groups in drawing order Jasmine,Hibiscus,Heliconia,Cassia,Begonia.','Corresponding junior groups across main foyer, with separate approach and reception/partition access.','Service corridor on opposite side of main groups; kitchen beside Begonia.','Bayview foyer and Shoppes glazing lie outside junior groups.','Fitness Centre at short end beside guest lift lobby; not the entire level.','Saraca meeting rooms drawn along angled Bayview side by Jasmine Junior.','Business and Mail Centre at short end opposite fitness, containing labels3A,3B,3D,3E,3F.'], 'published_hall_height_m':6.1,'height_scope':'Clear hall-height statement, not finished-floor elevation or floor-to-floor height.','text_map_count_conflict':'Brochure heading/table still mentions six junior types including Angsana Junior; diagram labels five junior groups and current detail page says five. Preserve Angsana/meeting mapping as unresolved, never silently delete or duplicate space.','individual_meeting_room_mapping_status':'Five requirements retained. Angsana/Angsana Junior/Saraca names and drawing subdivisions are not a verified one-to-one mapping to the five count.'},'museum':{'page_1_based':11,'source_zone_references':museum,'source_topological_constraints':['Cinema, lift lobby and VR occupy successive adjacent sectors around the central circular core.','Two lift labels L-A01 and L-A02 are within the lobby sector.','VR sector has adjacent support/toilet markings; do not erase them when reserving circulation.','Other lotus sectors are not empty by implication and not covered by the three rental areas.'],'current_detail_area_precedence':{'cinema_m2':236,'lift_lobby_m2':166,'vr_gallery_m2':184,'source_url':'https://www.marinabaysands.com/museum/about-us/services/venue-rental/rate.html'},'rounded_brochure_total_m2':600,'areas_not_asbuilt_survey':True},'scope':'Factual relative programme geometry from visually reviewed operator pages. No georeferenced slab/zone, height schedule or engine acceptance is created.'}
(HERE/'OPERATOR_PLAN_OBSERVATIONS.json').write_text(json.dumps(result,indent=2)+'\n')
print('operator locators',len(obs),'museum curved zones',len(museum))
