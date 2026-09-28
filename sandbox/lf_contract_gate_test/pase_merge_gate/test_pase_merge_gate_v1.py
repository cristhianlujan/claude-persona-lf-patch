#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "pase_merge_gate_v1.py"

HEAD = "dafdf2a8ceea2f298fd4edb72dbc6af183c20fd9"
ROUTE_REV = "a" * 64
VALIDATOR_REV = "b" * 64
PLAN_DIGEST = "d" * 64


def load():
    spec = importlib.util.spec_from_file_location("pase_merge_gate_v1_test_target", TARGET)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_PASE_MERGE_GATE_LOAD")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def plan(required):
    return {
        "schema_version": "lf-ci-execution-plan/v2",
        "coverage_complete": True,
        "required_controls": sorted(required),
        "plan_sha256": PLAN_DIGEST,
    }


def enforcement(required, blocking):
    required = sorted(required)
    blocking = sorted(blocking)
    observe = sorted(set(required) - set(blocking))
    value = {
        "schema_version": "lf-pase-control-enforcement/v1",
        "authority": "CHANGESET_GOVERNANCE_LF_V1",
        "policy_id": "PASE_CONTROL_REPAIR_QUARANTINE_V1",
        "source_plan_sha256": PLAN_DIGEST,
        "required_controls": required,
        "blocking_controls": blocking,
        "observe_only_controls": observe,
        "repair_window_active": True,
        "manual_diagnostic_execution_allowed": True,
        "observe_only_results_cannot_block_merge": True,
        "no_applicability_reclassification": True,
        "structural_governance_fail_closed": True,
        "silent_reactivation_forbidden": True,
    }
    value["result_sha256"] = digest(value)
    return value


def route(mode, required, candidate_id=None, **overrides):
    value = {
        "schema_version": "lf-pase-merge-route/v1",
        "authority": "CHANGESET_GOVERNANCE_LF_V1",
        "mode": mode,
        "head_sha": HEAD,
        "source_revision": ROUTE_REV,
        "required_control_ids": sorted(required),
        "candidate_id": candidate_id,
    }
    value.update(overrides)
    return value


def control_result(cid, verdict="PASS", **overrides):
    value = {
        "control_id": cid,
        "head_sha": HEAD,
        "verdict": verdict,
        "authority": f"{cid}_OWNER",
        "evidence_sha256": "c" * 64,
    }
    value.update(overrides)
    return value


def diagnostic_result(cid, verdict="FAIL", **overrides):
    value = {"control_id": cid, "head_sha": HEAD, "verdict": verdict}
    value.update(overrides)
    return value


def qualification_result(verdict="CANDIDATE_QUALIFIED", **overrides):
    value = {
        "schema_version": "lf-pase-control-qualification-result/v1",
        "candidate_id": "PASE_ORCHESTRATOR_V1",
        "base_sha": "8bb18f9521702b958193d92640a08d04a53b1b85",
        "head_sha": HEAD,
        "declared_owner": "LF_GOVERNANCE",
        "checks": [{"id": f"Q{i:02d}", "status": "PASS", "evidence": [f"e{i}@{HEAD}"]} for i in range(1, 12)],
        "external_findings": [],
        "coverage_complete": True,
        "verdict": verdict,
        "qualified_only": True,
        "activation_authorized": False,
        "cutover_authorized": False,
        "rebind_authorized": False,
        "legacy_retirement_authorized": False,
    }
    value.update(overrides)
    return value


def qualification_envelope(result=None, **overrides):
    result = qualification_result() if result is None else result
    value = {
        "schema_version": "lf-pase-qualified-evidence/v1",
        "authority": "PASE_CONTROL_QUALIFICATION_V1",
        "independent": True,
        "validated": True,
        "validator_revision": VALIDATOR_REV,
        "result_sha256": digest(result),
        "result": result,
    }
    value.update(overrides)
    return value


def packet(mode="CONTROL_SYSTEM_QUALIFICATION"):
    if mode == "CONTROL_SYSTEM_QUALIFICATION":
        applicable = ["E16_GOVERNANCE", "PROFILE_RUNTIME_V3"]
        return {
            "schema_version": "lf-pase-merge-gate-input/v1",
            "head_sha": HEAD,
            "route": route(mode, [], "PASE_ORCHESTRATOR_V1"),
            "plan": plan(applicable),
            "enforcement": enforcement(applicable, []),
            "qualification": qualification_envelope(),
            "control_results": [],
            "diagnostic_results": [diagnostic_result("E16_GOVERNANCE", "FAIL"), diagnostic_result("PROFILE_RUNTIME_V3", "FAIL")],
        }
    applicable = ["CONTROL_A", "CONTROL_B"]
    blocking = ["CONTROL_A"]
    return {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": HEAD,
        "route": route(mode, blocking),
        "plan": plan(applicable),
        "enforcement": enforcement(applicable, blocking),
        "qualification": None,
        "control_results": [control_result("CONTROL_A")],
        "diagnostic_results": [diagnostic_result("CONTROL_B", "FAIL")],
    }


def expect_error(module, value, code):
    try:
        module.evaluate_merge_gate(value)
    except module.PaseMergeGateError as exc:
        assert str(exc).startswith(code), (code, str(exc))
        return
    raise AssertionError(code)


def rehash_enforcement(p):
    e = p["enforcement"]
    e.pop("result_sha256", None)
    e["result_sha256"] = digest(e)


