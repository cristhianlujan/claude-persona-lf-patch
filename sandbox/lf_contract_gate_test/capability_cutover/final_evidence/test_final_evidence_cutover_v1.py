from pathlib import Path
import json

ROOT=Path(__file__).resolve().parent
APPLY=(ROOT/'FINAL_EVIDENCE_cutover_v1.sql').read_text(encoding='utf-8')
ROLLBACK=(ROOT/'FINAL_EVIDENCE_cutover_rollback_v1.sql').read_text(encoding='utf-8')
INV=json.loads((ROOT/'final_evidence_cutover_inventory_v1.json').read_text(encoding='utf-8'))
checks=0
assert INV['capability_code']=='FINAL_EVIDENCE'; checks+=1
assert INV['functional_core']['git_blob_sha1']=='a5873b919e5668977cbae7d20ffb1ca156f7d0ad'; checks+=1
assert INV['validator']['git_blob_sha1']=='b811e450dbd0d7e2a9931b83cc8052ebf5a79ccf'; checks+=1
assert INV['validator']['known_check_count']==29; checks+=1
assert INV['evidence_collection'] is False and INV['ledger_rehydration'] is False and INV['control_reexecution'] is False; checks+=1
assert INV['bulk_cutover'] is False and INV['production_activation'] is False; checks+=1
for x in ('PLAN_AUTHORITY_DRIFT_GUARD','EVIDENCE_LEDGER','EVIDENCE_RESOLVER_REGISTRY','TYPED_EVIDENCE_REGISTRY','public.fn_lf_capability_promote_v1','functional_core_unchanged'):
    assert x in APPLY; checks+=1
assert 'delete from public.lf_capability_current' in ROLLBACK; checks+=1
assert 'delete from public.lf_capability_version_registry' not in ROLLBACK; checks+=1
print(f'PASS_FINAL_EVIDENCE_CUTOVER_V1 checks={checks}')
