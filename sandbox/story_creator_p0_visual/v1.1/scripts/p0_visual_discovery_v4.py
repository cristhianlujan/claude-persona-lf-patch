#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json
from typing import Any
from p0_visual_graders_v4 import GRADERS, canonical_sha

def applicable_graders(e:dict)->set[str]:
    out=set(GRADERS)
    if not (e.get('visible_text') or e.get('element_type') in {'TEXT','LABEL','HEADING','LINK','BUTTON_TEXT','BADGE_TEXT','INPUT_TEXT'}): out.discard('J-TEXT')
    return out

def union_findings(outputs:list[dict])->list[dict]:
    seen=set(); out=[]
    for g in outputs:
      for f in g.get('findings',[]):
        key=(f.get('category'),f.get('element_id'),canonical_sha(f.get('observed_evidence')))
        if key not in seen: seen.add(key); out.append(f)
    return out

def coverage_receipt(candidate:dict,outputs:list[dict],ctx:dict)->dict:
    by={o.get('grader_id'):o for o in outputs}; errors=[]
    missing=[g for g in GRADERS if g not in by]
    for g in missing: errors.append({'grader_id':g,'error':'MISSING_GRADER_OUTPUT'})
    execs=[]
    for g,o in by.items():
      eid=o.get('execution_id'); execs.append(eid)
      if o.get('error'): errors.append({'grader_id':g,'error':'GRADER_ERROR:'+str(o['error'])})
      if o.get('reader_execution_id')!=ctx['reader_execution_id']: errors.append({'grader_id':g,'error':'STALE_READER_EXECUTION'})
      if o.get('source_sha256')!=ctx['source_sha256'] or o.get('candidate_sha256')!=ctx['candidate_sha256']: errors.append({'grader_id':g,'error':'HASH_BINDING_MISMATCH'})
      if o.get('coverage_complete') is not True: errors.append({'grader_id':g,'error':'COVERAGE_INCOMPLETE'})
      if not o.get('screen_regions_evaluated'): errors.append({'grader_id':g,'error':'EMPTY_REGION_OUTPUT'})
    if len([x for x in execs if x])!=len(set(x for x in execs if x)): errors.append({'grader_id':'J-COVERAGE','error':'DUPLICATE_GRADER_EXECUTION_ID'})
    matrix=[]
    for e in candidate.get('elements',[]):
      req=applicable_graders(e); done={g for g,o in by.items() if e['element_id'] in set(o.get('evaluated_element_ids') or [])}
      complete=req<=done
      if not complete: errors.append({'grader_id':'J-COVERAGE','error':f"ELEMENT_NOT_FULLY_EVALUATED:{e['element_id']}"})
      refs=[]
      for g in req:
        for f in by.get(g,{}).get('findings',[]):
          if f.get('element_id')==e['element_id']: refs.extend(f.get('evidence_refs') or [])
      matrix.append({'element_id':e['element_id'],'applicable_graders':sorted(req),'evaluated_graders':sorted(done & req),'evidence_refs':sorted(set(refs)),'complete':complete})
    regions=[]
    material=[r for r in candidate.get('coverage_map',[]) if r.get('material',True)] or [{'region_id':'FULL'}]
    complete_sweeps=set(by.get('J-COMPLETE',{}).get('screen_regions_evaluated') or [])
    for r in material:
      rid=str(r.get('region_id','FULL')); status='COMPLETE' if rid in complete_sweeps or 'FULL' in complete_sweeps else 'INCOMPLETE'
      if status!='COMPLETE': errors.append({'grader_id':'J-COVERAGE','error':'REGION_SWEEP_INCOMPLETE:'+rid})
      regions.append({'region_id':rid,'omission_sweep_status':status,'evidence_refs':['coverage://'+rid] if status=='COMPLETE' else []})
    denom=max(1,len(matrix)+len(regions)); numer=sum(m['complete'] for m in matrix)+sum(r['omission_sweep_status']=='COMPLETE' for r in regions)
    pct=100.0*numer/denom
    pass_=not errors and pct==100.0 and len(by)==len(GRADERS)
    return {'schema_version':'p0-grader-coverage-v4/v1','execution_id':ctx['coverage_execution_id'],'cycle_id':ctx['cycle_id'],'pass_id':ctx['pass_id'],'source_sha256':ctx['source_sha256'],'candidate_sha256':ctx['candidate_sha256'],'reader_execution_id':ctx['reader_execution_id'],'required_graders':list(GRADERS),'grader_execution_ids':{g:by[g]['execution_id'] for g in GRADERS if g in by},'element_matrix':matrix,'region_sweeps':regions,'grader_errors':errors,'coverage_percent':pct,'coverage_pass':pass_}
