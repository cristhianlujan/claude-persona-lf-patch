#!/usr/bin/env python3
"""V0.5 producer-depth cases.

Proves three things generically (no domain, table or incident names):
1. The cheap stop exit is closed: a DESIGN_BLOCKING gap without resolved attempts fails.
2. A genuine stop (attempts that resolve in the external manifest) still passes.
3. ARCHITECTURE_AUDIT relaxes only incident-specific requirements.
V0.4 behavior is unchanged (backward compatibility).
"""
import copy
import runpy
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
import json

v04 = runpy.run_path(str(ROOT / "evals" / "v04_transversal_closure_cases.py"), run_name="v05_import")
v04_pair = v04["v04_pair"]
runtime_validate = v04["runtime_validate"]
runtime_semantic_utility = v04["runtime_semantic_utility"]
V04_PROCESS_FIXTURE = v04["process"]
closure_proof = v04["closure_proof"]
schema_validator = Draft7Validator(json.loads((ROOT / "schemas" / "output.schema.json").read_text()))

V04 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_4"
V05 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5"
RESULTS = []


def codes(result):
    return {e["code"] for e in result["errors"]}


def check(label, condition, detail=""):
    RESULTS.append((label, bool(condition), detail))


def v05_pair(mode="INCIDENT_REPAIR"):
    candidate, evidence = v04_pair()
    candidate["profile_pack_id"] = V05
    candidate["case_mode"] = mode
    return candidate, evidence


LOCATOR = "sql:select count(*) from governed_receipts where subject = $1"


def add_manifest_evidence(evidence, evidence_id, locator=LOCATOR):
    evidence = copy.deepcopy(evidence)
    evidence["evidence"].append({
        "evidence_id": evidence_id,
        "subject": "generic-governed-surface",
        "evidence_class": "OBSERVED_LIVE",
        "source_locator": locator,
        "revision_or_observed_at": "2026-01-01T00:00:00Z",
        "digest": "sha256:" + "a" * 64,
        "state": "CURRENT",
    })
    evidence["bundle_digest"] = closure_proof.canonical_evidence_bundle_digest(evidence)
    return evidence


def to_nonready(candidate, attempts=None):
    """Turn a ready fixture into a NEEDS_MORE_EVIDENCE with one design-blocking gap."""
    n = copy.deepcopy(candidate)
    n["status"] = "NEEDS_MORE_EVIDENCE"
    n["selected_alternative"] = None
    n["residual_risks"] = []
    for key in ("systemic_root_cause", "first_bad_control", "escape_control", "immediate_cause"):
        n[key] = {"status": "UNRESOLVED", "statement": "Physical wiring not proven.", "evidence_refs": [], "missing_evidence": ["physical wiring proof"]}
    n["repair_level"] = "UNDETERMINED"
    row = {
        "uncertainty_id": "U-WIRING",
        "uncertainty": "Physical wiring of a material edge is not proven",
        "impact": "DESIGN_BLOCKING",
        "evidence_needed": ["physical wiring proof"],
        "design_consequence": "Can change the enforcement point.",
        "containment_ref": None,
    }
    if attempts is not None:
        row["attempted_sources"] = attempts
    n["current_uncertainties"] = [row]
    n["blocking_codes"] = ["PHYSICAL_WIRING_NOT_PROVEN"]
    n["repair_disposition"]["decision"] = "UNDETERMINED"
    cp = n["closure_proof"]
    cp["proof_obligations"][0]["status"] = "OPEN"
    cp["proof_obligations"][0]["missing_requirements"] = ["wiring not proven"]
    d = cp["derived_decision_closure"]
    d["handoff_ready"] = False
    d["closed_obligation_ids"] = [o["obligation_id"] for o in cp["proof_obligations"] if o["status"] == "CLOSED"]
    d["open_obligation_ids"] = [o["obligation_id"] for o in cp["proof_obligations"] if o["status"] == "OPEN"]
    n["implementation_package"]["decision_closure"]["handoff_ready"] = False
    return n


