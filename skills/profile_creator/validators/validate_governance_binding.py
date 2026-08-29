#!/usr/bin/env python3
import copy
import json
import sys
from pathlib import Path

READY = "INPUT_GOVERNANCE_BINDING_READY"
REPAIR = "RETURN_TO_WORKER_FOR_SELF_REPAIR"
BINDING_PATH = "contracts/input_governance_binding.json"

TRIGGERS = {
    "input_not_governed_by_adapter",
    "cross_adapter_conflict",
    "profile_specific_constraint",
    "authority_or_policy_uncertainty",
    "critical_input_validation",
}


def canonical_binding():
    return {
        "governance_binding": {
            "capability": "INPUT_GOVERNANCE_AGENT",
            "mode": "selective",
            "invoke_from": "profile",
            "entrypoint": "router_only",
            "trigger": sorted(TRIGGERS),
            "request_contract": {
                "input_ref": "required",
                "intent": "required",
                "profile_id": "required",
                "checks": "profile_relevant_only",
                "constraints": "profile_scope_only",
            },
            "response_contract": {
                "verdict": "PASS|REPAIR|BLOCK",
                "governed_input_ref": "required_on_pass_or_repair",
                "findings": "compact",
                "evidence_refs": "compact",
                "receipt_id": "required",
            },
            "token_policy": {
                "reuse_adapter_receipts": True,
                "duplicate_checks": False,
                "default": "L1_LOCAL",
                "max_normal": "L2_COMPACT",
                "expanded_context": "L3_EXCEPTION_ONLY",
                "full_policy_injection": False,
            },
            "execution_policy": {
                "second_llm_call": "exception_only",
                "prefer_same_execution_context": True,
                "cache_key": "input_hash+governance_version+profile_id",
            },
            "fail_policy": {
                "critical_uncertainty": "BLOCK",
                "missing_receipt": "BLOCK",
                "narrative_override": False,
            },
        }
    }


def parse_binding(files, blocking):
    raw = files.get(BINDING_PATH)
    if not isinstance(raw, str) or not raw.strip():
        blocking.append("INPUT_GOVERNANCE_BINDING_REQUIRED")
        return None
    try:
        value = json.loads(raw)
    except Exception as exc:
        blocking.append(f"INPUT_GOVERNANCE_BINDING_INVALID_JSON:{exc}")
        return None
    if not isinstance(value, dict) or not isinstance(value.get("governance_binding"), dict):
        blocking.append("INPUT_GOVERNANCE_BINDING_OBJECT_REQUIRED")
        return None
    return value


def require_equal(actual, expected, code, blocking):
    if actual != expected:
        blocking.append(code)


