#!/usr/bin/env python3
"""C3 ADVERSARIAL DIAGNOSIS, not an independent C3 verdict and not product PASS.

Runs the actual frozen C2 validator against proof-of-concept false-valid payloads.
Exit 0 means the known gaps are reproduced, NOT that the Router passes.
"""
from __future__ import annotations
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CORPUS = ROOT / "docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json"
VALIDATOR = ROOT / "sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py"
spec = importlib.util.spec_from_file_location("rw101_oracle", VALIDATOR)
if spec is None or spec.loader is None:
    raise SystemExit("C3_IMPORT_ERROR: validation source not loadable")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
doc = json.loads(CORPUS.read_text(encoding="utf-8"))
cases = {c["id"]: c for c in doc["cases"]}

def baseline(cid: str, step: str | None = None) -> dict:
    c = cases[cid]
    o = c["oracle"]
    route = step or o["acceptable_next_steps"][0]
    ans = {
        "id": cid, "next_step": route,
        "handoff_literal": c["literal_request"],
        "request_sha256": mod.sha(c["literal_request"]),
        "router_effect_authorized": False,
        "effect_performed": False,
        "claims_e2e": False, "selected_effect_targets": [],
        "acknowledged_goals": list(o["must_acknowledge_goal_terms"]),
        "acknowledged_exclusions": list(o["excluded_subjects"]),
        "candidate_responsibilities": [{"authority_evidence_ref": "fixture://UNVERIFIED"}],
    }
    if route == "DISCOVER":
        ans["discovery_handoff"] = {
            "registered_discovery_capability_ref": "fixture://UNVERIFIED",
            "catalog_revision_ref": "fixture://UNVERIFIED",
            "unresolved_route_reason": "unknown fixture capability",
        }
    if route == "CAPABILITY_GAP":
        ans.update(source_search_receipt_ref="fixture://UNVERIFIED",missing_capability="mock")
    if route == "CLARIFY":
        reason=o.get("clarification_reason")
        ans.update(clarification_question="¿Cuál?",
          clarification_reason=reason, material_route_discriminator="identity",
          unresolved_responsibility_alternatives=["a","b"] if reason=="ROUTE_AMBIGUITY" else [],
          recovered_context_refs=[])
    return ans

probes = [
    # First four exhibit literal-preserved text with omitted binding of meaning.
    ("F01","R07","IMPLICIT_AUTH_NEGATION_NOT_STRUCTURED",
     {"selected_effect_targets":["autenticación"],"acknowledged_exclusions":[]}),
    ("F02","R09","IMPLICIT_PERMISSION_NEGATION_NOT_STRUCTURED",
     {"selected_effect_targets":["permisos"],"acknowledged_exclusions":[]}),
    ("F03","R04","SIMULATION_NON_EFFECT_SCOPE_NOT_BOUND",
     {"selected_effect_targets":["skill de validación"],"acknowledged_exclusions":[]}),
    ("F04","R17","RECOVERED_CONTEXT_NOT_ATTESTED",
     {"recovered_context_refs":[],"context_digest":None}),
    # The oracle admits DERIVE/COMPOSE with an unresolved fixture.
    ("F05","R20","UNKNOWN_CAPABILITY_DERIVE_ACCEPTABLE",
     {"next_step":"DERIVE","candidate_responsibilities":[{"authority_evidence_ref":"fixture://unknown"}]}),
    ("F06","R22","UNKNOWN_CAPABILITY_COMPOSE_ACCEPTABLE",
     {"next_step":"COMPOSE","candidate_responsibilities":[{"authority_evidence_ref":"fixture://unknown"}]}),
    ("F07","R10","MULTIGOAL_ACKNOWLEDGED_NOT_COVERED_BY_SINGLE_EXECUTOR",
     {"candidate_responsibilities":[{"authority_evidence_ref":"fixture://only-skill"}],
      "acknowledged_goals":["regla","skill"]}),
    ("F08","R27","PRODUCTION_DERIVATION_NOT_BOUND_TO_PERMISSION",
     {"next_step":"DERIVE","candidate_responsibilities":[{"authority_evidence_ref":"fixture://unchecked"}]}),
    ("F09","R08","UNVERIFIED_AUTHORITY_REF_PASSES_NONEMPTY_TEST",
     {"candidate_responsibilities":[{"authority_evidence_ref":"not-a-verified-provider"}]}),
]
findings=[]
for code,cid,hypothesis,delta in probes:
    answer=baseline(cid)
    answer.update(delta)
    reasons=mod.check_result(cases[cid],answer)
    findings.append({
        "id":code,"case":cid,"falsifier":hypothesis,
        "shape_accepted":not reasons,"actual_validator_rejection_codes":reasons,
        "has_live_catalog_verification":False,
        "has_real_consumer_receipt":False,
    })

# Guard against a fake checker that accepts everything, including obvious faults.
control=baseline("R08")
control["request_sha256"]="0"*64
negative_control_rejected=bool(mod.check_result(cases["R08"],control))
control2=baseline("R08")
control2["router_effect_authorized"]=True
negative_authority_control_rejected=bool(mod.check_result(cases["R08"],control2))
corpus_errors,stats=mod.corpus_check(doc)
valid=(len(findings)==9 and all(x["shape_accepted"] for x in findings)
       and negative_control_rejected and negative_authority_control_rejected
       and not corpus_errors and stats["cases"]==30 and stats["requirements"]==12
       and len(stats["groups"])==9)
print(json.dumps({
  "diagnosis_status":"REPRODUCED_SHAPE_LIMITATIONS" if valid else "REPRODUCTION_FAILED",
  "product_result":"NOT_TESTED",
  "c3_independent_judge":"NOT_PERFORMED",
  "c2_checkpoint_state_claim":"UNCHANGED",
  "frozen_corpus_case_count":stats.get("cases"),
  "frozen_corpus_req_count":stats.get("requirements"),
  "frozen_corpus_family_count":len(stats.get("groups",{})),
  "false_valid_shape_probes":sum(x["shape_accepted"] for x in findings),
  "test_countercontrols_rejected":int(negative_control_rejected)+int(negative_authority_control_rejected),
  "observations":findings,
  "source_note":"Fixture:// references are deliberately not authority; a shape pass does not certify them.",
},ensure_ascii=False))
sys.exit(0 if valid else 3)
