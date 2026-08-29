#!/usr/bin/env python3
import copy
import json
import sys
from pathlib import Path

READY = "CONTRACT_CONSISTENCY_READY_FOR_SEMANTIC_REVIEW"
REPAIR = "RETURN_TO_WORKER_FOR_SELF_REPAIR"


def parse_json_text(files, path, blocking):
    raw = files.get(path)
    if not isinstance(raw, str) or not raw.strip():
        blocking.append(f"MISSING_OR_EMPTY:{path}")
        return None
    try:
        return json.loads(raw)
    except Exception as exc:
        blocking.append(f"INVALID_JSON:{path}:{exc}")
        return None


def closed_values(spec):
    values = set()
    if not isinstance(spec, dict):
        return values
    if "const" in spec:
        values.add(json.dumps(spec["const"], sort_keys=True))
    enum = spec.get("enum")
    if isinstance(enum, list):
        values.update(json.dumps(v, sort_keys=True) for v in enum)
    for key in ("oneOf", "anyOf"):
        branches = spec.get(key)
        if isinstance(branches, list):
            for branch in branches:
                values.update(closed_values(branch))
    return values


def root_discriminators(schema):
    result = {}

    def scan(node):
        if not isinstance(node, dict):
            return
        props = node.get("properties")
        if isinstance(props, dict):
            for name, spec in props.items():
                vals = closed_values(spec)
                if vals:
                    result.setdefault(name, set()).update(vals)
        for key in ("oneOf", "anyOf", "allOf"):
            branches = node.get(key)
            if isinstance(branches, list):
                for branch in branches:
                    scan(branch)

    scan(schema)
    return result


def schema_root_properties(schema):
    names = set()

    def scan(node):
        if not isinstance(node, dict):
            return
        props = node.get("properties")
        if isinstance(props, dict):
            names.update(props)
        for key in ("oneOf", "anyOf", "allOf"):
            branches = node.get(key)
            if isinstance(branches, list):
                for branch in branches:
                    scan(branch)

    scan(schema)
    return names


def validate_example(name, obj, schema, discriminators, blocking):
    if not isinstance(obj, dict):
        blocking.append(f"EXAMPLE_NOT_OBJECT:{name}")
        return
    required = schema.get("required", []) if isinstance(schema, dict) else []
    if isinstance(required, list):
        for field in required:
            if field not in obj:
                blocking.append(f"EXAMPLE_REQUIRED_FIELD_MISSING:{name}:{field}")
    if schema.get("additionalProperties") is False:
        allowed = schema_root_properties(schema)
        for field in obj:
            if field not in allowed:
                blocking.append(f"EXAMPLE_UNDECLARED_ROOT_FIELD:{name}:{field}")
    matched = False
    for field, allowed_values in discriminators.items():
        if field not in obj:
            continue
        matched = True
        encoded = json.dumps(obj[field], sort_keys=True)
        if encoded not in allowed_values:
            blocking.append(f"EXAMPLE_UNDECLARED_DISCRIMINATOR_VALUE:{name}:{field}:{obj[field]}")
    if not matched:
        blocking.append(f"EXAMPLE_DISCRIMINATOR_MISSING:{name}")


def validate_eval_expectations(evals, discriminators, blocking):
    cases = evals.get("cases") if isinstance(evals, dict) else None
    if not isinstance(cases, list) or not cases:
        blocking.append("CONSISTENCY_EVAL_CASES_REQUIRED")
        return
    router_direct_covered = False
    for idx, case in enumerate(cases):
        if not isinstance(case, dict):
            blocking.append(f"CONSISTENCY_EVAL_CASE_INVALID:{idx}")
            continue
        cid = case.get("id", f"case_{idx}")
        expected_output = case.get("expected_output") if isinstance(case.get("expected_output"), dict) else {}
        matched = False
        for field, allowed_values in discriminators.items():
            key = f"expected_{field}"
            if key in case:
                value = case[key]
            elif field in expected_output:
                value = expected_output[field]
            else:
                continue
            matched = True
            if json.dumps(value, sort_keys=True) not in allowed_values:
                blocking.append(f"EVAL_UNDECLARED_DISCRIMINATOR_VALUE:{cid}:{field}:{value}")
        if not matched:
            blocking.append(f"EVAL_EXPECTED_DISCRIMINATOR_MISSING:{cid}")
        assertions = case.get("assertions")
        if isinstance(assertions, list):
            joined = " ".join(str(v).lower() for v in assertions)
            if "router" in joined and "direct" in joined:
                router_direct_covered = True
    if not router_direct_covered:
        blocking.append("ROUTER_DIRECT_EQUIVALENCE_EVAL_REQUIRED")


