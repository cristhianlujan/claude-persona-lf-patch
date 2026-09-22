#!/usr/bin/env python3
"""V0.6 explicit material-edge closure cases.

The cases are generic. They prove that component existence/proposed wiring cannot
stand in for an observed producer->consumer path, and that route, currentness,
terminality, identity and rollback concerns are explicit when applicable.
"""
import copy
import json
import runpy
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
v05 = runpy.run_path(str(ROOT / "evals" / "v05_producer_depth_cases.py"), run_name="v06_import")
v05_pair = v05["v05_pair"]
runtime_validate = v05["runtime_validate"]
closure_proof = v05["closure_proof"]
V04_PROCESS_FIXTURE = v05["V04_PROCESS_FIXTURE"]
schema_validator = Draft7Validator(json.loads((ROOT / "schemas" / "output.schema.json").read_text()))

V05 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5"
V06 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
RESULTS = []


def codes(result):
    return {e["code"] for e in result["errors"]}


def check(label, condition, detail=""):
    RESULTS.append((label, bool(condition), detail))


def add_evidence(evidence, evidence_id):
    evidence["evidence"].append({
        "evidence_id": evidence_id,
        "subject": "generic-material-edge-proof",
        "evidence_class": "OBSERVED_LIVE",
        "source_locator": f"supabase://governed/material-edge/{evidence_id}",
        "revision_or_observed_at": "2026-01-01T00:00:00Z",
        "digest": "sha256:" + (evidence_id.encode().hex() + "0" * 64)[:64],
        "state": "CURRENT",
    })


def proof(evidence_id, status="OBSERVED_PASS", applicability="REQUIRED"):
    return {
        "applicability": applicability,
        "status": status,
        "evidence_refs": [] if status in {"PROPOSED_ONLY", "UNRESOLVED", "NOT_APPLICABLE"} else [evidence_id],
    }


def v06_pair():
    candidate, evidence = v05_pair("ARCHITECTURE_AUDIT")
    candidate = copy.deepcopy(candidate)
    evidence = copy.deepcopy(evidence)
    candidate["profile_pack_id"] = V06
    candidate["material_process_graph"] = copy.deepcopy(V04_PROCESS_FIXTURE["material_process_graph"])

    nodes = candidate["material_process_graph"]["nodes"]
    if not nodes:
        raise AssertionError("fixture requires >=1 material node")
    if len(nodes) == 1:
        second = copy.deepcopy(nodes[0])
        second["node_id"] = "NODE-V06-B"
        second["phase"] = "GENERIC_DOWNSTREAM_STAGE"
        nodes.append(second)
    node_ids = [x["node_id"] for x in nodes]

    ids = [
        "EV-E-PRODUCER","EV-E-TRANSPORT","EV-E-CONSUMER","EV-E-ENFORCEMENT",
        "EV-E-READBACK","EV-E-NEXT","EV-E-ROUTE","EV-E-CURRENTNESS",
        "EV-E-TERMINALITY","EV-E-IDENTITY","EV-E-ROLLBACK",
    ]
    for evidence_id in ids:
        add_evidence(evidence, evidence_id)
    evidence["bundle_digest"] = closure_proof.canonical_evidence_bundle_digest(evidence)

    edge = {
        "edge_id": "EDGE-01",
        "from_node": node_ids[0],
        "to_node": node_ids[1],
        "edge_kind": "CONTROL_FLOW",
        "observation_status": "OBSERVED_CLOSED",
        "disposition": "REUSE_AS_IS",
        "producer_evidence_refs": ["EV-E-PRODUCER"],
        "transport_evidence_refs": ["EV-E-TRANSPORT"],
        "consumer_evidence_refs": ["EV-E-CONSUMER"],
        "enforcement_evidence_refs": ["EV-E-ENFORCEMENT"],
        "effect_readback_evidence_refs": ["EV-E-READBACK"],
        "gap_evidence_refs": [],
        "next_gate": "NEXT-MATERIAL-STAGE",
        "next_gate_consumer_evidence_refs": ["EV-E-NEXT"],
        "canonical_route_consistency": proof("EV-E-ROUTE"),
        "post_transition_currentness": proof("EV-E-CURRENTNESS"),
        "terminality": proof("EV-E-TERMINALITY"),
        "identity_consistency": proof("EV-E-IDENTITY"),
        "rollback_executability": proof("EV-E-ROLLBACK"),
        "proposed_change_ref": None,
        "blocking_uncertainty_id": None,
    }
    candidate["material_process_graph"]["edges"] = [edge]
    return candidate, evidence


