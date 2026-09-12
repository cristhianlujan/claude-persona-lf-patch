#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,unicodedata
from typing import Any
GRADERS=("J-TEXT","J-OBJECT","J-COMPLETE","J-GEOMETRY","J-STRUCTURE","J-STYLE","J-SEMANTIC","J-UNCERTAINTY","J-SKEPTIC")
TEXT_TYPES={"TEXT","LABEL","HEADING","LINK","BUTTON_TEXT","BADGE_TEXT","INPUT_TEXT"}
MATERIAL_SEVERITIES={"CRITICAL","HIGH","MEDIUM"}
def canonical_sha(obj:Any)->str:return hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
def strip_marks(s:str)->str:return ''.join(c for c in unicodedata.normalize('NFD',s) if unicodedata.category(c)!='Mn')
def common_prefix(a:str,b:str)->str:
 out=[]
 for x,y in zip(a,b):
  if x!=y:break
  out.append(x)
 return ''.join(out)
def bbox(e:dict)->dict:return e.get('region') or {'x':0,'y':0,'width':0,'height':0}
def finding(ctx:dict,grader:str,category:str,severity:str,element:dict|None,evidence:Any,actionability:str='REREAD',confidence:float=.9,root:str|None=None,claim:Any=None)->dict:
 eid=(element or {}).get('element_id');rid=bbox(element or {});seed=f"{ctx['cycle_id']}|{ctx['pass_id']}|{grader}|{category}|{eid}|{canonical_sha(evidence)}"
 return {'schema_version':'p0-visual-finding-v4/v1','finding_id':'F-'+hashlib.sha256(seed.encode()).hexdigest()[:16],'cycle_id':ctx['cycle_id'],'pass_id':ctx['pass_id'],'grader_id':grader,'category':category,'severity':severity,'element_id':eid,'region':{k:int(rid.get(k,0) or 0) for k in ('x','y','width','height')},'candidate_claim':claim if claim is not None else (element or {}).get('visible_text'),'observed_evidence':evidence,'evidence_refs':list((element or {}).get('evidence_refs') or []),'confidence':float(max(0,min(1,confidence))),'actionability':actionability,'root_cause_candidate':root,'status':'OPEN'}
def output(ctx:dict,grader:str,applicable:list[str],evaluated:list[str],findings:list[dict],regions:list[str]|None=None,error:str|None=None)->dict:
 return {'schema_version':'p0-grader-output-v4/v1','execution_id':ctx['grader_execution_id'],'reader_execution_id':ctx['reader_execution_id'],'cycle_id':ctx['cycle_id'],'pass_id':ctx['pass_id'],'grader_id':grader,'source_sha256':ctx['source_sha256'],'candidate_sha256':ctx['candidate_sha256'],'applicable_element_ids':applicable,'evaluated_element_ids':evaluated,'screen_regions_evaluated':regions or ['FULL'],'findings':findings,'coverage_complete':error is None and set(evaluated)==set(applicable),'status':'ERROR' if error else ('BLOCKED' if any(f['severity'] in MATERIAL_SEVERITIES for f in findings) else 'PASS'),'error':error}
def applies_text(e:dict)->bool:return bool(e.get('visible_text')) or e.get('element_type') in TEXT_TYPES
def inside(child:dict,parent:dict,tol:int=12)->bool:
 c=bbox(child);p=bbox(parent)
 return c['x']>=p['x']-tol and c['y']>=p['y']-tol and c['x']+c['width']<=p['x']+p['width']+tol and c['y']+c['height']<=p['y']+p['height']+tol
