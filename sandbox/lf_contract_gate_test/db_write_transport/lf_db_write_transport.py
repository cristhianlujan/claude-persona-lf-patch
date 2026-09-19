#!/usr/bin/env python3
"""Deterministic selector for LF database-write transport.

This module selects the transport lane only. It does not grant authority and it
never performs database writes by itself.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass

CAPABILITY_CODE = "DB_WRITE_TRANSPORT"
MIGRATION_MODE = "EXACT_VERSION_SOURCE_FIRST"
DIRECT_MODE = "SUPABASE_MCP"
MIGRATION_PRIMARY = "SUPABASE_CLI_DB_PUSH_LINKED"
MIGRATION_FALLBACK = "SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML"
FILENAME_RE = re.compile(r"^(?P<version>\d{14})_(?P<name>[a-zA-Z0-9][a-zA-Z0-9_]*)\.sql$")
DIRECT_TYPES = {"DB", "FUNCTION", "TRIGGER"}
MIGRATION_ALLOWED_EXECUTORS = {MIGRATION_PRIMARY, MIGRATION_FALLBACK}
RECONCILIATION_SCHEMA = "lf-db-applied-source-reconciliation/v1"
RECONCILIATION_EFFECT_PREFIX = "SUPABASE_MIGRATION_RECONCILIATION:"


@dataclass(frozen=True)
class Decision:
    capability_code: str
    target_type: str
    mode: str
    executor: str
    fallback_executor: str | None
    migration_version: str | None
    migration_name: str | None
    fail_closed: bool
    forbidden: tuple[str, ...]
    required_preconditions: tuple[str, ...]
    required_postconditions: tuple[str, ...]


def select_transport(target_type: str, migration_path: str | None = None) -> Decision:
    target = (target_type or "").strip().upper()
    if target == "MIGRATION":
        if not migration_path:
            raise ValueError("MIGRATION_PATH_REQUIRED")
        filename = migration_path.replace("\\", "/").rsplit("/", 1)[-1]
        match = FILENAME_RE.fullmatch(filename)
        if not match:
            raise ValueError("MIGRATION_FILENAME_MUST_BE_TIMESTAMPED_SQL")
        return Decision(
            capability_code=CAPABILITY_CODE,
            target_type=target,
            mode=MIGRATION_MODE,
            executor=MIGRATION_PRIMARY,
            fallback_executor=MIGRATION_FALLBACK,
            migration_version=match.group("version"),
            migration_name=match.group("name"),
            fail_closed=True,
            forbidden=(
                "SUPABASE_MCP_APPLY_MIGRATION_WHEN_EXACT_VERSION_REQUIRED",
                "SERVER_SIDE_TIMESTAMP_REMINT",
                "POST_APPLY_RENAME_AS_NORMAL_FLOW",
                "MIGRATION_PARITY_BYPASS",
                "WRITE_BEFORE_TRANSPORT_SELECTION",
            ),
            required_preconditions=(
                "ROUTER_BINDING_ACTUALIZACION_DB_LF",
                "DB_WRITE_TRANSPORT_DECISION",
                "EKB_READBACK",
                "EXACT_SOURCE_PATH_BOUND",
                "MIGRATION_SOURCE_PARITY_PRECHECK",
                "ROLLBACK_OR_FAIL_FORWARD_PLAN",
            ),
            required_postconditions=(
                "EXACT_LEDGER_VERSION_NAME_READBACK",
                "MIGRATION_SOURCE_PARITY_RETEST",
                "EXACT_HEAD_CI_PASS",
                "EKB_CLOSEOUT",
            ),
        )
    if target in DIRECT_TYPES:
        return Decision(
            capability_code=CAPABILITY_CODE,
            target_type=target,
            mode="DIRECT_DB_WRITE",
            executor=DIRECT_MODE,
            fallback_executor=None,
            migration_version=None,
            migration_name=None,
            fail_closed=True,
            forbidden=("UNSCOPED_DDL", "WRITE_WITHOUT_EXACT_TARGET", "WRITE_WITHOUT_READBACK", "WRITE_BEFORE_TRANSPORT_SELECTION"),
            required_preconditions=("ROUTER_BINDING_ACTUALIZACION_DB_LF", "DB_WRITE_TRANSPORT_DECISION", "EKB_READBACK", "EXACT_TARGET_BOUND"),
            required_postconditions=("EXACT_TARGET_READBACK", "REGRESSION_OR_PARITY_RETEST", "EKB_CLOSEOUT"),
        )
    raise ValueError(f"UNSUPPORTED_TARGET_TYPE:{target or 'EMPTY'}")


def validate_requested_executor(decision: Decision, requested_executor: str) -> str:
    requested = (requested_executor or "").strip().upper()
    if not requested:
        raise ValueError("REQUESTED_EXECUTOR_REQUIRED")
    allowed = MIGRATION_ALLOWED_EXECUTORS if decision.target_type == "MIGRATION" else {DIRECT_MODE}
    if requested not in allowed:
        raise ValueError(
            "BLOCK_DB_WRITE_TRANSPORT_EXECUTOR_NOT_ALLOWED:"
            f"target_type={decision.target_type}:requested={requested}:"
            f"allowed={','.join(sorted(allowed))}"
        )
    return requested


def classify_migration_runtime_state(
    ledger_present: bool,
    original_receipt_exact: bool,
    reconciliation_receipt_exact: bool,
) -> str:
    if not ledger_present:
        return "UNAPPLIED"
    if original_receipt_exact:
        return "APPLIED_EXACT"
    if reconciliation_receipt_exact:
        return "APPLIED_RECONCILED"
    return "APPLIED_UNVERIFIED"


def reconciliation_effect_scope(migration_version: str) -> str:
    if not re.fullmatch(r"\d{14}", migration_version or ""):
        raise ValueError("RECONCILIATION_MIGRATION_VERSION_INVALID")
    return RECONCILIATION_EFFECT_PREFIX + migration_version


def self_test() -> None:
    m = select_transport("MIGRATION", "supabase/migrations/20260917191749_lf_example_v1.sql")
    assert m.mode == MIGRATION_MODE
    assert m.executor == MIGRATION_PRIMARY
    assert m.migration_version == "20260917191749"
    assert m.migration_name == "lf_example_v1"
    assert validate_requested_executor(m, MIGRATION_PRIMARY) == MIGRATION_PRIMARY
    assert validate_requested_executor(m, MIGRATION_FALLBACK) == MIGRATION_FALLBACK
    for forbidden_executor in ("SUPABASE_MCP", "APPLY_MIGRATION", "MANAGEMENT_API"):
        try:
            validate_requested_executor(m, forbidden_executor)
        except ValueError as exc:
            assert str(exc).startswith("BLOCK_DB_WRITE_TRANSPORT_EXECUTOR_NOT_ALLOWED")
        else:
            raise AssertionError(f"forbidden migration executor accepted: {forbidden_executor}")
    assert classify_migration_runtime_state(False, False, False) == "UNAPPLIED"
    assert classify_migration_runtime_state(True, True, False) == "APPLIED_EXACT"
    assert classify_migration_runtime_state(True, False, True) == "APPLIED_RECONCILED"
    assert classify_migration_runtime_state(True, False, False) == "APPLIED_UNVERIFIED"
    assert reconciliation_effect_scope("20260917191749") == "SUPABASE_MIGRATION_RECONCILIATION:20260917191749"
    for target in sorted(DIRECT_TYPES):
        d = select_transport(target)
        assert d.executor == DIRECT_MODE
        assert d.mode == "DIRECT_DB_WRITE"
        assert validate_requested_executor(d, DIRECT_MODE) == DIRECT_MODE
    for bad in ("lf_missing_timestamp.sql", "20260917_short.sql", "20260917191749_bad-name.sql"):
        try:
            select_transport("MIGRATION", bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"bad migration filename accepted: {bad}")
    try:
        select_transport("MIGRATION")
    except ValueError as exc:
        assert str(exc) == "MIGRATION_PATH_REQUIRED"
    else:
        raise AssertionError("missing migration path accepted")
    try:
        select_transport("TABLE")
    except ValueError as exc:
        assert str(exc).startswith("UNSUPPORTED_TARGET_TYPE")
    else:
        raise AssertionError("unsupported target accepted")
    print("PASS_DB_WRITE_TRANSPORT_SELFTEST")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-type")
    parser.add_argument("--migration-path")
    parser.add_argument("--requested-executor")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.target_type:
        parser.error("--target-type is required unless --self-test is used")
    decision = select_transport(args.target_type, args.migration_path)
    output = asdict(decision)
    if args.requested_executor:
        output["requested_executor"] = validate_requested_executor(decision, args.requested_executor)
        output["executor_validation"] = "PASS"
    print(json.dumps(output, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
