#!/usr/bin/env python3
import json
import sys
from pathlib import Path

PASS = "ADAPTER_FACTORY_COMPOSITION_PASS"
FAIL = "ADAPTER_FACTORY_COMPOSITION_FAIL"


def read(path, failures, code):
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

    for marker, code in [
        ("ACT-0040", "PARENT_AUTHORITY_ACT0040_MISSING"),
        ("ACT-0045", "FACTORY_CORE_ACT0045_MISSING"),
        ("CREACION_ADAPTER_LF", "ADAPTER_SPECIALIZATION_OPERATION_MISSING"),
        ("Router", "ROUTER_AUTHORITY_MISSING"),
    ]:
        require(combined, marker, code, failures)

    require(adapter_contract, "composition_mode: IN_PROCESS_COMPOSITION_NOT_FORK", "COMPOSITION_NOT_FORK_MISSING", failures)
    require(adapter_contract, "separate_factory_llm_call: FORBIDDEN", "SEPARATE_FACTORY_LLM_NOT_FORBIDDEN", failures)
    require(adapter_contract, "parallel_adapter_factory", "PARALLEL_FACTORY_HARD_FAIL_MISSING", failures)
    require(adapter_contract, "adapter_as_alternate_worker", "ADAPTER_AS_WORKER_HARD_FAIL_MISSING", failures)
    require(binding, "Direct Profile → `INPUT_GOVERNANCE_AGENT` invocation is forbidden.", "DIRECT_PROFILE_GOVERNANCE_NOT_FORBIDDEN", failures)
    require(binding, "Profile declares governance need", "PROFILE_DECLARES_NEED_MISSING", failures)
    require(specialization, "separate_factory: FORBIDDEN", "SEPARATE_FACTORY_NOT_FORBIDDEN", failures)
    require(specialization, "separate_factory_llm_call: FORBIDDEN", "SECOND_FACTORY_LLM_NOT_FORBIDDEN", failures)
    require(specialization, "DIRECT_PROFILE_INPUT_GOVERNANCE_INVOCATION", "DIRECT_PROFILE_GOVERNANCE_HARD_FAIL_MISSING", failures)
    require(specialization, "runtime_change: false", "RUNTIME_CHANGE_FALSE_MISSING", failures)
    require(specialization, "production_change: false", "PRODUCTION_CHANGE_FALSE_MISSING", failures)

    for marker, code in [
        ("invoke_from=profile", "LEGACY_DIRECT_PROFILE_GOVERNANCE_BINDING_PRESENT"),
        ("invoke_from: profile", "LEGACY_DIRECT_PROFILE_GOVERNANCE_BINDING_PRESENT"),
        ("separate_factory: ALLOWED", "PARALLEL_FACTORY_ALLOWED"),
        ("separate_factory_llm_call: ALLOWED", "SECOND_FACTORY_LLM_ALLOWED"),
    ]:
        forbid(combined, marker, code, failures)

    result = {
        "status": PASS if not failures else FAIL,
        "validation_scope": "DETERMINISTIC_FACTORY_COMPOSITION_AND_ANTI_REGRESSION",
        "factory_core": "ACT-0045",
        "parent_authority": "ACT-0040",
        "adapter_specialization": "CREACION_ADAPTER_LF",
        "direct_profile_input_governance": "FORBIDDEN",
        "separate_adapter_factory": "FORBIDDEN",
        "separate_adapter_llm_call": "FORBIDDEN",
        "runtime_authorized": False,
        "production_authorized": False,
        "failures": failures,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