c, e = v06_pair()
r = runtime_validate.validate(c, e)
check("V06_READY_EDGE_VALID", r["valid"], r["errors"][:5])
schema_errors = list(schema_validator.iter_errors(c))
check("V06_READY_EDGE_SCHEMA_VALID", not schema_errors, [x.message for x in schema_errors][:5])

# Backward compatibility: V0.5 does not require explicit edges.
c5, e5 = v05_pair("ARCHITECTURE_AUDIT")
r5 = runtime_validate.validate(c5, e5)
check("V05_NO_EDGE_BEHAVIOR_UNCHANGED", r5["valid"], r5["errors"][:5])

# 1. Explicit edge inventory.
x = copy.deepcopy(c); x["material_process_graph"]["edges"] = []
r = runtime_validate.validate(x, e)
check("V06_EDGE_INVENTORY_REQUIRED", "V06_MATERIAL_EDGES_REQUIRED" in codes(r), codes(r))

# 2. Physical consumer is required for an AS-IS reused edge.
x = copy.deepcopy(c); x["material_process_graph"]["edges"][0]["consumer_evidence_refs"] = []
r = runtime_validate.validate(x, e)
check("V06_EDGE_CLOSURE_REQUIRES_CONSUMER", "V06_EDGE_EVIDENCE_REFS_INVALID" in codes(r), codes(r))

# 3. A next-gate label without a consumer is not wiring.
x = copy.deepcopy(c); x["material_process_graph"]["edges"][0]["next_gate_consumer_evidence_refs"] = []
r = runtime_validate.validate(x, e)
check("V06_NEXT_GATE_CONSUMER_REQUIRED", "V06_NEXT_GATE_CONSUMER_UNRESOLVED" in codes(r), codes(r))

# 4. Canonical route must be observed on reused current path.
x = copy.deepcopy(c); x["material_process_graph"]["edges"][0]["canonical_route_consistency"] = proof("EV-E-ROUTE", "OBSERVED_FAIL")
r = runtime_validate.validate(x, e)
check("V06_CANONICAL_ROUTE_PROOF_REQUIRED", "V06_REUSE_EDGE_CANONICAL_ROUTE_CONSISTENCY_NOT_OBSERVED_PASS" in codes(r), codes(r))

# 5. Post-transition currentness must be re-read after the effect.
x = copy.deepcopy(c); x["material_process_graph"]["edges"][0]["post_transition_currentness"] = proof("EV-E-CURRENTNESS", "OBSERVED_FAIL")
r = runtime_validate.validate(x, e)
check("V06_POST_TRANSITION_CURRENTNESS_REQUIRED", "V06_REUSE_EDGE_POST_TRANSITION_CURRENTNESS_NOT_OBSERVED_PASS" in codes(r), codes(r))

# 6. Blocked/return path without terminal proof cannot close reuse.
x = copy.deepcopy(c); x["material_process_graph"]["edges"][0]["terminality"] = proof("EV-E-TERMINALITY", "UNRESOLVED")
r = runtime_validate.validate(x, e)
check("V06_TERMINALITY_PROOF_REQUIRED", "V06_REUSE_EDGE_TERMINALITY_NOT_OBSERVED_PASS" in codes(r), codes(r))

# 7. Release/asset/runtime identity consistency is explicit.
x = copy.deepcopy(c); x["material_process_graph"]["edges"][0]["identity_consistency"] = proof("EV-E-IDENTITY", "OBSERVED_FAIL")
r = runtime_validate.validate(x, e)
check("V06_IDENTITY_CONSISTENCY_REQUIRED", "V06_REUSE_EDGE_IDENTITY_CONSISTENCY_NOT_OBSERVED_PASS" in codes(r), codes(r))

