#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MANIFEST=ROOT/'sandbox/lf_contract_gate_test/learning_behavioral_readiness_v2.json'
RUNTIME=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime/run_zero_cost_profile_request.py'
WORKFLOW=ROOT/'.github/workflows/story-agent-evidence-verifier.yml'
RUNTIME_CANDIDATE=ROOT/'sandbox/lf_contract_gate_test/learning_behavioral_runtime_candidate_v1.json'

def fail(msg): raise SystemExit('FAIL learning-behavioral-readiness-v2: '+msg)
def main():
 m=json.loads(MANIFEST.read_text())
 if m['status']!='WAITING_CURRENT_INPUT_GOVERNANCE_RECEIPT': fail('status not fail-closed')
 if m['production_impact'] is not False or m['runtime_invoked'] is not False or m['holdout_consumed'] is not False: fail('unsafe execution flags')
 if m['authority_contract']!='INPUT_READINESS_CONTRACT' or m['input_governance_observed_revision']!='5.12' or m['continuation_policy']!='PASS_ONLY' or m['contract_resolution']!='LIVE_CURRENT': fail('governance contract mismatch')
 if not RUNTIME.is_file() or not WORKFLOW.is_file() or not RUNTIME_CANDIDATE.is_file(): fail('runtime sources missing')
 rt=RUNTIME.read_text(); wf=WORKFLOW.read_text(); rc=json.loads(RUNTIME_CANDIDATE.read_text())
 for term in ['allow_test_doubles=False','EJECUCION_PERFIL_LF','lf_adapter_bindings']:
  if term not in rt: fail('runtime invariant missing '+term)
 for term in ['run-zero-cost-profile-runtime','issue_comment','/lf-profile-runtime ','author_association == \'OWNER\'']:
  if term not in wf: fail('trigger invariant missing '+term)
 rtm=m.get('runtime',{})
 if rtm.get('candidate_runtime_available') is not True: fail('candidate runtime not recorded')
 if rtm.get('candidate_runtime_canonical') is not False or rtm.get('candidate_runtime_authorizes_execution') is not False: fail('candidate widened authority')
 if rtm.get('candidate_runtime_exact_head_ci')!='4/4_PASS': fail('candidate CI not frozen')
 if rc.get('status')!='CANDIDATE_AVAILABLE_NOT_CANONICAL': fail('candidate status')
 if rc.get('learning_use',{}).get('behavioral_ab_execution_authorized_from_this_file') is not False: fail('candidate file authorizes execution')
 consumers={x['consumer_id']:x for x in m['consumers']}
 if set(consumers)!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('consumer set')
 for cid,c in consumers.items():
  if c['routing_benchmark']!='50/50_PASS': fail(cid+' routing not frozen')
  if not c['required_before_runtime'] or not c['required_evidence_after_runtime']: fail(cid+' readiness incomplete')
  if 'AUTHORIZED_OWNER_RUNTIME_TRIGGER' not in c['required_before_runtime']: fail(cid+' owner trigger absent')
 if 'PRODUCT_DIRECTION_AUTHORIZED_CURRENT' not in consumers['PERFIL-UI-ARCHITECT']['required_before_runtime']: fail('ui product precondition absent')
 ekb=m.get('ekb_preflight',{})
 if ekb.get('status') not in {'RECOVERED_LIVE_READBACK','RECOVERED_LIVE_READBACK_PRIOR_DURABLE_CHECKPOINT'} or ekb.get('live_db_readback') is not True or ekb.get('supabase_outage') is not False: fail('EKB durable recovery not evidenced')
 if ekb.get('current_run_live_db_claims_added') is not False: fail('current-run live DB claims fabricated')
 required_ekb={'DB-001','GOV-010','KB-PROD-001','PROFILE-RUNTIME-DISPATCH-001'}
 if not required_ekb.issubset(set(ekb.get('matched_error_codes',[]))): fail('required EKB controls missing')
 print('LEARNING_BEHAVIORAL_READINESS_V2=PASS consumers=2 runtime_candidate=1 canonical_runtime=0 runtime_invoked=0 holdout_consumed=0 fail_closed=1')
 return 0
if __name__=='__main__': raise SystemExit(main())
