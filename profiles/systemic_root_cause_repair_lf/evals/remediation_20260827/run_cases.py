#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROFILE = HERE.parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


validator = load_module("srcr_runtime_validate", PROFILE / "validators/runtime_validate.py")
utility = load_module("srcr_runtime_semantic", PROFILE / "validators/runtime_semantic_utility.py")
GOOD = json.loads((PROFILE / "examples/good_output.json").read_text(encoding="utf-8"))


def contract_gate():
    return {"status": "PASS"}


def run():
    cases = []

    result = validator.validate(copy.deepcopy(GOOD))
    sem = utility.evaluate(copy.deepcopy(GOOD), contract_gate())
    cases.append(("positive_structural_candidate", result["valid"] and sem["status"] == "PASS"))

    contradiction = copy.deepcopy(GOOD)
    contradiction["authority_contradictions"] = [{
        "classification": "SOURCE_LIVE_DIVERGENCE",
        "declared": "declared owner",
        "observed": "different live executor",
        "blocking": True,
        "evidence_ref": "run://external/1",
    }]
    r = validator.validate(contradiction)
    cases.append(("declared_live_contradiction_blocks_spec", "UNRESOLVED_AUTHORITY_CONTRADICTION" in r["blocking_codes"]))

    existence = copy.deepcopy(GOOD)
    existence["should_exist_assessment"]["verdict"] = "INSUFFICIENT_EVIDENCE"
    r = validator.validate(existence)
    cases.append(("should_exist_insufficient_blocks_spec", "SHOULD_EXIST_ASSESSMENT_UNRESOLVED" in r["blocking_codes"]))

    self_review = copy.deepcopy(GOOD)
    self_review["independent_review"]["producer_is_reviewer"] = True
    r = validator.validate(self_review)
    cases.append(("self_review_rejected", "SELF_REVIEW_FORBIDDEN" in r["blocking_codes"]))

    missing_family = copy.deepcopy(GOOD)
    missing_family["falsification_results"] = [
        item for item in missing_family["falsification_results"]
        if item["case"] != "undeclared_or_unversioned_caller"
    ]
    r = validator.validate(missing_family)
    cases.append(("caller_provenance_falsification_required", "FALSIFICATION_FAMILIES_MISSING" in r["blocking_codes"]))

    unknown_selected = copy.deepcopy(GOOD)
    unknown_selected["selected_alternative"] = "NOT_DECLARED"
    r = utility.evaluate(unknown_selected, contract_gate())
    cases.append(("selected_alternative_must_exist", "SELECTED_ALTERNATIVE_NOT_DECLARED" in r["blocking_codes"]))

    with_blocker = copy.deepcopy(GOOD)
    with_blocker["blocking_codes"] = ["MATERIAL_CONTRADICTION"]
    r = validator.validate(with_blocker)
    cases.append(("spec_with_blockers_rejected", "SYSTEMIC_SPEC_WITH_BLOCKERS" in r["blocking_codes"]))

    malformed = [None, [], {}, {"status": "SYSTEMIC_REPAIR_SPEC"}]
    cases.append(("malformed_fail_closed_no_crash", all(validator.validate(item)["valid"] is False for item in malformed)))

    protocol = (HERE / "behavioral_eval_protocol.md").read_text(encoding="utf-8")
    cases.append(("external_holdout_not_fixture_claim", "fresh external holdout" in protocol.lower() and "not embedded in this profile pack" in protocol.lower()))

    ok = all(value for _, value in cases)
    print(json.dumps({
        "suite": "SYSTEMIC_ROOT_CAUSE_REPAIR_STRUCTURAL_REMEDIATION_20260827",
        "evidence_class": "STRUCTURAL_VALIDATOR_ONLY_NOT_PROFILE_EXECUTION",
        "passed": sum(1 for _, value in cases if value),
        "total": len(cases),
        "cases": [{"case": name, "ok": value} for name, value in cases],
    }, ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(run())
