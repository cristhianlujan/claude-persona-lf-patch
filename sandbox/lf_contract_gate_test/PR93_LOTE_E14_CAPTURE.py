#!/usr/bin/env python3
"""Authoritative PR #93 LOTE-E.14 evidence capture."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import PR93_LOTE_E14_SEMANTICS as semantics
from PR93_LOTE_E14_COMMON import (
    SCHEMA_VERSION,
    REPOSITORY,
    assert_repository,
    canonical_json_bytes,
    connectivity_preflight,
    count_exact_line,
    count_prefixed_line,
    exact_line_count,
    json_output_matches,
    run_psql,
    run_state_readback,
    sha256_bytes,
    source_inventory,
    utc_now,
    write_exclusive,
)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--psql-bin", default="psql")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    args = parser.parse_args()

    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        parser.error("DATABASE_URL environment variable is required")
    if args.timeout_seconds < 1:
        parser.error("--timeout-seconds must be positive")

    repo_root = args.repo_root.resolve()
    output_dir = args.output_dir.resolve()
    assert_repository(repo_root, args.head_sha, args.timeout_seconds)
    if output_dir == repo_root or repo_root in output_dir.parents:
        raise RuntimeError("output directory must be outside the audited repository")
    if output_dir.exists():
        raise RuntimeError(
            "output directory already exists; evidence capture refuses overwrite"
        )

    sources = source_inventory(repo_root, args.timeout_seconds)
    sandbox = repo_root / "sandbox/lf_contract_gate_test"

    preflight_exit, preflight_output = connectivity_preflight(
        args.psql_bin,
        database_url,
        sandbox,
        args.timeout_seconds,
    )
    if preflight_exit != 0:
        sys.stderr.buffer.write(preflight_output)
        print(
            f"E14_CONNECTIVITY_PREFLIGHT_FAILED={preflight_exit}",
            file=sys.stderr,
        )
        return 21

    # No evidence directory exists before connectivity has been proven.
    output_dir.mkdir(parents=True, exist_ok=False)
    started_at = utc_now()

    t1_script = sandbox / "PR93_LOTE_E13_T1.psql"
    t2_script = sandbox / "PR93_LOTE_E13_T2.psql"
    state_script = sandbox / "PR93_LOTE_E13_STATE_READBACK.sql"

    t1_exit, t1_output = run_psql(
        args.psql_bin,
        database_url,
        t1_script,
        sandbox,
        args.timeout_seconds,
        args.head_sha,
    )
    try:
        semantic_checks = semantics.parse_t1_semantics(t1_output, args.head_sha)
    except (UnicodeDecodeError, ValueError) as exc:
        semantic_checks = {"all_pass": False, "validation_error": str(exc)}

    pre_exit = post_exit = 99
    pre_output = post_output = b""
    pre_state = post_state = None
    t2_exit = 99
    t2_output = b"E14_T2_NOT_EXECUTED\n"

    t1_ok = t1_exit == 0 and semantic_checks.get("all_pass") is True
    if t1_ok:
        pre_exit, pre_output, pre_state = run_state_readback(
            args.psql_bin,
            database_url,
            state_script,
            sandbox,
            args.timeout_seconds,
        )
        if pre_exit == 0:
            t2_exit, t2_output = run_psql(
                args.psql_bin,
                database_url,
                t2_script,
                sandbox,
                args.timeout_seconds,
                args.head_sha,
            )
            post_exit, post_output, post_state = run_state_readback(
                args.psql_bin,
                database_url,
                state_script,
                sandbox,
                args.timeout_seconds,
            )

    state_match = (
        pre_state is not None
        and post_state is not None
        and pre_state == post_state
    )
    explicit_rollback_count = count_exact_line(t2_output, "ROLLBACK")
    if t2_exit == 0 and explicit_rollback_count == 1 and state_match:
        rollback_status = "EXPLICIT"
    elif t2_exit != 0 and explicit_rollback_count == 0 and state_match:
        rollback_status = "IMPLICIT_ON_DISCONNECT"
    else:
        rollback_status = "NOT_VERIFIED"

    t2_head_ok = (
        t2_exit != 99
        and count_exact_line(t2_output, f"E13_T2_HEAD_SHA={args.head_sha}") == 1
        and count_prefixed_line(t2_output, "E13_T1_HEAD_SHA=") == 0
        and count_prefixed_line(t2_output, "E14_HEAD_SHA=") == 0
    )
    state_logs_match = (
        json_output_matches(pre_output, pre_state)
        and json_output_matches(post_output, post_state)
    )
    t2_ok = (
        t2_exit == 0
        and count_exact_line(t2_output, "E13_T2_BEGIN") == 1
        and count_exact_line(t2_output, "E13_T2_CONTEXT_GUARD_PASS") == 1
        and count_exact_line(t2_output, "E13_T2_COMPLETE") == 1
        and t2_head_ok
        and state_logs_match
        and rollback_status == "EXPLICIT"
    )
    overall_status = "PASS" if t1_ok and t2_ok else "FAIL"

    pre_state_bytes = (
        canonical_json_bytes(pre_state) if pre_state is not None else b"null\n"
    )
    post_state_bytes = (
        canonical_json_bytes(post_state) if post_state is not None else b"null\n"
    )
    finished_at = utc_now()

    full_output = b"".join(
        [
            b"E14_CAPTURE_BEGIN\n",
            f"E14_HEAD_SHA={args.head_sha}\n".encode(),
            f"E14_STARTED_AT={started_at}\n".encode(),
            b"E14_T1_PROCESS_BEGIN\n",
            t1_output,
            f"E14_T1_PROCESS_EXIT={t1_exit}\n".encode(),
            b"E14_T2_PRE_STATE_BEGIN\n",
            pre_state_bytes,
            f"E14_T2_PRE_STATE_EXIT={pre_exit}\n".encode(),
            b"E14_T2_PROCESS_BEGIN\n",
            t2_output,
            f"E14_T2_PROCESS_EXIT={t2_exit}\n".encode(),
            b"E14_T2_POST_STATE_BEGIN\n",
            post_state_bytes,
            f"E14_T2_POST_STATE_EXIT={post_exit}\n".encode(),
            f"E14_T2_STATE_MATCH={str(state_match).lower()}\n".encode(),
            f"E14_T2_ROLLBACK_STATUS={rollback_status}\n".encode(),
            f"E14_OVERALL_STATUS={overall_status}\n".encode(),
            f"E14_FINISHED_AT={finished_at}\n".encode(),
            b"E14_CAPTURE_END\n",
        ]
    )

    files: dict[str, bytes] = {
        "PR93_E14_FULL_TRANSCRIPT.log": full_output,
        "PR93_E14_T1_TRANSCRIPT.log": t1_output,
        "PR93_E14_T2_TRANSCRIPT.log": t2_output,
        "PR93_E14_PRE_STATE.json": pre_state_bytes,
        "PR93_E14_POST_STATE.json": post_state_bytes,
        "PR93_E14_PRE_STATE_COMMAND.log": pre_output,
        "PR93_E14_POST_STATE_COMMAND.log": post_output,
    }
    for name, data in files.items():
        write_exclusive(output_dir / name, data)

    evidence_files = {
        name: {
            "sha256": sha256_bytes(data),
            "size_bytes": len(data),
            "line_count": exact_line_count(data),
        }
        for name, data in files.items()
    }

    receipt = {
        "schema_version": SCHEMA_VERSION,
        "governance_contract_version": "PR93_E14_V1",
        "repository": REPOSITORY,
        "head_sha": args.head_sha,
        "started_at_utc": started_at,
        "finished_at_utc": finished_at,
        "connectivity_preflight": {
            "passed": True,
            "exit_code": preflight_exit,
            "output_sha256": sha256_bytes(preflight_output),
            "output_was_exact_select_one": True,
            "completed_before_output_directory_creation": True,
        },
        "source_artifacts": sources,
        "evidence_files": evidence_files,
        "t1": {
            "exit_code": t1_exit,
            "semantic_checks": semantic_checks,
            "status": "PASS" if t1_ok else "FAIL",
        },
        "t2": {
            "exit_code": t2_exit,
            "context_guard_pass_marker_count": count_exact_line(
                t2_output, "E13_T2_CONTEXT_GUARD_PASS"
            ),
            "complete_marker_count": count_exact_line(
                t2_output, "E13_T2_COMPLETE"
            ),
            "head_marker_match": t2_head_ok,
            "cross_scope_markers_absent": t2_head_ok,
            "explicit_rollback_marker_count": explicit_rollback_count,
            "pre_state_exit_code": pre_exit,
            "post_state_exit_code": post_exit,
            "state_match": state_match,
            "state_command_outputs_match": state_logs_match,
            "rollback_status": rollback_status,
            "status": "PASS" if t2_ok else "FAIL",
        },
        "overall_status": overall_status,
        "capture_invariants": {
            "full_transcript_first_line": "E14_CAPTURE_BEGIN",
            "full_transcript_last_line": "E14_CAPTURE_END",
            "receipt_requires_external_trust_anchor": True,
            "output_directory_created_exclusively": True,
            "receipt_written_once_exclusively": True,
            "legacy_entrypoints_fail_closed": True,
            "database_url_not_persisted": True,
        },
    }
    receipt_bytes = canonical_json_bytes(receipt)
    receipt_path = output_dir / "PR93_E14_RECEIPT.json"
    write_exclusive(receipt_path, receipt_bytes)
    receipt_sha = sha256_bytes(receipt_bytes)
    write_exclusive(
        output_dir / "PR93_E14_RECEIPT.sha256",
        f"{receipt_sha}  PR93_E14_RECEIPT.json\n".encode(),
    )

    print(f"E14_RECEIPT_SHA256={receipt_sha}")
    print(f"E14_OVERALL_STATUS={overall_status}")
    print(f"E14_T2_ROLLBACK_STATUS={rollback_status}")

    if overall_status == "PASS":
        return 0
    if not t1_ok:
        return 10
    if rollback_status == "NOT_VERIFIED":
        return 12
    return 11


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"E14_CAPTURE_FATAL={exc}", file=sys.stderr)
        raise SystemExit(20)
