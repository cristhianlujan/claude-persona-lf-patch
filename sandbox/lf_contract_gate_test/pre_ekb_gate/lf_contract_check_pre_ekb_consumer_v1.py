#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any, NoReturn

OPERATION_CODE = "GITHUB_CONTRACT_GATE_LF"
CANONICAL_STEP_ID = "contract_judge"
WORKFLOW_PATH = ".github/workflows/lf-contract-check.yml"
DEFAULT_ROOT = Path(".lf_gate_diagnostics/lf_contract_check")
DEFAULT_SQL_PATH = Path("/tmp/lf_contract_pre_ekb.sql")
DEFAULT_META_PATH = Path("/tmp/lf_contract_pre_ekb_meta.json")


class ConsumerError(RuntimeError):
    pass


def fail(code: str) -> NoReturn:
    raise ConsumerError(code)


def _sql_text(value: str) -> str:
    encoded = base64.b64encode(value.encode("utf-8")).decode("ascii")
    return f"convert_from(decode('{encoded}','base64'),'UTF8')"


def _sql_json(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return f"{_sql_text(raw)}::jsonb"


def _validate_sha(value: str) -> None:
    if len(value) != 40 or any(ch not in "0123456789abcdef" for ch in value.lower()):
        fail("FAIL_LF_CONTRACT_PRE_EKB_SOURCE_SHA_INVALID")


def load_report(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_REPORT_READ:{path}:{type(exc).__name__}")
    if not isinstance(value, dict):
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_REPORT_NOT_OBJECT:{path}")
    if value.get("contract") != "LF_GATE_ERROR_V1":
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_REPORT_CONTRACT:{path}")
    return value


def durable_ref(*, root: Path, path: Path, repository: str, run_id: str, run_attempt: int, check_id: str) -> str:
    rel = path.relative_to(root).as_posix()
    artifact_name = f"lf-gate-diagnostics-lf-contract-check-{run_id}-{run_attempt}"
    return f"github-actions://{repository}/runs/{run_id}/artifacts/{artifact_name}/{rel}#check={check_id}"


def transformed_check(
    *,
    root: Path,
    report: dict[str, Any],
    path: Path,
    raw: dict[str, Any],
    repository: str,
    run_id: str,
    run_attempt: int,
) -> dict[str, Any]:
    status = str(raw.get("check_status") or raw.get("status") or "").upper()
    check_id = str(raw.get("check_id") or "").strip()
    if status not in {"PASS", "FAIL", "BLOCKED", "SKIPPED"} or not check_id:
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_CHECK_ID_OR_STATUS:{path}")
    condition = str(raw.get("condition") or "").strip()
    producer = str(raw.get("producer") or raw.get("source_path") or report.get("producer") or "").strip()
    owner = str(raw.get("owner") or report.get("owner") or "LF_CONTRACT_CHECK").strip()
    next_action = str(raw.get("next_action") or report.get("next_action") or "FIX_FAILED_LF_CONTRACT_CHECK_AND_RERUN").strip()
    error_class = raw.get("error_class")
    if not condition or not producer or not owner or not next_action:
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_CHECK_METADATA:{path}:{check_id}")
    if status in {"FAIL", "BLOCKED"} and not str(error_class or "").strip():
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_ERROR_CLASS:{path}:{check_id}")
    rc = raw.get("rc", raw.get("exit_code"))
    if not isinstance(rc, int):
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_RC:{path}:{check_id}")
    return {
        "check_id": check_id,
        "status": status,
        "critical": bool(raw.get("critical", False)),
        "error_class": error_class,
        "condition": condition,
        "expected": raw.get("expected"),
        "actual": raw.get("actual"),
        "input_ref": raw.get("input_ref"),
        "evidence_ref": durable_ref(
            root=root,
            path=path,
            repository=repository,
            run_id=run_id,
            run_attempt=run_attempt,
            check_id=check_id,
        ),
        "producer": producer,
        "rc": rc,
        "downstream_impact": raw.get("downstream_impact", report.get("downstream_impact", [])),
        "owner": owner,
        "next_action": next_action,
    }


def collect_batches(
    *,
    root: Path,
    exact_source: str,
    repository: str,
    run_id: str,
    run_attempt: int,
) -> list[dict[str, Any]]:
    _validate_sha(exact_source)
    batches: list[dict[str, Any]] = []
    seen_gate_ids: set[str] = set()

    for path in sorted(root.rglob("lf_gate_error_v1.json")):
        report = load_report(path)
        gate_result = str(report.get("gate_result") or "").upper()
        if gate_result == "PASS":
            continue
        if gate_result not in {"FAIL", "BLOCKED"}:
            fail(f"FAIL_LF_CONTRACT_PRE_EKB_GATE_RESULT:{path}:{gate_result}")

        for key in ("source_commit", "tested_commit"):
            value = str(report.get(key) or "").strip()
            if value and value != exact_source:
                fail(
                    f"FAIL_LF_CONTRACT_PRE_EKB_EXACT_HEAD:{path}:{key}:"
                    f"expected={exact_source}:actual={value}"
                )

        gate_id = str(report.get("gate_id") or "").strip()
        if not gate_id:
            fail(f"FAIL_LF_CONTRACT_PRE_EKB_GATE_ID:{path}")
        if gate_id in seen_gate_ids:
            fail(f"FAIL_LF_CONTRACT_PRE_EKB_DUPLICATE_GATE_ID:{gate_id}")
        seen_gate_ids.add(gate_id)

        raw_checks = report.get("checks")
        if raw_checks is None:
            raw_checks = []
        if not isinstance(raw_checks, list):
            fail(f"FAIL_LF_CONTRACT_PRE_EKB_CHECKS_NOT_ARRAY:{path}")

        if raw_checks:
            checks = [
                transformed_check(
                    root=root,
                    report=report,
                    path=path,
                    raw=item,
                    repository=repository,
                    run_id=run_id,
                    run_attempt=run_attempt,
                )
                for item in raw_checks
                if isinstance(item, dict)
            ]
            expected_ids = report.get("expected_check_ids")
            if not isinstance(expected_ids, list) or not expected_ids:
                fail(f"FAIL_LF_CONTRACT_PRE_EKB_EXPECTED_IDS:{path}")
        else:
            synthetic_id = "GATE-BLOCKED" if gate_result == "BLOCKED" else "GATE-FAILED"
            synthetic = {
                "check_id": synthetic_id,
                "status": gate_result,
                "critical": True,
                "error_class": str(report.get("error_class") or f"GATE_{gate_result}"),
                "condition": str(report.get("condition") or "gate execution reaches PASS"),
                "expected": report.get("expected", {"gate_result": "PASS"}),
                "actual": report.get("actual", {"gate_result": gate_result}),
                "input_ref": WORKFLOW_PATH,
                "evidence_ref": durable_ref(
                    root=root,
                    path=path,
                    repository=repository,
                    run_id=run_id,
                    run_attempt=run_attempt,
                    check_id=synthetic_id,
                ),
                "producer": str(report.get("producer") or "GATE_CHECK_OBSERVABILITY"),
                "rc": int(report.get("rc", 2 if gate_result == "BLOCKED" else 1)),
                "downstream_impact": report.get("downstream_impact", ["CI_GOVERNANCE"]),
                "owner": str(report.get("owner") or "LF_CONTRACT_CHECK"),
                "next_action": str(report.get("next_action") or "FIX_FAILED_LF_CONTRACT_CHECK_AND_RERUN"),
            }
            checks = [synthetic]
            expected_ids = [synthetic_id]

        if not checks:
            fail(f"FAIL_LF_CONTRACT_PRE_EKB_EMPTY_TRANSFORMED_CHECKS:{path}")
        nonpass = sum(1 for item in checks if item["status"] in {"FAIL", "BLOCKED"})
        if nonpass == 0:
            fail(f"FAIL_LF_CONTRACT_PRE_EKB_NONPASS_REPORT_WITHOUT_NONPASS_CHECK:{path}")

        batches.append(
            {
                "gate_id": gate_id,
                "gate_mode": str(report.get("gate_mode") or "COLLECT_ALL"),
                "expected_check_ids": expected_ids,
                "checks": checks,
                "report_ref": durable_ref(
                    root=root,
                    path=path,
                    repository=repository,
                    run_id=run_id,
                    run_attempt=run_attempt,
                    check_id="REPORT",
                ),
            }
        )
    return batches


def build_payloads(
    *,
    root: Path,
    exact_source: str,
    repository: str,
    run_id: str,
    run_attempt: int,
    job_id: str,
    workflow_event: str,
) -> tuple[dict[str, Any], str]:
    batches = collect_batches(
        root=root,
        exact_source=exact_source,
        repository=repository,
        run_id=run_id,
        run_attempt=run_attempt,
    )
    artifact_name = f"lf-gate-diagnostics-lf-contract-check-{run_id}-{run_attempt}"
    total_checks = sum(len(batch["checks"]) for batch in batches)
    nonpass_checks = sum(
        1
        for batch in batches
        for item in batch["checks"]
        if item["status"] in {"FAIL", "BLOCKED"}
    )
    metadata = {
        "schema_version": "lf-contract-check-pre-ekb-ingress/v1",
        "operation_code": OPERATION_CODE,
        "canonical_step_id": CANONICAL_STEP_ID,
        "source_commit": exact_source,
        "run_id": run_id,
        "run_attempt": run_attempt,
        "workflow_event": workflow_event,
        "artifact_name": artifact_name,
        "batch_count": len(batches),
        "total_check_count": total_checks,
        "nonpass_check_count": nonpass_checks,
    }
    if not batches:
        return metadata, ""

    execution_id = f"EXEC-LF-CONTRACT-CHECK-{run_id}-{run_attempt}"
    idempotency_key = f"LF-CONTRACT-CHECK:{run_id}:{run_attempt}:{exact_source}"
    target_code = f"LF_CONTRACT_CHECK_RUN_{run_id}_{run_attempt}"
    request_payload = {
        "operation_code": OPERATION_CODE,
        "execution_id": execution_id,
        "source_commit": exact_source,
        "workflow_event": workflow_event,
        "batches": batches,
    }
    request_sha = hashlib.sha256(
        json.dumps(request_payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()

    manifest = {
        "scope": "LF_CONTRACT_CHECK_PRE_EKB_GATE_HANDOFF",
        "source_commit": exact_source,
        "github_run_id": run_id,
        "github_run_attempt": run_attempt,
        "workflow_event": workflow_event,
        "diagnostic_artifact": artifact_name,
        "canonical_step_id": CANONICAL_STEP_ID,
        "productive_ingress": "public.lf_record_gate_checks_v1",
        "ekb_governance": "PRE_EKB_GATE",
        "direct_ekb_write_allowed": False,
    }

    statements = ["\\set ON_ERROR_STOP on"]
    statements.append(
        "select public.fn_lf_operation_reserve_execution_v1("
        f"{_sql_text(execution_id)},"
        f"'{OPERATION_CODE}',"
        "'REPOSITORY_GOVERNED_PATHS',"
        f"{_sql_text(target_code)},"
        f"{_sql_text(idempotency_key)},"
        f"'{request_sha}',"
        f"{_sql_text(execution_id)},"
        f"{_sql_text(repository)},"
        f"{_sql_text(WORKFLOW_PATH)},"
        f"{_sql_json(manifest)}"
        ")::text;"
    )

    for batch in batches:
        context = {
            "source_commit": exact_source,
            "source_path": WORKFLOW_PATH,
            "run_id": run_id,
            "job_id": job_id,
            "owner": OPERATION_CODE,
            "next_action": "FIX_FAILED_LF_CONTRACT_CHECK_AND_RERUN",
            "environment": "CANDIDATE" if workflow_event == "pull_request" else "CI",
            "attempt_no": run_attempt,
            "downstream_impact": ["CI_GOVERNANCE", "EKB"],
        }
        statements.append(
            "select public.lf_record_gate_checks_v1("
            f"{_sql_text(execution_id)},"
            f"'{CANONICAL_STEP_ID}',"
            f"{_sql_text(batch['gate_id'])},"
            f"{_sql_text(batch['gate_mode'])},"
            f"{_sql_json(batch['expected_check_ids'])},"
            f"{_sql_json(batch['checks'])},"
            f"{_sql_json(context)},"
            f"{_sql_text(execution_id)}"
            ")::text;"
        )

    statements.append(
        f"""
do $verify$
declare
  v_total integer;
  v_nonpass integer;
  v_missing integer;
  v_blocked integer;
  v_bad_child integer;
begin
  select count(*) into v_total
  from public.lf_operation_gate_check_results
  where execution_id={_sql_text(execution_id)};

  if v_total<>{total_checks} then
    raise exception 'LF_CONTRACT_PRE_EKB_TOTAL_CHECK_READBACK_MISMATCH expected={total_checks} actual=%',v_total;
  end if;

  select count(*) into v_nonpass
  from public.lf_operation_gate_check_results
  where execution_id={_sql_text(execution_id)}
    and check_status in ('FAIL','BLOCKED');

  if v_nonpass<>{nonpass_checks} then
    raise exception 'LF_CONTRACT_PRE_EKB_NONPASS_READBACK_MISMATCH expected={nonpass_checks} actual=%',v_nonpass;
  end if;

  select count(*) into v_missing
  from public.lf_operation_gate_check_results g
  where g.execution_id={_sql_text(execution_id)}
    and g.check_status in ('FAIL','BLOCKED')
    and not exists (
      select 1
      from public.lf_eventos e
      where e.created_by_execution_id=g.execution_id
        and e.origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
        and e.payload->>'persistence_result'='EKB_PERSISTED'
        and e.payload->>'gate_check_result_id'=g.id::text
    );

  if v_missing<>0 then
    raise exception 'LF_CONTRACT_PRE_EKB_RECEIPT_MISSING count=%',v_missing;
  end if;

  select count(*) into v_blocked
  from public.lf_eventos e
  where e.created_by_execution_id={_sql_text(execution_id)}
    and e.origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
    and e.payload->>'persistence_result'='BLOCKED_EKB_PERSISTENCE';

  if v_blocked<>0 then
    raise exception 'LF_CONTRACT_PRE_EKB_AUTOPERSIST_BLOCKED count=%',v_blocked;
  end if;

  select count(*) into v_bad_child
  from public.lf_eventos e
  left join public.lf_operation_execution child
    on child.execution_id=e.payload->>'child_execution_id'
  where e.created_by_execution_id={_sql_text(execution_id)}
    and e.origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
    and e.payload->>'persistence_result'='EKB_PERSISTED'
    and (
      child.execution_id is null
      or child.operation_code<>'EJECUCION_SKILL_LF'
      or child.target_code<>'ACT-0057'
      or child.status<>'COMPLETED'
    );

  if v_bad_child<>0 then
    raise exception 'LF_CONTRACT_PRE_EKB_CHILD_READBACK_MISMATCH count=%',v_bad_child;
  end if;

  update public.lf_operation_execution
  set status='BLOCKED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'lot_code','LF_CONTRACT_CHECK_PRE_EKB_HANDOFF',
        'source_commit',{_sql_text(exact_source)},
        'github_run_id',{_sql_text(run_id)},
        'github_run_attempt',{run_attempt},
        'batch_count',{len(batches)},
        'total_check_count',{total_checks},
        'nonpass_check_count',{nonpass_checks},
        'persistence_result','EKB_PERSISTED',
        'readback_result','PASS'
      ),
      updated_by_execution_id={_sql_text(execution_id)},
      updated_at=clock_timestamp()
  where execution_id={_sql_text(execution_id)}
    and status='IN_PROGRESS';

  if not found then
    raise exception 'LF_CONTRACT_PRE_EKB_PARENT_FINALIZE_FAILED';
  end if;
end
$verify$;
"""
    )
    statements.append(
        "select jsonb_build_object("
        "'result','PASS_LF_CONTRACT_PRE_EKB_HANDOFF',"
        "'execution_id'," + _sql_text(execution_id) + ","
        "'gate_rows',(select count(*) from public.lf_operation_gate_check_results where execution_id=" + _sql_text(execution_id) + "),"
        "'ekb_receipts',(select count(*) from public.lf_eventos where created_by_execution_id=" + _sql_text(execution_id) + " and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1' and payload->>'persistence_result'='EKB_PERSISTED'),"
        "'status',(select status from public.lf_operation_execution where execution_id=" + _sql_text(execution_id) + ")"
        ")::text;"
    )
    return metadata, "\n".join(statements) + "\n"


def prepare_from_env(root: Path, sql_path: Path, meta_path: Path) -> dict[str, Any]:
    exact_source = os.environ.get("LF_EXACT_SOURCE_SHA", "").strip()
    repository = os.environ.get("LF_REPOSITORY", "").strip()
    run_id = os.environ.get("LF_RUN_ID", "").strip()
    raw_attempt = os.environ.get("LF_RUN_ATTEMPT", "").strip()
    job_id = os.environ.get("LF_JOB_ID", "lf-contract-check").strip() or "lf-contract-check"
    workflow_event = os.environ.get("LF_WORKFLOW_EVENT", "").strip()
    if not repository or not run_id or not raw_attempt.isdigit():
        fail("FAIL_LF_CONTRACT_PRE_EKB_ENVIRONMENT_INVALID")
    metadata, sql = build_payloads(
        root=root,
        exact_source=exact_source,
        repository=repository,
        run_id=run_id,
        run_attempt=int(raw_attempt),
        job_id=job_id,
        workflow_event=workflow_event,
    )
    meta_path.write_text(json.dumps(metadata, sort_keys=True) + "\n", encoding="utf-8")
    sql_path.write_text(sql, encoding="utf-8")
    print(
        "LF_CONTRACT_PRE_EKB_PREPARED "
        f"batches={metadata['batch_count']} total_checks={metadata['total_check_count']} "
        f"nonpass_checks={metadata['nonpass_check_count']}"
    )
    return metadata


def _run_psql(args: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-At", *args],
        input=input_text,
        text=True,
        check=False,
        capture_output=True,
    )


def execute(root: Path, sql_path: Path, meta_path: Path) -> int:
    if not os.environ.get("PGPASSWORD", "").strip():
        fail("FAIL_LF_CONTRACT_PRE_EKB_DB_PASSWORD_MISSING")
    binding = _run_psql(["-c", f"select public.lf_pre_ekb_gate_consumer_v1('{OPERATION_CODE}')::text"])
    if binding.returncode != 0:
        fail("FAIL_LF_CONTRACT_PRE_EKB_CONSUMER_BINDING_READ")
    if binding.stdout.strip() not in {"true", "t"}:
        fail("FAIL_LF_CONTRACT_PRE_EKB_CONSUMER_NOT_BOUND")

    metadata = prepare_from_env(root, sql_path, meta_path)
    nonpass = int(metadata["nonpass_check_count"])
    if nonpass == 0:
        print("PASS_LF_CONTRACT_PRE_EKB_NOT_REQUIRED_ALL_DIAGNOSTICS_PASS")
        return 0
    result = _run_psql(["-f", str(sql_path)])
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip(), file=os.sys.stderr)
    if result.returncode != 0:
        fail(f"FAIL_LF_CONTRACT_PRE_EKB_PSQL_EXECUTION_RC_{result.returncode}")
    print(f"PASS_LF_CONTRACT_PRE_EKB_CANONICAL_HANDOFF nonpass_checks={nonpass}")
    return 0


def _write_fixture(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")


def run_self_test() -> None:
    sha = "1" * 40
    with tempfile.TemporaryDirectory(prefix="lf-pre-ekb-") as tmp:
        root = Path(tmp)
        fail_report = {
            "contract": "LF_GATE_ERROR_V1",
            "gate_id": "G1",
            "gate_mode": "COLLECT_ALL",
            "gate_result": "FAIL",
            "source_commit": sha,
            "expected_check_ids": ["C1"],
            "checks": [
                {
                    "check_id": "C1",
                    "check_status": "FAIL",
                    "critical": True,
                    "error_class": "AssertionError",
                    "condition": "condition",
                    "expected": {"x": 1},
                    "actual": {"x": 2},
                    "input_ref": "x.py",
                    "producer": "SELFTEST",
                    "rc": 1,
                    "owner": "GITHUB_CONTRACT_GATE_LF",
                    "next_action": "FIX_AND_RERUN",
                }
            ],
        }
        _write_fixture(root / "a" / "lf_gate_error_v1.json", fail_report)
        metadata, sql = build_payloads(
            root=root,
            exact_source=sha,
            repository="o/r",
            run_id="123",
            run_attempt=1,
            job_id="lf-contract-check",
            workflow_event="pull_request",
        )
        assert metadata["batch_count"] == 1
        assert metadata["total_check_count"] == 1
        assert metadata["nonpass_check_count"] == 1
        assert "public.fn_lf_operation_reserve_execution_v1" in sql
        assert "public.lf_record_gate_checks_v1" in sql
        assert "LF_PRE_EKB_GATE_AUTOPERSIST_V1" in sql
        assert "public.lf_write_pipeline_ekb_v1" not in sql
        assert "PASS_LF_CONTRACT_PRE_EKB_HANDOFF" in sql

    with tempfile.TemporaryDirectory(prefix="lf-pre-ekb-pass-") as tmp:
        root = Path(tmp)
        _write_fixture(
            root / "pass" / "lf_gate_error_v1.json",
            {
                "contract": "LF_GATE_ERROR_V1",
                "gate_id": "G2",
                "gate_result": "PASS",
                "source_commit": sha,
                "checks": [],
            },
        )
        metadata, sql = build_payloads(
            root=root,
            exact_source=sha,
            repository="o/r",
            run_id="124",
            run_attempt=1,
            job_id="lf-contract-check",
            workflow_event="pull_request",
        )
        assert metadata["nonpass_check_count"] == 0
        assert sql == ""

    with tempfile.TemporaryDirectory(prefix="lf-pre-ekb-head-") as tmp:
        root = Path(tmp)
        _write_fixture(
            root / "bad" / "lf_gate_error_v1.json",
            {
                "contract": "LF_GATE_ERROR_V1",
                "gate_id": "G3",
                "gate_result": "FAIL",
                "source_commit": "2" * 40,
                "expected_check_ids": ["C3"],
                "checks": [
                    {
                        "check_id": "C3",
                        "check_status": "FAIL",
                        "error_class": "X",
                        "condition": "c",
                        "producer": "P",
                        "rc": 1,
                        "owner": "O",
                        "next_action": "N",
                    }
                ],
            },
        )
        try:
            build_payloads(
                root=root,
                exact_source=sha,
                repository="o/r",
                run_id="125",
                run_attempt=1,
                job_id="lf-contract-check",
                workflow_event="pull_request",
            )
        except ConsumerError as exc:
            assert "FAIL_LF_CONTRACT_PRE_EKB_EXACT_HEAD" in str(exc)
        else:
            raise AssertionError("head mismatch did not fail closed")

    print("PASS_LF_CONTRACT_PRE_EKB_CONSUMER_SELFTEST checks=3")


def main() -> int:
    parser = argparse.ArgumentParser(description="PRE_EKB_GATE consumer adapter for GITHUB_CONTRACT_GATE_LF")
    parser.add_argument("--diagnostics-root", default=str(DEFAULT_ROOT))
    parser.add_argument("--sql-path", default=str(DEFAULT_SQL_PATH))
    parser.add_argument("--meta-path", default=str(DEFAULT_META_PATH))
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            run_self_test()
            return 0
        root = Path(args.diagnostics_root)
        if args.prepare_only:
            prepare_from_env(root, Path(args.sql_path), Path(args.meta_path))
            return 0
        return execute(root, Path(args.sql_path), Path(args.meta_path))
    except ConsumerError as exc:
        print(str(exc), file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
