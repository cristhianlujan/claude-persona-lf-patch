from pathlib import Path
import json

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent.parent.parent
MIG=(REPO/'supabase'/'migrations'/'20261001133000_post_pase_orchestrator_cutover_v1.sql').read_text(encoding='utf-8')
ROLLBACK=(ROOT/'POST_PASE_ORCHESTRATOR_cutover_rollback_v1.sql').read_text(encoding='utf-8')
INV=json.loads((ROOT/'post_pase_orchestrator_cutover_inventory_v1.json').read_text(encoding='utf-8'))
checks=0
assert INV['capability_code']=='POST_PASE_ORCHESTRATOR'; checks+=1
assert INV['functional_core']['git_blob_sha1']=='5dca9b717803f78c5e2ef79747219919a74f12b3'; checks+=1
assert INV['validator']['git_blob_sha1']=='bc831e852540f8c26f71beb83e38a56ce7030657'; checks+=1
assert INV['validator']['known_check_count']==33; checks+=1
for key in ('applicability_rediscovery','parallel_dispatch','embedded_control_logic','owner_recalculation','new_receipt_store'):
    assert INV[key] is False; checks+=1
assert INV['bulk_cutover'] is False and INV['production_activation'] is False; checks+=2
for x in ('POST_PASE_ORCHESTRATOR','POST_PASE_ROUTER','OWNER_RUNNER_CARRIER_AUTHORITY','CAPABILITY_EXECUTION_CONTRACT','EVIDENCE_LEDGER','ORCHESTRATOR_EXECUTION_GUARD_V1',"'rollback',jsonb_build_object",'public.fn_lf_capability_promote_v1'):
    assert x in MIG; checks+=1
assert 'delete from public.lf_capability_current' in ROLLBACK; checks+=1
assert 'drop table' not in ROLLBACK.lower(); checks+=1
print(f'PASS_POST_PASE_ORCHESTRATOR_CUTOVER_V1 checks={checks}')
