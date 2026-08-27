#!/usr/bin/env python3
import json
import sys
from pathlib import Path

CORE_FILES = {
    "SKILL.md",
    "README.md",
    "contracts/main_contract.md",
    "schemas/output.schema.json",
    "judges/score_rubric.md",
    "judges/mini_judge.md",
    "evals/eval_matrix.json",
    "handoffs/to_quality_pack.handoff.json",
    "examples/good_output.json",
    "examples/bad_output.json",
    "manifest.json",
}

TEXT_MINIMUMS = {
    "SKILL.md": 300,
    "contracts/main_contract.md": 350,
    "judges/score_rubric.md": 180,
    "judges/mini_judge.md": 160,
}

PLACEHOLDER_TOKENS = ("TODO", "TBD", "PLACEHOLDER", "LOREM IPSUM")


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


def has_any(text, words):
    low = text.lower()
    return any(word in low for word in words)


def validate_text_contract(files, path, minimum, groups, blocking):
    raw = files.get(path)
    if not isinstance(raw, str) or not raw.strip():
        blocking.append(f"MISSING_OR_EMPTY:{path}")
        return
    if len(raw.strip()) < minimum:
        blocking.append(f"UNDERDEVELOPED_TEXT:{path}")
    upper = raw.upper()
    if any(token in upper for token in PLACEHOLDER_TOKENS):
        blocking.append(f"PLACEHOLDER_CONTENT:{path}")
    for code, words in groups:
        if not has_any(raw, words):
            blocking.append(f"{code}:{path}")