def main():
    m = load()
    checks = 0

    # Qualification route: contaminated legacy diagnostics may FAIL and cannot block.
    got = m.evaluate_merge_gate(packet())
    assert got["verdict"] == "PASS"
    assert got["required_control_ids"] == []
    assert got["observe_only_control_ids"] == ["E16_GOVERNANCE", "PROFILE_RUNTIME_V3"]
    assert got["qualification_candidate_id"] == "PASE_ORCHESTRATOR_V1"
    checks += 1

    # Normal route: only ACTIVE_BLOCKING controls are required; observe-only FAIL is diagnostic.
    got = m.evaluate_merge_gate(packet("EXECUTION_PLAN"))
    assert got["verdict"] == "PASS"
    assert got["applicable_control_ids"] == ["CONTROL_A", "CONTROL_B"]
    assert got["required_control_ids"] == ["CONTROL_A"]
    assert got["observe_only_control_ids"] == ["CONTROL_B"]
    checks += 1

    p = packet(); p["enforcement"] = None
    expect_error(m, p, "FAIL_PASE_MERGE_ENFORCEMENT_SCHEMA"); checks += 1

    p = packet(); p["enforcement"]["authority"] = "OTHER"; rehash_enforcement(p)
    expect_error(m, p, "FAIL_PASE_MERGE_ENFORCEMENT_AUTHORITY"); checks += 1

    p = packet(); p["enforcement"]["source_plan_sha256"] = "e" * 64; rehash_enforcement(p)
    expect_error(m, p, "FAIL_PASE_MERGE_ENFORCEMENT_PLAN_DRIFT"); checks += 1

    p = packet(); p["enforcement"]["required_controls"] = ["E16_GOVERNANCE"]; rehash_enforcement(p)
    expect_error(m, p, "FAIL_PASE_MERGE_ENFORCEMENT_REQUIRED_DRIFT"); checks += 1

    p = packet("EXECUTION_PLAN"); p["enforcement"]["blocking_controls"] = ["CONTROL_A", "CONTROL_B"]; p["enforcement"]["observe_only_controls"] = ["CONTROL_B"]; rehash_enforcement(p)
    expect_error(m, p, "FAIL_PASE_MERGE_ENFORCEMENT_PARTITION"); checks += 1

    p = packet(); p["enforcement"]["observe_only_results_cannot_block_merge"] = False; rehash_enforcement(p)
    expect_error(m, p, "FAIL_PASE_MERGE_ENFORCEMENT_FLAG"); checks += 1

    p = packet(); p["enforcement"]["result_sha256"] = "0" * 64
    expect_error(m, p, "FAIL_PASE_MERGE_ENFORCEMENT_DIGEST"); checks += 1

    p = packet("EXECUTION_PLAN"); p["route"]["required_control_ids"] = ["CONTROL_A", "CONTROL_B"]
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_ENFORCEMENT_DRIFT"); checks += 1

    p = packet("EXECUTION_PLAN"); p["control_results"][0]["verdict"] = "FAIL"
    expect_error(m, p, "BLOCK_PASE_MERGE_CONTROL_NOT_PASS"); checks += 1

    p = packet("EXECUTION_PLAN"); p["control_results"] = []
    expect_error(m, p, "FAIL_PASE_MERGE_CONTROL_RESULT_COVERAGE"); checks += 1

    p = packet("EXECUTION_PLAN"); p["control_results"].append(control_result("CONTROL_B"))
    expect_error(m, p, "FAIL_PASE_MERGE_CONTROL_RESULT_COVERAGE"); checks += 1

    p = packet("EXECUTION_PLAN"); p["diagnostic_results"][0]["head_sha"] = "1" * 40
    expect_error(m, p, "FAIL_PASE_MERGE_DIAGNOSTIC_RESULT_HEAD"); checks += 1

    p = packet("EXECUTION_PLAN"); p["diagnostic_results"].append(diagnostic_result("CONTROL_A", "FAIL"))
    expect_error(m, p, "FAIL_PASE_MERGE_DIAGNOSTIC_RESULT_CONTROL"); checks += 1

    p = packet(); p["qualification"] = None
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_MISSING"); checks += 1

    p = packet(); r = qualification_result(verdict="FAIL"); p["qualification"] = qualification_envelope(r)
    expect_error(m, p, "BLOCK_PASE_MERGE_QUALIFICATION_NOT_QUALIFIED"); checks += 1

    p = packet(); r = qualification_result(head_sha="1" * 40); p["qualification"] = qualification_envelope(r)
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_HEAD_DRIFT"); checks += 1

    p = packet(); p["qualification"]["independent"] = False
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_NOT_INDEPENDENT_VALIDATED"); checks += 1

    p = packet(); p["qualification"]["result_sha256"] = "f" * 64
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_RESULT_DIGEST_MISMATCH"); checks += 1

    p = packet("EXECUTION_PLAN"); p["qualification"] = qualification_envelope()
    expect_error(m, p, "FAIL_PASE_MERGE_UNEXPECTED_QUALIFICATION"); checks += 1

    p = packet(); p["plan"]["coverage_complete"] = False
    expect_error(m, p, "FAIL_PASE_MERGE_PLAN_COVERAGE"); checks += 1

    p = packet(); p["plan"]["plan_sha256"] = "bad"
    expect_error(m, p, "FAIL_PASE_MERGE_PLAN_DIGEST"); checks += 1

    p = packet(); p["route"]["authority"] = "OTHER"
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_AUTHORITY"); checks += 1

    p = packet(); p["route"]["head_sha"] = "1" * 40
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_HEAD_DRIFT"); checks += 1

    source = TARGET.read_text(encoding="utf-8")
    for forbidden in (
        "import subprocess",
        "import requests",
        "urllib",
        "changed_paths",
        "classify(",
        "validate_contract(",
        "execute_sql",
        "apply_migration",
        "merge_pull_request",
    ):
        assert forbidden not in source, forbidden
    checks += 1

    print(f"PASS_PASE_MERGE_GATE_REPAIR_ENFORCEMENT_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
