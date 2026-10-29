#!/usr/bin/env python3
"""Small lexical scope/signature scan, NOT a replacement for Godot parsing."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re
root=Path(__file__).resolve().parents[3]
path=root/'game/src/systems/fidelity_tests/mbs_public_core_entry_test.gd'
text=path.read_text();findings=[];functions={};scope={};current=None
for number,line in enumerate(text.splitlines(),1):
 stripped=line.strip();indent=len(line)-len(line.lstrip('\t'))
 if line.startswith('func '):
  match=re.match(r'func\s+(\w+)\((.*?)\).*',line)
  if not match:continue
  current=match.group(1);functions[current]=number
  params=set(re.findall(r'(?:^|,)\s*(\w+)\s*:',match.group(2)))
  scope={1:{p:('parameter',number) for p in params}}
  continue
 if current is None or not stripped or stripped.startswith('#'):continue
 if indent==0:current=None;continue
 for level in list(scope):
  if level>indent:scope.pop(level)
 scope.setdefault(indent,{})
 declarations=[]
 for m in re.finditer(r'(?:^|;)\s*var\s+(\w+)\b',stripped):declarations.append((m.group(1),indent,'var'))
 m=re.match(r'for\s+(\w+)\s*(?::[^\s]+)?\s+in\b',stripped)
 if m:declarations.append((m.group(1),indent+1,'for'))
 for name,level,kind in declarations:
  existing=[(old,where) for old,where in scope.items() if old<=level and name in where]
  if existing:findings.append({'function':current,'line':number,'name':name,'kind':kind,'visible_previous':existing[0][1][name]})
  # A one-line for loop's index has no retained child block.
  inline_for=kind=='for' and ':' in stripped and not stripped.endswith(':')
  if not inline_for:scope.setdefault(level,{})[name]=(kind,number)
parent=(root/'game/src/systems/fidelity_tests/mbs_guest_floor_test.gd').read_text()
required=['frames','prepare_player','capsule_clear','ray','walk_public_to','walk_to','native_e','_light_fixture']
helpers={name:bool(re.search(r'^func '+name+r'\(',parent,re.M)) for name in required}
result={'created_utc':datetime.now(timezone.utc).isoformat(),'method':'LEXICAL_INDENTATION_NAME_AND_HELPER_PRESENCE_SCAN_NOT_GODOT_COMPILER','source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'functions':functions,'scope_findings':findings,'required_inherited_helpers_present':helpers,'engine_parse_verified':False,'native_runtime_verified':False}
Path(__file__).with_name('QA_SCOPE_AUDIT.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'scope_findings':findings,'required_inherited_helpers_present':helpers,'source_sha256':result['source_sha256'],'engine_parse_verified':False}))
assert not findings
assert all(helpers.values())