def validate_candidate(pack):
    blocking = []
    warnings = []
    if not isinstance(pack, dict):
        return ["CANDIDATE_NOT_OBJECT"], warnings
    files = pack.get("files")
    if not isinstance(files, dict):
        return ["CANDIDATE_FILES_MISSING"], warnings

    parsed = parse_binding(files, blocking)
    if parsed is None:
        return blocking, warnings
    binding = parsed["governance_binding"]

    require_equal(binding.get("capability"), "INPUT_GOVERNANCE_AGENT", "INPUT_GOVERNANCE_CAPABILITY_INVALID", blocking)
    require_equal(binding.get("mode"), "selective", "INPUT_GOVERNANCE_MODE_MUST_BE_SELECTIVE", blocking)
    require_equal(binding.get("invoke_from"), "profile", "INPUT_GOVERNANCE_INVOKE_FROM_PROFILE_REQUIRED", blocking)
    require_equal(binding.get("entrypoint"), "router_only", "INPUT_GOVERNANCE_ROUTER_ONLY_REQUIRED", blocking)

    triggers = binding.get("trigger")
    if not isinstance(triggers, list) or set(triggers) != TRIGGERS or len(triggers) != len(TRIGGERS):
        blocking.append("INPUT_GOVERNANCE_TRIGGER_SET_INVALID")

    request = binding.get("request_contract")
    expected_request = canonical_binding()["governance_binding"]["request_contract"]
    require_equal(request, expected_request, "INPUT_GOVERNANCE_REQUEST_CONTRACT_INVALID", blocking)

    response = binding.get("response_contract")
    expected_response = canonical_binding()["governance_binding"]["response_contract"]
    require_equal(response, expected_response, "INPUT_GOVERNANCE_RESPONSE_CONTRACT_INVALID", blocking)

    token_policy = binding.get("token_policy")
    expected_token = canonical_binding()["governance_binding"]["token_policy"]
    require_equal(token_policy, expected_token, "INPUT_GOVERNANCE_TOKEN_POLICY_INVALID", blocking)

    execution = binding.get("execution_policy")
    expected_execution = canonical_binding()["governance_binding"]["execution_policy"]
    require_equal(execution, expected_execution, "INPUT_GOVERNANCE_EXECUTION_POLICY_INVALID", blocking)

    fail_policy = binding.get("fail_policy")
    expected_fail = canonical_binding()["governance_binding"]["fail_policy"]
    require_equal(fail_policy, expected_fail, "INPUT_GOVERNANCE_FAIL_POLICY_INVALID", blocking)

    manifest_raw = files.get("manifest.json")
    try:
        manifest = json.loads(manifest_raw) if isinstance(manifest_raw, str) else None
    except Exception:
        manifest = None
    required_files = manifest.get("required_files") if isinstance(manifest, dict) else None
    if not isinstance(required_files, list) or BINDING_PATH not in required_files:
        blocking.append("MANIFEST_INPUT_GOVERNANCE_BINDING_NOT_DECLARED")

    skill = str(files.get("SKILL.md", "")).lower()
    contract = str(files.get("contracts/main_contract.md", "")).lower()
    combined = skill + "\n" + contract
    required_markers = {
        "input_governance_agent": "PROFILE_INPUT_GOVERNANCE_CAPABILITY_NOT_DECLARED",
        "adapter receipt": "PROFILE_ADAPTER_RECEIPT_REUSE_NOT_DECLARED",
        "router": "PROFILE_GOVERNANCE_ROUTER_BOUNDARY_NOT_DECLARED",
        "pass": "PROFILE_GOVERNANCE_PASS_NOT_DECLARED",
        "repair": "PROFILE_GOVERNANCE_REPAIR_NOT_DECLARED",
        "block": "PROFILE_GOVERNANCE_BLOCK_NOT_DECLARED",
    }
    for marker, code in required_markers.items():
        if marker not in combined:
            blocking.append(code)

    forbidden = (
        "invoke input_governance_agent on every execution",
        "always invoke input_governance_agent",
        "full policy injection",
        "bypass router",
    )
    for marker in forbidden:
        if marker in combined:
            blocking.append(f"PROFILE_INPUT_GOVERNANCE_ANTIPATTERN:{marker.replace(' ', '_').upper()}")

    if not blocking:
        warnings.extend([
            "ADAPTER_RECEIPTS_HAVE_PRECEDENCE_FOR_COVERED_CHECKS",
            "L3_CONTEXT_EXPANSION_REQUIRES_EXCEPTION_RECEIPT",
            "BLOCK_IS_FAIL_CLOSED_AND_CANNOT_BE_DOWNGRADED_TO_WARNING",
        ])
    return blocking, warnings


