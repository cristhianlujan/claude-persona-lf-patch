from pathlib import Path
import json

ROOT=Path(__file__).resolve().parent
MIG=(ROOT.parent.parent.parent.parent/'supabase'/'migrations'/'20261001064000_post_pase_waiver_authority_cutover_v1.sql')
SQL=MIG.read_text(encoding='utf-8')
ROLLBACK=(ROOT/'WAIVER_AUTHORITY_cutover_rollback_v1.sql').read_text(encoding='utf-8')
INV=json.loads((ROOT/'waiver_authority_cutover_inventory_v1.json').read_text(encoding='utf-8'))
checks=0
assert INV['capability_code']=='WAIVER_AUTHORITY'; checks+=1
assert INV['functional_core']['git_blob_sha1']=='839792277cf71f2a3f3585e2e1f0b21351da533c'; checks+=1
assert INV['validator']['git_blob_sha1']=='397a612f044332b359f251f8d8101948be73a376'; checks+=1
assert INV['validator']['known_check_count']==12; checks+=1
assert INV['validation_exemption_semantic_reuse'] is False; checks+=1
assert INV['max_uses']==1 and INV['max_ttl_seconds']==3600; checks+=1
for x in ('private.lf_post_pase_waivers','lf_post_pase_waiver_readback_v1','lf_post_pase_waiver_consume_v1','max_uses = 1','approval_authority = \'LF_GOVERNANCE\'','public.fn_lf_capability_promote_v1','ORCHESTRATOR_EXECUTION_GUARD_V1'):
    assert x in SQL; checks+=1
assert 'lf_event_validation_exemptions' not in SQL; checks+=1
assert 'delete from public.lf_capability_current' in ROLLBACK; checks+=1
assert 'drop table' not in ROLLBACK.lower(); checks+=1
print(f'PASS_WAIVER_AUTHORITY_CUTOVER_V1 checks={checks}')