def attempt(evidence_id="EV-ATTEMPT-1", result="ABSENT"):
    return {
        "surface": "OPERATION_EXECUTION_RECEIPT",
        "locator": LOCATOR,
        "result": result,
        "observation": "Query returned zero receipts for the edge.",
        "evidence_id": evidence_id,
    }


# 1. Ready spec carried to V0.5 stays valid.
c, e = v05_pair()
r = runtime_validate.validate(c, e)
check("V05_READY_SPEC_VALID", r["valid"], r["errors"][:3])
check("V05_READY_SPEC_SCHEMA_VALID", not list(schema_validator.iter_errors(c)))

# 2. case_mode is required for V0.5.
c2 = copy.deepcopy(c); del c2["case_mode"]
r = runtime_validate.validate(c2, e)
check("V05_CASE_MODE_REQUIRED", "V05_CASE_MODE_INVALID" in codes(r), codes(r))
check("V05_CASE_MODE_SCHEMA_REQUIRED", list(schema_validator.iter_errors(c2)))

# 3. Cheap stop: design-blocking gap with no attempts fails in V0.5.
lazy = to_nonready(c)
r = runtime_validate.validate(lazy, e)
check("V05_LAZY_NEEDS_REJECTED", codes(r) == {"V05_DESIGN_BLOCKER_WITHOUT_ATTEMPT"}, codes(r))

# 4. Backward compatibility: the same payload under V0.4 keeps V0.4 behavior (known gap, documented).
c4, e4 = v04_pair()
lazy_v04 = to_nonready(c4)
r = runtime_validate.validate(lazy_v04, e4)
check("V04_BEHAVIOR_UNCHANGED_LAZY_NEEDS_STILL_ACCEPTED", r["valid"], codes(r))

# 5. Genuine stop: attempts resolving in the external manifest pass.
e5 = add_manifest_evidence(e, "EV-ATTEMPT-1")
genuine = to_nonready(c, [attempt()])
r = runtime_validate.validate(genuine, e5)
check("V05_GENUINE_NEEDS_ACCEPTED", r["valid"], r["errors"][:3])
check("V05_GENUINE_NEEDS_SCHEMA_VALID", not list(schema_validator.iter_errors(genuine)), [x.message for x in schema_validator.iter_errors(genuine)][:3])

# 6. Claimed attempt that the external manifest does not contain is rejected.
r = runtime_validate.validate(to_nonready(c, [attempt("EV-NOT-READ")]), e5)
check("V05_UNRESOLVED_ATTEMPT_REJECTED", "V05_ATTEMPT_EVIDENCE_NOT_IN_MANIFEST" in codes(r), codes(r))

# 7. Evidence found and sufficient cannot justify a blocker.
r = runtime_validate.validate(to_nonready(c, [attempt(result="FOUND_SUFFICIENT")]), e5)
check("V05_FOUND_SUFFICIENT_NOT_A_BLOCKER", "V05_ATTEMPT_RESULT_INVALID" in codes(r), codes(r))

# 8. Superseded evidence does not count as a current attempt.
e8 = copy.deepcopy(e5)
e8["evidence"][-1]["state"] = "SUPERSEDED"
e8["bundle_digest"] = closure_proof.canonical_evidence_bundle_digest(e8)
r = runtime_validate.validate(to_nonready(c, [attempt()]), e8)
check("V05_SUPERSEDED_ATTEMPT_REJECTED", "V05_ATTEMPT_EVIDENCE_NOT_IN_MANIFEST" in codes(r), codes(r))

