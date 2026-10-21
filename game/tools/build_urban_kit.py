"""Original boundary railing module, CPU Blender authoring; no provider input."""
import sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_interiors as kit
import bpy
kit.setup()
kit.box('GraniteSill',(0,.22,0),(15,.44,.5),'plaster',.05)
for x in [-7.5,0,7.5]:
 kit.cylinder('FencePost',(x,1.25,0),.095,2.5,'trim',12)
 kit.cylinder('PostCap',(x,2.51,0),.12,.08,'gold',12)
for y in [.65,1.45,2.15]:kit.box('HorizontalRail',(0,y,0),(15,.075,.09),'trim',.015)
for i in range(53):kit.box('VerticalBar',(-7.3+i*.28,1.38,0),(.04,1.58,.04),'darksteel',.008)
result=kit.save('boundary_railing')
(kit.OUT/'boundary_manifest.json').write_text(json.dumps(result,indent=2))

# A small original meal tray for occupied hawker tables.
kit.setup()
kit.box('MealTray',(0,.009,0),(.44,.018,.32),'trim',.02)
kit.cylinder('BowlBody',(-.055,.045,0),.105,.065,'white',24)
kit.torus('BowlRim',(-.055,.079,0),.101,.009,'white')
kit.cylinder('SoupSurface',(-.055,.076,0),.093,.004,'gold',24)
for i in range(7):
    ob=kit.box('Noodles',(-.10+i*.014,.083,.005),(.008,.005,.10),'white',.003)
    ob.rotation_euler.z=(i-3)*.15
for i in range(4):kit.box('Garnish',(-.09+i*.022,.087,.024*(1 if i%2 else -1)),(.018,.004,.012),'green',.004)
kit.cylinder('TeaCup',(.145,.056,-.045),.037,.09,'white',16)
kit.cylinder('TeaSurface',(.145,.102,-.045),.032,.003,'wood_edge',16)
kit.torus('CupHandle',(.188,.064,-.045),.025,.006,'white',True)
for x in [.12,.135]:kit.box('Chopstick',(x,.026,.078),(.004,.004,.19),'wood',.002)
kit.save('hawker_meal')
