#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "assurance_activation_contract_v1.json"
GATE_PATH = HERE / "assurance_activation_gate_v1.py"

spec = importlib.util.spec_from_file_location("assurance_activation_gate_v1", GATE_PATH)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def decision(**overrides):
    value = {
        "schema_version": "lf-assurance-router-decision/v1",
        "applicability_authority": "CHANGESET_GOVERNANCE_LF_V1",
        "assurance_applicable": True,
        "subject_type": "WORKFLOW",
        "subject_code": "validate-lf-packs",
        "subject_revision": "candidate-revision-001",
        "decision_ref": "router-decision:test:001",
    }
    value.update(overrides)
    return value


def binding(code: str, *, status: str = "CANDIDATO", subject_code: str = "validate-lf-packs"):
    return {
        "binding_code": code,
        "subject_type": "WORKFLOW",
        "subject_code": subject_code,
        "standard_claim_code": "WF_DIAGNOSTIC_COMPLETE_V1",
        "standard_claim_version": 1,
        "status": status,
    }


def main() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    assert contract["schema_version"] == "lf-assurance-activation-contract/v1"
    assert contract["authority"]["applicability_owner"] == "CHANGESET_GOVERNANCE_LF_V1"
    assert contract["authority"]["binding_authority"] == "public.lf_assurance_subject_bindings"
    assert contract["activation_rule"]["active_binding_required"] is True
    assert contract["activation_rule"]["exact_subject_code_required"] is True
    assert contract["activation_rule"]["wildcard_active_binding_forbidden"] is True
    assert contract["live_readback_2026_09_30"]["subject_bindings_active"] == 0

    # Current live shape: candidate binding never authorizes execution.
    out = mod.resolve_assurance_activation(
        router_decision=decision(),
        subject_bindings=[binding("B-CANDIDATE")],
    )
    assert out["status"] == "NOT_APPLICABLE_NO_EXECUTION", out
    assert out["execute_assurance"] is False
    assert out["reason_code"] == "NO_ACTIVE_EXACT_BINDING"

    # Router N/A always stays N/A even if an exact ACTIVE row is supplied.
    out = mod.resolve_assurance_activation(
        router_decision=decision(assurance_applicable=False),
        subject_bindings=[binding("B-ACTIVE", status="ACTIVE")],
    )
    assert out["status"] == "NOT_APPLICABLE_NO_EXECUTION", out
    assert out["reason_code"] == "ROUTER_NOT_APPLICABLE"

    # The only positive activation shape: Router applicable + one ACTIVE exact binding.
    out = mod.resolve_assurance_activation(
        router_decision=decision(),
        subject_bindings=[binding("B-ACTIVE", status="ACTIVE")],
    )
    assert out["status"] == "READY_FOR_ASSURANCE_EVALUATOR", out
    assert out["execute_assurance"] is True
    assert out["binding_code"] == "B-ACTIVE"
    assert out["claim_code"] == "WF_DIAGNOSTIC_COMPLETE_V1"

    # ACTIVE wildcard can never become a global Assurance switch.
    out = mod.resolve_assurance_activation(
        router_decision=decision(),
        subject_bindings=[binding("B-WILDCARD", status="ACTIVE", subject_code="*")],
    )
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_NON_EXACT_ACTIVE_BINDING"

    # More than one ACTIVE exact binding is ambiguous and fail-closed.
    out = mod.resolve_assurance_activation(
        router_decision=decision(),
        subject_bindings=[
            binding("B-ACTIVE-1", status="ACTIVE"),
            binding("B-ACTIVE-2", status="ACTIVE"),
        ],
    )
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_AMBIGUOUS_ACTIVE_BINDING"

    # Wrong applicability authority is rejected before binding resolution.
    out = mod.resolve_assurance_activation(
        router_decision=decision(applicability_authority="ASSURANCE_EVALUATOR"),
        subject_bindings=[binding("B-ACTIVE", status="ACTIVE")],
    )
    assert out["status"] == "BLOCKED", out
    assert out["reason_code"] == "BLOCKED_APPLICABILITY_AUTHORITY"

    # Subject must be exact and revision-bound.
    out = mod.resolve_assurance_activation(
        router_decision=decision(subject_code="*"),
        subject_bindings=[],
    )
    assert out["reason_code"] == "BLOCKED_NON_EXACT_ROUTER_SUBJECT", out
    out = mod.resolve_assurance_activation(
        router_decision=decision(subject_revision=""),
        subject_bindings=[],
    )
    assert out["reason_code"] == "BLOCKED_SUBJECT_REVISION", out

    # An ACTIVE binding for another exact subject does not leak applicability.
    out = mod.resolve_assurance_activation(
        router_decision=decision(),
        subject_bindings=[binding("B-OTHER", status="ACTIVE", subject_code="other-workflow")],
    )
    assert out["status"] == "NOT_APPLICABLE_NO_EXECUTION", out
    assert out["reason_code"] == "NO_ACTIVE_EXACT_BINDING"

    print("ASSURANCE_ACTIVATION_GATE_V1=PASS checks=9 active_bindings_live=0")


if __name__ == "__main__":
    main()
