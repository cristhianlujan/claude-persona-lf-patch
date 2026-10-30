#!/usr/bin/env python3
"""Generic, bounded and adversarial policy-resolution evidence tests.

No hard-coded owner default, no database writes, no external policy engine.
Uses the exact pre-existing source contracts, current external manifest shape.
"""
import copy
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "validators"))
from producer_depth import _policy_resolution_errors

CATALOG = json.loads((ROOT / "contracts/dynamic_method_catalog.v1.json").read_text(encoding="utf-8"))
SCHEMA = json.loads((ROOT / "schemas/output.schema.json").read_text(encoding="utf-8"))
method = CATALOG["policy_resolution_method"]
assert method["method_id"] == "SCOPED_POLICY_APPLICABILITY"
assert "policy_resolution" in SCHEMA["properties"]

SOURCES = ["public.v_lf_operation_policy_snapshot", "public.lf_policy_versions"]
def context(need, operation, target, decision="POLICY_NOT_REGISTERED"):
    rows = [
        {
            "level": "N1" if i == 0 else "N2",
            "role": "POLICY_SNAPSHOT" if i == 0 else "CANONICAL_VERSION",
            "source": source,
            "locator": "sql:select governed policy where operation_code=$1 and applicability=$2 from " + source,
            "evidence_id": "EV-POLICY-" + str(i),
            "result_kind": "ROWS",
            "applicability": "NO_MATCH",
            "observed_at": "2026-10-30T16:00:00Z",
        }
        for i, source in enumerate(SOURCES)
    ]
    proof = {
        "evidence": [
            {
                "evidence_id": item["evidence_id"],
                "source_locator": item["locator"],
                "state": "CURRENT",
                "digest": "sha256:" + str(i+1)*64,
                "revision_or_observed_at": "2026-10-30T16:00:00Z",
            }
            for i, item in enumerate(rows)
        ]
    }
    decision_actions = {
        "POLICY_NOT_REGISTERED": "PROPOSE_GOVERNED_RULE",
        "POLICY_APPLICABLE": "USE_GOVERNED_RULE",
        "POLICY_NOT_APPLICABLE": "TARGETED_SOURCE_RESEARCH",
        "POLICY_SOURCE_UNAVAILABLE": "BLOCK_UNVERIFIED",
    }
    packet = {
        "policy_resolution": [{
            "question_id": "RULE-" + operation,
            "need": need,
            "scope": {"operation_code": operation, "target_code": target},
            "decision": decision,
            "selected_policy_code": None,
            "selected_policy_sha": None,
            "lookups": rows,
            "next_action": decision_actions[decision],
        }]
    }
    return packet, proof


def errors(packet, manifest):
    return {x["code"] for x in _policy_resolution_errors(packet, manifest)}

def mutate(base, fn):
    candidate, proof = copy.deepcopy(base[0]), copy.deepcopy(base[1])
    fn(candidate, proof)
    return errors(candidate, proof)


checks = {}
for domain, operation in (
    ("OWNER", "ORQUESTACION_PIPELINE_LF"),
    ("RETRY", "EJECUCION_WEB_LF"),
    ("PERMISSION", "EJECUCION_PERFIL_LF"),
    ("VALIDATION", "ACTUALIZACION_PERFIL_LF"),
):
    packet, proof = context("missing governed " + domain.lower() + " decision", operation, "target-" + domain)
    checks["RULE_NOT_REGISTERED_" + domain] = not errors(packet, proof)

