#!/usr/bin/env python3
"""Replay the Lifecycle escape classes against the generic V0.6 edge floor.

These are historical regression cases only. The validator contains no Lifecycle
literals; each replay mutates a generic material edge into the shape that escaped
the V0.5 producer/quality boundary.
"""
from __future__ import annotations

import copy
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
fixture = runpy.run_path(str(ROOT / "evals" / "v06_edge_closure_cases.py"), run_name="v06_lifecycle_fixture")
v06_pair = fixture["v06_pair"]
runtime_validate = fixture["runtime_validate"]
proof = fixture["proof"]


def codes(result):
    return {row["code"] for row in result["errors"]}


def expect(label, mutate, expected):
    candidate, evidence = v06_pair()
    edge = candidate["material_process_graph"]["edges"][0]
    mutate(edge)
    result = runtime_validate.validate(candidate, evidence)
    observed = codes(result)
    if expected not in observed:
        print(f"FAIL {label}: expected={expected} observed={sorted(observed)}")
        raise SystemExit(1)
    print(f"ok   {label} -> {expected}")


# CREATE produced a repository artifact, but the materialized registry consumer was not observed.
expect(
    "LC_CREATE_TO_REGISTER_CONSUMER_GAP",
    lambda edge: edge.update({"consumer_evidence_refs": []}),
    "V06_EDGE_EVIDENCE_REFS_INVALID",
)

# UPDATE/refresh emitted a material next gate, but no concrete consumer resolved it.
expect(
    "LC_ACTIVATION_NEXT_GATE_ORPHAN",
    lambda edge: edge.update({"next_gate_consumer_evidence_refs": []}),
    "V06_NEXT_GATE_CONSUMER_UNRESOLVED",
)
expect(
    "LC_CANARY_NEXT_GATE_ORPHAN",
    lambda edge: edge.update({"next_gate_consumer_evidence_refs": []}),
    "V06_NEXT_GATE_CONSUMER_UNRESOLVED",
)

# The canonical router blocked while a direct executor path still mutated runtime.
expect(
    "LC_CANONICAL_ROUTE_BYPASS",
    lambda edge: edge.update({
        "canonical_route_consistency": proof("EV-E-ROUTE", "OBSERVED_FAIL")
    }),
    "V06_REUSE_EDGE_CANONICAL_ROUTE_CONSISTENCY_NOT_OBSERVED_PASS",
)

# Promotion changed the identity used by qualification, making the receipt stale after effect.
expect(
    "LC_POST_PROMOTION_QUALIFICATION_STALE",
    lambda edge: edge.update({
        "post_transition_currentness": proof("EV-E-CURRENTNESS", "OBSERVED_FAIL")
    }),
    "V06_REUSE_EDGE_POST_TRANSITION_CURRENTNESS_NOT_OBSERVED_PASS",
)

# Blocked executions remained IN_PROGRESS instead of reaching a governed terminal state.
expect(
    "LC_BLOCKED_EXECUTION_NONTERMINAL",
    lambda edge: edge.update({
        "terminality": proof("EV-E-TERMINALITY", "UNRESOLVED")
    }),
    "V06_REUSE_EDGE_TERMINALITY_NOT_OBSERVED_PASS",
)

# Registry/version projection diverged from the actual release identity.
expect(
    "LC_RELEASE_IDENTITY_DIVERGENCE",
    lambda edge: edge.update({
        "identity_consistency": proof("EV-E-IDENTITY", "OBSERVED_FAIL")
    }),
    "V06_REUSE_EDGE_IDENTITY_CONSISTENCY_NOT_OBSERVED_PASS",
)

# Declared reversible transition had no executable inverse/readback proof.
expect(
    "LC_DECLARED_REVERSIBLE_WITHOUT_EXECUTOR",
    lambda edge: edge.update({
        "rollback_executability": proof("EV-E-ROLLBACK", "UNRESOLVED")
    }),
    "V06_REUSE_EDGE_ROLLBACK_EXECUTABILITY_NOT_OBSERVED_PASS",
)

# A materially open retire/deprecate path cannot be reused as if operational.
def retire_open(edge):
    edge["observation_status"] = "OBSERVED_OPEN"
    edge["gap_evidence_refs"] = ["EV-E-READBACK"]

expect(
    "LC_RETIRE_PATH_NOT_OPERATIONAL",
    retire_open,
    "V06_OPEN_EDGE_CANNOT_BE_REUSED_AS_IS",
)

print("SRCR_V06_LIFECYCLE_ESCAPE_REPLAY=9/9")
