#!/usr/bin/env python3
"""PG-01_C3 isolated candidate tests. Existing A9->PG01 matrix oracle is reused."""
import copy
import runpy
from pathlib import Path

from pg01_c3_scope_front_clean_v1 import (
    CONTRACT, ROOT, assess_scope_front_clean,
)

# Existing canonical A7/A9 test defines fixture and executes its own
# positive + adversarial matrix suite rather than copying the validator.
fixture = runpy.run_path(
    str(Path(__file__).with_name("test_analysis_pg01_snapshot_payload_v1.py"))
)["fixture"]
snapshot = fixture()
paths = [
    ROOT + f.removesuffix("[]")
    for f in CONTRACT["programming_context_snapshot"]["required_fields"]
]
receipt = {"verdict": "ACCEPT", "validated_material_paths": paths}
good = assess_scope_front_clean(snapshot, receipt, ["S1"])
assert good["admissible"] is True and good["authority"] == "NONE"
assert good["scope_ids"] == ["S1"] and good["runtime_verified"] is False

cases = [
    ("PG01_C3_RECEIPT_NOT_ACCEPTED", snapshot, {"**": "missing"}, ["S1"]),
    ("PG01_C3_RECEIPT_NOT_ACCEPTED", snapshot, {"verdict": "BLOCK", "validated_material_paths": paths}, ["S1"]),
    ("PG01_C3_MATERIAL_PATHS_INCOMPLETE_OR_EXTRA", snapshot, {"verdict": "ACCEPT", "validated_material_paths": paths[:-1]}, ["S1"]),
    ("PG01_C3_MATERIAL_PATHS_INCOMPLETE_OR_EXTRA", snapshot, {"verdict": "ACCEPT", "validated_material_paths": paths + ["extra"]}, ["S1"]),
    ("PG01_C3_MATERIAL_PATHS_INCOMPLETE_OR_EXTRA", snapshot, {"verdict": "ACCEPT", "validated_material_paths": paths + [paths[0]]}, ["S1"]),
    ("PG01_C3_MATERIAL_PATHS_INVALID", snapshot, {"verdict": "ACCEPT", "validated_material_paths": paths + [None]}, ["S1"]),
    ("PG01_C3_REQUESTED_SCOPE_NOT_READY", snapshot, receipt, ["S2"]),
    ("PG01_C3_REQUESTED_SCOPE_NOT_READY", snapshot, receipt, ["S1", "S2"]),
    ("PG01_C3_REQUESTED_SCOPE_NOT_READY", snapshot, receipt, ["UNKNOWN"]),
    ("PG01_C3_REQUESTED_SCOPES_DUPLICATE", snapshot, receipt, ["S1", "S1"]),
    ("PG01_C3_REQUESTED_SCOPES_INVALID", snapshot, receipt, []),
    ("PG01_C3_REQUESTED_SCOPES_INVALID", snapshot, receipt, [""]),
]
for code, snap, rec, requested in cases:
    result = assess_scope_front_clean(snap, rec, requested)
    assert result["admissible"] is False and result["reason"] == code and result["authority"] == "NONE", (code, result)

bad = copy.deepcopy(snapshot)
bad["scope_front_matrix"][0]["front_closure"] = "BLOCKED"
result = assess_scope_front_clean(bad, receipt, ["S1"])
assert not result["admissible"] and result["reason"].startswith("PG01_C3_MATRIX_INVALID:")

blocked = copy.deepcopy(snapshot)
blocked["package_readiness"] = "BLOCKED"
result = assess_scope_front_clean(blocked, receipt, ["S1"])
assert result["reason"] == "PG01_C3_PACKAGE_NOT_READY"

print(
    "PASS_PG01_C3_SCOPE_FRONT_CLEAN candidate_positive=1 negative=14 "
    "canonical_matrix_oracle=reused material_paths=exact ready_only=true "
    "authority=NONE pg01_runtime_verified=false"
)