# 8. Declared reversible is not executable rollback proof.
x = copy.deepcopy(c); x["material_process_graph"]["edges"][0]["rollback_executability"] = proof("EV-E-ROLLBACK", "UNRESOLVED")
r = runtime_validate.validate(x, e)
check("V06_EXECUTABLE_ROLLBACK_REQUIRED", "V06_REUSE_EDGE_ROLLBACK_EXECUTABILITY_NOT_OBSERVED_PASS" in codes(r), codes(r))

# 9. Future wiring cannot prove the current AS-IS edge.
x = copy.deepcopy(c)
edge = x["material_process_graph"]["edges"][0]
edge["observation_status"] = "PROPOSED_ONLY"
r = runtime_validate.validate(x, e)
check("V06_PROPOSED_CANNOT_PROVE_REUSE", "V06_PROPOSED_EDGE_CANNOT_PROVE_REUSE" in codes(r), codes(r))

# 10. An observed-open edge cannot be silently called REUSE_AS_IS.
x = copy.deepcopy(c)
edge = x["material_process_graph"]["edges"][0]
edge["observation_status"] = "OBSERVED_OPEN"
edge["gap_evidence_refs"] = ["EV-E-READBACK"]
r = runtime_validate.validate(x, e)
check("V06_OBSERVED_OPEN_NOT_REUSE", "V06_OPEN_EDGE_CANNOT_BE_REUSED_AS_IS" in codes(r), codes(r))

# 11. A ready repair may explicitly repair an observed-open edge.
x = copy.deepcopy(c)
edge = x["material_process_graph"]["edges"][0]
edge["observation_status"] = "OBSERVED_OPEN"
edge["disposition"] = "IMPLEMENTABLE"
edge["gap_evidence_refs"] = ["EV-E-READBACK"]
edge["consumer_evidence_refs"] = []
edge["next_gate_consumer_evidence_refs"] = []
edge["canonical_route_consistency"] = proof("EV-E-ROUTE", "OBSERVED_FAIL")
edge["post_transition_currentness"] = proof("EV-E-CURRENTNESS", "OBSERVED_FAIL")
edge["terminality"] = proof("EV-E-TERMINALITY", "OBSERVED_FAIL")
edge["identity_consistency"] = proof("EV-E-IDENTITY", "OBSERVED_FAIL")
edge["rollback_executability"] = proof("EV-E-ROLLBACK", "PROPOSED_ONLY")
edge["proposed_change_ref"] = "$.implementation_delta[0]"
r = runtime_validate.validate(x, e)
check("V06_OPEN_EDGE_WITH_IMPLEMENTABLE_REPAIR_ACCEPTED", r["valid"], r["errors"][:5])

# 12. Implementable future edge must bind to the implementation delta.
y = copy.deepcopy(x)
y["material_process_graph"]["edges"][0]["proposed_change_ref"] = None
r = runtime_validate.validate(y, e)
check("V06_IMPLEMENTABLE_EDGE_CHANGE_REF_REQUIRED", "V06_IMPLEMENTABLE_EDGE_CHANGE_REF_REQUIRED" in codes(r), codes(r))

# 13. Current edge evidence must resolve in the external manifest.
x = copy.deepcopy(c)
x["material_process_graph"]["edges"][0]["producer_evidence_refs"] = ["EV-NOT-OBSERVED"]
r = runtime_validate.validate(x, e)
check("V06_EDGE_EVIDENCE_MUST_RESOLVE", "V06_EDGE_EVIDENCE_NOT_IN_MANIFEST" in codes(r), codes(r))

failed = [x for x in RESULTS if not x[1]]
for label, ok, detail in RESULTS:
    print(("ok   " if ok else "FAIL ") + label + ("" if ok else f"  {detail}"))
if failed:
    sys.exit(1)
print(f"SRCR_V06_EDGE_CLOSURE={len(RESULTS)}/{len(RESULTS)}")
