"""CPU project Blender-evaluated NPZs, not rendered gameplay evidence.
Run rig_characters.py --diagnostics /tmp/astra_rig_samples first.
Requires local Python numpy and Pillow; no engine or GPU is launched.
"""
import pathlib,numpy as np
from PIL import Image,ImageDraw,ImageFont
repo=pathlib.Path(__file__).resolve().parents[3]
folder=pathlib.Path('/tmp/astra_rig_samples')
labels=['idle','walk_contact','walk_swing','run_swing','aim','hit','fall','seated','drive']
for name in ['player','officer','civilian']:
 source='player' if name=='civilian' else name
 tex=np.asarray(Image.open(next((repo/'game/assets/providers').glob(source+'_clean_Color*jpg'))))
 canvas=Image.new('RGB',(len(labels)*300,1300),(34,39,46));draw=ImageDraw.Draw(canvas)
 for idx,label in enumerate(labels):
  p=folder/(name+'_'+label+'.npz')
  if not p.exists():continue
  a=np.load(p);verts=a['positions'];tri=a['triangles'];uv=a['uv'].mean(axis=1)
  ix=np.clip((uv[:,0]*tex.shape[1]).astype(int),0,tex.shape[1]-1);iy=np.clip(((1-uv[:,1])*tex.shape[0]).astype(int),0,tex.shape[0]-1);colors=tex[iy,ix,:3].copy()
  if source=='player' and 'materials' in a:
   colors[a['materials']==2]=[72,77,79]
   colors[a['materials']==3]=[121,125,127]
  for row,kind in enumerate(['front','side']):
   horiz=0 if row==0 else 1;depth_axis=1 if row==0 else 0
   pts=np.stack([verts[:,horiz],verts[:,2]],axis=1)*300
   pts[:,0]+=idx*300+150;pts[:,1]=row*650+610-pts[:,1]
   depth=verts[tri,depth_axis].mean(axis=1)
   for t in np.argsort(depth):draw.polygon([tuple(p) for p in pts[tri[t]]],fill=tuple(colors[t]))
   draw.text((idx*300+15,row*650+18),f'{name} {label} | {kind}',fill='white')
   draw.line((idx*300,row*650+611,(idx+1)*300,row*650+611),fill=(80,90,100),width=1)
 draw.text((15,1280),'CPU-projected evaluated Blender skin; diagnostic only, not in-game capture.',fill=(185,192,200))
 canvas.save(repo/'docs/wave-02/characters'/(name+'_rig_round01.png'));print(name,'saved')
