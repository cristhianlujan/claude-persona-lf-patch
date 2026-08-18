#!/usr/bin/env python3
from __future__ import annotations
import ast,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
GRADERS=[ROOT/'scripts/p0_visual_grader_text_v4.py',ROOT/'scripts/p0_visual_grader_object_v4.py',ROOT/'scripts/p0_visual_grader_structure_v4.py']
READER_FILES=[ROOT/'scripts/p0_full_reader_v4.py',ROOT/'scripts/p0_full_reader_v4_core.py']
EXTERNAL_GUARDS={'previous_full_pass_candidate_sha256':'anti-reuse input guard; absence is safe and the same grader also checks fresh_source_read/reader_origin'}

def consumed_fields(path:Path)->dict[str,set[str]]:
 tree=ast.parse(path.read_text(encoding='utf-8'));out={'element':set(),'candidate':set()}
 for n in ast.walk(tree):
  if not isinstance(n,ast.Call) or not isinstance(n.func,ast.Attribute) or n.func.attr!='get' or not n.args or not isinstance(n.args[0],ast.Constant) or not isinstance(n.args[0].value,str):continue
  recv=n.func.value
  if isinstance(recv,ast.Name) and recv.id=='e':out['element'].add(n.args[0].value)
  elif isinstance(recv,ast.Name) and recv.id=='candidate':out['candidate'].add(n.args[0].value)
 return out

def produced_keys(path:Path)->set[str]:
 tree=ast.parse(path.read_text(encoding='utf-8'));keys=set()
 for n in ast.walk(tree):
  if isinstance(n,ast.Dict):
   for k in n.keys:
    if isinstance(k,ast.Constant) and isinstance(k.value,str):keys.add(k.value)
 return keys

def main():
 missing_producers=[str(path) for path in READER_FILES if not path.is_file()];assert not missing_producers,missing_producers
 wrapper=READER_FILES[0].read_text(encoding='utf-8');assert 'import p0_full_reader_v4_core as _core' in wrapper,'CANONICAL_READER_CORE_BINDING_MISSING'
 produced=set().union(*(produced_keys(path) for path in READER_FILES));consumed={'element':set(),'candidate':set()};by_file={}
 for path in GRADERS:
  fields=consumed_fields(path);by_file[path.name]={k:sorted(v) for k,v in fields.items()};consumed['element'].update(fields['element']);consumed['candidate'].update(fields['candidate'])
 all_consumed=consumed['element']|consumed['candidate'];missing=sorted(f for f in all_consumed if f not in produced);unresolved=sorted(f for f in missing if f not in EXTERNAL_GUARDS);classified={f:EXTERNAL_GUARDS[f] for f in missing if f in EXTERNAL_GUARDS}
 required_live={'text_group_consistency','source_observation_refs','subcomponent_role','brand_mark_score','business_rule_claim','business_rule_visible_evidence','risk_zone','fresh_source_read','reader_origin'}
 live_missing=sorted(required_live-produced);assert not live_missing,live_missing;assert not unresolved,{'unresolved':unresolved,'missing':missing,'by_file':by_file,'produced':sorted(produced)}
 print(json.dumps({'gate':'PASS_V4_GRADER_PRODUCER_FIELD_AUDIT','grader_files':[p.name for p in GRADERS],'producer_files':[p.name for p in READER_FILES],'core_binding_verified':True,'consumed_direct_field_count':len(all_consumed),'produced_key_count':len(produced),'missing_fields':missing,'external_guard_fields':classified,'unresolved_inert_fields':unresolved,'required_live_fields':sorted(required_live),'required_live_missing':live_missing},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
