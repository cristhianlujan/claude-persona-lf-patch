from __future__ import annotations
import copy, json, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from s30_quality_preservation import *


def projection():
    return {
        "contract_version": "S30_QUALITY_OBLIGATION_INPUT_V1",
        "execution_id": "EXEC-Q-001",
        "profile_code": "PERFIL-UI-ARCHITECT",
        "readiness_receipt_sha256": "a" * 64,
        "readiness_status": "EXECUTION_READY",
        "card_coverage_status": "PASS",
        "coverage_reason": "critical profile capabilities are covered by exact/compatible/generic-safe sources",
        "coverage_evidence_refs": ["profile-readiness://receipt/001"],
        "quality_obligations": [
            {"obligation_id": "Q-HIER", "statement": "Preserve meaningful visual hierarchy", "criticality": "CRITICAL", "source_ref": "PROFILE_CARD_READINESS", "verification_mode": "FINAL_SEMANTIC_EVALUATION"},
            {"obligation_id": "Q-SCAN", "statement": "Preserve scan-friendly grouping", "criticality": "REQUIRED", "source_ref": "PROFILE_CARD_READINESS", "verification_mode": "SEMANTIC_DELTA"},
            {"obligation_id": "Q-LIMIT", "statement": "Preserve deterministic item limit", "criticality": "REQUIRED", "source_ref": "PROFILE_CARD_READINESS", "verification_mode": "DETERMINISTIC_READBACK"},
        ],
    }


def graph():
    return {
        "contract_version": "S30_CANONICAL_WORKING_GRAPH_V1",
        "ids": ["cmp-search", "cmp-category", "cmp-service-card"],
        "relations": [{"relation_id": "r-category-cards", "relation_type": "PARENT_CHILD", "member_ids": ["cmp-category", "cmp-service-card"]}],
    }


def semantic_delta(manifest, *, include_semantic=True):
    evidence = []
    if include_semantic:
        for oid in manifest["semantic_delta_obligation_ids"]:
            evidence.append({"obligation_id": oid, "evidence_pointer": {"field": "proposals", "index": 0}})
    return {"semantic_delta": {
        "decisions": [{"choice": "balanced hierarchy"}],
        "proposals": [{"grouping": "search then categories then service cards"}],
        "rationale": ["reduces scanning cost"],
        "unresolved": [],
        "obligation_evidence": evidence,
    }}


def readback():
    return {
        "readback_contract": "S30_MATERIALIZATION_PRESERVATION_READBACK_V1",
        "artifact_sha256": "b" * 64,
        "producer_is_materializer": False,
        "readback_source": "consumer-specific-deterministic-validator",
        "observed_component_ids": ["cmp-search", "cmp-category", "cmp-service-card"],
        "observed_relation_ids": ["r-category-cards"],
        "observed_quality_obligation_ids": ["QLT::Q-LIMIT"],
    }


def final_eval(manifest, verdict="COMPLIES"):
    return {
        "contract_version": "S30_FINAL_SEMANTIC_QUALITY_EVALUATION_V1",
        "artifact_sha256": "b" * 64,
        "manifest_sha256": manifest["manifest_sha256"],
        "evaluator_role": "INDEPENDENT_EVALUATION_ONLY",
        "producer_is_materializer": False,
        "results": [
            {"obligation_id": oid, "verdict": verdict, "evidence_ref": "quality-eval://artifact/001"}
            for oid in manifest["final_semantic_evaluation_obligation_ids"]
        ],
    }


