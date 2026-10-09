#!/usr/bin/env python3
"""Live-payload shape falsification for A9 -> PG-01, without PG-01 activation."""
import copy
import importlib.util
from pathlib import Path
p=Path(__file__).with_name("validate_wave1_boundary_contracts_v1.py")
spec=importlib.util.spec_from_file_location("wave1_validator",p)
v=importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

def fixture():
    return {
      "schema_version":"PROGRAMMING_CONTEXT_SNAPSHOT_V1",
      "package_readiness":"PARTIAL_READY",
      "material_front_coverage":{
        "schema_version":"MATERIAL_FRONT_COVERAGE_V1",
        "all_material_fronts_accounted":True,
        "front_candidate_refs":["F1","F2"],
        "unmapped_material_signals":[],
        "source_refs":["source://replay"],
        "currentness_refs":["currentness://proof"],
        "coverage_fingerprint_sha256":"a"*64,
        "material_fronts":[
          {"front_id":"F1","front_kind":"UI_RULE","status":"REQUIRED",
           "closure":"CLOSED","source_signal_refs":["signal://f1"],
           "scope_refs":["S1"],"authority_refs":["authority://f1"],
           "evidence_refs":["evidence://f1"],"currentness_refs":["currentness://f1"],
           "blockers":[],"reason":"source-bound requirement"},
          {"front_id":"F2","front_kind":"AUTHORITY","status":"REQUIRED",
           "closure":"BLOCKED","source_signal_refs":["signal://f2"],
           "scope_refs":["S2"],"authority_refs":["authority://f2"],
           "evidence_refs":[],"currentness_refs":[],
           "blockers":["OWNER_PENDING"],"reason":"authority unresolved"},
        ]},
      "scope_readiness":[
        {"scope_id":"S1","status":"READY","material_front_refs":["F1"],
         "depends_on_scope_ids":[],"blockers":[]},
        {"scope_id":"S2","status":"BLOCKED","material_front_refs":["F2"],
         "depends_on_scope_ids":["S1"],"blockers":["OWNER_PENDING"]},
      ],
      "scope_front_matrix":[
        {"scope_id":"S1","front_id":"F1","front_status":"REQUIRED",
         "front_closure":"CLOSED","effect_on_scope":"PRESERVE"},
        {"scope_id":"S2","front_id":"F2","front_status":"REQUIRED",
         "front_closure":"BLOCKED","effect_on_scope":"BLOCKS"},
      ]}

def rejected(candidate,code):
    try:v.validate_programming_snapshot_payload_v1(candidate)
    except v.ContractError as e:
        assert str(e)==code,(e,code)
        return
    raise AssertionError("Unexpected ready snapshot: "+code)

s=fixture()
assert v.validate_programming_snapshot_payload_v1(s)=={
    "state":"PASS","scopes":2,"fronts":2,"matrix_pairs":2,"ready_scopes":1}

tests=[
  ("SNAPSHOT_PAYLOAD_MATRIX_REQUIRED",lambda x:x.update(scope_front_matrix=[])),
  ("SNAPSHOT_MATRIX_INCOMPLETE",lambda x:x["scope_front_matrix"].pop()),
  ("SNAPSHOT_MATRIX_EFFECT_MISMATCH",lambda x:x["scope_front_matrix"][1].update(effect_on_scope="PRESERVE")),
  ("SNAPSHOT_MATRIX_FRONT_MISMATCH",lambda x:x["scope_front_matrix"][0].update(front_closure="BLOCKED")),
  ("SNAPSHOT_MATRIX_DUPLICATE",lambda x:x["scope_front_matrix"].append(copy.deepcopy(x["scope_front_matrix"][0]))),
  ("SNAPSHOT_SCOPE_UNKNOWN_FRONT",lambda x:x["scope_readiness"][0].update(material_front_refs=["OTHER"])),
  ("SNAPSHOT_BLOCKED_FRONT_READY_SCOPE",lambda x:x["scope_readiness"][1].update(status="READY",blockers=[])),
  ("SNAPSHOT_READY_BLOCKED_DEPENDENCY",lambda x:x["scope_readiness"][0].update(depends_on_scope_ids=["S2"])),
  ("SNAPSHOT_DEPENDENCY_CYCLE",lambda x:x["scope_readiness"][0].update(depends_on_scope_ids=["S2"],status="BLOCKED")),
  ("SNAPSHOT_FRONT_SCOPE_PARITY",lambda x:x["material_front_coverage"]["material_fronts"][0].update(scope_refs=["S2"])),
  ("SNAPSHOT_FRONT_REQUIRED_REFS",lambda x:x["material_front_coverage"]["material_fronts"][0].pop("authority_refs")),
  ("SNAPSHOT_COVERAGE_PROVENANCE",lambda x:x["material_front_coverage"].update(coverage_fingerprint_sha256=None)),
  ("SNAPSHOT_FRONT_REUSE_CURRENTNESS",lambda x:x["material_front_coverage"]["material_fronts"][0].update(status="REUSE_AS_IS",currentness_refs=[])),
  ("SNAPSHOT_FRONT_NOT_APPLICABLE_PROOF",lambda x:x["material_front_coverage"]["material_fronts"][0].update(status="NOT_APPLICABLE",evidence_refs=[])),
]
for code,mutate in tests:
    variant=copy.deepcopy(s)
    mutate(variant)
    rejected(variant,code)
print("PASS_ANALYSIS_PG01_SNAPSHOT_PAYLOAD positive=1 negative="+str(len(tests))+
      " evidence_tier=DETERMINISTIC_PAYLOAD_VALIDATION pg01_runtime_verified=false")
