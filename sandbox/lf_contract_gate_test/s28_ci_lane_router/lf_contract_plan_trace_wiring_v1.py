#!/usr/bin/env python3
"""Governed lifecycle SQL for LF_CONTRACT_PLAN_TRACE_V1.

This module owns only the wiring lifecycle around the trace request produced by
lf_contract_plan_trace_v1.py. It does not classify changes, choose controls,
execute controls, write EKB, or create a second execution authority.

Lifecycle:
  RESERVE (owned by LF_CONTRACT_PLAN_TRACE_V1 emitter SQL, once)
  ASSERT/REUSE (this module)
  CLOSE as COMPLETED or BLOCKED (this module)
"""
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
from typing import Any, Mapping

TRACE_SCHEMA = "lf-contract-plan-trace/v1"
OPERATION_CODE = "GITHUB_CONTRACT_GATE_LF"
TARGET_TYPE = "REPOSITORY_GOVERNED_PATHS"
TRACE_SCOPE = "LF_CONTRACT_PLAN_TRACE"
_HEX64 = set("0123456789abcdef")


class WiringError(ValueError):
    pass


def _require_text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise WiringError(code)
    return value.strip()


def _require_sha40(value: Any, code: str) -> str:
    raw = _require_text(value, code).lower()
    if len(raw) != 40 or any(ch not in _HEX64 for ch in raw):
        raise WiringError(code)
    return raw


def _require_hex64(value: Any, code: str) -> str:
    raw = _require_text(value, code).lower()
    if len(raw) != 64 or any(ch not in _HEX64 for ch in raw):
        raise WiringError(code)
    return raw


def _sql_text(value: str) -> str:
    encoded = base64.b64encode(value.encode("utf-8")).decode("ascii")
    return f"convert_from(decode('{encoded}','base64'),'UTF8')"


def validate_trace_request(
    request: Mapping[str, Any],
    *,
    exact_source: str | None = None,
    repository: str | None = None,
    run_id: str | None = None,
    run_attempt: int | None = None,
) -> dict[str, Any]:
    if not isinstance(request, Mapping):
        raise WiringError("FAIL_PLAN_TRACE_WIRING_REQUEST_NOT_OBJECT")
    if request.get("schema_version") != TRACE_SCHEMA:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_SCHEMA")
    if request.get("operation_code") != OPERATION_CODE:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_OPERATION")
    if request.get("target_type") != TARGET_TYPE:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_TARGET_TYPE")

    execution_id = _require_text(request.get("execution_id"), "FAIL_PLAN_TRACE_WIRING_EXECUTION_ID")
    idempotency_key = _require_text(request.get("idempotency_key"), "FAIL_PLAN_TRACE_WIRING_IDEMPOTENCY_KEY")
    target_code = _require_text(request.get("target_code"), "FAIL_PLAN_TRACE_WIRING_TARGET_CODE")
    target_repo = _require_text(request.get("target_repo"), "FAIL_PLAN_TRACE_WIRING_TARGET_REPO")
    target_path = _require_text(request.get("target_path"), "FAIL_PLAN_TRACE_WIRING_TARGET_PATH")
    request_sha = _require_hex64(request.get("request_sha256"), "FAIL_PLAN_TRACE_WIRING_REQUEST_SHA")

    manifest = request.get("manifest")
    if not isinstance(manifest, Mapping):
        raise WiringError("FAIL_PLAN_TRACE_WIRING_MANIFEST")
    if manifest.get("schema_version") != TRACE_SCHEMA or manifest.get("scope") != TRACE_SCOPE:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_MANIFEST_AUTHORITY")
    source = _require_sha40(manifest.get("source_commit"), "FAIL_PLAN_TRACE_WIRING_SOURCE")
    manifest_run_id = _require_text(manifest.get("github_run_id"), "FAIL_PLAN_TRACE_WIRING_RUN_ID")
    manifest_attempt = manifest.get("github_run_attempt")
    if not isinstance(manifest_attempt, int) or manifest_attempt < 1:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_RUN_ATTEMPT")
    evidence_sha = _require_hex64(manifest.get("evidence_sha256"), "FAIL_PLAN_TRACE_WIRING_EVIDENCE_SHA")
    if evidence_sha != request_sha:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_REQUEST_EVIDENCE_MISMATCH")

    expected_execution = f"EXEC-LF-CONTRACT-CHECK-{manifest_run_id}-{manifest_attempt}"
    expected_idempotency = f"LF-CONTRACT-CHECK:{manifest_run_id}:{manifest_attempt}:{source}"
    expected_target = f"LF_CONTRACT_CHECK_RUN_{manifest_run_id}_{manifest_attempt}"
    if execution_id != expected_execution:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_EXECUTION_DERIVATION")
    if idempotency_key != expected_idempotency:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_IDEMPOTENCY_DERIVATION")
    if target_code != expected_target:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_TARGET_DERIVATION")

    if exact_source is not None and source != _require_sha40(exact_source, "FAIL_PLAN_TRACE_WIRING_EXPECTED_SOURCE"):
        raise WiringError("FAIL_PLAN_TRACE_WIRING_EXACT_HEAD")
    if repository is not None and target_repo != _require_text(repository, "FAIL_PLAN_TRACE_WIRING_EXPECTED_REPO"):
        raise WiringError("FAIL_PLAN_TRACE_WIRING_REPOSITORY")
    if run_id is not None and manifest_run_id != _require_text(run_id, "FAIL_PLAN_TRACE_WIRING_EXPECTED_RUN_ID"):
        raise WiringError("FAIL_PLAN_TRACE_WIRING_RUN_ID_MISMATCH")
    if run_attempt is not None and manifest_attempt != run_attempt:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_RUN_ATTEMPT_MISMATCH")

    result = dict(request)
    result["manifest"] = dict(manifest)
    return result


