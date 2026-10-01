from pathlib import Path
import json

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent.parent.parent
MIG=(REPO/'supabase'/'migrations'/'20261001132000_post_pase_router_cutover_v1.sql').read_text(encoding='utf-8')
ROLLBACK=(ROOT/'POST_PASE_ROUTER_cutover_rollback_v1.sql').read_text(encoding='utf-8')
INV=json.loads((ROOT/'post_pase_router_cutover_inventory_v1.json').read_text(encoding='utf-8'))
checks=0
assert INV['capability_code']=='POST_PASE_ROUTER'; checks+=1
assert INV['functional_core']['git_blob_sha1']=='8054667e225247c1b1b213d8d2ac970c33871690'; checks+=1
assert INV['validator']['git_blob_sha1']=='60ad1a3c3d1b58bd00d5f0689763c432a5d2483f'; checks+=1
assert INV['validator']['known_check_count']==32; checks+=1
assert INV['control_execution'] is False and INV['control_logic'] is False and INV['evidence_collection'] is False; checks+=3
assert INV['bulk_cutover'] is False and INV['production_activation'] is False; checks+=2
for x in ('POST_PASE_ROUTER','CURRENTNESS_AUTHORITY','GITHUB_RECONCILIATION','AUTHORITY_READBACK','RUNTIME_DEPLOY_VERIFICATION','FINAL_EVIDENCE','CLOSURE_GATE','ORCHESTRATOR_EXECUTION_GUARD_V1',"'rollback',jsonb_build_object",'public.fn_lf_capability_promote_v1'):
    assert x in MIG; checks+=1
assert 'delete from public.lf_capability_current' in ROLLBACK; checks+=1
assert 'drop table' not in ROLLBACK.lower(); checks+=1
print(f'PASS_POST_PASE_ROUTER_CUTOVER_V1 checks={checks}')
