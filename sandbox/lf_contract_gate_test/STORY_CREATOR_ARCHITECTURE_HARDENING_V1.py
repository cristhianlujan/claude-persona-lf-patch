#!/usr/bin/env python3
"""Deterministic hardening controls for Creating Integral User Stories v1."""
from __future__ import annotations
import hashlib, json, math, re
from difflib import SequenceMatcher
from itertools import product

SHA256_RE=re.compile(r'^[0-9a-f]{64}$')
EKB_RELATIONS={
'EKB-P0-003':'BLOCKED','EKB-P0-014':'BLOCKED_OR_REVIEW','EKB-P0-016':'BLOCKED',
'EKB-P0-017':'BLOCKED','EKB-P0-020':'BLOCKED','EKB-P0-021':'BLOCKED',
'EKB-P0-022':'BLOCKED','AUD-020':'BLOCKED'}

def canonical_sha(v):
 return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def ekb_gate(results):
 allowed={'BLOCKED':{'BLOCKED','FAIL'},'BLOCKED_OR_REVIEW':{'BLOCKED','FAIL','HUMAN_REVIEW_REQUIRED'}}
 missing=[c for c in EKB_RELATIONS if c not in results]
 bad=[c for c,e in EKB_RELATIONS.items() if c in results and results[c] not in allowed[e]]
 return {'result':'PASS_WITH_EVIDENCE' if not missing and not bad else 'BLOCKED','missing':missing,'incompatible':bad,'registry_sha256':canonical_sha(EKB_RELATIONS),'auto_acceptance_allowed':False}

def _phi(a,b):
 ma=sum(a)/len(a); mb=sum(b)/len(b); va=sum((x-ma)**2 for x in a); vb=sum((x-mb)**2 for x in b)
 if not va or not vb:return None
 return sum((x-ma)*(y-mb) for x,y in zip(a,b))/math.sqrt(va*vb)

def grader_audit(payload):
 cases=payload['cases']; graders=payload['graders']; ids=[c['case_id'] for c in cases]; exp={c['case_id']:c['expected'] for c in cases}
 vec={g['grader_id']:[int(g['decisions'][i]!=exp[i]) for i in ids] for g in graders}; fam={g['grader_id']:g['family'] for g in graders}
 corr=[]; pairs=[]; gs=sorted(vec)
 for i,a in enumerate(gs):
  for b in gs[i+1:]:
   p=_phi(vec[a],vec[b]); corr += [max(0,p)] if p is not None else []
   pairs.append({'left':a,'right':b,'same_family':fam[a]==fam[b],'same_error_vector':vec[a]==vec[b],'error_phi':None if p is None else round(p,6)})
 mean=sum(corr)/len(corr) if corr else 0; n=len(gs); ne=n/(1+(n-1)*mean) if n else 0
 redundant=sorted({x[k] for x in pairs if x['same_family'] and x['same_error_vector'] for k in ('left','right')})
 return {'result':'MEASURED_NO_AUTO_REMOVAL','mean_positive_error_correlation':round(mean,6),'effective_vote_proxy':round(ne,6),'redundancy_review_candidates':redundant,'pairwise':pairs,'automatic_grader_removal_allowed':False}

def _iou(a,b):
 ax,ay,aw,ah=a; bx,by,bw,bh=b; x=max(0,min(ax+aw,bx+bw)-max(ax,bx)); y=max(0,min(ay+ah,by+bh)-max(ay,by)); inter=x*y; union=aw*ah+bw*bh-inter
 return inter/union if union>0 else 0

def visual_challenger(primary,challenger):
 blockers=[]
 if not SHA256_RE.fullmatch(str(primary.get('source_sha256',''))) or primary.get('source_sha256')!=challenger.get('source_sha256'):blockers.append('SOURCE_HASH_MISMATCH')
 if not primary.get('engine_family') or primary.get('engine_family')==challenger.get('engine_family'):blockers.append('ENGINE_FAMILY_NOT_INDEPENDENT')
 if challenger.get('primary_output_visible_to_challenger') is not False:blockers.append('CHALLENGER_NOT_BLIND_TO_PRIMARY')
 if blockers:return {'result':'BLOCKED','blocking_assertions':blockers,'auto_confirm_allowed':False}
 used=set(); disagreements=[]
 for p in primary.get('observations',[]):
  cand=[(_iou(p['region'],c['region']),i,c) for i,c in enumerate(challenger.get('observations',[])) if i not in used and c.get('kind')==p.get('kind') and _iou(p['region'],c['region'])>=.5]
  if not cand:disagreements.append({'type':'PRIMARY_ONLY','id':p.get('observation_id')});continue
  _,i,c=max(cand);used.add(i); a=' '.join(str(p.get('text','')).lower().split()); b=' '.join(str(c.get('text','')).lower().split()); sim=1 if not a and not b else SequenceMatcher(None,a,b).ratio()
  if (a or b) and sim<.85:disagreements.append({'type':'TEXT_DISAGREEMENT','primary_id':p.get('observation_id'),'challenger_id':c.get('observation_id')})
 for i,c in enumerate(challenger.get('observations',[])):
  if i not in used:disagreements.append({'type':'CHALLENGER_ONLY','id':c.get('observation_id')})
 return {'result':'HUMAN_REVIEW_REQUIRED' if disagreements else 'ORTHOGONAL_SUPPORT_OBSERVED','disagreements':disagreements,'auto_confirm_allowed':False,'classification_mutation':None}

