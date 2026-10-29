"""Remove only Finder/resource-fork metadata from the owned copied app.
This deliberately preserves quarantine, provenance and every other attribute.
"""
import subprocess
from pathlib import Path

def clean(app:Path)->list:
    app=app.resolve()
    rows=subprocess.check_output(['/usr/bin/xattr','-r',str(app)],text=True).splitlines()
    removed=[]
    for row in rows:
        path,sep,key=row.rpartition(': ')
        if not sep or key not in ('com.apple.FinderInfo','com.apple.ResourceFork'):continue
        target=Path(path).resolve()
        if target!=app and app not in target.parents:raise ValueError('Metadata target outside owned app')
        subprocess.run(['/usr/bin/xattr','-d',key,str(target)],check=True)
        removed.append({'path':str(target.relative_to(app)),'attribute':key})
    return removed
