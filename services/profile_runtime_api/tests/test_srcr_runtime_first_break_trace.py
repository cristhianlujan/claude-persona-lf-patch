from __future__ import annotations

import json
import runpy
import warnings
from pathlib import Path

from profile_runtime_api.repository import RepositoryBindings
from profile_runtime_api.validation import OutputGates


ROOT = Path(__file__).resolve().parents[3]
PROFILE = "systemic_root_cause_repair_lf"
EVAL = ROOT / "profiles" / PROFILE / "evals" / "v05_producer_depth_cases.py"


def test_srcr_v05_runtime_first_break_trace() -> None:
    ns = runpy.run_path(str(EVAL), run_name="srcr_runtime_first_break_trace")
    candidate, evidence_manifest = ns["v05_pair"]("ARCHITECTURE_AUDIT")

    repository = RepositoryBindings(ROOT, max_prompt_chars=200_000)
    repository.validate()
    schema = repository.runtime_schema(PROFILE, "AUTO")
    gates = OutputGates(repository)

    raw = json.dumps(candidate, ensure_ascii=False, separators=(",", ":"))
    runtime_contract, parsed = gates.contract(
        profile_slug=PROFILE,
        raw_output=raw,
        schema=schema,
    )
    runtime_semantic = gates.semantic_utility(
        profile_slug=PROFILE,
        payload=parsed,
        contract_gate=runtime_contract,
    )

    validator_module = repository.load_validator(PROFILE)
    assert validator_module is not None
    validator_name = repository.validator_callable_name(PROFILE)
    assert validator_name
    direct_gate = getattr(validator_module, validator_name)(candidate, evidence_manifest)

    semantic_module, semantic_name = repository.load_semantic_utility(PROFILE)  # type: ignore[misc]
    direct_semantic = getattr(semantic_module, semantic_name)(
        candidate,
        direct_gate,
        evidence_manifest,
    )

    trace = {
        "T0_binding_loaded": repository.runtime_binding(PROFILE) is not None,
        "T1_schema_loaded": bool(schema.sha256),
        "T2_candidate_schema_plus_runtime_contract": runtime_contract.get("status"),
        "T2_blocking_codes": runtime_contract.get("blocking_codes"),
        "T3_runtime_semantic_utility": runtime_semantic.get("status"),
        "T3_independent_semantic_judge": runtime_semantic.get("independent_semantic_judge"),
        "CONTROL_direct_validator_with_manifest": direct_gate.get("status"),
        "CONTROL_direct_semantic_with_manifest": direct_semantic.get("status"),
        "FIRST_BREAK": "RUNTIME_DOES_NOT_TRANSPORT_EVIDENCE_MANIFEST",
    }
    warnings.warn("SRCR_RUNTIME_TRACE=" + json.dumps(trace, ensure_ascii=False, sort_keys=True))

    assert direct_gate.get("status") == "PASS", direct_gate
    assert direct_semantic.get("status") == "PASS", direct_semantic
    assert runtime_contract.get("status") == "FAIL", runtime_contract
    assert "SRCR_EVIDENCE_MANIFEST_REQUIRED" in set(runtime_contract.get("blocking_codes") or [])
    assert runtime_semantic.get("status") == "NOT_EVALUATED", runtime_semantic
    assert runtime_semantic.get("independent_semantic_judge") == "NOT_EXECUTED"


def test_srcr_v05_after_manifest_next_break_quality_boundary() -> None:
    repository = RepositoryBindings(ROOT, max_prompt_chars=200_000)
    binding = repository.runtime_binding(PROFILE)
    assert binding is not None

    binding_path = ROOT / "profiles" / PROFILE / "contracts" / "runtime_binding.json"
    raw_binding = json.loads(binding_path.read_text(encoding="utf-8"))
    declared_quality = raw_binding.get("canonical_quality")

    service_pkg = ROOT / "services" / "profile_runtime_api" / "profile_runtime_api"
    canonical_quality_consumers = []
    quality_receipt_consumers = []
    for path in service_pkg.rglob("*.py"):
        body = path.read_text(encoding="utf-8")
        if "canonical_quality" in body:
            canonical_quality_consumers.append(str(path.relative_to(ROOT)))
        if "validate_quality_receipt" in body:
            quality_receipt_consumers.append(str(path.relative_to(ROOT)))

    trace = {
        "CONTROL_after_W1_direct_validator": "PASS",
        "CONTROL_after_W1_direct_semantic": "PASS",
        "T4_canonical_quality_declared": isinstance(declared_quality, dict),
        "T4_v05_quality_required": "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5" in set((declared_quality or {}).get("required_for_profile_pack_ids") or []),
        "T4_runtime_binding_exposes_canonical_quality": hasattr(binding, "canonical_quality"),
        "T4_runtime_canonical_quality_consumers": canonical_quality_consumers,
        "T5_runtime_quality_receipt_validator_consumers": quality_receipt_consumers,
        "SECOND_BREAK": "CANONICAL_QUALITY_BOUNDARY_DECLARED_BUT_NOT_CONSUMED_BY_RUNTIME",
    }
    warnings.warn("SRCR_RUNTIME_TRACE_2=" + json.dumps(trace, ensure_ascii=False, sort_keys=True))

    assert isinstance(declared_quality, dict)
    assert "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5" in set(declared_quality.get("required_for_profile_pack_ids") or [])
    assert not hasattr(binding, "canonical_quality")
    assert canonical_quality_consumers == []
    assert quality_receipt_consumers == []
