#!/usr/bin/env python3
"""Build the durable trace envelope for one lf-contract-check applicability plan.

This module is deliberately transport-only:
- it validates the existing lf-ci-execution-plan/v2 artifact;
- it derives the exact GITHUB_CONTRACT_GATE_LF execution identity;
- it builds the manifest/request consumed by the existing
  public.fn_lf_operation_reserve_execution_v1 authority;
- it can render SQL, but never connects to Supabase or executes writes itself.

It does not classify changes, choose controls, resolve dependencies, execute
controls, finalize executions, or write EKB.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
from typing import Any, Mapping

TRACE_SCHEMA = "lf-contract-plan-trace/v1"
PLAN_SCHEMA = "lf-ci-execution-plan/v2"
OPERATION_CODE = "GITHUB_CONTRACT_GATE_LF"
TARGET_TYPE = "REPOSITORY_GOVERNED_PATHS"
DEFAULT_WORKFLOW_PATH = ".github/workflows/lf-contract-check.yml"
_HEX64 = set("0123456789abcdef")


class TraceError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _require_text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise TraceError(code)
    return value.strip()


def _require_hex64(value: Any, code: str) -> str:
    raw = _require_text(value, code).lower()
    if len(raw) != 64 or any(ch not in _HEX64 for ch in raw):
        raise TraceError(code)
    return raw


def _require_sha40(value: Any, code: str) -> str:
    raw = _require_text(value, code).lower()
    if len(raw) != 40 or any(ch not in _HEX64 for ch in raw):
        raise TraceError(code)
    return raw


def validate_plan(plan: Mapping[str, Any], *, exact_source: str) -> dict[str, Any]:
    if not isinstance(plan, Mapping):
        raise TraceError("FAIL_PLAN_TRACE_PLAN_NOT_OBJECT")
    if plan.get("schema_version") != PLAN_SCHEMA:
        raise TraceError("FAIL_PLAN_TRACE_PLAN_SCHEMA")

    exact = _require_sha40(exact_source, "FAIL_PLAN_TRACE_EXACT_SOURCE")
    head_sha = _require_sha40(plan.get("head_sha"), "FAIL_PLAN_TRACE_HEAD_SHA")
    if head_sha != exact:
        raise TraceError("FAIL_PLAN_TRACE_EXACT_HEAD_MISMATCH")

    changed = plan.get("changed_paths")
    required = plan.get("required_controls")
    reasons = plan.get("required_control_reasons")
    not_applicable = plan.get("not_applicable_controls")
    carriers = plan.get("carrier_controls")
    source_authority = plan.get("source_authority")

    if not isinstance(changed, list) or any(not isinstance(x, str) or not x for x in changed):
        raise TraceError("FAIL_PLAN_TRACE_CHANGED_PATHS")
    if changed != sorted(set(changed)):
        raise TraceError("FAIL_PLAN_TRACE_CHANGED_PATHS_NOT_CANONICAL")
    if not isinstance(required, list) or any(not isinstance(x, str) or not x for x in required):
        raise TraceError("FAIL_PLAN_TRACE_REQUIRED_CONTROLS")
    if required != sorted(set(required)):
        raise TraceError("FAIL_PLAN_TRACE_REQUIRED_CONTROLS_NOT_CANONICAL")
    if not isinstance(reasons, dict) or set(reasons) != set(required):
        raise TraceError("FAIL_PLAN_TRACE_REQUIRED_REASONS")
    for control_id, values in reasons.items():
        if not isinstance(values, list) or not values or any(not isinstance(x, str) or not x for x in values):
            raise TraceError(f"FAIL_PLAN_TRACE_REQUIRED_REASON_VALUES:{control_id}")
    if not isinstance(not_applicable, list):
        raise TraceError("FAIL_PLAN_TRACE_NOT_APPLICABLE")
    if not isinstance(carriers, dict):
        raise TraceError("FAIL_PLAN_TRACE_CARRIER_CONTROLS")
    carrier_union: set[str] = set()
    for carrier, values in carriers.items():
        if not isinstance(carrier, str) or not carrier or not isinstance(values, list):
            raise TraceError("FAIL_PLAN_TRACE_CARRIER_SHAPE")
        if values != sorted(set(values)):
            raise TraceError(f"FAIL_PLAN_TRACE_CARRIER_VALUES:{carrier}")
        carrier_union.update(values)
    if carrier_union != set(required):
        raise TraceError("FAIL_PLAN_TRACE_CARRIER_COVERAGE")

    if not isinstance(plan.get("full_regression"), bool):
        raise TraceError("FAIL_PLAN_TRACE_FULL_REGRESSION")
    _require_text(plan.get("lane_mode"), "FAIL_PLAN_TRACE_LANE_MODE")
    _require_hex64(plan.get("plan_sha256"), "FAIL_PLAN_TRACE_PLAN_SHA")
    _require_hex64(plan.get("applicability_sha256"), "FAIL_PLAN_TRACE_APPLICABILITY_SHA")
    evidence_sha = _require_hex64(plan.get("evidence_sha256"), "FAIL_PLAN_TRACE_EVIDENCE_SHA")
    authority_revision = _require_sha40(
        plan.get("authority_evidence_revision"), "FAIL_PLAN_TRACE_AUTHORITY_REVISION"
    )
    if not isinstance(source_authority, dict):
        raise TraceError("FAIL_PLAN_TRACE_SOURCE_AUTHORITY")
    _require_text(source_authority.get("decision"), "FAIL_PLAN_TRACE_CURRENTNESS_DECISION")
    resolved_revision = _require_sha40(
        source_authority.get("resolved_revision"), "FAIL_PLAN_TRACE_CURRENTNESS_REVISION"
    )
    if resolved_revision != authority_revision:
        raise TraceError("FAIL_PLAN_TRACE_CURRENTNESS_REVISION_MISMATCH")

    evidence_source = dict(plan)
    evidence_source.pop("evidence_sha256", None)
    calculated_evidence = _sha256(_canonical(evidence_source).encode("utf-8"))
    if calculated_evidence != evidence_sha:
        raise TraceError("FAIL_PLAN_TRACE_EVIDENCE_DIGEST_MISMATCH")

    return dict(plan)


def build_trace_request(
    plan: Mapping[str, Any],
    *,
    exact_source: str,
    repository: str,
    run_id: str,
    run_attempt: int,
    workflow_event: str,
    workflow_path: str = DEFAULT_WORKFLOW_PATH,
) -> dict[str, Any]:
    validated = validate_plan(plan, exact_source=exact_source)
    repository = _require_text(repository, "FAIL_PLAN_TRACE_REPOSITORY")
    run_id = _require_text(run_id, "FAIL_PLAN_TRACE_RUN_ID")
    workflow_event = _require_text(workflow_event, "FAIL_PLAN_TRACE_WORKFLOW_EVENT")
    workflow_path = _require_text(workflow_path, "FAIL_PLAN_TRACE_WORKFLOW_PATH")
    if not isinstance(run_attempt, int) or run_attempt < 1:
        raise TraceError("FAIL_PLAN_TRACE_RUN_ATTEMPT")

    source = exact_source.lower()
    execution_id = f"EXEC-LF-CONTRACT-CHECK-{run_id}-{run_attempt}"
    idempotency_key = f"LF-CONTRACT-CHECK:{run_id}:{run_attempt}:{source}"
    target_code = f"LF_CONTRACT_CHECK_RUN_{run_id}_{run_attempt}"

    trace = {
        "schema_version": TRACE_SCHEMA,
        "scope": "LF_CONTRACT_PLAN_TRACE",
        "source_commit": source,
        "github_run_id": run_id,
        "github_run_attempt": run_attempt,
        "workflow_event": workflow_event,
        "changed_files": validated["changed_paths"],
        "changed_paths": validated["changed_paths"],
        "lane_mode": validated["lane_mode"],
        "required_controls": validated["required_controls"],
        "required_control_reasons": validated["required_control_reasons"],
        "not_applicable_controls": validated["not_applicable_controls"],
        "carrier_controls": validated["carrier_controls"],
        "full_regression": validated["full_regression"],
        "full_regression_reason": validated.get("full_regression_reason"),
        "plan_sha256": validated["plan_sha256"],
        "applicability_sha256": validated["applicability_sha256"],
        "evidence_sha256": validated["evidence_sha256"],
        "authority_evidence_revision": validated["authority_evidence_revision"],
        "currentness_decision": validated["source_authority"]["decision"],
        "currentness_revision": validated["source_authority"]["resolved_revision"],
        "semantic_stage": "REQUIRED_CONTROLS_PRE_SOLUTION_REFACTOR",
    }

    return {
        "schema_version": TRACE_SCHEMA,
        "execution_id": execution_id,
        "operation_code": OPERATION_CODE,
        "target_type": TARGET_TYPE,
        "target_code": target_code,
        "target_repo": repository,
        "target_path": workflow_path,
        "idempotency_key": idempotency_key,
        "request_sha256": validated["evidence_sha256"],
        "manifest": trace,
    }


def _sql_text(value: str) -> str:
    encoded = base64.b64encode(value.encode("utf-8")).decode("ascii")
    return f"convert_from(decode('{encoded}','base64'),'UTF8')"


def _sql_json(value: Any) -> str:
    return f"{_sql_text(_canonical(value))}::jsonb"


def render_reserve_sql(request: Mapping[str, Any]) -> str:
    required = {
        "execution_id",
        "operation_code",
        "target_type",
        "target_code",
        "target_repo",
        "target_path",
        "idempotency_key",
        "request_sha256",
        "manifest",
    }
    if not isinstance(request, Mapping) or not required.issubset(request):
        raise TraceError("FAIL_PLAN_TRACE_REQUEST_SHAPE")
    if request["operation_code"] != OPERATION_CODE or request["target_type"] != TARGET_TYPE:
        raise TraceError("FAIL_PLAN_TRACE_REQUEST_AUTHORITY")
    request_sha = _require_hex64(request["request_sha256"], "FAIL_PLAN_TRACE_REQUEST_SHA")
    execution_id = _require_text(request["execution_id"], "FAIL_PLAN_TRACE_EXECUTION_ID")

    return (
        "\\set ON_ERROR_STOP on\n"
        "select public.fn_lf_operation_reserve_execution_v1("
        f"{_sql_text(execution_id)},"
        f"{_sql_text(OPERATION_CODE)},"
        f"{_sql_text(TARGET_TYPE)},"
        f"{_sql_text(str(request['target_code']))},"
        f"{_sql_text(str(request['idempotency_key']))},"
        f"'{request_sha}',"
        f"{_sql_text(execution_id)},"
        f"{_sql_text(str(request['target_repo']))},"
        f"{_sql_text(str(request['target_path']))},"
        f"{_sql_json(request['manifest'])}"
        ")::text;\n"
    )


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser()
    p.add_argument("--plan", required=True)
    p.add_argument("--exact-source", required=True)
    p.add_argument("--repository", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--run-attempt", required=True, type=int)
    p.add_argument("--workflow-event", required=True)
    p.add_argument("--workflow-path", default=DEFAULT_WORKFLOW_PATH)
    p.add_argument("--output-json", required=True)
    p.add_argument("--output-sql", required=True)
    return p


def main() -> int:
    args = parser().parse_args()
    plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    request = build_trace_request(
        plan,
        exact_source=args.exact_source,
        repository=args.repository,
        run_id=args.run_id,
        run_attempt=args.run_attempt,
        workflow_event=args.workflow_event,
        workflow_path=args.workflow_path,
    )
    Path(args.output_json).write_text(_canonical(request) + "\n", encoding="utf-8")
    Path(args.output_sql).write_text(render_reserve_sql(request), encoding="utf-8")
    print(
        "PASS_LF_CONTRACT_PLAN_TRACE "
        f"execution_id={request['execution_id']} "
        f"controls={len(request['manifest']['required_controls'])} "
        f"changed={len(request['manifest']['changed_paths'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
