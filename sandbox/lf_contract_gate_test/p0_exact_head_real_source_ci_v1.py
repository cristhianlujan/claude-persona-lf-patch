#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
P0_ROOT = REPO_ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1"
RUNNER = P0_ROOT / "evals" / "p0_visual_real_rerun_v4.py"
CONFIG = P0_ROOT / "evals" / "p0-closed-loop-runtime-config-v4.json"
SOURCE_EVIDENCE_OBJECT_ID = "be7fcf20-5f83-46d4-be0e-c80dc3ceed7c"
SOURCE_SHA256 = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
SOURCE_BYTES = 1_384_686
EXPECTED_REF = "refs/heads/lf/p0-persistence-ocr-completion-20260812"
PROJECT_ID = "mhwmirqcgxxukpctffuv"
POOLER_HOST = "aws-1-us-east-1.pooler.supabase.com"
POSTGRES_IMAGE = "postgres:17.6"


def die(code: str, detail: str = "") -> "NoReturn":
    message = code if not detail else f"{code}: {detail}"
    print(message, file=sys.stderr)
    raise SystemExit(2)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        die(f"FAIL_{name}_MISSING")
    return value


def git_head() -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True
    ).strip()


def pg_env() -> dict[str, str]:
    return {
        "PGHOST": POOLER_HOST,
        "PGPORT": "5432",
        "PGUSER": f"postgres.{PROJECT_ID}",
        "PGPASSWORD": require_env("PGPASSWORD"),
        "PGDATABASE": "postgres",
        "PGSSLMODE": "require",
    }


