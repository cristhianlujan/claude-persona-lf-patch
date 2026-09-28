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
    }


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


def qualification_result(verdict="CANDIDATE_QUALIFIED", **overrides):
    value = {
        "schema_version": "lf-pase-control-qualification-result/v1",
        "candidate_id": "PASE_ORCHESTRATOR_V1",
        "base_sha": "8bb18f9521702b958193d92640a08d04a53b1b85",
        "head_sha": HEAD,
        "declared_owner": "LF_GOVERNANCE",
        "checks": [
            {"id": f"Q{i:02d}", "status": "PASS", "evidence": [f"e{i}@{HEAD}"]}
            for i in range(1, 12)
        ],
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
        # #1170 regression fixture: the upstream route explicitly selects
        # qualification, so legacy plan controls are not silently treated as
        # the candidate's own verdict. PASE_MERGE_GATE does not make that
        # selection; it only enforces the supplied Changeset Governance route.
        return {
            "schema_version": "lf-pase-merge-gate-input/v1",
            "head_sha": HEAD,
            "route": route(mode, [], "PASE_ORCHESTRATOR_V1"),
            "plan": plan(["E16_GOVERNANCE", "PROFILE_RUNTIME_V3"]),
            "qualification": qualification_envelope(),
            "control_results": [],
        }
    required = ["CONTROL_A", "CONTROL_B"]
    return {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": HEAD,
        "route": route(mode, required),
        "plan": plan(required),
        "qualification": None,
        "control_results": [control_result(cid) for cid in required],
    }


def expect_error(module, value, code):
    try:
        module.evaluate_merge_gate(value)
    except module.PaseMergeGateError as exc:
        assert str(exc).startswith(code), (code, str(exc))
        return
    raise AssertionError(code)


def main():
    m = load()
    checks = 0

    got = m.evaluate_merge_gate(packet())
    assert got["verdict"] == "PASS"
    assert got["mode"] == "CONTROL_SYSTEM_QUALIFICATION"
    assert got["qualification_candidate_id"] == "PASE_ORCHESTRATOR_V1"
    assert got["required_control_ids"] == []
    checks += 1

    got = m.evaluate_merge_gate(packet("EXECUTION_PLAN"))
    assert got["verdict"] == "PASS"
    assert got["required_control_ids"] == ["CONTROL_A", "CONTROL_B"]
    checks += 1

    p = packet(); p["route"] = None
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_SCHEMA"); checks += 1

    p = packet(); p["route"]["authority"] = "OTHER"
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_AUTHORITY"); checks += 1

    p = packet(); p["route"]["head_sha"] = "1" * 40
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_HEAD_DRIFT"); checks += 1

    p = packet(); p["qualification"] = None
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_MISSING"); checks += 1

    p = packet(); r = qualification_result(verdict="FAIL"); p["qualification"] = qualification_envelope(r)
    expect_error(m, p, "BLOCK_PASE_MERGE_QUALIFICATION_NOT_QUALIFIED"); checks += 1

    p = packet(); r = qualification_result(head_sha="1" * 40); p["qualification"] = qualification_envelope(r)
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_HEAD_DRIFT"); checks += 1

    p = packet(); p["qualification"]["independent"] = False
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_NOT_INDEPENDENT_VALIDATED"); checks += 1

    p = packet(); p["qualification"]["result"]["candidate_id"] = "OTHER"; p["qualification"]["result_sha256"] = digest(p["qualification"]["result"])
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_CANDIDATE_DRIFT"); checks += 1

    p = packet("EXECUTION_PLAN"); p["route"]["required_control_ids"] = ["CONTROL_A"]
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_PLAN_DRIFT"); checks += 1

    p = packet("EXECUTION_PLAN"); p["control_results"] = [control_result("CONTROL_A")]
    expect_error(m, p, "FAIL_PASE_MERGE_CONTROL_RESULT_COVERAGE"); checks += 1

    p = packet("EXECUTION_PLAN"); p["control_results"][0]["verdict"] = "FAIL"
    expect_error(m, p, "BLOCK_PASE_MERGE_CONTROL_NOT_PASS"); checks += 1

    p = packet("EXECUTION_PLAN"); p["control_results"].append(control_result("CONTROL_C"))
    expect_error(m, p, "FAIL_PASE_MERGE_CONTROL_RESULT_COVERAGE"); checks += 1

    p = packet("EXECUTION_PLAN"); p["control_results"].append(copy.deepcopy(p["control_results"][0]))
    expect_error(m, p, "FAIL_PASE_MERGE_CONTROL_RESULT_DUPLICATE"); checks += 1

    p = packet(); p["route"]["required_control_ids"] = ["UNKNOWN"]
    expect_error(m, p, "FAIL_PASE_MERGE_ROUTE_CONTROL_OUTSIDE_PLAN"); checks += 1

    p = packet(); p["plan"]["coverage_complete"] = False
    expect_error(m, p, "FAIL_PASE_MERGE_PLAN_COVERAGE"); checks += 1

    p = packet(); p["qualification"]["result_sha256"] = "d" * 64
    expect_error(m, p, "FAIL_PASE_MERGE_QUALIFICATION_RESULT_DIGEST_MISMATCH"); checks += 1

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

    print(f"PASS_PASE_MERGE_GATE_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
