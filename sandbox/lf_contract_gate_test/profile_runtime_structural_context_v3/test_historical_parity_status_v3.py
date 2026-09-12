#!/usr/bin/env python3
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
p=json.loads((ROOT/'HISTORICAL_PARITY_STATUS_V3_20260902.json').read_text(encoding='utf-8'))
b=json.loads((ROOT/'BASELINE_CURRENT_199_V1_20260902.json').read_text(encoding='utf-8'))
e=json.loads((ROOT.parent/'evidence'/'PROFILE_RUNTIME_STRUCTURAL_CONTEXT_RESOLVER_V3_20260902.json').read_text(encoding='utf-8'))
ART='ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287'
assert p['artifact_sha256']==ART
assert b['artifact']['sha256']==ART
assert e['artifact']['sha256']==ART
h=p['historical_334_bbox_baseline']
assert h['status']=='NOT_PROVEN'
assert h['recovery_status']=='NOT_RECOVERED_FROM_DURABLE_REPO_EVIDENCE'
assert h['current_199_may_substitute_for_historical_parity'] is False
assert h['allowed_use_of_current_199']=='FORWARD_SAME_INPUT_BASELINE_ONLY'
assert p['p02_p03']['profile_runtime_historical_definition_status']=='NOT_RECOVERED'
assert p['p02_p03']['label_hits_prove_profile_runtime_contract'] is False
assert p['p02_p03']['historical_334_parity']=='NOT_PROVEN'
assert p['direct_current_behavior_evidence']['decomposer_context_pack_gate']=='14/14 PASS'
assert p['direct_current_behavior_evidence']['critical_regressions_count']==0
assert p['claim_policy']['forbid_historical_334_parity_claim'] is True
assert p['claim_policy']['forbid_p02_p03_parity_claim_without_definition'] is True
assert p['claim_policy']['allow_current_199_forward_comparison'] is True
assert e['source_evidence']['historical_334_bbox_baseline']=='NOT_PROVEN'
print('PROFILE_RUNTIME_V3_HISTORICAL_PARITY_STATUS_PASS 16/16')