def inject_binding(pack):
    out = copy.deepcopy(pack)
    files = out.setdefault("files", {})
    files[BINDING_PATH] = json.dumps(canonical_binding(), indent=2)

    manifest_raw = files.get("manifest.json")
    if isinstance(manifest_raw, str):
        try:
            manifest = json.loads(manifest_raw)
        except Exception:
            manifest = {}
    else:
        manifest = {}
    required = manifest.setdefault("required_files", [])
    if BINDING_PATH not in required:
        required.append(BINDING_PATH)
    files["manifest.json"] = json.dumps(manifest, indent=2)

    declaration = (
        "\n\n## Input governance binding\n"
        "INPUT_GOVERNANCE_AGENT is a selective capability reached only from the Router-started Profile flow. "
        "Reuse a valid Adapter receipt for covered checks; do not repeat those checks. "
        "Use PASS / REPAIR / BLOCK and require a receipt for governed decisions. BLOCK is fail-closed.\n"
    )
    files["SKILL.md"] = str(files.get("SKILL.md", "")) + declaration
    files["contracts/main_contract.md"] = str(files.get("contracts/main_contract.md", "")) + declaration
    return out


def validate_file(path):
    try:
        pack = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        return {"status": REPAIR, "blocking_codes": [f"CANDIDATE_READ_ERROR:{exc}"], "warnings": []}
    blocking, warnings = validate_candidate(pack)
    return {
        "status": READY if not blocking else REPAIR,
        "validation_scope": "DETERMINISTIC_INPUT_GOVERNANCE_BINDING",
        "blocking_codes": blocking,
        "warnings": warnings,
    }


def self_test():
    base = {
        "files": {
            "SKILL.md": "# Worker\n",
            "contracts/main_contract.md": "# Contract\n",
            "manifest.json": json.dumps({"required_files": []}),
        }
    }
    positive = inject_binding(base)
    cases = []

    def run(name, pack, expected_ready, expected_code=None):
        blocking, _ = validate_candidate(pack)
        ready = not blocking
        aligned = ready == expected_ready and (expected_code is None or expected_code in blocking)
        cases.append({"case": name, "aligned": aligned, "blocking_codes": blocking})

    run("canonical_binding_passes", positive, True)

    missing = copy.deepcopy(positive)
    missing["files"].pop(BINDING_PATH, None)
    run("missing_binding_rejected", missing, False, "INPUT_GOVERNANCE_BINDING_REQUIRED")

    always = copy.deepcopy(positive)
    payload = json.loads(always["files"][BINDING_PATH])
    payload["governance_binding"]["mode"] = "always"
    always["files"][BINDING_PATH] = json.dumps(payload)
    run("always_mode_rejected", always, False, "INPUT_GOVERNANCE_MODE_MUST_BE_SELECTIVE")

    duplicate = copy.deepcopy(positive)
    payload = json.loads(duplicate["files"][BINDING_PATH])
    payload["governance_binding"]["token_policy"]["duplicate_checks"] = True
    duplicate["files"][BINDING_PATH] = json.dumps(payload)
    run("duplicate_checks_rejected", duplicate, False, "INPUT_GOVERNANCE_TOKEN_POLICY_INVALID")

    no_receipt = copy.deepcopy(positive)
    payload = json.loads(no_receipt["files"][BINDING_PATH])
    payload["governance_binding"]["fail_policy"]["missing_receipt"] = "WARN"
    no_receipt["files"][BINDING_PATH] = json.dumps(payload)
    run("missing_receipt_fail_open_rejected", no_receipt, False, "INPUT_GOVERNANCE_FAIL_POLICY_INVALID")

    failed = [case["case"] for case in cases if not case["aligned"]]
    return {
        "status": "PASS" if not failed else "FAIL",
        "validation_scope": "DETERMINISTIC_INPUT_GOVERNANCE_BINDING_SELF_TEST",
        "cases": cases,
        "aligned": len(cases) - len(failed),
        "total": len(cases),
        "failed_cases": failed,
    }


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        result = self_test()
        print(json.dumps(result, indent=2))
        return 0 if result["status"] == "PASS" else 1
    if len(sys.argv) < 2:
        print("usage: validate_governance_binding.py <candidate.json> | --self-test", file=sys.stderr)
        return 2
    result = validate_file(Path(sys.argv[1]))
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == READY else 1


if __name__ == "__main__":
    raise SystemExit(main())