# 9. Architecture audit: no recurrence and a one-link chain are acceptable.
ca, ea = v05_pair("ARCHITECTURE_AUDIT")
ca["recurrence_evidence"] = []
ca["causal_chain"] = ca["causal_chain"][:1]
r = runtime_validate.validate(ca, ea)
check("V05_AUDIT_WITHOUT_RECURRENCE_ACCEPTED", r["valid"], r["errors"][:3])
audit_schema_errors = list(schema_validator.iter_errors(ca))
check(
    "V05_AUDIT_SCHEMA_WITHOUT_RECURRENCE_ACCEPTED",
    not audit_schema_errors,
    [x.message for x in audit_schema_errors][:3],
)

# 10. Incident mode keeps requiring recurrence and a three-link chain.
ci = copy.deepcopy(ca); ci["case_mode"] = "INCIDENT_REPAIR"
r = runtime_validate.validate(ci, ea)
check("V05_INCIDENT_STILL_REQUIRES_RECURRENCE", {"RECURRENCE_EVIDENCE_INVALID", "CAUSAL_CHAIN_INSUFFICIENT"} <= codes(r), codes(r))
incident_schema_errors = list(schema_validator.iter_errors(ci))
check(
    "V05_INCIDENT_SCHEMA_STILL_REQUIRES_RECURRENCE_AND_CHAIN",
    bool(incident_schema_errors),
    [x.message for x in incident_schema_errors][:3],
)

# 10b. V0.4 keeps the legacy incident-oriented schema contract.
cv4, ev4 = v04_pair()
cv4["recurrence_evidence"] = []
cv4["causal_chain"] = cv4["causal_chain"][:1]
v04_schema_errors = list(schema_validator.iter_errors(cv4))
check(
    "V04_SCHEMA_BEHAVIOR_UNCHANGED",
    bool(v04_schema_errors),
    [x.message for x in v04_schema_errors][:3],
)

# 11. Audit mode does not relax the stop exit.
r = runtime_validate.validate(to_nonready(ca), ea)
check("V05_AUDIT_LAZY_NEEDS_REJECTED", "V05_DESIGN_BLOCKER_WITHOUT_ATTEMPT" in codes(r), codes(r))

# 12. Borrowed evidence: a CURRENT manifest row produced by a different query cannot back this attempt.
e12 = add_manifest_evidence(e, "EV-OTHER-QUERY", locator="git:runtime/manifest.json@abc123")
r = runtime_validate.validate(to_nonready(c, [attempt("EV-OTHER-QUERY")]), e12)
check("V05_BORROWED_EVIDENCE_REJECTED", "V05_ATTEMPT_EVIDENCE_LOCATOR_MISMATCH" in codes(r), codes(r))

# 13. Whitespace-only differences in the locator are not a mismatch.
spaced = attempt(); spaced["locator"] = "  " + LOCATOR.replace(" ", "   ") + " "
r = runtime_validate.validate(to_nonready(c, [spaced]), e5)
check("V05_LOCATOR_WHITESPACE_TOLERATED", r["valid"], r["errors"][:3])

# 14. Design-blocking uncertainty must carry an id.
no_id = to_nonready(c, [attempt()]); del no_id["current_uncertainties"][0]["uncertainty_id"]
r = runtime_validate.validate(no_id, e5)
check("V05_BLOCKER_ID_REQUIRED", "V05_DESIGN_BLOCKER_ID_REQUIRED" in codes(r), codes(r))


def with_blocked_node(candidate, ref=None):
    x = copy.deepcopy(candidate)
    x["material_process_graph"] = copy.deepcopy(V04_PROCESS_FIXTURE["material_process_graph"])
    node = x["material_process_graph"]["nodes"][0]
    node["disposition"] = "DESIGN_BLOCKING"
    if ref is not None:
        node["blocking_uncertainty_id"] = ref
    return x


# 15. A blocked process node without a link to its uncertainty is rejected.
r = runtime_validate.validate(with_blocked_node(to_nonready(c, [attempt()])), e5)
check("V05_BLOCKED_NODE_NEEDS_REF", "V05_BLOCKED_NODE_WITHOUT_UNCERTAINTY_REF" in codes(r), codes(r))