def _lit(s):
 s=str(s).strip()
 if not s:raise ValueError('empty literal')
 return (s[1:] if s.startswith('!') else s,not s.startswith('!'))

def formal_rule_gate(payload):
 compiled=[]; skipped=[]; vars=set(); failures=[]
 for r in payload.get('rules',[]):
  rid=str(r.get('rule_id',''))
  if not rid:failures.append('RULE_ID_MISSING');continue
  if r.get('formalizable') is not True:skipped.append(rid);continue
  if len(str(r.get('source_ref','')).strip())<3:failures.append('SOURCE_REF_MISSING:'+rid);continue
  try: ants=[_lit(x) for x in r.get('antecedent',[])]; cons=_lit(r.get('consequent',''))
  except ValueError:failures.append('FORMALIZATION_INVALID:'+rid);continue
  compiled.append((ants,cons)); vars.update(x for x,_ in ants);vars.add(cons[0])
 if failures:return {'result':'BLOCKED','failures':failures,'semantic_truth_claimed':False}
 if len(vars)>16:return {'result':'BLOCKED_FORMAL_SOLVER_LIMIT','semantic_truth_claimed':False}
 names=sorted(vars); witness=None
 for bits in product((False,True),repeat=len(names)):
  env=dict(zip(names,bits))
  if all(not all(env[n] is p for n,p in ants) or env[cons[0]] is cons[1] for ants,cons in compiled):witness=env;break
 return {'result':'SAT_FORMALIZATION' if witness is not None else 'UNSAT_FORMALIZATION','witness':witness,'not_formalizable':skipped,'semantic_truth_claimed':False,'source_translation_verified':False,'production_authorized':False}

def self_test():
 ekb=ekb_gate({c:('HUMAN_REVIEW_REQUIRED' if e=='BLOCKED_OR_REVIEW' else 'BLOCKED') for c,e in EKB_RELATIONS.items()})
 graders=grader_audit({'cases':[{'case_id':'1','expected':'FAIL'},{'case_id':'2','expected':'FAIL'},{'case_id':'3','expected':'PASS'}],'graders':[{'grader_id':'G1','family':'A','decisions':{'1':'PASS','2':'FAIL','3':'PASS'}},{'grader_id':'G2','family':'A','decisions':{'1':'PASS','2':'FAIL','3':'PASS'}},{'grader_id':'G3','family':'B','decisions':{'1':'FAIL','2':'PASS','3':'PASS'}}]})
 sha='a'*64; p={'source_sha256':sha,'engine_family':'OCR','observations':[{'observation_id':'P','kind':'TEXT','region':[0,0,10,10],'text':'Ej. 123'}]}; c={'source_sha256':sha,'engine_family':'SCREEN_PARSER','primary_output_visible_to_challenger':False,'observations':[{'observation_id':'C','kind':'TEXT','region':[0,0,10,10],'text':'Ej. 123'}]}; d=json.loads(json.dumps(c));d['observations'][0]['text']='55 123'
 sat=formal_rule_gate({'rules':[{'rule_id':'R','source_ref':'SRC','formalizable':True,'antecedent':['A'],'consequent':'B'}]}); unsat=formal_rule_gate({'rules':[{'rule_id':'R1','source_ref':'SRC','formalizable':True,'antecedent':[],'consequent':'A'},{'rule_id':'R2','source_ref':'SRC','formalizable':True,'antecedent':[],'consequent':'!A'}]})
 checks={'ekb':ekb['result']=='PASS_WITH_EVIDENCE','grader':set(graders['redundancy_review_candidates'])>={'G1','G2'} and not graders['automatic_grader_removal_allowed'],'visual_support':visual_challenger(p,c)['result']=='ORTHOGONAL_SUPPORT_OBSERVED','visual_disagreement':visual_challenger(p,d)['result']=='HUMAN_REVIEW_REQUIRED','visual_same_family':visual_challenger(p,{**c,'engine_family':'OCR'})['result']=='BLOCKED','formal_sat':sat['result']=='SAT_FORMALIZATION','formal_unsat':unsat['result']=='UNSAT_FORMALIZATION'}
 return {'schema_version':'story-creator-architecture-hardening-self-test/v1','result':'PASS' if all(checks.values()) else 'FAIL','checks':checks,'production_authorized':False}

if __name__=='__main__':
 r=self_test();print(json.dumps(r,sort_keys=True));raise SystemExit(0 if r['result']=='PASS' else 1)
