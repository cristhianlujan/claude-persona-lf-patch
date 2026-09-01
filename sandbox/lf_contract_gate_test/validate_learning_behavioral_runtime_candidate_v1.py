#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_behavioral_runtime_candidate_v1.json'

def fail(msg): raise SystemExit('FAIL learning-behavioral-runtime-candidate: '+msg)

def main():
 d=json.loads(P.read_text())
 if d.get('schema')!='LF_LEARNING_BEHAVIORAL_RUNTIME_CANDIDATE_V1': fail('schema')
 if d.get('status')!='CANDIDATE_AVAILABLE_NOT_CANONICAL': fail('status')
 if d.get('source_pr_state')!='OPEN_DRAFT_UNMERGED': fail('source boundary')
 if set(d.get('supported_learning_consumers',[]))!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('consumer set')
 ci=d.get('exact_head_ci',[])
 if len(ci)!=4 or any(x.get('conclusion')!='success' for x in ci): fail('exact-head CI')
 use=d.get('learning_use',{})
 if use.get('behavioral_ab_execution_authorized_from_this_file') is not False: fail('behavioral authority')
 if use.get('canonical_runtime_replacement') is not False or use.get('production_authorized') is not False: fail('impact boundary')
 c=d.get('observed_contract',{})
 if c.get('max_batch_size')!=3 or c.get('max_parallelism')!=2 or c.get('visual_artifact_fail_closed') is not True: fail('runtime contract')
 req=set(c.get('governance_receipt_reusable_requires',[]))
 expected={'status_READY','continuation_allowed_true','decision_PASS','currentness_LIVE_CURRENT','screen_code_match','snapshot_hash_nonempty'}
 if req!=expected: fail('receipt requirements')
 print('LEARNING_BEHAVIORAL_RUNTIME_CANDIDATE=PASS candidate_only=1 canonical=0 production=0 consumers=2 exact_head_ci=4/4')
if __name__=='__main__': main()
