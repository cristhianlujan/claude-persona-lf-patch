#!/usr/bin/env python3
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent
EVIDENCE=ROOT.parent/'evidence'/'PROFILE_RUNTIME_STRUCTURAL_CONTEXT_RESOLVER_V3_20260902.json'
CONTROL=ROOT/'PROFILE_RUNTIME_CONTROL_GATES_PROBE_20260902.json'
PERSISTENT=ROOT/'PERSISTENT_CPU_RUNTIME_CONTRACT_V1_20260902.json'
ARTIFACT='ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287'

e=json.loads(EVIDENCE.read_text(encoding='utf-8'))
c=json.loads(CONTROL.read_text(encoding='utf-8'))
p=json.loads(PERSISTENT.read_text(encoding='utf-8'))
assert e['artifact']['sha256']==ARTIFACT
assert c['artifact_sha256']==ARTIFACT
assert p['artifact_sha256']==ARTIFACT
q=e['quality_non_regression']
assert q['run_close_timing_gate']=='14/14'
assert q['semantic_after_claim_gate']=='8/8'
assert q['persistent_cpu_boundary_gate']=='18/18'
assert q['persistent_cpu_adapter_verifier_gate']=='10/10'
assert q['persistent_cpu_request_wiring_gate']=='11/11'
assert q['persistent_scratch_cleanup_gate']=='PASS'
assert q['critical_regressions_count']==0
assert e['semantic_utility']['candidate_after']=='NOT_EXECUTED'
assert e['semantic_utility']['semantic_after_claim_gate']=='PASS_8_8_FAIL_CLOSED'
assert e['semantic_utility']['persistent_cpu_runtime']==p['status']=='IMPLEMENTED_DETERMINISTICALLY_TESTED_NO_REAL_INFERENCE'
assert e['semantic_utility']['persistent_cpu_scope']=='ISOLATED_CANDIDATE_ONLY'
assert e['semantic_utility']['persistent_cpu_scratch_cleanup']=='REQUIRED_AND_TESTED'
assert p['real_host_assets_observed'] is False
assert p['real_host_readiness']=='NOT_EXECUTED'
assert p['real_model_inference']=='NOT_EXECUTED'
assert p['semantic_after_status']=='NOT_EXECUTED'
assert p['implementation']['request_wiring_gate']=='11/11 PASS'
assert p['implementation']['persistent_scratch_cleanup']=='REQUIRED_AND_TESTED'
assert e['reporting_governance']['work_report_timing_separated'] is True
assert e['reporting_governance']['next_execution_readback_required'] is True
assert c['anti_close_gate']['tests'].startswith('14/14 PASS')
assert c['semantic_after_gate']['tests'].startswith('8/8 PASS')
assert c['semantic_after_gate']['candidate_after_status']=='NOT_EXECUTED'
assert e['source_evidence']['historical_334_bbox_baseline']=='NOT_PROVEN'
assert c['historical_334_parity']=='NOT_PROVEN'
assert c['p02_p03_historical_parity']=='NOT_PROVEN'
print('PROFILE_RUNTIME_V3_EVIDENCE_CONSISTENCY_PASS 30/30')
