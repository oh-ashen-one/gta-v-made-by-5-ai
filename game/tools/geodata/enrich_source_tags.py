#!/usr/bin/env python3
"""Versioned regional full-tag sidecar from an exact pinned private OSM PBF.

No geometry, measurement inference, absent=false interpretation or v1 mutation.
Only requested way/relation IDs are retained. No credentials or environment
values are read, and private source paths are excluded from reports/errors.
"""
import argparse
from collections import Counter,defaultdict
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
import time
from urllib.parse import urlsplit

import osmium

SCHEMA='singapore_regional_source_tags_v1'
HASH_RE=re.compile(r'^[0-9a-f]{64}$')
ID_RE=re.compile(r'^(way|relation)/([1-9][0-9]*)$')
MAX_METADATA_BYTES=32*1024*1024
MAX_TARGETS=10000

class EnrichmentError(ValueError):
    pass

def canonical_bytes(value):
    return (json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)+'\n').encode('utf-8')

def sha(data):return hashlib.sha256(data).hexdigest()

def sha_file(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def read_json(path):
    if path.is_symlink():raise EnrichmentError('Symlink metadata input refused')
    data=path.read_bytes()
    if not data or len(data)>MAX_METADATA_BYTES:raise EnrichmentError('Metadata input size outside bound')
    return json.loads(data),data

def source_id(value):
    if not isinstance(value,str):raise EnrichmentError('Source identity must be a typed OSM string')
    match=ID_RE.fullmatch(value)
    if match is None:raise EnrichmentError('Only positive way/relation source identities are supported')
    return match.group(1),int(match.group(2))

def string_tags(tags):
    if not isinstance(tags,dict) or not all(isinstance(k,str) and isinstance(v,str) for k,v in tags.items()):
        raise EnrichmentError('Full source tags must retain string keys and values')
    return deepcopy(tags)

def catalog_targets(catalog):
    if not isinstance(catalog,list) or not catalog or len(catalog)>MAX_TARGETS:
        raise EnrichmentError('Regional catalog must contain1..10000 features')
    targets=defaultdict(list);seen=set()
    for item in catalog:
        if not isinstance(item,dict):raise EnrichmentError('Catalog feature must be an object')
        identifier=item.get('id');source_id(identifier)
        kind=item.get('kind');key=item.get('feature_key')
        if not isinstance(kind,str) or not kind or key!=kind+'|'+identifier or key in seen:
            raise EnrichmentError('Catalog semantic identity is invalid/duplicated')
        checksum=item.get('source_feature_sha256')
        if not isinstance(checksum,str) or HASH_RE.fullmatch(checksum) is None:
            raise EnrichmentError('Catalog source feature checksum is required')
        seen.add(key)
        targets[identifier].append({'feature_key':key,'source_feature_sha256':checksum,'tags':string_tags(item.get('tags'))})
    return {key:sorted(items,key=lambda i:i['feature_key']) for key,items in sorted(targets.items())}

def public_url(value):
    if value is None:return None
    if not isinstance(value,str):raise EnrichmentError('Public provenance URL must be a string')
    url=urlsplit(value)
    if url.scheme not in ('https','http') or not url.hostname or url.username is not None or url.password is not None or url.query or url.fragment:
        raise EnrichmentError('Public provenance URL contains unsupported/private authentication fields')
    return value

def input_binding(catalog_path,patch_manifest_path,snapshot_manifest_path,expected_pbf_sha256):
    if not isinstance(expected_pbf_sha256,str) or HASH_RE.fullmatch(expected_pbf_sha256) is None:
        raise EnrichmentError('Exact expected PBF SHA256 is required')
    catalog,catalog_bytes=read_json(catalog_path)
    patch,patch_bytes=read_json(patch_manifest_path)
    snapshot,snapshot_bytes=read_json(snapshot_manifest_path)
    if not isinstance(patch,dict) or not isinstance(snapshot,dict):raise EnrichmentError('Input manifests must be objects')
    source=patch.get('source',{})
    if patch.get('schema')!='singapore_source_geometry_patch_v1' or patch.get('feature_catalog',{}).get('sha256')!=sha(catalog_bytes):
        raise EnrichmentError('Regional source catalog differs from its bound geometry patch')
    if source.get('snapshot_manifest_sha256')!=sha(snapshot_bytes):raise EnrichmentError('Geometry patch belongs to a different canonical snapshot')
    if snapshot.get('pbf_sha256')!=expected_pbf_sha256 or source.get('source',{}).get('pbf_sha256')!=expected_pbf_sha256:
        raise EnrichmentError('Canonical/patch PBF identity differs from explicitly pinned input')
    if source.get('source',{}).get('source_snapshot_utc')!=snapshot.get('source_snapshot_utc'):
        raise EnrichmentError('Canonical and patch snapshot timestamps conflict')
    targets=catalog_targets(catalog)
    binding={'pbf_sha256':expected_pbf_sha256,'source_snapshot_utc':snapshot.get('source_snapshot_utc'),
        'canonical_snapshot_manifest_sha256':sha(snapshot_bytes),'geometry_patch_manifest_sha256':sha(patch_bytes),
        'regional_source_catalog_sha256':sha(catalog_bytes),'logical_features':len(catalog),'source_ids':len(targets)}
    provenance={'source_url':public_url(snapshot.get('source_url')),'attribution':snapshot.get('attribution'),
        'data_license':snapshot.get('data_license'),'license_url':public_url(snapshot.get('license_url'))}
    if provenance['data_license']!='ODbL-1.0' or provenance['attribution']!='© OpenStreetMap contributors':
        raise EnrichmentError('Expected separate OSM attribution/ODbL contract is missing')
    return targets,binding,provenance

class TagCollector(osmium.SimpleHandler):
    def __init__(self,targets):
        super().__init__();self.targets=targets;self.found={};self.duplicate_source_ids=[]
    def observe(self,kind,identifier,tags,metadata):
        if kind not in ('way','relation') or not isinstance(identifier,int) or isinstance(identifier,bool) or identifier<=0:
            raise EnrichmentError('Invalid typed source observation')
        key=f'{kind}/{identifier}'
        if key not in self.targets:return
        item={'source_tags':string_tags(tags),'osm_metadata':deepcopy(metadata)}
        if key in self.found:
            self.duplicate_source_ids.append(key)
            return # Ambiguous source is rejected by audit, never last-writer wins.
        self.found[key]=item
    def _object(self,kind,obj):
        key=f'{kind}/{obj.id}'
        if key not in self.targets:return
        stamp=str(obj.timestamp)
        if stamp.startswith('1970-01-01'):stamp=None
        self.observe(kind,int(obj.id),dict(obj.tags),{
            'version':int(obj.version) if obj.version>0 else None,
            'timestamp_utc':stamp,'changeset':int(obj.changeset) if obj.changeset>0 else None,
            'visible':bool(obj.visible),'metadata_note':'Null version/time means unavailable in this extract, not an invented source revision'})
    def way(self,obj):self._object('way',obj)
    def relation(self,obj):self._object('relation',obj)

def scan_pbf(path,targets,expected_sha256):
    if path.is_symlink():raise EnrichmentError('Private PBF symlink refused')
    before=path.stat()
    if sha_file(path)!=expected_sha256:raise EnrichmentError('Private PBF bytes differ from the exact pinned SHA256')
    collector=TagCollector(targets)
    reader=osmium.io.Reader(str(path),osmium.osm.osm_entity_bits.WAY|osmium.osm.osm_entity_bits.RELATION)
    try:
        header=reader.header()
        header_metadata={k:header.get(k) or None for k in ('osmosis_replication_timestamp','osmosis_replication_sequence_number','generator')}
        # No location cache, geometry assembly or node callbacks are requested.
        osmium.apply(reader,collector)
    finally:reader.close()
    after=path.stat()
    if (before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_ino,after.st_size,after.st_mtime_ns):
        raise EnrichmentError('Private PBF changed during verification/metadata scan')
    return collector,header_metadata

def enrich(targets,found,binding,provenance,*,header_metadata=None,duplicate_source_ids=()):
    records={};conflicts=[];missing=[];added=Counter();present=Counter();matched=0
    duplicates=sorted(set(duplicate_source_ids))
    for identifier,features in sorted(targets.items()):
        kind,osm_id=source_id(identifier);observed=found.get(identifier)
        base={'osm_type':kind,'osm_id':osm_id,'feature_keys':[i['feature_key'] for i in features],
            'canonical_feature_sha256':{i['feature_key']:i['source_feature_sha256'] for i in features}}
        if observed is None:
            missing.append(identifier);records[identifier]={**base,'status':'unresolved_missing_source_id','source_tags':None,'osm_metadata':None};continue
        tags=string_tags(observed.get('source_tags'));local_conflicts=[];old_keys=set()
        for f in features:
            for tag,value in f['tags'].items():
                old_keys.add(tag)
                if tag not in tags or tags[tag]!=value:
                    local_conflicts.append({'source_id':identifier,'feature_key':f['feature_key'],'tag':tag,
                        'canonical_v1_value':value,'pbf_value':tags.get(tag),'pbf_tag_present':tag in tags})
        conflicts.extend(local_conflicts)
        for tag in tags:present[tag]+=1
        for tag in set(tags)-old_keys:added[tag]+=1
        status='unresolved_duplicate_source_id' if identifier in duplicates else ('conflict_with_canonical_v1' if local_conflicts else 'exact_canonical_tags_match')
        if status=='exact_canonical_tags_match':matched+=1
        records[identifier]={**base,'status':status,'source_tags':tags,'source_tags_sha256':sha(canonical_bytes(tags)),
            'osm_metadata':deepcopy(observed.get('osm_metadata')),'additional_tag_keys':sorted(set(tags)-old_keys),
            'canonical_tag_conflicts':local_conflicts}
    header_metadata=deepcopy(header_metadata or {})
    header_time=header_metadata.get('osmosis_replication_timestamp')
    time_conflict=header_time is not None and header_time!=binding.get('source_snapshot_utc')
    ready=not missing and not conflicts and not duplicates and not time_conflict
    return {'schema':SCHEMA,'binding':deepcopy(binding),'source_attribution':deepcopy(provenance),
        'pbf_header_metadata':header_metadata,'records':records,
        'audit':{'ready_for_exact_bound_tag_overlay':ready,'source_ids_requested':len(targets),
            'source_ids_found':len(records)-len(missing),'exact_canonical_tag_matches':matched,
            'missing_source_ids':missing,'conflicts':conflicts,'duplicate_source_ids':duplicates,
            'header_snapshot_time_conflict':time_conflict,
            'additional_tag_counts_by_source_id':dict(sorted(added.items())),
            'all_tag_counts_by_source_id':dict(sorted(present.items()))},
        'merge_contract':{'geometry_changed':False,'canonical_v1_mutated':False,
            'missing_tag_is_false':False,'inferred_measurements':False,
            'accept_only_exact_bound_catalog_and_pbf':True,
            'reject_conflict_missing_duplicate_or_snapshot_time_conflict':True,
            'overlay_semantics':'Only exact_canonical_tags_match records may supply a new read-only full-tag view for every referenced semantic feature key. Never overwrite source geometry, old feature hashes, parsed heights or canonical tags.',
            'absent_tag_meaning':'Not supplied by this exact source object in this snapshot; not a real-world negative assertion.',
            'source_values':'All original tag strings preserved verbatim. No height/width/elevation conversion or driveability inference is performed.'},
        'limitations':['Regional metadata only, not national enrichment or completed city geometry.',
            'OSM tag presence is not independent survey, access-law or architectural/vertical accuracy verification.',
            'Missing metric terrain, road width/elevation, and interior fit-out are not resolved through estimates.']}

def write_sidecar(output,document):
    if output.exists():raise EnrichmentError('Refusing to overwrite prior metadata evidence')
    output.parent.mkdir(parents=True,exist_ok=True)
    data=canonical_bytes(document)
    with output.open('xb') as f:f.write(data)
    return {'schema':SCHEMA,'sidecar_sha256':sha(data),'bytes':len(data),
        'ready_for_exact_bound_tag_overlay':document['audit']['ready_for_exact_bound_tag_overlay'],
        'source_ids_requested':document['audit']['source_ids_requested'],
        'source_ids_found':document['audit']['source_ids_found'],
        'conflicts':len(document['audit']['conflicts']),'missing_source_ids':len(document['audit']['missing_source_ids'])}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pbf',type=Path,required=True);p.add_argument('--expected-pbf-sha256',required=True)
    p.add_argument('--catalog',type=Path,required=True);p.add_argument('--patch-manifest',type=Path,required=True)
    p.add_argument('--snapshot-manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();started=time.monotonic()
    try:
        targets,binding,provenance=input_binding(args.catalog,args.patch_manifest,args.snapshot_manifest,args.expected_pbf_sha256)
        collector,header=scan_pbf(args.pbf,targets,args.expected_pbf_sha256)
        doc=enrich(targets,collector.found,binding,provenance,header_metadata=header,duplicate_source_ids=collector.duplicate_source_ids)
        report=write_sidecar(args.output,doc);report['scan_and_verify_seconds']=round(time.monotonic()-started,3)
        print(json.dumps(report,sort_keys=True),flush=True)
        return 0 if report['ready_for_exact_bound_tag_overlay'] else 1
    except EnrichmentError as e:
        print(json.dumps({'status':'failed','reason':str(e)}),flush=True);return 2
    except Exception:
        # Native exception text may contain private paths. Report its safe class
        # at the caller, not full messages/tracebacks or environmental values.
        print(json.dumps({'status':'failed','reason':'Input I/O, JSON or OSM parser failure; no private source paths emitted'}),flush=True);return 2

if __name__=='__main__':raise SystemExit(main())