# 16. A link to a non-existent / non-blocking uncertainty is rejected.
r = runtime_validate.validate(with_blocked_node(to_nonready(c, [attempt()]), "U-DOES-NOT-EXIST"), e5)
check("V05_BLOCKED_NODE_BAD_REF", "V05_BLOCKED_NODE_REF_NOT_DESIGN_BLOCKING" in codes(r), codes(r))

# 17. Blocked node linked to a design-blocking uncertainty with resolved attempts passes.
linked = with_blocked_node(to_nonready(c, [attempt()]), "U-WIRING")
r = runtime_validate.validate(linked, e5)
check("V05_BLOCKED_NODE_LINKED_ACCEPTED", r["valid"], r["errors"][:3])
check("V05_BLOCKED_NODE_LINKED_SCHEMA_VALID", not list(schema_validator.iter_errors(linked)), [x.message for x in schema_validator.iter_errors(linked)][:3])

# 18. Audit mode keeps systemic causality: a ready audit spec with a non-established causal claim fails semantic utility.
gate = runtime_validate.validate(ca, ea)
u = runtime_semantic_utility.evaluate(ca, gate, ea)
check("V05_AUDIT_READY_SEMANTIC_UTILITY_ACCEPTED", u["status"] == "PASS", u)
weak = copy.deepcopy(ca)
weak["first_bad_control"]["status"] = "HYPOTHESIS"
weak["first_bad_control"]["missing_evidence"] = ["control design authority"]
weak_gate = runtime_validate.validate(weak, ea)
check("V05_AUDIT_STILL_REQUIRES_ESTABLISHED_CAUSALITY", "SYSTEMIC_SPEC_CAUSAL_CLAIM_NOT_ESTABLISHED" in codes(weak_gate), codes(weak_gate))
u = runtime_semantic_utility.evaluate(weak, weak_gate, ea)
check("V05_AUDIT_WEAK_CAUSALITY_BLOCKED_BY_SEMANTIC_UTILITY", u["status"] != "PASS", u.get("blocking_codes"))

# 19-22. V0.5 integration parity.
main_contract_text = (ROOT / "contracts" / "main_contract.md").read_text()
semantic_judge_text = (ROOT / "judges" / "systemic_root_cause_semantic_judge.md").read_text()
quality_handoff = json.loads((ROOT / "handoffs" / "to_quality_pack.handoff.json").read_text())
runtime_binding = json.loads((ROOT / "contracts" / "runtime_binding.json").read_text())

check(
    "V05_MAIN_CONTRACT_CURRENT",
    "Current provider-side generation is pinned to SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5." in main_contract_text
    and "- `case_mode`" in main_contract_text,
)
check(
    "V05_SEMANTIC_JUDGE_PREMATURE_STOP_PRESENT",
    "### T4 — V0.5 premature-stop verification" in semantic_judge_text
    and "PREMATURE_DESIGN_BLOCKING" in semantic_judge_text,
)
handoff_include = set(quality_handoff.get("include") or [])
check(
    "V05_QUALITY_HANDOFF_FIELDS_PRESENT",
    {"case_mode", "live_authority_packet", "material_process_graph", "current_uncertainties"} <= handoff_include,
    sorted(handoff_include),
)
quality_ids = set((runtime_binding.get("canonical_quality") or {}).get("required_for_profile_pack_ids") or [])
check(
    "V05_RUNTIME_BINDING_QUALITY_REQUIRED",
    V05 in quality_ids,
    sorted(quality_ids),
)

failed = [x for x in RESULTS if not x[1]]
for label, ok, detail in RESULTS:
    print(("ok   " if ok else "FAIL ") + label + ("" if ok else f"  {detail}"))
if failed:
    sys.exit(1)
print(f"SRCR_V05_PRODUCER_DEPTH={len(RESULTS)}/{len(RESULTS)}")
