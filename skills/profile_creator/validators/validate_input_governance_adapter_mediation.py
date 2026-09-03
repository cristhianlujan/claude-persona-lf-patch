#!/usr/bin/env python3
import json
import sys
from pathlib import Path

PASS = "INPUT_GOVERNANCE_ADAPTER_MEDIATION_PASS"
FAIL = "INPUT_GOVERNANCE_ADAPTER_MEDIATION_FAIL"


def read(path: Path, failures, code):
    try:
        return path.read_text(encoding="utf-8")
    except Exception as exc:
        failures.append(f"{code}:{exc}")
        return ""


def require(text, marker, code, failures):
    if marker not in text:
        failures.append(code)


def forbid(text, marker, code, failures):
    if marker in text:
        failures.append(code)


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    repo = root.parent.parent
    failures = []

    skill = read(root / "SKILL.md", failures, "SKILL_READ_FAILED")
    contract = read(root / "contracts/main_contract.md", failures, "PROFILE_CONTRACT_READ_FAILED")
    binding = read(root / "adapters/adapter_factory_binding.md", failures, "ADAPTER_FACTORY_BINDING_READ_FAILED")
    adapter_contract = read(repo / "gobernanza/contratos/contrato_adapter_lf.yaml", failures, "ADAPTER_CONTRACT_READ_FAILED")
    specialization = read(repo / "gobernanza/procedimientos/creacion_adapter_lf_specialization.yaml", failures, "ADAPTER_SPECIALIZATION_READ_FAILED")

    combined = "\n".join([skill, contract, binding, adapter_contract, specialization])

    required = [
        (binding, "Profile declares governance need", "PROFILE_DECLARES_GOVERNANCE_NEED_MISSING"),
        (binding, "Direct Profile → `INPUT_GOVERNANCE_AGENT` invocation is forbidden.", "DIRECT_PROFILE_GOVERNANCE_GUARDRAIL_MISSING"),
        (specialization, "INPUT_READINESS_CONTRACT_resolved_live", "LIVE_INPUT_READINESS_CONTRACT_REQUIRED"),
        (specialization, "governance_receipt_complete", "GOVERNANCE_RECEIPT_REQUIRED"),
        (specialization, "continuation_only_on_PASS", "PASS_ONLY_CONTINUATION_REQUIRED"),
        (specialization, "DIRECT_PROFILE_INPUT_GOVERNANCE_INVOCATION", "DIRECT_PROFILE_HARD_FAIL_MISSING"),
        (specialization, "INPUT_GOVERNANCE_REQUIRED_BUT_NOT_GOVERNED", "MISSING_GOVERNANCE_HARD_FAIL_MISSING"),
        (adapter_contract, "input_governance_binding_when_applicable", "ADAPTER_GOVERNANCE_BINDING_MISSING"),
        (adapter_contract, "no_second_llm_call", "NO_SECOND_LLM_CALL_MISSING"),
        (combined, "Router", "ROUTER_ENTRYPOINT_MISSING"),
    ]
    for text, marker, code in required:
        require(text, marker, code, failures)

    forbidden = [
        ("invoke_from: profile", "LEGACY_DIRECT_PROFILE_BINDING_PRESENT"),
        ("invoke_from=profile", "LEGACY_DIRECT_PROFILE_BINDING_PRESENT"),
        ("missing_receipt: WARN", "FAIL_OPEN_MISSING_RECEIPT_PRESENT"),
        ("continuation_on_REPAIR", "REPAIR_CONTINUATION_PRESENT"),
        ("continuation_on_BLOCK", "BLOCK_CONTINUATION_PRESENT"),
        ("second_llm_call: required", "SECOND_LLM_CALL_REQUIRED"),
    ]
    for marker, code in forbidden:
        forbid(combined, marker, code, failures)

    result = {
        "status": PASS if not failures else FAIL,
        "validation_scope": "DETERMINISTIC_INPUT_GOVERNANCE_ADAPTER_MEDIATION",
        "entrypoint": "ROUTER",
        "profile_direct_invocation": "FORBIDDEN",
        "adapter_mediation": "REQUIRED_WHEN_APPLICABLE",
        "receipt_required": True,
        "continuation_policy": "PASS_ONLY",
        "second_llm_call": "FORBIDDEN_BY_ADAPTER_CONTRACT",
        "runtime_authorized": False,
        "production_authorized": False,
        "failures": failures,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
