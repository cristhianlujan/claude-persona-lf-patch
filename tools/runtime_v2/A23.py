#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, json
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[2]
SKILL=ROOT/'skills'/'creating-integral-user-stories'

def paths(d):
 r=[]
 for v in d.get('files',{}).values():
  if isinstance(v,list): r += [str(x) for x in v]
 return r

def findings(d):
 p=paths(d); f=[]; g=d.get('github_contract',{}); q=d.get('quality_policy',{}); s=d.get('current_state',{})
 if d.get('package_contract',{}).get('canonical_file_count')!=62: f.append('canonical_file_count')
 if len(p)!=62 or len(set(p))!=62: f.append('canonical_inventory_cardinality')
 missing=[x for x in p if not (SKILL/x).is_file()]
 if missing: f.append('missing_paths')
 if set(p)&set(d.get('auxiliary_files',[])): f.append('auxiliary_canonical_overlap')
 if g.get('base_branch')!='feat/integral-story-creator-r8-forward' or g.get('target_branch')!='fix/deep-audit-a01-a62': f.append('branch_contract')
 if g.get('direct_main_write')!='BLOCKED' or g.get('merge_allowed') is not False: f.append('write_safety')
 if q.get('benchmark_gate')!='DUAL_REQUIRED' or q.get('score_formula')!='MIN(CLAUDE,GITHUB,TECHNICAL)': f.append('quality_formula')
 if any('stars_verified' in x for x in q.get('github_references',[])): f.append('temporal_star_count')
 if s.get('production_authorized') or s.get('merge_authorized') or s.get('runtime_enabled'): f.append('operational_authorization')
 return sorted(set(f))

def case(name,d,expected):
 f=findings(d); actual='PASS_WITH_EVIDENCE' if not f else 'RETURN_TO_WORKER'; return {'case':name,'expected':expected,'actual':actual,'findings':f,'passed':actual==expected}

def main():
 d=yaml.safe_load((SKILL/'manifest.yaml').read_text())
 cases=[case('positive',copy.deepcopy(d),'PASS_WITH_EVIDENCE')]
 x=copy.deepcopy(d); x['files']['agents'].append(x['files']['agents'][0]); cases.append(case('duplicate_path',x,'RETURN_TO_WORKER'))
 x=copy.deepcopy(d); x['github_contract']['target_branch']='main'; x['github_contract']['direct_main_write']='ALLOWED'; cases.append(case('unsafe_branch',x,'RETURN_TO_WORKER'))
 x=copy.deepcopy(d); x['package_contract']['canonical_file_count']=61; cases.append(case('wrong_count',x,'RETURN_TO_WORKER'))
 out={'artifact':'A23','passed':all(c['passed'] for c in cases),'cases':cases,'manifest_sha256':hashlib.sha256((SKILL/'manifest.yaml').read_bytes()).hexdigest()}
 print(json.dumps(out,ensure_ascii=False,sort_keys=True)); return 0 if out['passed'] else 1
if __name__=='__main__': raise SystemExit(main())
