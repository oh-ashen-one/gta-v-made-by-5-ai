"""Independent streamed R1/R2 invariants; no engine or source mutations."""
from pathlib import Path
import hashlib,json,sys
import numpy as np

def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return (json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)+'\n').encode()
def verify(source,target):
 old=json.loads((source/'manifest.json').read_bytes());new=json.loads((target/'manifest.json').read_bytes())
 for field in ('catalogs','counts','exclusions','world_y_policy','height_game_policy','road_source_audit','terrain_reference','georeference'):
  assert old[field]==new[field],field
 catalogs=0;surfaces=0;triangles=0;attributes=0
 for a,b in zip(old['catalogs'],new['catalogs']):
  assert a==b
  pa,pb=source/a['file'],target/b['file']
  # The repair uses hardlinks when on the same volume; prove that immutable
  # catalogs remain byte-identical without re-reading both copies.
  if (pa.stat().st_dev,pa.stat().st_ino)!=(pb.stat().st_dev,pb.stat().st_ino):assert pa.read_bytes()==pb.read_bytes()
  catalogs+=1
 assert len(old['meshes'])==len(new['meshes'])
 for a,b in zip(old['meshes'],new['meshes']):
  assert a['key']==b['key'] and a['features']==b['features']
  ar=(source/a['file']).read_bytes();br=(target/b['file']).read_bytes()
  av=(source/a['binary_file']).read_bytes();bv=(target/b['binary_file']).read_bytes()
  assert sha(ar)==a['sha256'] and sha(br)==b['sha256']
  assert sha(av)==a['binary_sha256'] and sha(bv)==b['binary_sha256']
  am,bm=json.loads(ar),json.loads(br);expected=json.loads(ar)
  assert len(am['features'])==len(bm['features'])
  for feature_index,(af,bf) in enumerate(zip(am['features'],bm['features'])):
   assert af['feature_key']==bf['feature_key'] and len(af['surfaces'])==len(bf['surfaces'])
   for surface_index,(s,t) in enumerate(zip(af['surfaces'],bf['surfaces'])):
    for key in ('role','vertex_offset_bytes','index_offset_bytes','vertex_count','index_count'):assert s[key]==t[key]
    vo,io,vc,ic=s['vertex_offset_bytes'],s['index_offset_bytes'],s['vertex_count'],s['index_count']
    assert av[vo:io]==bv[vo:io];attributes+=io-vo
    old_i=np.frombuffer(av,dtype='<u4',count=ic,offset=io).reshape(-1,3)
    new_i=np.frombuffer(bv,dtype='<u4',count=ic,offset=io).reshape(-1,3)
    assert np.array_equal(old_i[:,0],new_i[:,0]) and np.array_equal(old_i[:,1],new_i[:,2]) and np.array_equal(old_i[:,2],new_i[:,1])
    vertices=np.ndarray((vc,8),dtype='<f4',buffer=bv,offset=vo)
    for begin in range(0,len(new_i),65536):
     ix=new_i[begin:begin+65536];p=vertices[ix[:,0],:3].astype(np.float64);q=vertices[ix[:,1],:3].astype(np.float64);r=vertices[ix[:,2],:3].astype(np.float64)
     normals=vertices[ix[:,0],3:6].astype(np.float64)
     assert np.all(np.einsum('ij,ij->i',np.cross(q-p,r-p),normals)<0)
    assert sha(bv[vo:io+ic*4])==t['topology_sha256']
    expected['features'][feature_index]['surfaces'][surface_index]['topology_sha256']=t['topology_sha256']
    surfaces+=1;triangles+=ic//3
  expected['binary']['sha256']=bm['binary']['sha256']
  assert canonical(expected)==br,'Only topology hashes/binary hash may change in tile metadata'
 return {'status':'PASS','catalog_pages_unchanged':catalogs,'mesh_tiles_checked':len(new['meshes']),
  'surfaces_checked':surfaces,'triangles_checked':triangles,'vertex_normal_uv_bytes_unchanged':attributes,
  'all_indices_exactly_opposite_R1_order':True,'all_Godot_clockwise_dot_outward_negative':True,
  'only_allowed_mesh_metadata_hash_fields_changed':True,'height_exclusion_road_source_policies_unchanged':True,
  'parent_identity_sha256':sha((source/'identity.json').read_bytes()),'new_identity_sha256':sha((target/'identity.json').read_bytes()),
  'new_manifest_sha256':sha((target/'manifest.json').read_bytes())}
if __name__=='__main__':
 result=verify(Path(sys.argv[1]),Path(sys.argv[2]));Path(__file__).with_name('REPAIRED_INVARIANTS.json').write_bytes(canonical(result));print(json.dumps(result))
