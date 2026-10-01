from pathlib import Path
import json

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent.parent.parent
MIG=(REPO/'supabase'/'migrations'/'20261001134000_post_pase_consumer_bindings_cutover_v1.sql').read_text(encoding='utf-8')
ROLLBACK=(ROOT/'CONSUMER_BINDINGS_cutover_rollback_v1.sql').read_text(encoding='utf-8')
INV=json.loads((ROOT/'consumer_bindings_cutover_inventory_v1.json').read_text(encoding='utf-8'))
checks=0
assert INV['asset_code']=='CONSUMER_BINDINGS'; checks+=1
assert INV['functional_core']['git_blob_sha1']=='0a8897b96c75818414606186944e25fcdb791ee6'; checks+=1
assert INV['validator']['git_blob_sha1']=='7388fcaf929c5723c67fa722695a842c124451af'; checks+=1
assert INV['validator']['known_check_count']==45; checks+=1
assert INV['parallel_binding_registry'] is False and INV['capability_registry_entry_created_for_bindings'] is False; checks+=2
assert INV['owner_recalculation'] is False and INV['binding_bypass_allowed'] is False and INV['applicability_rediscovery'] is False; checks+=3
assert INV['legacy_execution_path_retained'] is True; checks+=1
for x in ('public.fn_lf_capability_bind_from_orchestrator_v1','POST_PASE_ORCHESTRATOR','CURRENTNESS_AUTHORITY','GITHUB_RECONCILIATION','AUTHORITY_READBACK','RUNTIME_DEPLOY_VERIFICATION','EVIDENCE_LEDGER','FINAL_EVIDENCE','CLOSURE_GATE'):
    assert x in MIG; checks+=1
assert 'insert into public.lf_capability_registry' not in MIG.lower(); checks+=1
assert "migration_batch_id=v_batch" in ROLLBACK; checks+=1
assert 'drop table' not in ROLLBACK.lower(); checks+=1
print(f'PASS_CONSUMER_BINDINGS_CUTOVER_V1 checks={checks}')
