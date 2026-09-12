from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from s30_quality_preservation import build_semantic_obligation_manifest
from s30_r16_invariant_assurance import *


def projection():
    return {
        "contract_version": "S30_QUALITY_OBLIGATION_INPUT_V1",
        "execution_id": "EXEC-R16-001",
        "profile_code": "PERFIL-UI-ARCHITECT",
        "readiness_receipt_sha256": "a" * 64,
        "readiness_status": "EXECUTION_READY",
        "card_coverage_status": "PASS",
        "coverage_reason": "profile quality obligations are bound before execution",
        "coverage_evidence_refs": ["profile-readiness://r16/001"],
        "quality_obligations": [
            {
                "obligation_id": "Q-SCAN",
                "statement": "Preserve scan-friendly grouping",
                "criticality": "REQUIRED",
                "source_ref": "PROFILE_CARD_READINESS",
                "verification_mode": "SEMANTIC_DELTA",
            },
            {
                "obligation_id": "Q-LIMIT",
                "statement": "Preserve deterministic item limit",
                "criticality": "REQUIRED",
                "source_ref": "PROFILE_CARD_READINESS",
                "verification_mode": "DETERMINISTIC_READBACK",
            },
        ],
    }


def graph():
    return {
        "contract_version": "S30_CANONICAL_WORKING_GRAPH_V1",
        "ids": ["cmp-search", "cmp-card"],
        "relations": [
            {
                "relation_id": "rel-search-card",
                "relation_type": "PRECEDES",
                "member_ids": ["cmp-search", "cmp-card"],
            }
        ],
    }


def manifest():
    out = build_semantic_obligation_manifest(projection(), graph())
    assert out["status"] == PASS
    return out["manifest"]


def delta_v3(m):
    atom = {"atom_id": "proposal-1", "text": "Keep search before the repeated card collection to preserve scanning order."}
    oid = m["semantic_delta_obligation_ids"][0]
    statement = next(o["statement"] for o in m["obligations"] if o["obligation_id"] == oid)
    return {
        "semantic_delta": {
            "contract_version": "S30_SEMANTIC_DELTA_V3",
            "decisions": [],
            "proposals": [atom],
            "rationale": [{"atom_id": "rationale-1", "text": "The order keeps navigation and scanning predictable."}],
            "unresolved": [],
            "obligation_evidence": [
                {
                    "obligation_id": oid,
                    "atom_id": atom["atom_id"],
                    "atom_sha256": canonical_sha256(atom),
                    "obligation_statement_sha256": canonical_sha256(statement),
                }
            ],
        }
    }


def substance_receipt(m, dsha, verdict="COMPLIES"):
    return {
        "contract_version": "S30_SEMANTIC_EVIDENCE_SUBSTANCE_EVALUATION_V1",
        "manifest_sha256": m["manifest_sha256"],
        "semantic_delta_sha256": dsha,
        "evaluator_role": "INDEPENDENT_EVALUATION_ONLY",
        "producer_is_materializer": False,
        "results": [
            {
                "obligation_id": oid,
                "verdict": verdict,
                "evidence_ref": "semantic-eval://r16/001",
                "reason": "The bound atom directly addresses the obligation statement.",
            }
            for oid in m["semantic_delta_obligation_ids"]
        ],
    }


def readback_v2(m):
    relation = next(o for o in m["obligations"] if o["kind"] == "RELATION_PRESERVATION")
    return {
        "readback_contract": "S30_MATERIALIZATION_PRESERVATION_READBACK_V2",
        "artifact_sha256": "b" * 64,
        "producer_is_materializer": False,
        "readback_source": "consumer-specific-deterministic-validator",
        "observed_components": [
            {"component_id": "cmp-search", "content_sha256": "c" * 64},
            {"component_id": "cmp-card", "content_sha256": "d" * 64},
        ],
        "observed_relations": [
            {
                "relation_id": relation["relation_id"],
                "member_ids": relation["member_ids"],
                "content_sha256": "e" * 64,
            }
        ],
        "deterministic_quality_evidence": [
            {
                "obligation_id": "QLT::Q-LIMIT",
                "evidence_ref": "readback://q-limit/001",
                "evidence_sha256": "f" * 64,
            }
        ],
    }


