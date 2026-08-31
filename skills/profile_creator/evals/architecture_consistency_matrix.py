#!/usr/bin/env python3
import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "validators"))
import validate_candidate_consistency as consistency


def load_pack():
    return json.loads((ROOT / "fixtures/semantic_depth/positive_candidate_pack.json").read_text(encoding="utf-8"))


def check(name, pack, expected_ready, expected_code=None):
    blocking, _ = consistency.validate_candidate(pack)
    ready = not blocking
    return {
        "case": name,
        "aligned": ready == expected_ready and (expected_code is None or expected_code in blocking),
        "blocking_codes": blocking,
    }


def rename_discriminator(pack):
    out = consistency.mutate_non_status_discriminator(pack)
    schema = json.loads(out["files"]["schemas/output.schema.json"])
    schema["required"] = ["decision_kind" if v == "output_type" else v for v in schema["required"]]
    schema["properties"]["decision_kind"] = schema["properties"].pop("output_type")
    out["files"]["schemas/output.schema.json"] = json.dumps(schema)
    for path in ("examples/good_output.json", "examples/bad_output.json"):
        obj = json.loads(out["files"][path])
        obj["decision_kind"] = obj.pop("output_type")
        out["files"][path] = json.dumps(obj)
    evals = json.loads(out["files"]["evals/eval_matrix.json"])
    for case in evals["cases"]:
        case["expected_decision_kind"] = case.pop("expected_output_type")
    out["files"]["evals/eval_matrix.json"] = json.dumps(evals)
    out["files"]["SKILL.md"] += "\nThe root `decision_kind` is the closed output discriminator.\n"
    out["files"]["contracts/main_contract.md"] += "\nThe root `decision_kind` is the governed typed discriminator.\n"
    return out


def main():
    positive = load_pack()
    results = [check("fresh_unseen_discriminator_name", rename_discriminator(positive), True)]

    loose = copy.deepcopy(positive)
    loose["files"]["adapters/loose.md"] = (
        "# Adapter\nThis integration may be used without Router binding. It has a broad input and a broad return. "
        "It does not declare a profile caller, activation trigger, or compact execution context contract."
    )
    results.append(check("loose_adapter_rejected", loose, False, "ADAPTER_ROUTER_ENTRY_BOUNDARY_MISSING:adapters/loose.md"))

    bound = copy.deepcopy(positive)
    bound["files"]["adapters/bound.md"] = (
        "# Adapter\nRouter resolves the profile first. The profile is the caller. Invocation trigger is explicit. "
        "Input is compact execution-changing context with a minimal token budget. The adapter returns to the profile."
    )
    results.append(check("bound_adapter_accepted", bound, True))

    overclaim = copy.deepcopy(positive)
    evals = json.loads(overclaim["files"]["evals/eval_matrix.json"])
    evals["behavioral_eval_status"] = "PASS"
    overclaim["files"]["evals/eval_matrix.json"] = json.dumps(evals)
    results.append(check("behavioral_overclaim_rejected", overclaim, False, "BEHAVIORAL_PASS_WITHOUT_EXECUTION_RECEIPT"))

    stale = copy.deepcopy(positive)
    schema = json.loads(stale["files"]["schemas/output.schema.json"])
    schema["properties"]["score"] = {
        "type": "object",
        "properties": {
            "architecture_quality": {"type": "integer"},
            "total": {"type": "integer"},
            "evidence_by_criterion": {"type": "object", "required": ["architecture_quality"]}
        }
    }
    stale["files"]["schemas/output.schema.json"] = json.dumps(schema)
    results.append(check("stale_rubric_rejected", stale, False, "RUBRIC_SCORE_CRITERION_MISSING:architecture_quality"))

    failed = [r["case"] for r in results if not r["aligned"]]
    print(json.dumps({
        "status": "PASS" if not failed else "FAIL",
        "matrix": "PROFILE_CREATOR_ARCHITECTURE_CONSISTENCY_FRESH_HOLDOUT_V1",
        "cases": results,
        "aligned": len(results) - len(failed),
        "total": len(results),
        "failed_cases": failed,
        "semantic_quality_review": "NOT_EXECUTED",
        "behavioral_eval_status": "NOT_EXECUTED"
    }, indent=2))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
