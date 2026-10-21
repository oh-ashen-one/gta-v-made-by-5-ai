#!/usr/bin/env python3
"""Original deterministic PBR surface maps. No downloaded/generated-provider art.
Each 1024px image represents a 4x4 metre tile. Rerun from repository root.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
ROOT=Path(__file__).resolve().parents[1]/'assets'/'authored'/'surfaces'
ROOT.mkdir(parents=True,exist_ok=True)
N=1024; rng=np.random.default_rng(20261021)
y,x=np.mgrid[:N,:N]
def noise(scale):
 a=rng.random((scale,scale)); return np.asarray(Image.fromarray(np.uint8(a*255)).resize((N,N),Image.Resampling.BICUBIC),dtype=float)/255
fine=rng.normal(0,1,(N,N)); coarse=noise(16); broad=noise(5)
def save(name,base,height,rough):
 if base.ndim==2: base=np.stack([base]*3,-1)
 Image.fromarray(np.uint8(np.clip(base,0,1)*255)).save(ROOT/(name+'_albedo.png'))
 gy,gx=np.gradient(height); nor=np.stack([-gx*8,-gy*8,np.ones_like(gx)],-1); nor/=np.linalg.norm(nor,axis=2)[...,None]
 Image.fromarray(np.uint8((nor*.5+.5)*255)).save(ROOT/(name+'_normal.png'))
 Image.fromarray(np.uint8(np.clip(rough,0,1)*255)).save(ROOT/(name+'_roughness.png'))
# Aggregate asphalt: fine aggregate, mottled wear, narrow tar repairs.
stone=np.clip(.66+fine*.075+(coarse-.5)*.17+(broad-.5)*.12,.3,1)
crack=Image.new('L',(N,N)); d=ImageDraw.Draw(crack)
for _ in range(13):
 pts=[]; xx=int(rng.integers(0,N)); yy=int(rng.integers(0,N))
 for j in range(8): pts.append((xx,yy)); xx+=int(rng.integers(-50,50)); yy+=int(rng.integers(12,65))
 d.line(pts,fill=255,width=int(rng.integers(1,4)))
c=np.asarray(crack)/255; asphalt=stone*(1-c*.5)
save('asphalt',asphalt,stone*.12-c*.04,np.clip(.77+coarse*.16-c*.25,0,1))
# Staggered cut stone pavers, 0.5x1m; dark mortar and bevels.
row=y//128; xx=(x+(row%2)*128)%256; yy=y%128
edge=np.minimum.reduce([xx,255-xx,yy,127-yy]); joint=edge<3; bevel=np.clip(edge/7,0,1)
variation=rng.random((8,5)); ids=(x+(row%2)*128)//256
pave=.67+(variation[row,ids]-.5)*.22+fine*.025+(coarse-.5)*.08
pave=np.where(joint,.25,pave)*(.85+.15*bevel)
save('pavers',np.stack([pave*1.04,pave,pave*.92],-1),bevel*.5+fine*.015,.82+fine*.025)
# Plaster is broad mineral staining with fine sand grain.
pl=.84+(coarse-.5)*.12+fine*.025
save('plaster',pl,coarse*.05+fine*.015,.91+fine*.02)
# Concrete expansion joints and subtle aggregate.
ce=.72+(coarse-.5)*.1+fine*.03; j=(x%512<3)|(y%512<3); ce[j]=.38
save('concrete',ce,np.where(j,0,.2)+fine*.015,.87+coarse*.08)
# Clay pantile rows: rounded raised ridges and offset overlap seams.
u=(x%64)/64; v=(y%128)/128; ridges=(np.cos(u*np.pi*2)*.5+.5)
rr=.7+ridges*.17+fine*.025+(coarse-.5)*.1; rr[v<.035]*=.5
save('tile',np.stack([rr,rr*.88,rr*.75],-1),ridges*.6+v*.1,.78+coarse*.1)
# Galvanized utility metal, satin not mirror.
mt=.76+fine*.035+(coarse-.5)*.08
save('metal',mt,fine*.006,.58+coarse*.13)
# Soil/ground cover under layered planted geometry.
gr=.58+fine*.08+(coarse-.5)*.22
save('soil',np.stack([gr,gr*.9,gr*.68],-1),fine*.03+coarse*.15,.95+fine*.01)
print('Authored',len(list(ROOT.glob('*.png'))),'PBR maps in',ROOT)
