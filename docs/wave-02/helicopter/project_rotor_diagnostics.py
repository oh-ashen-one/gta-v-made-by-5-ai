"""CPU project the evaluated source partitions; not an in-game render."""
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3]
a=np.load('/tmp/astra_heli_refined.npz');base=a['vertices'];tri=a['triangles'];uv=a['uv'].mean(axis=1);roles=a['roles'];pivots=a['pivots']
tex=np.asarray(Image.open(next((ROOT/'game/assets/providers').glob('helicopter_clean_Color*jpg'))))
rgb=tex[np.clip(((1-uv[:,1])*tex.shape[0]).astype(int),0,tex.shape[0]-1),np.clip((uv[:,0]*tex.shape[1]).astype(int),0,tex.shape[1]-1),:3]
canvas=Image.new('RGB',(2100,1300),(45,52,59));draw=ImageDraw.Draw(canvas)
for column,angle in enumerate([0,45,90]):
 v=base.copy()
 for role in [1,2]:
  indices=np.unique(tri[roles==role]);p=v[indices]-pivots[role];r=np.deg2rad(angle*(1 if role==1 else 2.4));c=np.cos(r);s=np.sin(r)
  R=np.array([[c,-s,0],[s,c,0],[0,0,1]]) if role==1 else np.array([[1,0,0],[0,c,-s],[0,s,c]])
  v[indices]=p@R.T+pivots[role]
 for row,(axis,vertical,depth,label) in enumerate([(1,2,0,'side'),(1,0,2,'top')]):
  pts=v[:,[axis,vertical]].copy()*78;pts[:,0]+=column*700+350;pts[:,1]=(500 if row==0 else 980)-pts[:,1]
  for ti in np.argsort(v[tri,depth].mean(axis=1)):
   color=rgb[ti].astype(float)
   if roles[ti]==1:color=color*.65+np.array([25,215,215])*.35
   if roles[ti]==2:color=color*.6+np.array([255,130,30])*.4
   draw.polygon([tuple(q) for q in pts[tri[ti]]],fill=tuple(color.astype(int)))
  draw.text((column*700+15,row*650+20),f'{label} | main={angle}deg tail={angle*2.4:.0f}deg',fill='white')
  draw.text((column*700+15,row*650+38),'nose right on sheet = Godot -Z',fill=(190,205,215))
  for role in [1,2]:
   p=pivots[role];px=p[axis]*78+column*700+350;py=(500 if row==0 else 980)-p[vertical]*78
   draw.ellipse((px-4,py-4,px+4,py+4),outline='red',width=2)
draw.text((15,1278),'Source geometry preserved. Cyan=main assembly, orange=tail blades. CPU diagnostic, not rendered acceptance.',fill=(210,215,220))
canvas.save(ROOT/'docs/wave-02/helicopter/rotor_partition_spin.png')