def _identity_predicate(request: Mapping[str, Any], alias: str = "e") -> str:
    r = validate_trace_request(request)
    return " and ".join(
        [
            f"{alias}.execution_id={_sql_text(r['execution_id'])}",
            f"{alias}.operation_code={_sql_text(OPERATION_CODE)}",
            f"{alias}.target_type={_sql_text(TARGET_TYPE)}",
            f"{alias}.target_code={_sql_text(r['target_code'])}",
            f"{alias}.target_repo={_sql_text(r['target_repo'])}",
            f"{alias}.target_path={_sql_text(r['target_path'])}",
            f"{alias}.idempotency_key={_sql_text(r['idempotency_key'])}",
            f"{alias}.request_sha256='{r['request_sha256']}'",
            f"{alias}.manifest->>'schema_version'={_sql_text(TRACE_SCHEMA)}",
            f"{alias}.manifest->>'scope'={_sql_text(TRACE_SCOPE)}",
            f"{alias}.manifest->>'source_commit'={_sql_text(r['manifest']['source_commit'])}",
        ]
    )


def render_assert_sql(request: Mapping[str, Any], *, preamble: bool = True) -> str:
    r = validate_trace_request(request)
    prefix = "\\set ON_ERROR_STOP on\n" if preamble else ""
    predicate = _identity_predicate(r)
    return (
        prefix
        + "do $trace_assert$\n"
        "declare\n"
        "  v_total integer;\n"
        "  v_exact integer;\n"
        "  v_status text;\n"
        "begin\n"
        f"  select count(*) into v_total from public.lf_operation_execution where execution_id={_sql_text(r['execution_id'])};\n"
        f"  select count(*),max(status) into v_exact,v_status from public.lf_operation_execution e where {predicate};\n"
        "  if v_total<>1 then raise exception 'LF_CONTRACT_PLAN_TRACE_EXECUTION_NOT_EXACT total=%',v_total; end if;\n"
        "  if v_exact<>1 then raise exception 'LF_CONTRACT_PLAN_TRACE_IDENTITY_READBACK_MISMATCH'; end if;\n"
        "  if v_status<>'IN_PROGRESS' then raise exception 'LF_CONTRACT_PLAN_TRACE_NOT_IN_PROGRESS status=%',v_status; end if;\n"
        "end\n"
        "$trace_assert$;\n"
        "select jsonb_build_object("
        "'result','PASS_LF_CONTRACT_PLAN_TRACE_READBACK',"
        f"'execution_id',{_sql_text(r['execution_id'])},"
        f"'request_sha256','{r['request_sha256']}',"
        f"'status',(select status from public.lf_operation_execution where execution_id={_sql_text(r['execution_id'])})"
        ")::text;\n"
    )