def validate_score_taxonomy(schema, rubric, blocking):
    props = schema.get("properties") if isinstance(schema, dict) else None
    score = props.get("score") if isinstance(props, dict) else None
    score_props = score.get("properties") if isinstance(score, dict) else None
    if not isinstance(score_props, dict) or not score_props:
        return
    criteria = set(score_props) - {"total", "evidence_by_criterion"}
    evidence = score_props.get("evidence_by_criterion")
    evidence_required = set(evidence.get("required", [])) if isinstance(evidence, dict) else set()
    if evidence_required and evidence_required != criteria:
        blocking.append("SCORE_EVIDENCE_CRITERIA_MISMATCH")
    low = rubric.lower() if isinstance(rubric, str) else ""
    for criterion in sorted(criteria):
        if criterion.lower() not in low:
            blocking.append(f"RUBRIC_SCORE_CRITERION_MISSING:{criterion}")


def validate_adapter_bindings(files, blocking):
    adapters = [(path, text) for path, text in files.items() if path.startswith("adapters/") and path.endswith((".md", ".json", ".yaml", ".yml"))]
    for path, text in adapters:
        low = text.lower() if isinstance(text, str) else ""
        if len(low.strip()) < 100:
            blocking.append(f"ADAPTER_UNDERDEVELOPED:{path}")
            continue
        if "router" not in low:
            blocking.append(f"ADAPTER_ROUTER_ENTRY_BOUNDARY_MISSING:{path}")
        if not any(token in low for token in ("profile", "skill", "caller")):
            blocking.append(f"ADAPTER_CALLER_BINDING_MISSING:{path}")
        if not any(token in low for token in ("trigger", "invocation", "invoke")):
            blocking.append(f"ADAPTER_INVOCATION_CONTRACT_MISSING:{path}")
        if not any(token in low for token in ("token", "compact", "minimal context", "execution-changing")):
            blocking.append(f"ADAPTER_CONTEXT_BUDGET_MISSING:{path}")


def validate_candidate(pack):
    blocking = []
    warnings = []
    if not isinstance(pack, dict):
        return ["CANDIDATE_NOT_OBJECT"], warnings
    files = pack.get("files")
    if not isinstance(files, dict):
        return ["CANDIDATE_FILES_MISSING"], warnings

    profile_validator = files.get("validators/validate_pack.py")
    if not isinstance(profile_validator, str) or len(profile_validator.strip()) < 180:
        blocking.append("EXECUTABLE_PROFILE_VALIDATOR_REQUIRED")
    else:
        low = profile_validator.lower()
        if "def main" not in low or "blocking" not in low or "return" not in low:
            blocking.append("PROFILE_VALIDATOR_NOT_EXECUTABLE_ENOUGH")

    manifest = parse_json_text(files, "manifest.json", blocking)
    if isinstance(manifest, dict):
        required_files = manifest.get("required_files")
        if not isinstance(required_files, list) or "validators/validate_pack.py" not in required_files:
            blocking.append("MANIFEST_PROFILE_VALIDATOR_NOT_DECLARED")

    schema = parse_json_text(files, "schemas/output.schema.json", blocking)
    if not isinstance(schema, dict):
        return blocking, warnings
    discriminators = root_discriminators(schema)
    if not discriminators:
        blocking.append("OUTPUT_DISCRIMINATOR_NOT_CLOSED")
    else:
        contract = str(files.get("contracts/main_contract.md", ""))
        skill = str(files.get("SKILL.md", ""))
        declared_text = (skill + "\n" + contract).lower()
        for field in sorted(discriminators):
            if field.lower() not in declared_text:
                blocking.append(f"OUTPUT_DISCRIMINATOR_NOT_DECLARED_IN_CONTRACT:{field}")

        for path in ("examples/good_output.json", "examples/bad_output.json", "examples/self_repair_output.json"):
            if path in files:
                obj = parse_json_text(files, path, blocking)
                if obj is not None:
                    validate_example(path, obj, schema, discriminators, blocking)

        evals = parse_json_text(files, "evals/eval_matrix.json", blocking)
        if isinstance(evals, dict):
            validate_eval_expectations(evals, discriminators, blocking)
            behavioral = str(evals.get("behavioral_eval_status", "NOT_EXECUTED")).upper()
            if any(token in behavioral for token in ("PASS", "PROVEN", "EXECUTED_SUCCESS")) and not evals.get("behavioral_execution_receipt_ref"):
                blocking.append("BEHAVIORAL_PASS_WITHOUT_EXECUTION_RECEIPT")

    rubric = str(files.get("judges/score_rubric.md", ""))
    validate_score_taxonomy(schema, rubric, blocking)

    judge = str(files.get("judges/mini_judge.md", "")).lower()
    if "schema" not in judge and "output contract" not in judge:
        blocking.append("MINI_JUDGE_CROSS_ARTIFACT_CHECK_MISSING")

    validate_adapter_bindings(files, blocking)

    if not blocking:
        warnings.extend([
            "DETERMINISTIC_CONSISTENCY_GATE_IS_NOT_SEMANTIC_QUALITY_APPROVAL",
            "BEHAVIORAL_EXECUTION_REMAINS_SEPARATE_FROM_CONTRACT_REGRESSION",
        ])
    return blocking, warnings