def docker_psql(
    sql: str,
    *,
    workdir: Path | None = None,
    capture: bool = True,
) -> str:
    env = pg_env()
    cmd = ["docker", "run", "--rm"]
    for key, value in env.items():
        cmd += ["-e", f"{key}={value}"]
    if workdir is not None:
        cmd += ["-v", f"{workdir}:/work"]
    cmd += [POSTGRES_IMAGE, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-At"]
    proc = subprocess.run(
        cmd,
        input=sql,
        text=True,
        capture_output=capture,
        check=False,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "psql failed").strip()[-1200:]
        die("FAIL_P0_PRIVATE_DB_OPERATION", detail)
    return proc.stdout if capture else ""


def main() -> int:
    event_name = require_env("GITHUB_EVENT_NAME")
    github_ref = require_env("GITHUB_REF")
    github_sha = require_env("GITHUB_SHA")
    if event_name not in {"push", "workflow_dispatch"}:
        die("FAIL_P0_EXACT_HEAD_EVENT_TYPE", event_name)
    if github_ref != EXPECTED_REF:
        die("FAIL_P0_EXACT_HEAD_BRANCH", github_ref)
    observed_head = git_head()
    if observed_head != github_sha:
        die("FAIL_P0_EXACT_HEAD_CHECKOUT", f"expected={github_sha} observed={observed_head}")
    if len(github_sha) != 40 or any(ch not in "0123456789abcdef" for ch in github_sha):
        die("FAIL_P0_EXACT_HEAD_SHA_FORMAT")

    run_root = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "lf-p0-real-source"
    run_root.mkdir(parents=True, exist_ok=True)
    review_id = f"P0-FRESH-REAL-{github_sha}"
    execution_id = f"EXEC-P0-FRESH-REAL-{github_sha}"

    binding_sql = f"""
insert into private.lf_p0_review_evidence_objects_v1(
  review_id, execution_id, object_role, object_name, mime_type,
  content_bytes, content_sha256, content, data_classification,
  source_head_sha, retention_policy, metadata
)
select
  '{review_id}', '{execution_id}', 'SOURCE_IMAGE', object_name, mime_type,
  content_bytes, content_sha256, content, data_classification,
  '{github_sha}', retention_policy,
  metadata || jsonb_build_object(
    'exact_head_binding', true,
    'bound_from_evidence_object_id', '{SOURCE_EVIDENCE_OBJECT_ID}',
    'github_run_id', '{os.environ.get("GITHUB_RUN_ID", "")}',
    'github_run_attempt', '{os.environ.get("GITHUB_RUN_ATTEMPT", "")}'
  )
from private.lf_p0_review_evidence_objects_v1
where evidence_object_id = '{SOURCE_EVIDENCE_OBJECT_ID}'::uuid
  and object_role = 'SOURCE_IMAGE'
  and content_bytes = {SOURCE_BYTES}
  and content_sha256 = '{SOURCE_SHA256}'
on conflict (review_id, object_role, content_sha256) do nothing;
select evidence_object_id::text || '|' || content_bytes::text || '|' || content_sha256
from private.lf_p0_review_evidence_objects_v1
where review_id = '{review_id}'
  and object_role = 'SOURCE_IMAGE'
  and content_sha256 = '{SOURCE_SHA256}';
"""
    binding_rows = [line for line in docker_psql(binding_sql).splitlines() if "|" in line]
    if len(binding_rows) != 1:
        die("FAIL_P0_EXACT_HEAD_SOURCE_BINDING_READBACK", repr(binding_rows))
    bound_id, bound_bytes, bound_sha = binding_rows[0].split("|", 2)
    if int(bound_bytes) != SOURCE_BYTES or bound_sha != SOURCE_SHA256:
        die("FAIL_P0_EXACT_HEAD_SOURCE_BINDING_INTEGRITY")

    source_hex = run_root / "source.hex"
    copy_source_sql = f"""\\copy (select encode(content,'hex') from private.lf_p0_review_evidence_objects_v1 where evidence_object_id='{bound_id}'::uuid and source_head_sha='{github_sha}' and content_bytes={SOURCE_BYTES} and content_sha256='{SOURCE_SHA256}') to '/work/source.hex' with (format text)
"""
    docker_psql(copy_source_sql, workdir=run_root)
    raw_hex = source_hex.read_text(encoding="ascii").strip()
    if not raw_hex:
        die("FAIL_P0_EXACT_HEAD_SOURCE_EXPORT_EMPTY")
    source = bytes.fromhex(raw_hex)
    source_hex.unlink(missing_ok=True)
    if len(source) != SOURCE_BYTES or sha256_bytes(source) != SOURCE_SHA256:
        die("FAIL_P0_EXACT_HEAD_SOURCE_EXPORT_INTEGRITY")
    source_path = run_root / "source.png"
    source_path.write_bytes(source)

    config_sha = sha256_bytes(CONFIG.read_bytes())
    receipt_path = run_root / "p0-real-rerun-v4.json"
    runner = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--source", str(source_path),
            "--source-sha", SOURCE_SHA256,
            "--code-head", github_sha,
            "--config-sha", config_sha,
            "--output", str(receipt_path),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ.copy(),
    )
    (run_root / "runner.stdout").write_text(runner.stdout, encoding="utf-8")
    (run_root / "runner.stderr").write_text(runner.stderr, encoding="utf-8")
    if not receipt_path.exists():
        die("FAIL_P0_EXACT_HEAD_RECEIPT_MISSING", f"runner_exit={runner.returncode}")

    receipt_bytes = receipt_path.read_bytes()
    receipt_sha = sha256_bytes(receipt_bytes)
    try:
        receipt = json.loads(receipt_bytes)
    except json.JSONDecodeError as exc:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_JSON", str(exc))
    if receipt.get("source_sha256") != SOURCE_SHA256:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_SOURCE_BINDING")
    if receipt.get("code_head_sha") != github_sha:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_HEAD_BINDING")
    if receipt.get("configuration_sha256") != config_sha:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_CONFIG_BINDING")

    mutation = receipt.get("mutation_campaign") if isinstance(receipt.get("mutation_campaign"), dict) else {}
    residual = receipt.get("visual_residual_gate") if isinstance(receipt.get("visual_residual_gate"), dict) else {}
    technical = receipt.get("result") if isinstance(receipt.get("result"), dict) else {}
    terminal = receipt.get("terminal_result")
    summary = {
        "schema_version": "p0-exact-head-ci-summary/v1",
        "github_event_name": event_name,
        "github_ref": github_ref,
        "github_sha": github_sha,
        "observed_git_head": observed_head,
        "source_sha256": SOURCE_SHA256,
        "source_bytes": SOURCE_BYTES,
        "source_evidence_object_id": bound_id,
        "configuration_sha256": config_sha,
        "receipt_sha256": receipt_sha,
        "receipt_bytes": len(receipt_bytes),
        "runner_exit_code": runner.returncode,
        "technical_result": technical.get("result"),
        "terminal_result": terminal,
        "human_review_ready": terminal == "READY_FOR_HUMAN_REVIEW_RECHECK",
        "mutation_status": mutation.get("status"),
        "mutation_count": mutation.get("mutation_count"),
        "mutation_detected_count": mutation.get("detected_count"),
        "residual_status": residual.get("status"),
        "residual_errors": residual.get("errors") if isinstance(residual.get("errors"), list) else [],
        "production_authorized": False,
        "p0_5_authorized": False,
    }
    audit_dir = REPO_ROOT / ".audit-output" / "creating-integral-user-stories"
    audit_dir.mkdir(parents=True, exist_ok=True)
    summary_path = audit_dir / "p0-exact-head-real-source-summary.json"
    summary_path.write_text(json.dumps(summary, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(summary, sort_keys=True))

    receipt_hex = run_root / "receipt.hex"
    receipt_hex.write_text(receipt_bytes.hex() + "\n", encoding="ascii")
    receipt_persist_sql = f"""
create temp table tmp_p0_receipt_hex(payload text not null);
\\copy tmp_p0_receipt_hex(payload) from '/work/receipt.hex' with (format text)
with decoded as (
  select decode(payload,'hex') as content from tmp_p0_receipt_hex
), ins as (
  insert into private.lf_p0_review_evidence_objects_v1(
    review_id, execution_id, object_role, object_name, mime_type,
    content_bytes, content_sha256, content, data_classification,
    source_head_sha, retention_policy, metadata
  )
  select
    '{review_id}', '{execution_id}', 'PACKET_MANIFEST', 'p0-real-rerun-v4.json', 'application/json',
    octet_length(content), encode(extensions.digest(content,'sha256'),'hex'), content, 'SENSITIVE',
    '{github_sha}', 'UNTIL_TERMINAL_REVIEW',
    jsonb_build_object(
      'evidence_schema_version','p0-v4-real-rerun-trace',
      'fresh_exact_head',true,
      'source_evidence_object_id','{bound_id}',
      'source_sha256','{SOURCE_SHA256}',
      'configuration_sha256','{config_sha}',
      'github_run_id','{os.environ.get("GITHUB_RUN_ID", "")}',
      'github_run_attempt','{os.environ.get("GITHUB_RUN_ATTEMPT", "")}',
      'runner_exit_code',{runner.returncode}
    )
  from decoded
  on conflict (review_id, object_role, content_sha256) do nothing
  returning evidence_object_id
)
select evidence_object_id::text from ins;
select evidence_object_id::text || '|' || content_bytes::text || '|' || content_sha256
from private.lf_p0_review_evidence_objects_v1
where review_id='{review_id}'
  and object_role='PACKET_MANIFEST'
  and content_sha256='{receipt_sha}';
"""
    receipt_rows = [line for line in docker_psql(receipt_persist_sql, workdir=run_root).splitlines() if "|" in line]
    receipt_hex.unlink(missing_ok=True)
    if len(receipt_rows) != 1:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_PERSISTENCE_READBACK", repr(receipt_rows))
    receipt_object_id, db_bytes, db_sha = receipt_rows[0].split("|", 2)
    if int(db_bytes) != len(receipt_bytes) or db_sha != receipt_sha:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_PERSISTENCE_INTEGRITY")
    print(f"P0_EXACT_HEAD_RECEIPT_OBJECT_ID={receipt_object_id}")

    source_path.unlink(missing_ok=True)
    if runner.returncode != 0:
        die("BLOCKED_P0_EXACT_HEAD_REAL_SOURCE_RERUN", f"runner_exit={runner.returncode} terminal={terminal}")
    if terminal != "READY_FOR_HUMAN_REVIEW_RECHECK":
        die("BLOCKED_P0_EXACT_HEAD_TERMINAL_RESULT", str(terminal))
    print("READY_FOR_HUMAN_REVIEW_RECHECK_EXACT_HEAD")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
