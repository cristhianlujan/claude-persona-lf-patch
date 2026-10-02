#!/usr/bin/env python3
"""Trusted carrier helper for IG_RUNTIME_CANDIDATE_JUDGE_V1.

The helper itself is checked out from the trusted pull-request base. A PR may
supply only a small JSON request plus candidate/prelude SQL objects. Candidate
SQL is always executed by the rollback-only N-9 judge and never imported as
Python or shell code.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
from typing import Any

import ig_runtime_candidate_judge_v1 as judge

REQUEST_SCHEMA = "LF_IG_RUNTIME_CANDIDATE_JUDGE_REQUEST_V1"
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SAFE_PART_RE = re.compile(r"^[A-Za-z0-9._/-]+$")
MAX_CASES = 4
ALLOWED_CANDIDATE_PREFIXES = ("supabase/migrations/", "sandbox/ig_cv/fixtures/")
ALLOWED_PRELUDE_PREFIXES = ("sandbox/ig_cv/fixtures/",)
ALLOWED_VERDICTS = {"NO_BLOCKING_FINDINGS", "BLOCKING_FINDINGS"}


class RequestError(RuntimeError):
    pass


def _safe_path(value: str, prefixes: tuple[str, ...], field: str) -> str:
    value = value.strip()
    if not value or value.startswith("/") or ".." in pathlib.PurePosixPath(value).parts:
        raise RequestError(f"{field}_PATH_INVALID")
    if not SAFE_PART_RE.fullmatch(value):
        raise RequestError(f"{field}_PATH_CHARS_INVALID")
    if not value.startswith(prefixes):
        raise RequestError(f"{field}_PATH_OUT_OF_SCOPE:{value}")
    return value


def _resolve_ref(value: str | None, head_sha: str) -> str:
    ref = head_sha if value in (None, "", "HEAD") else str(value).strip().lower()
    if not SHA40_RE.fullmatch(ref):
        raise RequestError(f"EXACT_REF_INVALID:{ref}")
    return ref


def _git_fetch_exact(ref: str) -> None:
    subprocess.run(
        ["git", "fetch", "--no-tags", "--depth=1", "origin", ref],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _git_object(ref: str, path: str) -> bytes:
    _git_fetch_exact(ref)
    proc = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return proc.stdout


def _decode_sql(raw: bytes, label: str) -> tuple[str, str]:
    digest = hashlib.sha256(raw).hexdigest()
    try:
        sql = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RequestError(f"{label}_NOT_UTF8") from exc
    judge.validate_transaction_bound_sql(sql)
    return sql, digest


def _run_case(case: dict[str, Any], head_sha: str) -> dict[str, Any]:
    case_id = str(case.get("case_id") or "").strip()
    if not case_id or not re.fullmatch(r"[A-Z0-9._-]{3,96}", case_id):
        raise RequestError("CASE_ID_INVALID")

    candidate_ref = _resolve_ref(case.get("candidate_ref"), head_sha)
    candidate_path = _safe_path(str(case.get("candidate_path") or ""), ALLOWED_CANDIDATE_PREFIXES, "CANDIDATE")
    candidate_sql, candidate_sha = _decode_sql(_git_object(candidate_ref, candidate_path), "CANDIDATE")

    prelude_sql = None
    prelude_sha = None
    prelude_path = case.get("prelude_path")
    prelude_ref = None
    if prelude_path:
        prelude_ref = _resolve_ref(case.get("prelude_ref"), head_sha)
        prelude_path = _safe_path(str(prelude_path), ALLOWED_PRELUDE_PREFIXES, "PRELUDE")
        prelude_sql, prelude_sha = _decode_sql(_git_object(prelude_ref, prelude_path), "PRELUDE")

    screen_id = int(case.get("screen_id"))
    if screen_id <= 0:
        raise RequestError("SCREEN_ID_INVALID")
    consumer = str(case.get("consumer") or "STORY_CREATOR").strip()
    if not re.fullmatch(r"[A-Z0-9_]{3,64}", consumer):
        raise RequestError("CONSUMER_INVALID")

    expected_verdict = str(case.get("expected_verdict") or "").strip()
    if expected_verdict not in ALLOWED_VERDICTS:
        raise RequestError("EXPECTED_VERDICT_INVALID")
    expected_codes = case.get("expected_finding_codes") or []
    if not isinstance(expected_codes, list) or not all(isinstance(x, str) and x for x in expected_codes):
        raise RequestError("EXPECTED_FINDING_CODES_INVALID")

    identity = judge.CandidateIdentity(
        exact_head_sha=candidate_ref,
        candidate_path=f"github://candidate@{candidate_ref}/{candidate_path}",
        candidate_sha256=candidate_sha,
        prelude_path=(f"github://prelude@{prelude_ref}/{prelude_path}" if prelude_path else None),
        prelude_sha256=prelude_sha,
    )
    conn = judge._connect()
    try:
        receipt = judge.run_judge(conn, identity, candidate_sql, screen_id, consumer, prelude_sql)
    finally:
        conn.close()

    observed_codes = {str(f.get("code")) for f in receipt.get("findings", [])}
    verdict_ok = receipt.get("verdict") == expected_verdict
    codes_ok = set(expected_codes).issubset(observed_codes)
    case_pass = verdict_ok and codes_ok
    return {
        "case_id": case_id,
        "case_pass": case_pass,
        "expected_verdict": expected_verdict,
        "expected_finding_codes": expected_codes,
        "receipt": receipt,
    }


def self_test() -> None:
    assert _resolve_ref("HEAD", "a" * 40) == "a" * 40
    assert _safe_path("supabase/migrations/x.sql", ALLOWED_CANDIDATE_PREFIXES, "CANDIDATE") == "supabase/migrations/x.sql"
    assert _safe_path("sandbox/ig_cv/fixtures/x.sql", ALLOWED_PRELUDE_PREFIXES, "PRELUDE") == "sandbox/ig_cv/fixtures/x.sql"
    for bad in ("../x.sql", "/tmp/x.sql", "docs/x.sql"):
        try:
            _safe_path(bad, ALLOWED_CANDIDATE_PREFIXES, "CANDIDATE")
        except RequestError:
            pass
        else:
            raise AssertionError(f"unsafe path accepted:{bad}")
    print("IG_RUNTIME_CANDIDATE_JUDGE_REQUEST_SELFTEST_PASS")


def run_request(path: pathlib.Path, head_sha: str) -> int:
    if not SHA40_RE.fullmatch(head_sha):
        raise RequestError("HEAD_SHA_INVALID")
    request = json.loads(path.read_text(encoding="utf-8"))
    if request.get("schema_version") != REQUEST_SCHEMA:
        raise RequestError("REQUEST_SCHEMA_INVALID")
    cases = request.get("cases")
    if not isinstance(cases, list) or not 1 <= len(cases) <= MAX_CASES:
        raise RequestError("REQUEST_CASE_COUNT_INVALID")
    results = [_run_case(case, head_sha) for case in cases]
    payload = {
        "schema_version": REQUEST_SCHEMA,
        "request_head_sha": head_sha,
        "case_count": len(results),
        "pass_count": sum(1 for r in results if r["case_pass"]),
        "results": results,
        "production_authorized": False,
        "runtime_activation_authorized": False,
    }
    print(json.dumps(payload, sort_keys=True, separators=(",", ":"), default=list))
    return 0 if payload["pass_count"] == payload["case_count"] else 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("self-test")
    run = sub.add_parser("run")
    run.add_argument("--request", required=True)
    run.add_argument("--head-sha", required=True)
    args = parser.parse_args(argv)
    if args.command == "self-test":
        self_test()
        return 0
    return run_request(pathlib.Path(args.request), args.head_sha)


if __name__ == "__main__":
    raise SystemExit(main())
