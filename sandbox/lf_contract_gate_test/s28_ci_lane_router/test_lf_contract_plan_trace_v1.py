#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

MODULE = Path(__file__).with_name("lf_contract_plan_trace_v1.py")
spec = importlib.util.spec_from_file_location("lf_contract_plan_trace_v1", MODULE)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_PLAN_TRACE_TEST_LOAD")
T = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = T
spec.loader.exec_module(T)

HEAD = "a" * 40
AUTH = "b" * 40


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def plan():
    value = {
        "schema_version": "lf-ci-execution-plan/v2",
        "router_capability": "CI_FAST_DEEP_LANE_ROUTER",
        "lane_mode": "SPECIALIZED_REQUIRED",
        "full_regression": False,
        "full_regression_reason": None,
        "carrier_regression": False,
        "carrier_regression_reason": None,
        "carrier_regression_carriers": [],
        "changed_paths": ["profiles/example/SKILL.md"],
        "material_evidence": [],
        "required_controls": ["LF_CONTRACT_CORE", "PROFILE_PACK"],
        "required_control_reasons": {
            "LF_CONTRACT_CORE": ["PATH:profiles/example/SKILL.md"],
            "PROFILE_PACK": ["PATH:profiles/example/SKILL.md"],
        },
        "not_applicable_controls": [],
        "carrier_controls": {
            "LF_CONTRACT_CHECK": ["LF_CONTRACT_CORE"],
            "VALIDATE_LF_PACKS": ["PROFILE_PACK"],
        },
        "control_universe": ["LF_CONTRACT_CORE", "PROFILE_PACK"],
        "full_regression_control_set": ["LF_CONTRACT_CORE", "PROFILE_PACK"],
        "coverage_complete": True,
        "plan_sha256": "1" * 64,
        "applicability_sha256": "1" * 64,
        "source_authority": {
            "decision": "READY",
            "resolved_revision": AUTH,
        },
        "authority_evidence_revision": AUTH,
        "base_sha": "c" * 40,
        "head_sha": HEAD,
        "event_name": "pull_request",
        "event_action": "synchronize",
    }
    source = dict(value)
    value["evidence_sha256"] = hashlib.sha256(canonical(source).encode("utf-8")).hexdigest()
    return value


def expect_error(code: str, fn) -> None:
    try:
        fn()
    except T.TraceError as exc:
        if str(exc) != code:
            raise AssertionError(f"expected {code}, got {exc}") from exc
    else:
        raise AssertionError(f"expected {code}")


def main() -> int:
    base = plan()
    request = T.build_trace_request(
        base,
        exact_source=HEAD,
        repository="cristhianlujan/claude-persona-lf-patch",
        run_id="123456",
        run_attempt=2,
        workflow_event="pull_request",
    )
    assert request["execution_id"] == "EXEC-LF-CONTRACT-CHECK-123456-2"
    assert request["request_sha256"] == base["evidence_sha256"]
    assert request["manifest"]["changed_files"] == ["profiles/example/SKILL.md"]
    assert request["manifest"]["required_controls"] == ["LF_CONTRACT_CORE", "PROFILE_PACK"]
    assert request["manifest"]["required_control_reasons"]["PROFILE_PACK"] == [
        "PATH:profiles/example/SKILL.md"
    ]
    assert request["manifest"]["semantic_stage"] == "REQUIRED_CONTROLS_PRE_SOLUTION_REFACTOR"

    replay = T.build_trace_request(
        copy.deepcopy(base),
        exact_source=HEAD,
        repository="cristhianlujan/claude-persona-lf-patch",
        run_id="123456",
        run_attempt=2,
        workflow_event="pull_request",
    )
    assert replay == request

    sql = T.render_reserve_sql(request)
    assert "fn_lf_operation_reserve_execution_v1" in sql
    assert "GITHUB_CONTRACT_GATE_LF" not in sql  # values are base64 encoded
    assert request["execution_id"] not in sql

    bad_head = copy.deepcopy(base)
    bad_head["head_sha"] = "d" * 40
    source = dict(bad_head)
    source.pop("evidence_sha256", None)
    bad_head["evidence_sha256"] = hashlib.sha256(canonical(source).encode("utf-8")).hexdigest()
    expect_error(
        "FAIL_PLAN_TRACE_EXACT_HEAD_MISMATCH",
        lambda: T.build_trace_request(
            bad_head,
            exact_source=HEAD,
            repository="repo/x",
            run_id="1",
            run_attempt=1,
            workflow_event="pull_request",
        ),
    )

    bad_reasons = copy.deepcopy(base)
    bad_reasons["required_control_reasons"].pop("PROFILE_PACK")
    source = dict(bad_reasons)
    source.pop("evidence_sha256", None)
    bad_reasons["evidence_sha256"] = hashlib.sha256(canonical(source).encode("utf-8")).hexdigest()
    expect_error(
        "FAIL_PLAN_TRACE_REQUIRED_REASONS",
        lambda: T.validate_plan(bad_reasons, exact_source=HEAD),
    )

    bad_digest = copy.deepcopy(base)
    bad_digest["evidence_sha256"] = "f" * 64
    expect_error(
        "FAIL_PLAN_TRACE_EVIDENCE_DIGEST_MISMATCH",
        lambda: T.validate_plan(bad_digest, exact_source=HEAD),
    )

    bad_carrier = copy.deepcopy(base)
    bad_carrier["carrier_controls"] = {"LF_CONTRACT_CHECK": ["LF_CONTRACT_CORE"]}
    source = dict(bad_carrier)
    source.pop("evidence_sha256", None)
    bad_carrier["evidence_sha256"] = hashlib.sha256(canonical(source).encode("utf-8")).hexdigest()
    expect_error(
        "FAIL_PLAN_TRACE_CARRIER_COVERAGE",
        lambda: T.validate_plan(bad_carrier, exact_source=HEAD),
    )

    print("PASS_LF_CONTRACT_PLAN_TRACE_TESTS=7/7")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
