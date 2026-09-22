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