def render_close_sql(request: Mapping[str, Any], *, job_status: str) -> str:
    r = validate_trace_request(request)
    status = _require_text(job_status, "FAIL_PLAN_TRACE_WIRING_JOB_STATUS").lower()
    if status not in {"success", "failure", "cancelled"}:
        raise WiringError("FAIL_PLAN_TRACE_WIRING_JOB_STATUS")
    desired = "COMPLETED" if status == "success" else "BLOCKED"
    predicate = _identity_predicate(r)
    execution = _sql_text(r["execution_id"])
    source = _sql_text(r["manifest"]["source_commit"])
    run_id = _sql_text(r["manifest"]["github_run_id"])
    run_attempt = int(r["manifest"]["github_run_attempt"])
    return f"""\\set ON_ERROR_STOP on
do $trace_close$
declare
  v_row public.lf_operation_execution%rowtype;
  v_exact integer;
begin
  select * into v_row
  from public.lf_operation_execution
  where execution_id={execution}
  for update;
  if v_row.execution_id is null then raise exception 'LF_CONTRACT_PLAN_TRACE_CLOSE_EXECUTION_NOT_FOUND'; end if;
  select count(*) into v_exact from public.lf_operation_execution e where {predicate};
  if v_exact<>1 then raise exception 'LF_CONTRACT_PLAN_TRACE_CLOSE_IDENTITY_MISMATCH'; end if;

  if v_row.status='COMPLETED' then
    if '{desired}'<>'COMPLETED' then
      raise exception 'LF_CONTRACT_PLAN_TRACE_COMPLETED_CANNOT_DOWNGRADE';
    end if;
    if v_row.checkpoint_payload->>'lot_code'<>'LF_CONTRACT_PLAN_TRACE_WIRING_V1'
       or v_row.checkpoint_payload->>'readback_result'<>'PASS' then
      raise exception 'LF_CONTRACT_PLAN_TRACE_COMPLETED_WITHOUT_WIRING_RECEIPT';
    end if;
    return;
  end if;

  if v_row.status='BLOCKED' then
    if '{desired}'='COMPLETED' then
      raise exception 'LF_CONTRACT_PLAN_TRACE_ALREADY_BLOCKED';
    end if;
    return;
  end if;

  if v_row.status<>'IN_PROGRESS' then
    raise exception 'LF_CONTRACT_PLAN_TRACE_CLOSE_INVALID_STATE status=%',v_row.status;
  end if;

  update public.lf_operation_execution
  set status='{desired}',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=coalesce(checkpoint_payload,'{{}}'::jsonb)||jsonb_build_object(
        'lot_code','LF_CONTRACT_PLAN_TRACE_WIRING_V1',
        'source_commit',{source},
        'github_run_id',{run_id},
        'github_run_attempt',{run_attempt},
        'job_status',{_sql_text(status)},
        'request_sha256','{r['request_sha256']}',
        'readback_result','PASS'
      ),
      updated_by_execution_id={execution},
      updated_at=clock_timestamp()
  where execution_id={execution} and status='IN_PROGRESS';
  if not found then raise exception 'LF_CONTRACT_PLAN_TRACE_CLOSE_RACE'; end if;
end
$trace_close$;
select jsonb_build_object(
  'result','PASS_LF_CONTRACT_PLAN_TRACE_CLOSE',
  'execution_id',{execution},
  'job_status',{_sql_text(status)},
  'status',(select status from public.lf_operation_execution where execution_id={execution}),
  'readback_result',(select checkpoint_payload->>'readback_result' from public.lf_operation_execution where execution_id={execution})
)::text;
"""


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser()
    p.add_argument("--request", required=True)
    p.add_argument("--mode", required=True, choices=("assert", "close"))
    p.add_argument("--job-status", choices=("success", "failure", "cancelled"))
    p.add_argument("--exact-source")
    p.add_argument("--repository")
    p.add_argument("--run-id")
    p.add_argument("--run-attempt", type=int)
    p.add_argument("--output-sql", required=True)
    return p


def main() -> int:
    args = parser().parse_args()
    request = json.loads(Path(args.request).read_text(encoding="utf-8"))
    validated = validate_trace_request(
        request,
        exact_source=args.exact_source,
        repository=args.repository,
        run_id=args.run_id,
        run_attempt=args.run_attempt,
    )
    if args.mode == "assert":
        sql = render_assert_sql(validated)
        marker = "PASS_LF_CONTRACT_PLAN_TRACE_ASSERT_PREPARED"
    else:
        if not args.job_status:
            raise SystemExit("FAIL_PLAN_TRACE_WIRING_JOB_STATUS_REQUIRED")
        sql = render_close_sql(validated, job_status=args.job_status)
        marker = f"PASS_LF_CONTRACT_PLAN_TRACE_CLOSE_PREPARED job_status={args.job_status}"
    Path(args.output_sql).write_text(sql, encoding="utf-8")
    print(f"{marker} execution_id={validated['execution_id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
