"""Independent source encoding/interpolation/seams, not surveyed ground QA."""
import gzip
import json
from pathlib import Path
import struct
import tempfile
import unittest
import numpy as np
from shapely.geometry import box
from compile_terrain import (TerrainError,VOID,HgtPair,STORED,CHUNK_BYTES,TILES,
    bounded_gunzip,decode_hgt,chunk_indices,compile_chunks,verify_shared_edge,sha,sha_file)

def plane_pair():
    row,col=np.meshgrid(np.arange(3),np.arange(5),indexing='ij')
    full=(100+row*3+col*10).astype(np.int16)
    return HgtPair(full[:,:3],full[:,2:]),full

class TerrainTests(unittest.TestCase):
    def test_big_endian_signed_height_and_void_decode(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'fixture.hgt';p.write_bytes(struct.pack('>hhhh',123,-20,VOID,400))
            a=decode_hgt(p,samples=2)
            self.assertEqual(a.tolist(),[[123,-20],[VOID,400]])
            self.assertNotEqual(struct.unpack('<h',p.read_bytes()[:2])[0],123)
            with self.assertRaises(TerrainError):decode_hgt(p,samples=3)
    def test_bilinear_known_plane_and_north_to_south_orientation(self):
        pair,_=plane_pair()
        self.assertAlmostEqual(float(pair.sample(103.25,1.75)),106.5)
        self.assertEqual(float(pair.sample(103,2)),100.)
        self.assertEqual(float(pair.sample(103,1)),106.)
        self.assertEqual(float(pair.sample(105,1)),146.)
    def test_shared_native_tile_postings_keep_seam_identity(self):
        pair,_=plane_pair();self.assertEqual(pair.seam_conflicts,0)
        self.assertEqual(float(pair.sample(104,1.5)),123.)
        self.assertAlmostEqual(float(pair.sample(104-1e-7,1.5)),float(pair.sample(104+1e-7,1.5)),places=4)
    def test_disagreeing_source_seam_unknown_not_averaged(self):
        pair,full=plane_pair();east=full[:,2:].copy();east[1,0]+=5
        pair=HgtPair(full[:,:3],east)
        self.assertEqual(pair.seam_conflicts,1)
        self.assertTrue(np.isnan(pair.sample(104,1.5)))
    def test_void_requires_only_nonzero_weight_source_posts(self):
        _,full=plane_pair();full[1,1]=VOID;pair=HgtPair(full[:,:3],full[:,2:])
        self.assertTrue(np.isnan(pair.sample(103.25,1.75)))
        self.assertEqual(float(pair.sample(103,2)),100.)
    def test_outside_or_nonfinite_source_coverage_unknown(self):
        pair,_=plane_pair()
        for lon,lat in [(102.9,1.5),(105.1,1.5),(104,.9),(104,2.1),(float('nan'),1.5)]:self.assertTrue(np.isnan(pair.sample(lon,lat)))
    def test_negative_global_indices_are_exact_and_halo_shared(self):
        a,b=chunk_indices(-2,-3);c,d=chunk_indices(-1,-3)
        self.assertEqual(a.shape,(43,43));self.assertEqual(int(a[0,0]),-81);self.assertEqual(int(b[0,0]),-121)
        self.assertTrue(np.array_equal(a[:,-3:],c[:,:3]));self.assertTrue(np.array_equal(b[:,-3:],d[:,:3]))
        self.assertEqual(int(a[0,1])*25,-2000)
    def test_bounded_gzip_exact_bytes_crc_and_exclusive_output(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);payload=b'12345678';(p/'a.gz').write_bytes(gzip.compress(payload))
            self.assertEqual(bounded_gunzip(p/'a.gz',p/'a.hgt',expected=8),sha(payload))
            self.assertEqual((p/'a.hgt').read_bytes(),payload)
            with self.assertRaises(FileExistsError):bounded_gunzip(p/'a.gz',p/'a.hgt',expected=8)
            with self.assertRaises(TerrainError):bounded_gunzip(p/'a.gz',p/'small.hgt',expected=7)
            self.assertFalse((p/'small.hgt').exists());self.assertFalse((p/'small.hgt.part').exists())
    def test_small_compiler_keeps_binary_halo_seams_and_no_overwrite(self):
        class FixturePair:
            def global_grid(self,gx,gz):return (100+gx*.25+gz*.5).astype('<f4')
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'new';inventory,seams=compile_chunks(FixturePair(),box(1,1,1999,1999),p)
            self.assertEqual(len(inventory),4);self.assertEqual(seams,4)
            a=np.fromfile(p/'0_0.f32',dtype='<f4').reshape(STORED,STORED)
            b=np.fromfile(p/'1_0.f32',dtype='<f4').reshape(STORED,STORED)
            self.assertTrue(verify_shared_edge(a,b,'x'));self.assertEqual((p/'0_0.f32').stat().st_size,CHUNK_BYTES)
            self.assertEqual(struct.unpack('<f',(p/'0_0.f32').read_bytes()[:4])[0],99.25)
            for item in inventory:self.assertEqual(sha_file(p/item['file']),item['sha256'])
            with self.assertRaises(TerrainError):compile_chunks(FixturePair(),box(1,1,1999,1999),p)
    def test_nodata_nan_has_consistent_shared_edge_bits(self):
        a=np.zeros((43,43),dtype='<f4');b=a.copy();a[:,-3:]=np.nan;b[:,:3]=np.nan
        self.assertTrue(verify_shared_edge(a,b,'x'))
    def test_download_allowlist_is_exactly_two_public_no_key_endpoints(self):
        self.assertEqual(set(TILES),{'N01E103','N01E104'})
        for key,url in TILES.items():
            self.assertEqual(url,'https://s3.amazonaws.com/elevation-tiles-prod/skadi/N01/'+key+'.hgt.gz')
            self.assertNotIn('?',url)
    def test_actual_source_posting_matches_independent_struct_decoder(self):
        base=Path('/private/tmp/orchard-geodata/terrain')
        west=base/'N01E103.hgt';east=base/'N01E104.hgt'
        pair=HgtPair(decode_hgt(west),decode_hgt(east))
        for tile,row,col in [('N01E103',1000,1000),('N01E103',2000,2500),('N01E104',2500,1500)]:
            with (base/(tile+'.hgt')).open('rb') as f:f.seek(2*(row*3601+col));known=struct.unpack('>h',f.read(2))[0]
            lon=(103 if tile.endswith('103') else 104)+col/3600.;lat=2-row/3600.
            value=float(pair.sample(lon,lat))
            if known==VOID:self.assertTrue(np.isnan(value))
            else:self.assertAlmostEqual(value,known,places=7)
            receipt=json.loads((base/(tile+'.download.json')).read_bytes())
            self.assertEqual(sha_file(base/(tile+'.hgt')),receipt['hgt_sha256'])
            self.assertEqual(receipt['http_status'],200)

if __name__=='__main__':unittest.main()
