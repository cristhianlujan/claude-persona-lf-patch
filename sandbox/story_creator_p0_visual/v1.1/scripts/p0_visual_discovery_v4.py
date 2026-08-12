#!/usr/bin/env python3
from __future__ import annotations
from p0_visual_grader_core_v4 import GRADERS,canonical_sha
from p0_independent_omission_sweep_v4 import validate_sweep_receipt

def applicable_graders(e:dict)->set[str]:
 out=set(GRADERS)
 if not (e.get('visible_text') or e.get('element_type') in {'TEXT','LABEL','HEADING','LINK','BUTTON_TEXT','BADGE_TEXT','INPUT_TEXT'}):out.discard('J-TEXT')
 return out

def union_findings(outputs:list[dict])->list[dict]:
 seen=set();out=[]
 for g in outputs:
  for f in g.get('findings',[]):
   key=(f.get('category'),f.get('element_id'),canonical_sha(f.get('observed_evidence')))
   if key not in seen:seen.add(key);out.append(f)
 return out

def coverage_receipt(candidate:dict,outputs:list[dict],ctx:dict)->dict:
 by={o.get('grader_id'):o for o in outputs};errors=[];missing=[g for g in GRADERS if g not in by]
 for g in missing:errors.append({'grader_id':g,'error':'MISSING_GRADER_OUTPUT'})
 execs=[]
 for g,o in by.items():
  eid=o.get('execution_id');execs.append(eid)
  if o.get('error'):errors.append({'grader_id':g,'error':'GRADER_ERROR:'+str(o['error'])})
  if o.get('reader_execution_id')!=ctx['reader_execution_id']:errors.append({'grader_id':g,'error':'STALE_READER_EXECUTION'})
  if o.get('source_sha256')!=ctx['source_sha256'] or o.get('candidate_sha256')!=ctx['candidate_sha256']:errors.append({'grader_id':g,'error':'HASH_BINDING_MISMATCH'})
  if o.get('coverage_complete') is not True:errors.append({'grader_id':g,'error':'COVERAGE_INCOMPLETE'})
  if not o.get('screen_regions_evaluated'):errors.append({'grader_id':g,'error':'EMPTY_REGION_OUTPUT'})
 if len([x for x in execs if x])!=len(set(x for x in execs if x)):errors.append({'grader_id':'J-COVERAGE','error':'DUPLICATE_GRADER_EXECUTION_ID'})
 matrix=[]
 for e in candidate.get('elements',[]):
  req=applicable_graders(e);done={g for g,o in by.items() if e['element_id'] in set(o.get('evaluated_element_ids') or [])};complete=req<=done
  if not complete:errors.append({'grader_id':'J-COVERAGE','error':f"ELEMENT_NOT_FULLY_EVALUATED:{e['element_id']}"})
  refs=[]
  for g in req:
   for f in by.get(g,{}).get('findings',[]):
    if f.get('element_id')==e['element_id']:refs.extend(f.get('evidence_refs') or [])
  matrix.append({'element_id':e['element_id'],'applicable_graders':sorted(req),'evaluated_graders':sorted(done & req),'evidence_refs':sorted(set(refs)),'complete':complete})
 candidate_total=len(matrix);candidate_done=sum(m['complete'] for m in matrix);candidate_pct=100.0 if candidate_total==0 else 100.0*candidate_done/candidate_total
 candidate_metric={'element_count':candidate_total,'fully_evaluated_count':candidate_done,'coverage_percent':candidate_pct,'complete':candidate_done==candidate_total}
 sweep=ctx.get('independent_sweep');sweep_errors=validate_sweep_receipt(sweep,candidate,ctx)
 for err in sweep_errors:errors.append({'grader_id':'J-COVERAGE','error':err})
 material_obs=[];regions=[]
 if isinstance(sweep,dict):
  material_obs=[o for o in sweep.get('observations',[]) if o.get('material') is True]
  for r in sweep.get('regions',[]):regions.append({'region_id':str(r.get('region_id','UNKNOWN')),'omission_sweep_status':r.get('sweep_status') if r.get('sweep_status') in {'COMPLETE','INCOMPLETE','ERROR'} else 'ERROR','evidence_refs':list(r.get('evidence_refs') or [])})
 if not regions:regions=[{'region_id':'FULL','omission_sweep_status':'ERROR','evidence_refs':[]}]
 matrix_by={m['element_id']:m for m in matrix}
 represented=[o for o in material_obs if o.get('match_status')=='REPRESENTED']
 evaluated=[o for o in represented if matrix_by.get(o.get('matched_element_id'),{}).get('complete') is True]
 uncertain=[o for o in material_obs if o.get('match_status')=='UNCERTAIN'];missing_obs=[o for o in material_obs if o.get('match_status')=='UNREPRESENTED']
 observed_count=len(material_obs);represented_count=len(represented);evaluated_count=len(evaluated);ind_pct=100.0 if observed_count==0 else 100.0*evaluated_count/observed_count
 sweep_complete=isinstance(sweep,dict) and sweep.get('status')=='COMPLETE' and not sweep_errors
 independent_complete=sweep_complete and represented_count==observed_count and evaluated_count==observed_count and not uncertain and not missing_obs
 independent_metric={'sweep_execution_id':sweep.get('execution_id') if isinstance(sweep,dict) else None,'observed_count':observed_count,'represented_count':represented_count,'evaluated_count':evaluated_count,'unrepresented_count':len(missing_obs),'uncertain_count':len(uncertain),'coverage_percent':ind_pct,'complete':independent_complete}
 if not independent_complete:errors.append({'grader_id':'J-COVERAGE','error':'INDEPENDENT_SCREEN_COVERAGE_INCOMPLETE'})
 pct=min(candidate_pct,ind_pct);pass_=not errors and candidate_metric['complete'] and independent_complete and pct==100.0 and len(by)==len(GRADERS)
 return {'schema_version':'p0-grader-coverage-v4/v1','execution_id':ctx['coverage_execution_id'],'cycle_id':ctx['cycle_id'],'pass_id':ctx['pass_id'],'source_sha256':ctx['source_sha256'],'candidate_sha256':ctx['candidate_sha256'],'reader_execution_id':ctx['reader_execution_id'],'required_graders':list(GRADERS),'grader_execution_ids':{g:by[g]['execution_id'] for g in GRADERS if g in by},'candidate_grader_coverage':candidate_metric,'independent_screen_coverage':independent_metric,'element_matrix':matrix,'region_sweeps':regions,'grader_errors':errors,'coverage_percent':pct,'coverage_pass':pass_}
