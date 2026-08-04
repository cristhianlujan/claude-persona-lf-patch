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
# CA-N127/N133: the capture entry point resolves every shared helper through
# the module object, so the deployable artifact is exactly what the negative
# matrix exercises; no helper is rebound at import time.
import PR93_LOTE_E14_COMMON as common

# CA-N127/N133: staging directories created exclusively by this process, each
# registered as (path, inode identity). The fail-closed cleanup path only ever
# discards a registered path whose identity still matches, so neither a foreign
# directory nor a substituted inode can be removed by an aborted run.
OWNED_STAGING: list[tuple[Path, tuple[int, int]]] = []


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

    # CA-N142: the unresolved --output-dir argument is inspected first. A
    # resolve() executed before the physical check would follow a symlink and
    # silently publish evidence at the link target, or drop a dangling link
    # from the comparison entirely. Order is therefore: (1) refuse any existing
    # object at the literal argument path, (2) resolve and validate the parent,
    # (3) rebuild the destination as resolved_parent / final_name.
    output_argument = args.output_dir.absolute()
    if os.path.lexists(output_argument):
        raise RuntimeError(
            "output path already exists; evidence capture refuses to replace, "
            "follow or reuse it"
        )
    if output_argument.name in {"", ".", ".."}:
        raise RuntimeError("output directory must have a concrete final name")
    parent = output_argument.parent.resolve()
    if not parent.is_dir() or parent.is_symlink():
        raise RuntimeError("output parent must resolve to a real directory")
    output_dir = parent / output_argument.name
    if os.path.lexists(output_dir):
        raise RuntimeError(
            "resolved output path already exists; evidence capture refuses "
            "overwrite"
        )

    common.assert_repository(repo_root, args.head_sha, args.timeout_seconds)
    if output_dir == repo_root or repo_root in output_dir.parents:
        raise RuntimeError("output directory must be outside the audited repository")

    sources = common.source_inventory(repo_root, args.timeout_seconds)
    sandbox = repo_root / "sandbox/lf_contract_gate_test"

    preflight_exit, preflight_output = common.connectivity_preflight(
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
    # CA-N127: assemble in an exclusive staging directory; the destination path
    # is only ever created by the single atomic rename in common.publish_atomically().
    staging = common.staging_directory(output_dir)
    OWNED_STAGING.append((staging, common.path_identity(staging)))
    started_at = common.utc_now()

    t1_script = sandbox / "PR93_LOTE_E13_T1.psql"
    t2_script = sandbox / "PR93_LOTE_E13_T2.psql"
    state_script = sandbox / "PR93_LOTE_E13_STATE_READBACK.sql"

    t1_exit, t1_output = common.run_psql(
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
        pre_exit, pre_output, pre_state = common.run_state_readback(
            args.psql_bin,
            database_url,
            state_script,
            sandbox,
            args.timeout_seconds,
        )
        if pre_exit == 0:
            t2_exit, t2_output = common.run_psql(
                args.psql_bin,
                database_url,
                t2_script,
                sandbox,
                args.timeout_seconds,
                args.head_sha,
            )
            post_exit, post_output, post_state = common.run_state_readback(
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
    explicit_rollback_count = common.count_exact_line(t2_output, "ROLLBACK")
    if t2_exit == 0 and explicit_rollback_count == 1 and state_match:
        rollback_status = "EXPLICIT"
    elif t2_exit != 0 and explicit_rollback_count == 0 and state_match:
        rollback_status = "IMPLICIT_ON_DISCONNECT"
    else:
        rollback_status = "NOT_VERIFIED"

    t2_head_ok = (
        t2_exit != 99
        and common.count_exact_line(t2_output, f"E13_T2_HEAD_SHA={args.head_sha}") == 1
        and common.count_prefixed_line(t2_output, "E13_T1_HEAD_SHA=") == 0
        and common.count_prefixed_line(t2_output, "E14_HEAD_SHA=") == 0
    )
    state_logs_match = (
        common.json_output_matches(pre_output, pre_state)
        and common.json_output_matches(post_output, post_state)
    )
    t2_ok = (
        t2_exit == 0
        and common.count_exact_line(t2_output, "E13_T2_BEGIN") == 1
        and common.count_exact_line(t2_output, "E13_T2_CONTEXT_GUARD_PASS") == 1
        and common.count_exact_line(t2_output, "E13_T2_COMPLETE") == 1
        and t2_head_ok
        and state_logs_match
        and rollback_status == "EXPLICIT"
    )
    overall_status = "PASS" if t1_ok and t2_ok else "FAIL"

    pre_state_bytes = (
        common.canonical_json_bytes(pre_state) if pre_state is not None else b"null\n"
    )
    post_state_bytes = (
        common.canonical_json_bytes(post_state) if post_state is not None else b"null\n"
    )
    finished_at = common.utc_now()

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
        common.write_exclusive(staging / name, data)

    evidence_files = {
        name: {
            "sha256": common.sha256_bytes(data),
            "size_bytes": len(data),
            "line_count": common.exact_line_count(data),
        }
        for name, data in files.items()
    }

    receipt = {
        "schema_version": common.SCHEMA_VERSION,
        "governance_contract_version": "PR93_E15_V1",
        "repository": common.REPOSITORY,
        "head_sha": args.head_sha,
        "started_at_utc": started_at,
        "finished_at_utc": finished_at,
        "connectivity_preflight": {
            "passed": True,
            "exit_code": preflight_exit,
            "output_sha256": common.sha256_bytes(preflight_output),
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
            "context_guard_pass_marker_count": common.count_exact_line(
                t2_output, "E13_T2_CONTEXT_GUARD_PASS"
            ),
            "complete_marker_count": common.count_exact_line(
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
        # Preventive control 7: these are capture-side declarations, not
        # measurements. They are labelled as such so no downstream reader
        # mistakes them for observed evidence.
        "capture_invariants": {
            "declaration_kind": "SELF_ASSERTED_NOT_MEASURED",
            "bundle_published_by_atomic_rename": True,
            "full_transcript_first_line": "E14_CAPTURE_BEGIN",
            "full_transcript_last_line": "E14_CAPTURE_END",
            "receipt_requires_external_trust_anchor": True,
            "output_directory_created_exclusively": True,
            "receipt_written_once_exclusively": True,
            "legacy_entrypoints_fail_closed": True,
            "database_url_not_persisted": True,
        },
    }
    receipt_bytes = common.canonical_json_bytes(receipt)
    common.write_exclusive(staging / "PR93_E14_RECEIPT.json", receipt_bytes)
    receipt_sha = common.sha256_bytes(receipt_bytes)
    common.write_exclusive(
        staging / "PR93_E14_RECEIPT.sha256",
        f"{receipt_sha}  PR93_E14_RECEIPT.json\n".encode(),
    )
    # CA-N135: publication and parent-directory durability both complete before
    # the external trust anchor below is printed. Any earlier failure raises and
    # the anchor is never emitted.
    common.publish_atomically(staging, output_dir)
    OWNED_STAGING.clear()

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


def _discard_owned_staging() -> None:
    # CA-N127: an aborted run must leave no partial bundle anywhere. Only
    # staging paths this process created exclusively are ever removed.
    while OWNED_STAGING:
        path, identity = OWNED_STAGING.pop()
        if not common.discard_staging(path, identity):
            print(
                f"E14_CAPTURE_CLEANUP_NOT_CONFIRMED={path}",
                file=sys.stderr,
            )


if __name__ == "__main__":
    try:
        code = main()
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        _discard_owned_staging()
        print(f"E14_CAPTURE_FATAL={exc}", file=sys.stderr)
        raise SystemExit(20)
    except BaseException:
        _discard_owned_staging()
        raise
    _discard_owned_staging()
    raise SystemExit(code)