def main():
    checks = 0
    p = projection(); g = graph()
    built = build_semantic_obligation_manifest(p, g); assert built["status"] == PASS; m = built["manifest"]; checks += 1
    assert set(m["required_obligation_ids"]) == {"CMP::cmp-search", "CMP::cmp-category", "CMP::cmp-service-card", "REL::r-category-cards", "QLT::Q-HIER", "QLT::Q-SCAN", "QLT::Q-LIMIT"}; checks += 1
    assert m["semantic_delta_obligation_ids"] == ["QLT::Q-SCAN"]; checks += 1
    assert "QLT::Q-HIER" in m["final_semantic_evaluation_obligation_ids"] and "CMP::cmp-search" in m["deterministic_readback_obligation_ids"]; checks += 1
    req = build_semantic_gap_request_v2({"semantic_context": {"goal": "choose hierarchy"}, "candidate_alternatives": ["balanced"]}, m)
    assert req["status"] == PASS and len(req["request"]["required_semantic_obligations"]) == 1 and len(req["request"]["deterministic_preservation_constraints"]) >= 4; checks += 1
    good = validate_semantic_delta_v2(semantic_delta(m), m); assert good["status"] == PASS and good["coverage_count"] == 1; checks += 1
    # Partial semantic PASS is forbidden for semantic obligations.
    missing_semantic = validate_semantic_delta_v2(semantic_delta(m, include_semantic=False), m)
    assert missing_semantic["code"] == "BLOCK_SEMANTIC_OBLIGATION_COVERAGE_MISSING" and missing_semantic["missing_obligation_ids"] == ["QLT::Q-SCAN"]; checks += 1
    unknown = semantic_delta(m); unknown["semantic_delta"]["obligation_evidence"][0]["obligation_id"] = "QLT::INVENTED"; assert validate_semantic_delta_v2(unknown, m)["code"] == "BLOCK_SEMANTIC_OBLIGATION_UNKNOWN"; checks += 1
    ptr = semantic_delta(m); ptr["semantic_delta"]["obligation_evidence"][0]["evidence_pointer"] = {"field": "proposals", "index": 99}; assert validate_semantic_delta_v2(ptr, m)["code"] == "BLOCK_SEMANTIC_OBLIGATION_EVIDENCE_POINTER"; checks += 1
    unresolved = semantic_delta(m); unresolved["semantic_delta"]["unresolved"] = [{"obligation_id": "QLT::Q-SCAN"}]; assert validate_semantic_delta_v2(unresolved, m)["code"] == "BLOCK_SEMANTIC_UNRESOLVED"; checks += 1
    nonready = projection(); nonready["readiness_status"] = "BLOCKED"; assert build_semantic_obligation_manifest(nonready, g)["code"] == "BLOCK_PROFILE_NOT_EXECUTION_READY"; checks += 1
    nominal = projection(); nominal["coverage_reason"] = ""; assert build_semantic_obligation_manifest(nominal, g)["code"] == "BLOCK_PROFILE_CARD_COVERAGE_REASON_MISSING"; checks += 1
    assert validate_materialization_readback(readback(), m)["status"] == PASS; checks += 1
    # This is the concrete fix for the prior false PASS: model omission alone need not repeat system-owned components, but actual materialized component loss is blocked.
    lost = readback(); lost["observed_component_ids"].remove("cmp-service-card"); r = validate_materialization_readback(lost, m); assert r["code"] == "BLOCK_MATERIALIZATION_QUALITY_LOSS" and r["missing_components"] == ["cmp-service-card"]; checks += 1
    flat = readback(); flat["observed_relation_ids"] = []; assert validate_materialization_readback(flat, m)["code"] == "BLOCK_MATERIALIZATION_QUALITY_LOSS"; checks += 1
    qlost = readback(); qlost["observed_quality_obligation_ids"] = []; assert validate_materialization_readback(qlost, m)["code"] == "BLOCK_MATERIALIZATION_QUALITY_LOSS"; checks += 1
    self_attest = readback(); self_attest["producer_is_materializer"] = True; assert validate_materialization_readback(self_attest, m)["code"] == "BLOCK_MATERIALIZATION_SELF_ATTESTATION_FORBIDDEN"; checks += 1
    assert validate_final_semantic_evaluation(final_eval(m), m, artifact_sha256="b"*64)["status"] == PASS; checks += 1
    uncertain = final_eval(m, "UNCERTAIN"); assert validate_final_semantic_evaluation(uncertain, m, artifact_sha256="b"*64)["code"] == "BLOCK_FINAL_SEMANTIC_QUALITY_NOT_COMPLIANT"; checks += 1
    # Same semantic readiness+graph across Direct/Router remains invariant even if execution IDs differ.
    p2 = projection(); p2["execution_id"] = "EXEC-Q-ROUTER"; p2["readiness_receipt_sha256"] = "c"*64
    m2 = build_semantic_obligation_manifest(p2, g)["manifest"]; assert compare_cross_route_invariants(m, m2)["status"] == PASS; checks += 1
    g2 = graph(); g2["ids"].remove("cmp-service-card"); g2["relations"] = []
    m3 = build_semantic_obligation_manifest(p2, g2)["manifest"]; assert compare_cross_route_invariants(m, m3)["code"] == "BLOCK_CROSS_ROUTE_SEMANTIC_INVARIANT_MISMATCH"; checks += 1
    print(json.dumps({
        "result": "PASS", "contract": "S30_SEMANTIC_QUALITY_PRESERVATION_V1", "tests": checks,
        "partial_semantic_pass_blocked": True, "materialized_component_loss_blocked": True,
        "relation_flattening_blocked": True, "uncertain_final_quality_blocked": True,
        "model_calls": 0, "s26_mutations": 0,
    }, sort_keys=True))

if __name__ == "__main__":
    main()
