#!/usr/bin/env python3
"""IG runtime candidate flow judge v1.

Runs a representative Input Governance Dispatcher -> Curator -> Validator flow
before and after candidate SQL in one PostgreSQL transaction and always rolls
the transaction back. It is a verification runner only: it grants no
runtime/production authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import time
import uuid
from dataclasses import asdict, dataclass
from typing import Any, Iterable

SCHEMA_VERSION = "LF_IG_RUNTIME_CANDIDATE_JUDGE_RECEIPT_V1"
CAPABILITY_CODE = "IG_RUNTIME_CANDIDATE_JUDGE"
MUTATION_POLICY = "ROLLBACK_ONLY_NO_PERSISTENT_EFFECT"
MAX_VALIDATOR_CALLS = 8
VOLATILE_TERMINAL_KEYS = {
    "run_id",
    "latest_run_id",
    "validator_identity",
    "curator_identity",
    "output_sha256",
}
FORBIDDEN_SQL = re.compile(
    r"(?is)(?:^|;)\s*(?:(?:--[^\r\n]*(?:\r?\n|$)|/\*.*?\*/)\s*)*"
    r"(?:commit\b|rollback\b|end\s+transaction\b|begin\s+transaction\b|start\s+transaction\b|"
    r"prepare\s+transaction\b|vacuum\b|cluster\b|reindex\s+database\b|create\s+database\b|"
    r"drop\s+database\b|alter\s+system\b|copy\b[^;]*\bprogram\b)"
)
FORBIDDEN_SERVER_IO = re.compile(
    r"(?i)\b(?:pg_read_file|pg_read_binary_file|pg_ls_dir|pg_stat_file|lo_import|dblink|dblink_exec|"
    r"http_get|http_post|http_put|http_delete|aws_lambda)\s*\(|\b(?:net|pg_net)\.http_[a-z_]+\s*\("
)
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class CandidateIdentity:
    exact_head_sha: str
    candidate_path: str
    candidate_sha256: str
    prelude_path: str | None = None
    prelude_sha256: str | None = None


@dataclass(frozen=True)
class FlowCapture:
    phase: str
    error: str | None
    statuses: tuple[str, ...]
    terminal_payload: dict[str, Any] | None
    proposal_validation_keys: tuple[str, ...]
    assessment_digest: str | None
    family_count: int | None
    pass_count: int | None
    run_status: str | None
    timing_rows: int
    timing: dict[str, Any]
    elapsed_ms: int
    retry_status: str | None


class JudgeError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_sql(path: pathlib.Path, expected_sha256: str | None = None) -> tuple[str, str]:
    raw = path.read_bytes()
    digest = sha256_bytes(raw)
    if expected_sha256 and digest != expected_sha256:
        raise JudgeError(f"SQL_SHA256_MISMATCH:{path}:{digest}")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise JudgeError(f"SQL_NOT_UTF8:{path}") from exc
    validate_transaction_bound_sql(text)
    return text, digest


def validate_transaction_bound_sql(sql: str) -> None:
    if not sql.strip():
        raise JudgeError("EMPTY_CANDIDATE_SQL")
    if FORBIDDEN_SQL.search(sql):
        raise JudgeError("TRANSACTION_ESCAPE_FORBIDDEN")
    if FORBIDDEN_SERVER_IO.search(sql):
        raise JudgeError("SERVER_IO_OR_EXTERNAL_EFFECT_FORBIDDEN")


def _normalize_terminal_value(value: Any) -> Any:
    """Remove execution-local identity fields at any nesting depth.

    Terminal payloads may embed proposal_validation.run_id. Baseline and
    candidate necessarily receive different transaction-local run IDs, so those
    identities are not semantic drift and must not block an otherwise equal
    flow. All non-volatile values and collection structure remain comparable.
    """
    if isinstance(value, dict):
        return {
            key: _normalize_terminal_value(item)
            for key, item in value.items()
            if key not in VOLATILE_TERMINAL_KEYS
        }
    if isinstance(value, list):
        return [_normalize_terminal_value(item) for item in value]
    if isinstance(value, tuple):
        return tuple(_normalize_terminal_value(item) for item in value)
    return value


def normalize_terminal(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if payload is None:
        return None
    normalized = _normalize_terminal_value(payload)
    if not isinstance(normalized, dict):
        raise JudgeError("NORMALIZED_TERMINAL_NOT_OBJECT")
    return normalized


def _fetchone_value(cur: Any) -> Any:
    row = cur.fetchone()
    if row is None:
        return None
    if isinstance(row, dict):
        return next(iter(row.values()))
    return row[0]


def _execute_json(cur: Any, sql: str, params: Iterable[Any]) -> dict[str, Any]:
    cur.execute(sql, tuple(params))
    value = _fetchone_value(cur)
    if isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, dict):
        raise JudgeError(f"EXPECTED_JSON_OBJECT:{type(value).__name__}")
    return value


def _start_governed_flow(cur: Any, screen_id: int, consumer: str, curator_id: str) -> tuple[int, tuple[str, str]]:
    """Enter through the real governed Dispatcher -> Curator boundary.

    R17 v3 and the N-7 prior art require the judge to exercise the same entry
    route as the runtime, not to call curator_rebind directly. This helper keeps
    that routing explicit and testable.
    """
    dispatched = _execute_json(
        cur,
        "select programacion.fn_input_governance_execute(%s,%s)",
        (screen_id, consumer),
    )
    dispatch_status = str(dispatched.get("status") or "")
    if dispatch_status != "CURATOR_RUNTIME_REQUIRED":
        raise JudgeError(f"DISPATCH_NOT_READY:{dispatch_status or 'EMPTY'}")

    materialized = _execute_json(
        cur,
        "select programacion.fn_input_governance_curator_materialize_v1(%s,%s,%s,true)",
        (screen_id, consumer, curator_id),
    )
    curator_status = str(materialized.get("status") or "")
    run_value = materialized.get("run_id") or materialized.get("latest_run_id")
    run_id = int(run_value) if run_value is not None else None
    if curator_status != "VALIDATOR_RUNTIME_REQUIRED" or run_id is None:
        raise JudgeError(f"CURATOR_NOT_READY:{curator_status or 'EMPTY'}")
    return run_id, (dispatch_status, curator_status)


def capture_flow(cur: Any, screen_id: int, consumer: str, phase: str) -> FlowCapture:
    curator_id = f"INPUT_CURATOR:EDGE:input-governance-curator-v1:n9-{uuid.uuid4().hex[:20]}"
    validator_id = f"INPUT_VALIDATOR:EDGE:input-governance-validator-v1:n9-{uuid.uuid4().hex[:20]}"
    started = time.monotonic_ns()
    statuses: list[str] = []
    last: dict[str, Any] | None = None
    run_id: int | None = None
    try:
        run_id, entry_statuses = _start_governed_flow(cur, screen_id, consumer, curator_id)
        statuses.extend(entry_statuses)

        for _ in range(MAX_VALIDATOR_CALLS):
            last = _execute_json(
                cur,
                "select programacion.fn_input_governance_validator_validate_v1(%s,%s)",
                (run_id, validator_id),
            )
            vstatus = str(last.get("status") or "")
            statuses.append(vstatus)
            if vstatus in {"COMPLETED", "NOOP_COMPLETED"}:
                break
        else:
            raise JudgeError("VALIDATOR_DID_NOT_TERMINATE")

        retry = _execute_json(
            cur,
            "select programacion.fn_input_governance_validator_validate_v1(%s,%s)",
            (run_id, validator_id),
        )
        retry_status = str(retry.get("status") or "")
        statuses.append(retry_status)
        if retry_status != "NOOP_COMPLETED":
            raise JudgeError(f"RETRY_NOT_IDEMPOTENT:{retry_status or 'EMPTY'}")

        cur.execute(
            """
            select
              md5(string_agg(
                family_code||'|'||validator_outcome||'|'||coalesce(validator_findings::text,'')||'|'||
                coalesce(validator_evidence->>'bootstrap_classifier_sha256','')||'|'||
                md5(coalesce((programacion.fn_input_validator_evidence_rehydrate_v1(validator_evidence)->'assertions')::text,'')),
                ',' order by family_code
              )) as digest,
              count(*)::int as family_count,
              count(*) filter (where validator_outcome='PASS')::int as pass_count
            from programacion.input_family_assessments where run_id=%s
            """,
            (run_id,),
        )
        row = cur.fetchone()
        if isinstance(row, dict):
            digest = row["digest"]
            family_count = int(row["family_count"])
            pass_count = int(row["pass_count"])
        else:
            digest, family_count, pass_count = row
            family_count, pass_count = int(family_count), int(pass_count)

        cur.execute("select status from programacion.input_readiness_runs where id=%s", (run_id,))
        run_status = str(_fetchone_value(cur) or "")

        cur.execute(
            """
            select jsonb_build_object(
              'rows',count(*)::int,
              'families_processed',coalesce(sum(families_processed),0)::int,
              'duration_ms',coalesce(sum(duration_ms),0)::bigint,
              'classification_ms',coalesce(sum(classification_ms),0)::bigint,
              'assertions_ms',coalesce(sum(assertions_ms),0)::bigint,
              'ekb_ms',coalesce(sum(ekb_ms),0)::bigint,
              'gap_proposals_ms',coalesce(sum(gap_proposals_ms),0)::bigint,
              'db_write_ms',coalesce(sum(db_write_ms),0)::bigint,
              'wait_resume_ms',coalesce(sum(wait_resume_ms),0)::bigint,
              'routes',coalesce(jsonb_agg(distinct route) filter (where route is not null),'[]'::jsonb)
            )
            from programacion.input_validator_chunk_timings where run_id=%s
            """,
            (run_id,),
        )
        timing = _fetchone_value(cur) or {}
        if isinstance(timing, str):
            timing = json.loads(timing)
        if not isinstance(timing, dict):
            raise JudgeError("TIMING_CAPTURE_INVALID")
        timing_rows = int(timing.get("rows") or 0)

        terminal = normalize_terminal(last)
        proposal = last.get("proposal_validation") if last else None
        proposal_keys = tuple(sorted(proposal.keys())) if isinstance(proposal, dict) else tuple()
        elapsed_ms = round((time.monotonic_ns() - started) / 1_000_000)
        return FlowCapture(
            phase=phase,
            error=None,
            statuses=tuple(statuses),
            terminal_payload=terminal,
            proposal_validation_keys=proposal_keys,
            assessment_digest=digest,
            family_count=family_count,
            pass_count=pass_count,
            run_status=run_status,
            timing_rows=timing_rows,
            timing=timing,
            elapsed_ms=elapsed_ms,
            retry_status=retry_status,
        )
    except Exception as exc:
        elapsed_ms = round((time.monotonic_ns() - started) / 1_000_000)
        return FlowCapture(
            phase=phase,
            error=f"{type(exc).__name__}:{exc}",
            statuses=tuple(statuses),
            terminal_payload=normalize_terminal(last),
            proposal_validation_keys=tuple(),
            assessment_digest=None,
            family_count=None,
            pass_count=None,
            run_status=None,
            timing_rows=0,
            timing={},
            elapsed_ms=elapsed_ms,
            retry_status=None,
        )


def compare_captures(baseline: FlowCapture, candidate: FlowCapture) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    if baseline.error:
        findings.append({"code": "BASELINE_FLOW_ERROR", "blocking": True, "detail": baseline.error})
    if candidate.error:
        findings.append({"code": "CANDIDATE_FLOW_ERROR", "blocking": True, "detail": candidate.error})
    if baseline.error or candidate.error:
        return findings

    checks = (
        ("TERMINAL_PAYLOAD_DRIFT", baseline.terminal_payload, candidate.terminal_payload),
        ("ASSESSMENT_DIGEST_DRIFT", baseline.assessment_digest, candidate.assessment_digest),
        ("FAMILY_CARDINALITY_DRIFT", baseline.family_count, candidate.family_count),
        ("PASS_CARDINALITY_DRIFT", baseline.pass_count, candidate.pass_count),
        ("RUN_STATUS_DRIFT", baseline.run_status, candidate.run_status),
        ("PROPOSAL_KEYS_DRIFT", baseline.proposal_validation_keys, candidate.proposal_validation_keys),
        ("RETRY_STATUS_DRIFT", baseline.retry_status, candidate.retry_status),
    )
    for code, before, after in checks:
        if before != after:
            findings.append({"code": code, "blocking": True, "before": before, "after": after})

    if candidate.family_count != candidate.pass_count:
        findings.append({
            "code": "CANDIDATE_NOT_ALL_FAMILIES_PASS",
            "blocking": True,
            "family_count": candidate.family_count,
            "pass_count": candidate.pass_count,
        })
    if candidate.timing_rows <= 0:
        findings.append({"code": "CANDIDATE_TIMING_EVIDENCE_MISSING", "blocking": True})
    elif int(candidate.timing.get("families_processed") or 0) != int(candidate.family_count or 0):
        findings.append({
            "code": "CANDIDATE_TIMING_FAMILY_COUNT_MISMATCH",
            "blocking": True,
            "timed": candidate.timing.get("families_processed"),
            "families": candidate.family_count,
        })
    return findings


def build_receipt(identity: CandidateIdentity, screen_id: int, consumer: str,
                  baseline: FlowCapture, candidate: FlowCapture,
                  findings: list[dict[str, Any]]) -> dict[str, Any]:
    blocking = [f for f in findings if f.get("blocking") is True]
    return {
        "schema_version": SCHEMA_VERSION,
        "capability_code": CAPABILITY_CODE,
        "mutation_policy": MUTATION_POLICY,
        "exact_head_sha": identity.exact_head_sha,
        "candidate_path": identity.candidate_path,
        "candidate_sha256": identity.candidate_sha256,
        "prelude_path": identity.prelude_path,
        "prelude_sha256": identity.prelude_sha256,
        "screen_id": screen_id,
        "consumer": consumer,
        "flow_entrypoint": "DISPATCHER_CURATOR_VALIDATOR",
        "baseline": asdict(baseline),
        "candidate": asdict(candidate),
        "findings": findings,
        "blocking_finding_count": len(blocking),
        "verdict": "BLOCKING_FINDINGS" if blocking else "NO_BLOCKING_FINDINGS",
        "production_authorized": False,
        "runtime_activation_authorized": False,
    }


def _savepoint(cur: Any, name: str) -> None:
    cur.execute(f"savepoint {name}")


def _rollback_to(cur: Any, name: str) -> None:
    cur.execute(f"rollback to savepoint {name}")
    cur.execute(f"release savepoint {name}")


def run_judge(conn: Any, identity: CandidateIdentity, candidate_sql: str,
              screen_id: int, consumer: str, prelude_sql: str | None = None) -> dict[str, Any]:
    if conn.autocommit:
        raise JudgeError("AUTOCOMMIT_MUST_BE_FALSE")
    cur = conn.cursor()
    try:
        if prelude_sql:
            cur.execute(prelude_sql, prepare=False)

        _savepoint(cur, "n9_baseline")
        baseline = capture_flow(cur, screen_id, consumer, "BASELINE")
        _rollback_to(cur, "n9_baseline")

        cur.execute(candidate_sql, prepare=False)

        _savepoint(cur, "n9_candidate")
        candidate = capture_flow(cur, screen_id, consumer, "CANDIDATE")
        _rollback_to(cur, "n9_candidate")

        findings = compare_captures(baseline, candidate)
        return build_receipt(identity, screen_id, consumer, baseline, candidate, findings)
    finally:
        conn.rollback()


def _connect() -> Any:
    try:
        import psycopg
        from psycopg.rows import dict_row
    except ImportError as exc:
        raise JudgeError("PSYCOPG_REQUIRED") from exc
    project = os.environ.get("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv").strip()
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com").strip()
    if not password:
        raise JudgeError("LF_SUPABASE_DB_PASSWORD_REQUIRED")
    return psycopg.connect(
        host=host,
        port=6543,
        dbname="postgres",
        user=f"postgres.{project}",
        password=password,
        sslmode="require",
        row_factory=dict_row,
        autocommit=False,
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--candidate-sql", required=True)
    p.add_argument("--candidate-sha256", required=True)
    p.add_argument("--exact-head-sha", required=True)
    p.add_argument("--screen-id", required=True, type=int)
    p.add_argument("--consumer", default="STORY_CREATOR")
    p.add_argument("--prelude-sql")
    p.add_argument("--prelude-sha256")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if not SHA40_RE.fullmatch(args.exact_head_sha):
        raise JudgeError("EXACT_HEAD_SHA_INVALID")
    if not SHA64_RE.fullmatch(args.candidate_sha256):
        raise JudgeError("CANDIDATE_SHA256_INVALID")
    candidate_path = pathlib.Path(args.candidate_sql)
    candidate_sql, candidate_sha = load_sql(candidate_path, args.candidate_sha256)
    prelude_sql = None
    prelude_sha = None
    if args.prelude_sql:
        if not args.prelude_sha256 or not SHA64_RE.fullmatch(args.prelude_sha256):
            raise JudgeError("PRELUDE_SHA256_REQUIRED")
        prelude_path = pathlib.Path(args.prelude_sql)
        prelude_sql, prelude_sha = load_sql(prelude_path, args.prelude_sha256)
    identity = CandidateIdentity(
        exact_head_sha=args.exact_head_sha,
        candidate_path=candidate_path.as_posix(),
        candidate_sha256=candidate_sha,
        prelude_path=pathlib.Path(args.prelude_sql).as_posix() if args.prelude_sql else None,
        prelude_sha256=prelude_sha,
    )
    conn = _connect()
    try:
        receipt = run_judge(conn, identity, candidate_sql, args.screen_id, args.consumer, prelude_sql)
    finally:
        conn.close()
    print(json.dumps(receipt, sort_keys=True, separators=(",", ":"), default=list))
    return 2 if receipt["blocking_finding_count"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