def validate_file(path):
    try:
        pack = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        return {"status": REPAIR, "blocking_codes": [f"CANDIDATE_READ_ERROR:{exc}"], "warnings": []}
    blocking, warnings = validate_candidate(pack)
    return {
        "status": READY if not blocking else REPAIR,
        "validation_scope": "DETERMINISTIC_CROSS_ARTIFACT_CONSISTENCY_ONLY",
        "semantic_quality_review": "NOT_EXECUTED",
        "behavioral_eval_status": "NOT_EXECUTED",
        "blocking_codes": blocking,
        "warnings": warnings,
    }


def mutate_non_status_discriminator(pack):
    out = copy.deepcopy(pack)
    schema = json.loads(out["files"]["schemas/output.schema.json"])
    schema["required"] = ["output_type" if x == "status" else x for x in schema.get("required", [])]
    props = schema["properties"]
    props["output_type"] = {"type": "string", "const": "SOURCE_REVIEW_RESULT"}
    props.pop("status", None)
    out["files"]["schemas/output.schema.json"] = json.dumps(schema, indent=2)
    for path in ("examples/good_output.json", "examples/bad_output.json"):
        obj = json.loads(out["files"][path])
        obj.pop("status", None)
        obj["output_type"] = "SOURCE_REVIEW_RESULT"
        out["files"][path] = json.dumps(obj, indent=2)
    evals = json.loads(out["files"]["evals/eval_matrix.json"])
    for case in evals.get("cases", []):
        case.pop("expected_status", None)
        case["expected_output_type"] = "SOURCE_REVIEW_RESULT"
    out["files"]["evals/eval_matrix.json"] = json.dumps(evals, indent=2)
    out["files"]["SKILL.md"] += "\nThe root `output_type` is the closed output discriminator.\n"
    out["files"]["contracts/main_contract.md"] += "\nThe root `output_type` is governed by the typed output schema.\n"
    return out


def self_test(root):
    positive_path = Path(root) / "fixtures/semantic_depth/positive_candidate_pack.json"
    positive = json.loads(positive_path.read_text(encoding="utf-8"))
    cases = []

    def run(name, pack, expected_ready, expected_code=None):
        blocking, _ = validate_candidate(pack)
        ready = not blocking
        ok = ready == expected_ready and (expected_code is None or expected_code in blocking)
        cases.append({"case": name, "aligned": ok, "blocking_codes": blocking})

    run("positive_control", positive, True)
    run("non_status_discriminator_supported", mutate_non_status_discriminator(positive), True)

    no_validator = copy.deepcopy(positive)
    no_validator["files"].pop("validators/validate_pack.py", None)
    run("missing_profile_validator_rejected", no_validator, False, "EXECUTABLE_PROFILE_VALIDATOR_REQUIRED")

    bad_eval = copy.deepcopy(positive)
    evals = json.loads(bad_eval["files"]["evals/eval_matrix.json"])
    evals["cases"][0]["expected_status"] = "UNDECLARED_MODE"
    bad_eval["files"]["evals/eval_matrix.json"] = json.dumps(evals, indent=2)
    run("undeclared_eval_mode_rejected", bad_eval, False)

    bad_example = copy.deepcopy(positive)
    example = json.loads(bad_example["files"]["examples/good_output.json"])
    example["status"] = "UNDECLARED_MODE"
    bad_example["files"]["examples/good_output.json"] = json.dumps(example, indent=2)
    run("undeclared_example_mode_rejected", bad_example, False)

    no_route = copy.deepcopy(positive)
    evals = json.loads(no_route["files"]["evals/eval_matrix.json"])
    for case in evals.get("cases", []):
        case["assertions"] = [a for a in case.get("assertions", []) if "router" not in str(a).lower() and "direct" not in str(a).lower()]
    no_route["files"]["evals/eval_matrix.json"] = json.dumps(evals, indent=2)
    run("router_direct_coverage_required", no_route, False, "ROUTER_DIRECT_EQUIVALENCE_EVAL_REQUIRED")

    failed = [c["case"] for c in cases if not c["aligned"]]
    return {
        "status": "PASS" if not failed else "FAIL",
        "validation_scope": "DETERMINISTIC_CONSISTENCY_SELF_TEST",
        "semantic_quality_review": "NOT_EXECUTED",
        "behavioral_eval_status": "NOT_EXECUTED",
        "cases": cases,
        "aligned": len(cases) - len(failed),
        "total": len(cases),
        "failed_cases": failed,
    }


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        root = Path(sys.argv[2]) if len(sys.argv) >= 3 else Path.cwd()
        result = self_test(root)
        print(json.dumps(result, indent=2))
        return 0 if result["status"] == "PASS" else 1
    if len(sys.argv) < 2:
        print("usage: validate_candidate_consistency.py <candidate.json> | --self-test <profile_creator_root>", file=sys.stderr)
        return 2
    result = validate_file(Path(sys.argv[1]))
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == READY else 1


if __name__ == "__main__":
    raise SystemExit(main())