def validate_candidate(pack):
    blocking = []
    warnings = []

    if not isinstance(pack, dict):
        return ["CANDIDATE_NOT_OBJECT"], warnings

    if pack.get("artifact_type") != "PROFILE_PACK_CANDIDATE":
        blocking.append("ARTIFACT_TYPE_INVALID")
    if not isinstance(pack.get("profile_pack_id"), str) or not pack.get("profile_pack_id", "").strip():
        blocking.append("PROFILE_PACK_ID_MISSING")
    if not isinstance(pack.get("source_authority"), str) or not pack.get("source_authority", "").strip():
        blocking.append("SOURCE_AUTHORITY_MISSING")
    if pack.get("document_status") != "CANDIDATO":
        blocking.append("DOCUMENT_STATUS_MUST_BE_CANDIDATO")
    if pack.get("operational_status") != "READ_ONLY":
        blocking.append("OPERATIONAL_STATUS_MUST_BE_READ_ONLY")
    if pack.get("runtime_enabled") is not False:
        blocking.append("RUNTIME_ENABLED_MUST_BE_FALSE")
    if pack.get("runtime") not in (None, "NO_HABILITADO"):
        blocking.append("RUNTIME_MUST_BE_NO_HABILITADO")
    if pack.get("automatic_impact") not in ("BLOQUEADO", "BLOCKED"):
        blocking.append("AUTOMATIC_IMPACT_MUST_BE_BLOCKED")
    if pack.get("production_authorization") not in (None, False):
        blocking.append("PRODUCTION_AUTHORIZATION_MUST_BE_FALSE")
    if not isinstance(pack.get("exposes_user_facing_output"), bool):
        blocking.append("EXPOSES_USER_FACING_OUTPUT_MUST_BE_BOOLEAN")

    evidence_map = pack.get("evidence_map")
    if not isinstance(evidence_map, list) or not evidence_map:
        blocking.append("EVIDENCE_MAP_REQUIRED")
    else:
        for idx, item in enumerate(evidence_map):
            if not isinstance(item, dict):
                blocking.append(f"EVIDENCE_ITEM_INVALID:{idx}")
                continue
            if not isinstance(item.get("source_ref"), str) or not item.get("source_ref", "").strip():
                blocking.append(f"EVIDENCE_SOURCE_REF_MISSING:{idx}")
            supports = item.get("supports")
            if not isinstance(supports, list) or not supports:
                blocking.append(f"EVIDENCE_SUPPORTS_MISSING:{idx}")

    files = pack.get("files")
    if not isinstance(files, dict):
        blocking.append("CANDIDATE_FILES_MISSING")
        return blocking, warnings

    for path in sorted(CORE_FILES):
        if path not in files or not isinstance(files.get(path), str) or not files.get(path, "").strip():
            blocking.append(f"CORE_FILE_MISSING_OR_EMPTY:{path}")

    validate_text_contract(
        files,
        "SKILL.md",
        TEXT_MINIMUMS["SKILL.md"],
        [
            ("SKILL_ROLE_MISSING", ("role", "purpose")),
            ("SKILL_INPUTS_MISSING", ("input", "source authority", "source")),
            ("SKILL_TRAJECTORY_MISSING", ("workflow", "route", "trajectory", "steps")),
            ("SKILL_FAILURE_BEHAVIOR_MISSING", ("failure", "block", "return")),
            ("SKILL_AUTHORITY_LIMITS_MISSING", ("limit", "must not", "cannot", "forbidden")),
        ],
        blocking,
    )
    validate_text_contract(
        files,
        "contracts/main_contract.md",
        TEXT_MINIMUMS["contracts/main_contract.md"],
        [
            ("CONTRACT_INPUTS_MISSING", ("input contract", "required input", "inputs")),
            ("CONTRACT_EVIDENCE_MISSING", ("evidence", "source ref", "source authority")),
            ("CONTRACT_SCOPE_MISSING", ("scope", "may decide", "must not", "forbidden")),
            ("CONTRACT_FAILURE_ROUTING_MISSING", ("failure", "reject", "block", "return")),
            ("CONTRACT_OUTPUT_MISSING", ("output", "decision", "result")),
        ],
        blocking,
    )
    validate_text_contract(
        files,
        "judges/score_rubric.md",
        TEXT_MINIMUMS["judges/score_rubric.md"],
        [
            ("RUBRIC_PASS_MISSING", ("pass", "ready")),
            ("RUBRIC_FAIL_MISSING", ("fail", "block", "return")),
            ("RUBRIC_EVIDENCE_MISSING", ("evidence", "source")),
        ],
        blocking,
    )
    validate_text_contract(
        files,
        "judges/mini_judge.md",
        TEXT_MINIMUMS["judges/mini_judge.md"],
        [
            ("MINI_JUDGE_SOURCE_MISSING", ("source", "authority", "evidence")),
            ("MINI_JUDGE_FAILURE_MISSING", ("block", "return", "fail")),
            ("MINI_JUDGE_OUTPUT_MISSING", ("output", "artifact", "result")),
        ],
        blocking,
    )

    manifest = parse_json_text(files, "manifest.json", blocking)
    if manifest is not None:
        if manifest.get("profile_pack_id") != pack.get("profile_pack_id"):
            blocking.append("MANIFEST_PROFILE_PACK_ID_MISMATCH")
        if manifest.get("operation") != "CREACION_PERFIL_LF":
            blocking.append("MANIFEST_OPERATION_INVALID")
        if manifest.get("document_status") != "CANDIDATO":
            blocking.append("MANIFEST_DOCUMENT_STATUS_INVALID")
        if manifest.get("operational_status") != "READ_ONLY":
            blocking.append("MANIFEST_OPERATIONAL_STATUS_INVALID")
        if manifest.get("runtime") != "NO_HABILITADO":
            blocking.append("MANIFEST_RUNTIME_INVALID")
        if manifest.get("automatic_impact") != "BLOQUEADO":
            blocking.append("MANIFEST_AUTOMATIC_IMPACT_INVALID")
        required_files = set(manifest.get("required_files", []))
        missing = sorted(CORE_FILES - required_files)
        for path in missing:
            blocking.append(f"MANIFEST_REQUIRED_FILE_NOT_DECLARED:{path}")

    schema = parse_json_text(files, "schemas/output.schema.json", blocking)
    if schema is not None:
        if schema.get("type") != "object":
            blocking.append("OUTPUT_SCHEMA_TYPE_MUST_BE_OBJECT")
        properties = schema.get("properties")
        required = schema.get("required")
        if not isinstance(properties, dict) or not properties:
            blocking.append("OUTPUT_SCHEMA_PROPERTIES_REQUIRED")
        if not isinstance(required, list) or not required:
            blocking.append("OUTPUT_SCHEMA_REQUIRED_FIELDS_REQUIRED")
        if isinstance(properties, dict) and isinstance(required, list):
            for field in required:
                if field not in properties:
                    blocking.append(f"OUTPUT_SCHEMA_REQUIRED_PROPERTY_UNDEFINED:{field}")
            typed = 0
            for spec in properties.values():
                if isinstance(spec, dict) and any(k in spec for k in ("type", "enum", "const", "oneOf", "anyOf", "allOf")):
                    typed += 1
            if typed < max(1, len(properties) // 2):
                blocking.append("OUTPUT_SCHEMA_INSUFFICIENTLY_TYPED")
        if pack.get("exposes_user_facing_output") is True:
            if not isinstance(properties, dict) or "user_payload" not in properties or "internal_envelope" not in properties:
                blocking.append("USER_INTERNAL_OUTPUT_BOUNDARY_MISSING")
            contract_text = files.get("contracts/main_contract.md", "")
            if "user_payload" not in contract_text or "internal_envelope" not in contract_text:
                blocking.append("USER_INTERNAL_CONTRACT_BOUNDARY_MISSING")

    evals = parse_json_text(files, "evals/eval_matrix.json", blocking)
    if evals is not None:
        cases = evals.get("cases")
        if not isinstance(cases, list) or len(cases) < 4:
            blocking.append("EVAL_MINIMUM_CASES_NOT_MET")
        else:
            positive = 0
            negative = 0
            seen = set()
            for idx, case in enumerate(cases):
                if not isinstance(case, dict):
                    blocking.append(f"EVAL_CASE_INVALID:{idx}")
                    continue
                cid = case.get("id")
                if not isinstance(cid, str) or not cid:
                    blocking.append(f"EVAL_CASE_ID_MISSING:{idx}")
                elif cid in seen:
                    blocking.append(f"EVAL_CASE_DUPLICATE:{cid}")
                else:
                    seen.add(cid)
                fixture = case.get("fixture")
                if not isinstance(fixture, str) or fixture not in files:
                    blocking.append(f"EVAL_FIXTURE_NOT_DELIVERED:{cid}:{fixture}")
                expected = case.get("expected_status")
                if not isinstance(expected, str) or not expected:
                    blocking.append(f"EVAL_EXPECTED_STATUS_MISSING:{cid}")
                else:
                    upper = expected.upper()
                    if any(token in upper for token in ("BLOCK", "FAIL", "RETURN", "REJECT")):
                        negative += 1
                    else:
                        positive += 1
                assertions = case.get("assertions")
                if not isinstance(assertions, list) or not assertions:
                    blocking.append(f"EVAL_ASSERTIONS_REQUIRED:{cid}")
            if positive < 1:
                blocking.append("EVAL_POSITIVE_CASE_REQUIRED")
            if negative < 2:
                blocking.append("EVAL_NEGATIVE_CASES_REQUIRED")

    handoff = parse_json_text(files, "handoffs/to_quality_pack.handoff.json", blocking)
    if handoff is not None:
        target = handoff.get("to") or handoff.get("target_profile")
        if not isinstance(target, str) or not target.strip():
            blocking.append("HANDOFF_TARGET_MISSING")
        artifact_required = handoff.get("requires_artifact") is True or handoff.get("artifact_identity_required") is True
        if not artifact_required:
            blocking.append("HANDOFF_ARTIFACT_IDENTITY_NOT_REQUIRED")
        context = handoff.get("required_receiver_context") or handoff.get("required_evidence")
        if not isinstance(context, list) or not context:
            blocking.append("HANDOFF_REQUIRED_CONTEXT_MISSING")
        else:
            joined = " ".join(str(v).lower() for v in context)
            concept_groups = {
                "HANDOFF_CONTEXT_ARTIFACT_MISSING": ("artifact", "deliverable"),
                "HANDOFF_CONTEXT_EVIDENCE_MISSING": ("evidence", "source"),
                "HANDOFF_CONTEXT_SCHEMA_OR_CONTRACT_MISSING": ("schema", "contract"),
                "HANDOFF_CONTEXT_RUBRIC_OR_JUDGE_MISSING": ("rubric", "judge"),
                "HANDOFF_CONTEXT_BLOCKING_MISSING": ("block", "failure", "risk"),
            }
            for code, words in concept_groups.items():
                if not any(word in joined for word in words):
                    blocking.append(code)
        failure_routing = handoff.get("failure_routing")
        if not isinstance(failure_routing, dict) or not failure_routing:
            blocking.append("HANDOFF_FAILURE_ROUTING_REQUIRED")
        if not isinstance(handoff.get("next_gate"), str) or not handoff.get("next_gate"):
            blocking.append("HANDOFF_NEXT_GATE_MISSING")

    if not blocking:
        warnings.append("DETERMINISTIC_DEPTH_GATE_IS_NOT_SEMANTIC_QUALITY_APPROVAL")
        warnings.append("INDEPENDENT_SEMANTIC_REVIEW_REMAINS_REQUIRED")

    return blocking, warnings


def validate_file(path):
    try:
        pack = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        return {
            "status": "RETURN_TO_WORKER_FOR_SELF_REPAIR",
            "blocking_codes": [f"CANDIDATE_READ_ERROR:{exc}"],
            "warnings": [],
        }
    blocking, warnings = validate_candidate(pack)
    return {
        "status": "DEPTH_READY_FOR_SEMANTIC_REVIEW" if not blocking else "RETURN_TO_WORKER_FOR_SELF_REPAIR",
        "validation_scope": "DETERMINISTIC_DEPTH_ONLY",
        "semantic_quality_review": "NOT_EXECUTED",
        "blocking_codes": blocking,
        "warnings": warnings,
    }


def self_test(root):
    root = Path(root)
    negative = root / "fixtures/handoff_outcome/candidate_pack.json"
    positive = root / "fixtures/semantic_depth/positive_candidate_pack.json"
    failures = []
    neg_result = validate_file(negative)
    pos_result = validate_file(positive)
    if neg_result["status"] != "RETURN_TO_WORKER_FOR_SELF_REPAIR":
        failures.append("HISTORICAL_STUB_PACK_WAS_NOT_REJECTED")
    if pos_result["status"] != "DEPTH_READY_FOR_SEMANTIC_REVIEW":
        failures.append("POSITIVE_DEPTH_PACK_DID_NOT_PASS")

    try:
        creator_schema = json.loads((root / "schemas/output.schema.json").read_text(encoding="utf-8"))
        depth_spec = creator_schema.get("properties", {}).get("depth_gate")
        if not isinstance(depth_spec, dict):
            failures.append("PROFILE_CREATOR_OUTPUT_SCHEMA_DEPTH_GATE_MISSING")
        schema_text = json.dumps(creator_schema, sort_keys=True)
        if "DEPTH_READY_FOR_SEMANTIC_REVIEW" not in schema_text:
            failures.append("PROFILE_CREATOR_OUTPUT_SCHEMA_DEPTH_STATUS_MISSING")
        conditional_text = json.dumps(creator_schema.get("allOf", []), sort_keys=True)
        if "depth_gate" not in conditional_text:
            failures.append("PROFILE_PACK_CREATED_DOES_NOT_REQUIRE_DEPTH_GATE")
    except Exception as exc:
        failures.append(f"PROFILE_CREATOR_OUTPUT_SCHEMA_READ_ERROR:{exc}")

    try:
        good = json.loads((root / "examples/good_output.json").read_text(encoding="utf-8"))
        if good.get("status") != "PROFILE_PACK_CREATED":
            failures.append("GOOD_OUTPUT_STATUS_INVALID")
        depth_gate = good.get("depth_gate")
        if not isinstance(depth_gate, dict) or depth_gate.get("status") != "DEPTH_READY_FOR_SEMANTIC_REVIEW":
            failures.append("GOOD_OUTPUT_DEPTH_GATE_INVALID")
        if good.get("deliverable_artifact_ref") != "fixtures/semantic_depth/positive_candidate_pack.json":
            failures.append("GOOD_OUTPUT_NOT_BOUND_TO_POSITIVE_DEPTH_FIXTURE")
    except Exception as exc:
        failures.append(f"GOOD_OUTPUT_READ_ERROR:{exc}")

    try:
        skill_text = (root / "SKILL.md").read_text(encoding="utf-8")
        contract_text = (root / "contracts/main_contract.md").read_text(encoding="utf-8")
        for label, body in (("SKILL", skill_text), ("CONTRACT", contract_text)):
            if "validate_candidate_depth.py" not in body:
                failures.append(f"{label}_DEPTH_VALIDATOR_BINDING_MISSING")
            if "DEPTH_READY_FOR_SEMANTIC_REVIEW" not in body:
                failures.append(f"{label}_DEPTH_STATUS_MISSING")
            if "independent semantic" not in body.lower():
                failures.append(f"{label}_INDEPENDENT_SEMANTIC_BOUNDARY_MISSING")
    except Exception as exc:
        failures.append(f"CREATOR_CONTRACT_READ_ERROR:{exc}")

    try:
        creator_handoff = json.loads((root / "handoffs/to_quality_pack.handoff.json").read_text(encoding="utf-8"))
        context = creator_handoff.get("required_receiver_context", [])
        if "depth_gate" not in context:
            failures.append("CREATOR_HANDOFF_DEPTH_GATE_CONTEXT_MISSING")
        if creator_handoff.get("next_gate") != "SEMANTIC_QUALITY_REVIEW":
            failures.append("CREATOR_HANDOFF_NEXT_GATE_NOT_SEMANTIC_REVIEW")
    except Exception as exc:
        failures.append(f"CREATOR_HANDOFF_READ_ERROR:{exc}")

    try:
        creator_evals = json.loads((root / "evals/eval_matrix.json").read_text(encoding="utf-8"))
        ids = {case.get("id") for case in creator_evals.get("cases", []) if isinstance(case, dict)}
        if "semantic_stub_pack_rejected" not in ids:
            failures.append("SEMANTIC_STUB_REGRESSION_CASE_MISSING")
        if "semantic_depth_positive_pack" not in ids:
            failures.append("SEMANTIC_DEPTH_POSITIVE_CASE_MISSING")
    except Exception as exc:
        failures.append(f"CREATOR_EVAL_MATRIX_READ_ERROR:{exc}")

    result = {
        "status": "PASS" if not failures else "FAIL",
        "validation_scope": "DETERMINISTIC_DEPTH_SELF_TEST",
        "historical_stub_status": neg_result["status"],
        "historical_stub_blocking_codes": neg_result["blocking_codes"],
        "positive_status": pos_result["status"],
        "positive_blocking_codes": pos_result["blocking_codes"],
        "blocking_codes": failures,
        "semantic_quality_review": "NOT_EXECUTED",
    }
    return result


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        root = Path(sys.argv[2]) if len(sys.argv) >= 3 else Path.cwd()
        result = self_test(root)
        print(json.dumps(result, indent=2))
        return 0 if result["status"] == "PASS" else 1
    if len(sys.argv) < 2:
        print("usage: validate_candidate_depth.py <candidate.json> | --self-test <profile_creator_root>", file=sys.stderr)
        return 2
    result = validate_file(Path(sys.argv[1]))
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "DEPTH_READY_FOR_SEMANTIC_REVIEW" else 1


if __name__ == "__main__":
    raise SystemExit(main())
