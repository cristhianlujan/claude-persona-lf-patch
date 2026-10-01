from pathlib import Path
import json

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent.parent.parent
MIG=(REPO/'supabase'/'migrations'/'20261001130000_post_pase_closure_gate_cutover_v1.sql').read_text(encoding='utf-8')
ROLLBACK=(ROOT/'CLOSURE_GATE_cutover_rollback_v1.sql').read_text(encoding='utf-8')
INV=json.loads((ROOT/'closure_gate_cutover_inventory_v1.json').read_text(encoding='utf-8'))
checks=0
assert INV['capability_code']=='CLOSURE_GATE'; checks+=1
assert INV['functional_core']['git_blob_sha1']=='f91433006bddcc51de53fe8ad6a2da3c7b3fa1e0'; checks+=1
assert INV['validator']['git_blob_sha1']=='fc401aa4deb046f071e9356561ffa74722791d15'; checks+=1
assert INV['validator']['known_check_count']==26; checks+=1
assert INV['evidence_collection'] is False and INV['control_execution'] is False; checks+=2
assert INV['bulk_cutover'] is False and INV['production_activation'] is False; checks+=2
for x in ('CLOSURE_GATE','PLAN_AUTHORITY_DRIFT_GUARD','FINAL_EVIDENCE','WAIVER_AUTHORITY','ORCHESTRATOR_EXECUTION_GUARD_V1',"'rollback',jsonb_build_object",'public.fn_lf_capability_promote_v1'):
    assert x in MIG; checks+=1
assert 'delete from public.lf_capability_current' in ROLLBACK; checks+=1
assert 'drop table' not in ROLLBACK.lower(); checks+=1
print(f'PASS_CLOSURE_GATE_CUTOVER_V1 checks={checks}')
