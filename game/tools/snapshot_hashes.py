"""Reuse artifact SHA256 only while full filesystem change identity matches.

This is a local build cache, not an adversarial tamper-proof attestation. Code
and project source remain freshly hashed by the supervisor on every run.
"""
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path

def signature(path):
    s=path.stat()
    return [s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns]

def snapshot(paths,cache_path):
    cache_path=Path(cache_path)
    cache_path.parent.mkdir(parents=True,exist_ok=True)
    result={};stats={'fresh_files':0,'cached_files':0,'fresh_bytes':0,'validation':'SHA256 cached only for unchanged dev/inode/size/mtime_ns/ctime_ns; not adversarial timestamp attestation'}
    with cache_path.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        try: cache=json.loads(cache_path.read_text())
        except (OSError,ValueError): cache={}
        updated={}
        for path in paths:
            path=Path(path);key=str(path.resolve());before=signature(path)
            old=cache.get(key,{})
            if isinstance(old,dict) and old.get('signature')==before and isinstance(old.get('sha256'),str) and re.fullmatch('[0-9a-f]{64}',old['sha256']):
                digest=old['sha256'];stats['cached_files']+=1
            else:
                for attempt in range(2):
                    before=signature(path);h=hashlib.sha256()
                    with path.open('rb') as source:
                        for block in iter(lambda:source.read(1024*1024),b''): h.update(block)
                    if signature(path)==before: break
                else: raise RuntimeError('Artifact changed during snapshot: '+key)
                digest=h.hexdigest();stats['fresh_files']+=1;stats['fresh_bytes']+=before[2]
            updated[key]={'signature':before,'sha256':digest};result[path]=digest
        temporary=cache_path.with_name(cache_path.name+'.'+str(os.getpid())+'.part')
        with temporary.open('x') as target: json.dump(updated,target,separators=(',',':'))
        temporary.replace(cache_path)
    return result,stats