def main():
    checks = 0
    catalog = json.loads((HERE / "r16_invariant_assurance_contract_v1.json").read_text())
    good_catalog = validate_invariant_catalog(catalog)
    assert good_catalog["status"] == PASS and good_catalog["finding_quota"] is None; checks += 1

    quota = copy.deepcopy(catalog); quota["target_findings"] = 10
    assert validate_invariant_catalog(quota)["code"] == "BLOCK_R16_INVARIANT_CATALOG_SHAPE"; checks += 1
    quota2 = copy.deepcopy(catalog); quota2["invariants"][0]["verification"]["minimum_findings"] = 10
    assert validate_invariant_catalog(quota2)["code"] == "BLOCK_R16_FINDING_QUOTA_FORBIDDEN"; checks += 1
    heuristic = copy.deepcopy(catalog); heuristic["invariants"][-1]["blocking"] = True
    assert validate_invariant_catalog(heuristic)["code"] == "BLOCK_R16_SIGNAL_CANNOT_BLOCK"; checks += 1
    unvalidated = copy.deepcopy(catalog); unvalidated["invariants"][0]["verification"]["mutation_case"] = False
    assert validate_invariant_catalog(unvalidated)["code"] == "BLOCK_R16_UNVALIDATED_INVARIANT"; checks += 1

    m = manifest()
    delta = delta_v3(m)
    bound = validate_semantic_delta_v3(delta, m)
    assert bound["status"] == PASS and bound["semantic_substance_status"] == "REQUIRES_INDEPENDENT_EVALUATION"; checks += 1

    nested = copy.deepcopy(delta); nested["semantic_delta"]["proposals"][0]["internal_trace_context"] = "x"
    assert validate_semantic_delta_v3(nested, m)["code"] == "BLOCK_R16_SEMANTIC_ATOM_ALLOWLIST"; checks += 1
    bad_hash = copy.deepcopy(delta); bad_hash["semantic_delta"]["obligation_evidence"][0]["atom_sha256"] = "0" * 64
    assert validate_semantic_delta_v3(bad_hash, m)["code"] == "BLOCK_R16_SEMANTIC_EVIDENCE_ATOM_HASH"; checks += 1
    bad_statement = copy.deepcopy(delta); bad_statement["semantic_delta"]["obligation_evidence"][0]["obligation_statement_sha256"] = "0" * 64
    assert validate_semantic_delta_v3(bad_statement, m)["code"] == "BLOCK_R16_SEMANTIC_EVIDENCE_OBLIGATION_HASH"; checks += 1
    missing = copy.deepcopy(delta); missing["semantic_delta"]["obligation_evidence"] = []
    assert validate_semantic_delta_v3(missing, m)["code"] == "BLOCK_R16_SEMANTIC_OBLIGATION_COVERAGE_MISSING"; checks += 1

    assert validate_semantic_evidence_substance_evaluation(substance_receipt(m, bound["semantic_delta_sha256"]), m, semantic_delta_sha256=bound["semantic_delta_sha256"])["status"] == PASS; checks += 1
    uncertain = substance_receipt(m, bound["semantic_delta_sha256"], "UNCERTAIN")
    assert validate_semantic_evidence_substance_evaluation(uncertain, m, semantic_delta_sha256=bound["semantic_delta_sha256"])["code"] == "BLOCK_R16_SEMANTIC_SUBSTANCE_NOT_COMPLIANT"; checks += 1
    self_eval = substance_receipt(m, bound["semantic_delta_sha256"]); self_eval["producer_is_materializer"] = True
    assert validate_semantic_evidence_substance_evaluation(self_eval, m, semantic_delta_sha256=bound["semantic_delta_sha256"])["code"] == "BLOCK_R16_SUBSTANCE_EVALUATOR_INDEPENDENCE"; checks += 1

    source = {
        "title": "Marketplace",
        "component_tree": [
            {"component_id": "search", "role": "search", "internal_trace_context": {"secret": "x"}},
            {"component_id": "card", "role": "item", "runtime_source_context": "opaque"},
        ],
        "governance_envelope": {"internal": True},
    }
    schema = {
        "type": "object",
        "required": ["title", "component_tree"],
        "properties": {
            "title": {"type": "string"},
            "component_tree": {
                "type": "array",
                "items": {
                    "type": "object",
                    "required": ["component_id", "role"],
                    "properties": {
                        "component_id": {"type": "string"},
                        "role": {"type": "string"}
                    }
                }
            }
        }
    }
    handoff = project_handoff_by_allowlist(source, schema)
    assert handoff["status"] == PASS; checks += 1
    serialized = json.dumps(handoff["payload"], sort_keys=True)
    assert "internal_trace_context" not in serialized and "runtime_source_context" not in serialized and "governance_envelope" not in serialized; checks += 1
    missing_source = {"title": "Marketplace"}
    assert project_handoff_by_allowlist(missing_source, schema)["code"] == "BLOCK_R16_HANDOFF_ALLOWLIST_PROJECTION"; checks += 1

    rb = readback_v2(m)
    assert validate_materialization_readback_v2(rb, m)["status"] == PASS; checks += 1
    rel_drift = copy.deepcopy(rb); rel_drift["observed_relations"][0]["member_ids"] = ["cmp-card", "cmp-search"]
    assert validate_materialization_readback_v2(rel_drift, m)["code"] == "BLOCK_R16_MATERIALIZATION_SUBSTANCE_LOSS"; checks += 1
    self_rb = copy.deepcopy(rb); self_rb["producer_is_materializer"] = True
    assert validate_materialization_readback_v2(self_rb, m)["code"] == "BLOCK_R16_READBACK_SELF_ATTESTATION"; checks += 1

    systematic = {"defect_class": "STATIC_TEMPLATE_EVIDENCE", "systematic": True, "producer_ref": "generator://evidence-template", "artifact_ref": "artifact://001"}
    assert classify_defect_remediation(systematic)["action"] == "FIX_PRODUCER_FIRST"; checks += 1
    producer_unknown = copy.deepcopy(systematic); producer_unknown["producer_ref"] = ""
    assert classify_defect_remediation(producer_unknown)["code"] == "BLOCK_R16_SYSTEMATIC_DEFECT_PRODUCER_UNRESOLVED"; checks += 1
    local = {"defect_class": "ONE_OFF_TYPO", "systematic": False, "producer_ref": "", "artifact_ref": "artifact://002"}
    assert classify_defect_remediation(local)["action"] == "ARTIFACT_LOCAL_FIX_ALLOWED"; checks += 1

    print(json.dumps({
        "result": "PASS",
        "contract": "S30_R16_INVARIANT_DRIVEN_SEMANTIC_HANDOFF_ASSURANCE_V1",
        "checks": checks,
        "finding_quota": None,
        "blocking_invariants_meta_validated": True,
        "signal_only_never_blocks": True,
        "semantic_evidence_bound_to_atom_and_obligation": True,
        "semantic_substance_requires_independent_evaluation": True,
        "recursive_handoff_allowlist": True,
        "relation_member_drift_blocked": True,
        "generator_first_systematic_remediation": True,
        "model_calls_for_machine_detectable_checks": 0,
        "s26_mutations": 0,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