base = context("missing governed value", "ANY_GOVERNED_OPERATION", "ANY_TARGET")
checks.update({
    "OPTIONAL_FIELD_LEGACY_SAFE": not errors({}, None),
    "N1_N2_MISSING_BLOCKS": "POLICY_N1_N2_ORDER_OR_COVERAGE" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"].pop(0)),
    "WRONG_CANONICAL_VIEW_BLOCKS": "POLICY_N1_SOURCE_NOT_CANONICAL" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"][0].update(source="public.lf_activos")),
    "WRONG_N2_SOURCE_BLOCKS": "POLICY_N2_SOURCE_NOT_CANONICAL" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"][1].update(source="public.random_table")),
    "NO_EXTERNAL_MANIFEST_BLOCKS": "POLICY_EVIDENCE_NOT_CURRENT" in errors(base[0], None),
    "BORROWED_RECEIPT_BLOCKS": "POLICY_EVIDENCE_LOCATOR_MISMATCH" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"][0].update(locator="sql:borrowed")),
    "SUPERSEDED_RECEIPT_BLOCKS": "POLICY_EVIDENCE_NOT_CURRENT" in mutate(base, lambda p, m: m["evidence"][1].update(state="SUPERSEDED")),
    "DUPLICATE_EVIDENCE_BLOCKS": "POLICY_EVIDENCE_REUSED" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"][1].update(evidence_id="EV-POLICY-0")),
    "WRONG_ACTION_BLOCKS": "POLICY_DECISION_ACTION_MISMATCH" in mutate(base, lambda p, m: p["policy_resolution"][0].update(next_action="USE_GOVERNED_RULE")),
    "FALSE_NOT_REGISTERED_BLOCKS": "POLICY_FALSE_NOT_REGISTERED" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"][1].update(applicability="MATCH")),
    "ACCESS_DENIED_NOT_EMPTY": "POLICY_UNAVAILABLE_IS_NOT_ABSENCE" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"][1].update(result_kind="ACCESS_DENIED",error_detail="DENIED")),
    "MISSING_ACCESS_ERROR_BLOCKS": "POLICY_ACCESS_ERROR_NOT_RECORDED" in mutate(base, lambda p, m: p["policy_resolution"][0]["lookups"][1].update(result_kind="ERROR")),
    "EMPTY_SCOPE_BLOCKS": "POLICY_SCOPE_REQUIRED" in mutate(base, lambda p, m: p["policy_resolution"][0].update(scope={})),
    "UNAVAILABLE_MUST_HAVE_ERROR": "POLICY_UNAVAILABLE_NOT_PROVEN" in mutate(base, lambda p, m: p["policy_resolution"][0].update(decision="POLICY_SOURCE_UNAVAILABLE",next_action="BLOCK_UNVERIFIED")),
    "UNAVAILABLE_WITH_ERROR_OK": not mutate(base, lambda p, m: (p["policy_resolution"][0].update(decision="POLICY_SOURCE_UNAVAILABLE",next_action="BLOCK_UNVERIFIED"), p["policy_resolution"][0]["lookups"][1].update(result_kind="ACCESS_DENIED",error_detail="READ_ACCESS_DENIED"))),
    "CANDIDATE_IS_NOT_ACTIVE_POLICY": "POLICY_APPLICABLE_ROW_NOT_PROVEN" in mutate(base, lambda p, m: (p["policy_resolution"][0].update(decision="POLICY_APPLICABLE",next_action="USE_GOVERNED_RULE",selected_policy_code="RULE-CANDIDATE",selected_policy_sha="a"*64),p["policy_resolution"][0]["lookups"][1].update(applicability="CANDIDATE_ONLY",policy_code="RULE-CANDIDATE",policy_status="CANDIDATE"))),
    "APPLICABLE_REQUIRES_CURRENT_SHA": "POLICY_ACTIVE_REFERENCE_REQUIRED" in mutate(base, lambda p, m: (p["policy_resolution"][0].update(decision="POLICY_APPLICABLE",next_action="USE_GOVERNED_RULE",selected_policy_code="RULE-1"),p["policy_resolution"][0]["lookups"][1].update(applicability="MATCH",policy_code="RULE-1",policy_status="ACTIVE"))),
    "CURRENT_IN_SCOPE_RULE_ACCEPTED": not mutate(base, lambda p, m: (p["policy_resolution"][0].update(decision="POLICY_APPLICABLE",next_action="USE_GOVERNED_RULE",selected_policy_code="RULE-1",selected_policy_sha="b"*64),p["policy_resolution"][0]["lookups"][1].update(applicability="MATCH",policy_code="RULE-1",policy_status="ACTIVE"))),
    "CANDIDATE_ONLY_RULE_CAN_ESCALATE": not mutate(base, lambda p, m: (p["policy_resolution"][0].update(decision="POLICY_NOT_APPLICABLE",next_action="TARGETED_SOURCE_RESEARCH"),p["policy_resolution"][0]["lookups"][1].update(applicability="CANDIDATE_ONLY",policy_status="CANDIDATE"))),
})
for name, passed in checks.items():
    print(("PASS " if passed else "FAIL ") + name)
print(f"SCOPED_POLICY_RESOLUTION_CASES={sum(checks.values())}/{len(checks)}")
raise SystemExit(0 if all(checks.values()) else 1)
