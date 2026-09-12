#!/usr/bin/env python3
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
s=json.loads((ROOT/'OPTIMIZATION_STATUS_V3_20260902.json').read_text(encoding='utf-8'))
p=json.loads((ROOT/'PROFILE_RUNTIME_BATCHED_REREAD_PROBE_20260902.json').read_text(encoding='utf-8'))
assert s['artifact_sha256']==p['artifact']['sha256']
assert s['targeted_reread_process_fanout']['before_invocations']==p['same_artifact_low_confidence_ab']['isolated_invocations']==72
assert s['targeted_reread_process_fanout']['after_invocations']==p['same_artifact_low_confidence_ab']['grouped_invocations']==4
assert s['targeted_reread_process_fanout']['same_artifact_speedup_x']==p['same_artifact_low_confidence_ab']['speedup_x']==13.26
assert s['targeted_reread_process_fanout']['decision_equivalence']==p['same_artifact_low_confidence_ab']['decision_equivalence']=='18/18'
assert s['targeted_reread_process_fanout']['worse_decisions']==0
assert s['cache_lookup_store_reuse']['status']=='NOT_PROVEN'
assert s['early_stop']['status']=='NOT_IMPLEMENTED'
assert s['serialization']['status']=='NOT_BENCHMARKED_SEPARATELY'
assert s['plateau']['runs']==p['repeatability_same_artifact_existing_observations']['runs']==8
assert s['plateau']['p50_ms']==p['repeatability_same_artifact_existing_observations']['p50_ms']
assert s['plateau']['p95_ms']==p['repeatability_same_artifact_existing_observations']['p95_ms']
assert s['parallelism3']['status']=='NOT_TESTED'
assert s['timeout_increased'] is False
assert s['quality_gate_relaxed'] is False
print('PROFILE_RUNTIME_V3_OPTIMIZATION_STATUS_PASS 15/15')
