#!/usr/bin/env python3
"""Build/verify append-only P0 V4 artifact envelopes without credentials or DB coupling."""
from __future__ import annotations
import argparse,hashlib,json
from dataclasses import dataclass,field
from typing import Any
ALLOWED_SUBTYPES={'P0_V4_FULL_READER_OUTPUT','P0_V4_INDEPENDENT_OMISSION_SWEEP','P0_V4_GRADER_FINDINGS','P0_V4_GRADER_COVERAGE_RECEIPT','P0_V4_REMEDIATION_PLAN','P0_V4_TARGETED_REREAD','P0_V4_FULL_REREAD','P0_V4_CONVERGENCE_RECEIPT','P0_V4_DISCOVERY_SUMMARY','P0_V4_RUN_STATE','P0_V4_HUMAN_REVIEW_PACKET','P0_V4_FINAL_COMPLIANCE'}
ROLE_BY_SUBTYPE={s:('PACKET_MANIFEST' if s in {'P0_V4_HUMAN_REVIEW_PACKET','P0_V4_FINAL_COMPLIANCE'} else 'VISUAL_OUTPUT') for s in ALLOWED_SUBTYPES}
def canonical_bytes(obj:Any)->bytes:return json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def sha256_bytes(data:bytes)->str:return hashlib.sha256(data).hexdigest()
def artifact_envelope(*,review_id:str,execution_id:str,subtype:str,object_name:str,payload:Any,source_head_sha:str,source_sha256:str,code_head_sha:str,configuration_sha256:str,cycle_id:str,pass_id:str,grader_id:str|None=None,candidate_sha256:str|None=None,previous_artifact_sha256:str|None=None,finding_count:int=0)->dict:
 if subtype not in ALLOWED_SUBTYPES:raise ValueError('UNSUPPORTED_V4_SUBTYPE')
 if len(source_head_sha)!=40 or len(code_head_sha)!=40:raise ValueError('MALFORMED_CODE_SHA')
 if len(source_sha256)!=64 or len(configuration_sha256)!=64:raise ValueError('MALFORMED_SHA256')
 if candidate_sha256 is not None and len(candidate_sha256)!=64:raise ValueError('MALFORMED_CANDIDATE_SHA256')
 data=canonical_bytes(payload);digest=sha256_bytes(data)
 return {'review_id':review_id,'execution_id':execution_id,'object_role':ROLE_BY_SUBTYPE[subtype],'object_name':object_name,'mime_type':'application/json','content_bytes':len(data),'content_sha256':digest,'content':data,'data_classification':'CONFIDENTIAL','source_head_sha':source_head_sha,'retention_policy':'UNTIL_TERMINAL_REVIEW','metadata':{'subtype':subtype,'cycle_id':cycle_id,'pass_id':pass_id,'grader_id':grader_id,'source_sha256':source_sha256,'candidate_sha256':candidate_sha256,'code_head_sha':code_head_sha,'configuration_sha256':configuration_sha256,'previous_artifact_sha256':previous_artifact_sha256,'finding_count':int(finding_count)}}
def verify_readback(envelope:dict,readback:bytes)->bool:return len(readback)==envelope['content_bytes'] and sha256_bytes(readback)==envelope['content_sha256']
def recover_run_state(rows:list[dict])->dict:
 candidates=[r for r in rows if (r.get('metadata') or {}).get('subtype')=='P0_V4_RUN_STATE']
 if not candidates:raise ValueError('NO_P0_V4_RUN_STATE')
 latest=max(candidates,key=lambda r:r.get('created_at',''));raw=latest.get('content')
 if isinstance(raw,str):raw=raw.encode()
 if not isinstance(raw,(bytes,bytearray)):raise ValueError('RUN_STATE_CONTENT_UNAVAILABLE')
 if sha256_bytes(bytes(raw))!=latest.get('content_sha256'):raise ValueError('RUN_STATE_HASH_MISMATCH')
 state=json.loads(bytes(raw).decode())
 if state.get('schema_version')!='p0-v4-run-state/v1' or not state.get('next_action'):raise ValueError('RUN_STATE_INVALID')
 return state
@dataclass
class AppendOnlyMemoryStore:
 rows:list[dict]=field(default_factory=list);keys:set=field(default_factory=set)
 def insert(self,envelope:dict,created_at:str)->dict:
  key=(envelope['review_id'],envelope['object_role'],envelope['content_sha256'])
  if key in self.keys:raise ValueError('DUPLICATE_ARTIFACT')
  row={**envelope,'created_at':created_at};self.keys.add(key);self.rows.append(row);return row
def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--resume-state');a=p.parse_args()
 if a.resume_state:
  raw=open(a.resume_state,'rb').read();s=recover_run_state([{'metadata':{'subtype':'P0_V4_RUN_STATE'},'content':raw,'content_sha256':sha256_bytes(raw),'created_at':'9999-12-31T23:59:59Z'}]);print(json.dumps({'gate':'PASS_V4_RESUME_STATE','next_action':s['next_action'],'last_completed_gate':s['last_completed_gate']},sort_keys=True));return 0
 print('P0_V4_PERSISTENCE_ENVELOPE_ONLY');return 0
if __name__=='__main__':raise SystemExit(main())
