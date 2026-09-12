#!/usr/bin/env python3
import copy
import json
import sys
from pathlib import Path

import validate_candidate_depth as depth


def load_positive(root: Path) -> dict:
    return json.loads((root / "fixtures/semantic_depth/positive_candidate_pack.json").read_text(encoding="utf-8"))


def mutate_prose_inflation(pack: dict) -> dict:
    out = copy.deepcopy(pack)
    out["files"]["contracts/main_contract.md"] = "# Main Contract\n\n" + (
        "inputs source authority evidence source ref scope may decide must not forbidden "
        "failure reject block return output decision result " * 30
    )
    return out


def mutate_weak_evidence_schema(pack: dict) -> dict:
    out = copy.deepcopy(pack)
    schema = json.loads(out["files"]["schemas/output.schema.json"])
    schema["properties"]["evidence_map"] = {"type": "object"}
    out["files"]["schemas/output.schema.json"] = json.dumps(schema, indent=2)
    return out


def mutate_generic_assertions(pack: dict) -> dict:
    out = copy.deepcopy(pack)
    evals = json.loads(out["files"]["evals/eval_matrix.json"])
    for case in evals.get("cases", []):
        if isinstance(case, dict):
            case["assertions"] = ["ok"]
    out["files"]["evals/eval_matrix.json"] = json.dumps(evals, indent=2)
    return out


def mutate_nominal_handoff(pack: dict) -> dict:
    out = copy.deepcopy(pack)
    handoff = json.loads(out["files"]["handoffs/to_quality_pack.handoff.json"])
    handoff["required_receiver_context"] = ["artifact evidence schema contract rubric judge blocking failure risk"]
    handoff["failure_routing"] = {"anything": "RETURN_TO_WORKER_FOR_SELF_REPAIR"}
    out["files"]["handoffs/to_quality_pack.handoff.json"] = json.dumps(handoff, indent=2)
    return out


def mutate_authority_not_evidenced(pack: dict) -> dict:
    out = copy.deepcopy(pack)
    out["evidence_map"] = [
        {"source_ref": "lf://source/SRC-001", "supports": ["generic claim"]}
    ]
    return out


def mutate_user_metadata_leakage(pack: dict) -> dict:
    out = copy.deepcopy(pack)
    out["exposes_user_facing_output"] = True
    return out


def mutate_runtime_enabled(pack: dict) -> dict:
    out = copy.deepcopy(pack)
    out["runtime_enabled"] = True
    return out


def run_case(name: str, pack: dict, expected_ready: bool) -> dict:
    blocking, warnings = depth.validate_candidate(pack)
    observed_ready = not blocking
    aligned = observed_ready == expected_ready
    return {
        "case": name,
        "champion_expected": "READY_FOR_SEMANTIC_REVIEW" if expected_ready else "REJECT_OR_REPAIR",
        "challenger_observed": "DEPTH_READY_FOR_SEMANTIC_REVIEW" if observed_ready else "RETURN_TO_WORKER_FOR_SELF_REPAIR",
        "aligned": aligned,
        "blocking_codes": blocking,
        "warnings": warnings,
    }


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    positive = load_positive(root)

    cases = [
        ("positive_control", positive, True),
        ("A_semantic_content_prose_inflation", mutate_prose_inflation(positive), False),
        ("B_weak_evidence_schema", mutate_weak_evidence_schema(positive), False),
        ("D_generic_eval_assertions", mutate_generic_assertions(positive), False),
        ("E_nominal_handoff_keywords_only", mutate_nominal_handoff(positive), False),
        ("B_authority_declared_without_authority_evidence", mutate_authority_not_evidenced(positive), False),
        ("F_user_facing_internal_metadata_boundary_missing", mutate_user_metadata_leakage(positive), False),
        ("C_runtime_governance_bypass", mutate_runtime_enabled(positive), False),
    ]

    results = [run_case(name, pack, expected) for name, pack, expected in cases]
    misaligned = [item["case"] for item in results if not item["aligned"]]
    payload = {
        "status": "PASS" if not misaligned else "FAIL",
        "evaluation_mode": "CHAMPION_CHALLENGER_DETERMINISTIC_ALIGNMENT",
        "champion": "INDEPENDENT_SEMANTIC_REVIEW_DISPOSITION_CLASSES_FROM_GOV021",
        "challenger": "skills/profile_creator/validators/validate_candidate_depth.py",
        "semantic_quality_review": "NOT_EXECUTED",
        "cases": results,
        "aligned": len(results) - len(misaligned),
        "total": len(results),
        "misaligned_cases": misaligned,
        "notes": [
            "Champion labels cover only deterministically observable failure classes derived from GOV-021.",
            "This suite does not automate semantic approval and cannot replace independent Quality Pack review.",
        ],
    }
    print(json.dumps(payload, indent=2))
    return 0 if not misaligned else 1


if __name__ == "__main__":
    raise SystemExit(main())
