#!/usr/bin/env python3
from lf_pase_merge_route_v1 import classify_route, load_registry

registry = load_registry()
mode, candidate = classify_route([".github/workflows/pase-merge-gate.yml"], registry)
assert mode == "CONTROL_SYSTEM_QUALIFICATION", mode
assert candidate == "PASE_MERGE_GATE_V1", candidate

for lookalike in (
    ".github/workflows/pase-merge-gate.yaml",
    ".github/workflows/pase-merge-gate-copy.yml",
    ".github/workflows/pase-merge-gate.yml.bak",
):
    mode, candidate = classify_route([lookalike], registry)
    assert mode == "EXECUTION_PLAN", (lookalike, mode)
    assert candidate is None, (lookalike, candidate)

print("PASS_PASE_MERGE_GATE_WORKFLOW_ROUTE_BINDING_V1")
