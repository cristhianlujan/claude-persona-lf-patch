#!/usr/bin/env python3
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
s=json.loads((ROOT/'SCREEN_DECOMPOSER_DOWNSTREAM_STATUS_V3_20260902.json').read_text(encoding='utf-8'))
e=json.loads((ROOT.parent/'evidence'/'PROFILE_RUNTIME_STRUCTURAL_CONTEXT_RESOLVER_V3_20260902.json').read_text(encoding='utf-8'))
assert s['artifact_sha256']==e['artifact']['sha256']
assert s['screen_decomposer_operational_version']=='v0.3'
assert s['context_pack_v3']['builder_gate']=='14/14 PASS'
assert s['context_pack_v3']['trace_data_e2e']=='PASS_WITH_ALL_CRITICAL_COUNTERS_0'
assert s['context_pack_v3']['source_bound'] is True
assert s['context_pack_v3']['dynamic_data_non_reconciliation'] is True
assert s['context_pack_v3']['offviewport_not_material_omission'] is True
assert s['j02_readiness']['status']=='NOT_PROVEN_FROM_CONTEXT_PACK_ALONE'
assert len(s['j02_readiness']['missing_or_not_bound_in_profile_runtime_evidence'])>=6
assert s['downstream_context_pack_equivalence']['structural_evidence_equivalence']=='PASS_DETERMINISTIC_FIXTURE'
assert s['downstream_context_pack_equivalence']['full_screen_decomposer_handoff_equivalence']=='NOT_PROVEN'
assert s['downstream_context_pack_equivalence']['j02_pass']=='NOT_EXECUTED'
assert s['claim_policy']['context_pack_pass_may_imply_j02_ready'] is False
assert s['claim_policy']['context_pack_pass_may_imply_profile_semantic_utility'] is False
assert s['claim_policy']['context_pack_pass_may_imply_screen_decomposer_judge_pass'] is False
print('PROFILE_RUNTIME_V3_SCREEN_DECOMPOSER_DOWNSTREAM_STATUS_PASS 15/15')
