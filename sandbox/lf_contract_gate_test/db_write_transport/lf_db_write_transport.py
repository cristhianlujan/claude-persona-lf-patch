#!/usr/bin/env python3
"""Deterministic selector for LF database-write transport (v2.2).

Agents resolve through ACT-0001, then route database changes through the LF
Migration Merge Train. The Train reserves, records, and closes the current
ACTUALIZACION_DB_LF execution. Applied migrations are immutable; repairs use a
new fail-forward migration through the Train.
This module grants no authority and never writes to the database by itself.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass

CAPABILITY_CODE = "DB_WRITE_TRANSPORT"
CAPABILITY_VERSION = "2.2.0"
MIGRATION_MODE = "EXACT_VERSION_SOURCE_FIRST"
# Train-internal executors (used only inside the LF Migration Merge Train).
MIGRATION_PRIMARY = "SUPABASE_CLI_DB_PUSH_LINKED"
FILENAME_RE = re.compile(r"^(?P<version>\d{14})_(?P<name>[a-zA-Z0-9][a-zA-Z0-9_]*)\.sql$")

# Agent-facing route.
ROUTER_AUTHORITY = "ACT-0001"
ROUTER_OPERATION = "ACTUALIZACION_DB_LF"
AGENT_ROUTE_REDIRECT = "REDIRECT_TO_ROUTER"
AGENT_ROUTE_TRAIN = "MIGRATION_VIA_MERGE_TRAIN"
AGENT_EXECUTOR = "LF_MIGRATION_MERGE_TRAIN"
AGENT_TARGET_TYPES = {"MIGRATION", "DB", "FUNCTION", "TRIGGER", "CAPABILITY"}
EXECUTION_ID_RE = re.compile(r"^EXEC-[A-Z0-9][A-Z0-9_-]*$")
AGENT_FORBIDDEN = (
    "SUPABASE_MCP_APPLY_MIGRATION",
    "SUPABASE_MCP_EXECUTE_SQL_DDL_OR_MIGRATION_DML",
    "SUPABASE_CLI_DB_PUSH_BY_AGENT",
    "SUPABASE_SQL_EDITOR_SCHEMA_CHANGE",
    "PSQL_DIRECT_SCHEMA_CHANGE",
    "MANUAL_SCHEMA_MIGRATIONS_LEDGER_DML",
    "DB_WRITE_WITHOUT_ROUTER_EXECUTION",
    "UNCLASSIFIED_MIGRATION_NAME",
)
TRAIN_STEPS = (
    "WRITE_CHANGE_AS_ONE_MIGRATION_FILE_IN_SUPABASE_MIGRATIONS",
    "ONE_MIGRATION_PER_PR",
    "NAME_PER_POL_LF_MIGRATION_NAMING",
    "VERSION_IS_ASSIGNED_OR_REASSIGNED_BY_TRAIN",
    "OPEN_PR_NOT_DRAFT",
    "REQUIRED_CHECKS_GREEN_ON_EXACT_HEAD",
    "ONE_TRAIN_AT_A_TIME_NO_OTHER_READY_TO_MERGE_IN_FLIGHT",
    "LABEL_READY_TO_MERGE",
    "MERGE_TRAIN_APPLIES_AND_MERGES",
    "LEDGER_AND_MAIN_READBACK",
)
ON_DENIED = "READ_ONLY_OR_PERMISSION_DENIAL_IS_INTENTIONAL_DO_NOT_SEEK_ANOTHER_ROUTE_USE_MERGE_TRAIN"
EXECUTION_REQUEST = "NONE_TRAIN_RESERVES_AND_CLOSES_EXECUTION"
PREVENTION_RULES = (
    "PRV-CI-009",
    "PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001",
    "PRV-SQL-001",
    "PRV-SQL-007",
    "PRV-SQL-012",
    "PRV-RTE-006",
)


@dataclass(frozen=True)
class Decision:
    capability_code: str
    target_type: str
    mode: str
    executor: str
    fallback_executor: str | None
    migration_version: str | None
    migration_name: str | None
    route: str
    migration_change_status: str | None
    fail_closed: bool
    forbidden: tuple[str, ...]
    required_preconditions: tuple[str, ...]
    required_postconditions: tuple[str, ...]


@dataclass(frozen=True)
class AgentRoute:
    capability_code: str
    capability_version: str
    target_type: str
    route: str
    executor: str | None
    router_authority: str
    router_operation: str
    router_execution_id: str | None
    migration_version: str | None
    migration_name: str | None
    migration_change_status: str | None
    fail_closed: bool
    steps: tuple[str, ...]
    forbidden: tuple[str, ...]
    policies: tuple[str, ...]
    on_denied: str
    execution_request: str | None
    prevention_rules: tuple[str, ...]


MIGRATION_CHANGE_STATUSES = {"added", "modified", "renamed", "deleted"}


def _applied_migration_blocked(change_status: str | None, present_in_main: bool, present_in_ledger: bool) -> bool:
    if change_status is not None and change_status not in MIGRATION_CHANGE_STATUSES:
        raise ValueError(f"INVALID_MIGRATION_CHANGE_STATUS:{change_status}")
    # An "added" path is new only if it is absent from both main and the ledger.
    return present_in_main or present_in_ledger


def select_route(
    target_type: str,
    migration_path: str | None = None,
    router_execution_id: str | None = None,
    router_operation: str | None = None,
    migration_change_status: str | None = None,
    migration_present_in_main: bool = False,
    migration_present_in_ledger: bool = False,
) -> AgentRoute:
    """Agent-facing route. Router first, then the LF Migration Merge Train."""
    target = (target_type or "").strip().upper()
    if target not in AGENT_TARGET_TYPES:
        raise ValueError(f"UNSUPPORTED_TARGET_TYPE:{target or 'EMPTY'}")
    version = name = None
    if target == "MIGRATION":
        if not migration_path:
            raise ValueError("MIGRATION_PATH_REQUIRED")
        filename = migration_path.replace("\\", "/").rsplit("/", 1)[-1]
        match = FILENAME_RE.fullmatch(filename)
        if not match:
            raise ValueError("MIGRATION_FILENAME_MUST_BE_TIMESTAMPED_SQL")
        version, name = match.group("version"), match.group("name")
        if _applied_migration_blocked(migration_change_status, migration_present_in_main, migration_present_in_ledger):
            return AgentRoute(
                capability_code=CAPABILITY_CODE,
                capability_version=CAPABILITY_VERSION,
                target_type=target,
                route="BLOCK_APPLIED_MIGRATION_IMMUTABLE",
                executor=None,
                router_authority=ROUTER_AUTHORITY,
                router_operation=ROUTER_OPERATION,
                router_execution_id=None,
                migration_version=version,
                migration_name=name,
                migration_change_status=migration_change_status,
                fail_closed=True,
                steps=("NEW_MIGRATION_FAIL_FORWARD_VIA_MERGE_TRAIN",),
                forbidden=AGENT_FORBIDDEN,
                policies=("POL-LF-MIGRATION-NAMING",),
                on_denied=ON_DENIED,
                execution_request=None,
                prevention_rules=PREVENTION_RULES,
            )
    execution = (router_execution_id or "").strip()
    has_execution = EXECUTION_ID_RE.fullmatch(execution) is not None
    resolved = (router_operation or "").strip().upper() == ROUTER_OPERATION
    if not has_execution and not resolved:
        return AgentRoute(
            capability_code=CAPABILITY_CODE,
            capability_version=CAPABILITY_VERSION,
            target_type=target,
            route=AGENT_ROUTE_REDIRECT,
            executor=None,
            router_authority=ROUTER_AUTHORITY,
            router_operation=ROUTER_OPERATION,
            router_execution_id=None,
            migration_version=version,
            migration_name=name,
            migration_change_status=migration_change_status,
            fail_closed=True,
            steps=(
                "RESOLVE_ROUTE_VIA_ACT_0001_LF_ROUTER_RESOLVE_V1",
                "READ_POLICY_SNAPSHOT_V_LF_OPERATION_POLICY_SNAPSHOT",
                "RETRY_SELECT_ROUTE_WITH_ROUTER_OPERATION_OR_EXECUTION_ID",
            ),
            forbidden=AGENT_FORBIDDEN,
            policies=(),
            on_denied=ON_DENIED,
            execution_request=None,
            prevention_rules=PREVENTION_RULES,
        )
    return AgentRoute(
        capability_code=CAPABILITY_CODE,
        capability_version=CAPABILITY_VERSION,
        target_type=target,
        route=AGENT_ROUTE_TRAIN,
        executor=AGENT_EXECUTOR,
        router_authority=ROUTER_AUTHORITY,
        router_operation=ROUTER_OPERATION,
        router_execution_id=execution if has_execution else None,
        migration_version=version,
        migration_name=name,
        migration_change_status=migration_change_status,
        fail_closed=True,
        steps=TRAIN_STEPS,
        forbidden=AGENT_FORBIDDEN,
        policies=("POL-LF-MIGRATION-NAMING",),
        on_denied=ON_DENIED,
        execution_request=None if has_execution else EXECUTION_REQUEST,
        prevention_rules=PREVENTION_RULES,
    )


def select_transport(
    target_type: str,
    migration_path: str | None = None,
    migration_change_status: str | None = None,
    migration_present_in_main: bool = False,
    migration_present_in_ledger: bool = False,
) -> Decision:
    """Train-internal transport; applied migration edits fail closed."""
    target = (target_type or "").strip().upper()
    if target == "MIGRATION":
        if not migration_path:
            raise ValueError("MIGRATION_PATH_REQUIRED")
        filename = migration_path.replace("\\", "/").rsplit("/", 1)[-1]
        match = FILENAME_RE.fullmatch(filename)
        if not match:
            raise ValueError("MIGRATION_FILENAME_MUST_BE_TIMESTAMPED_SQL")
        version, name = match.group("version"), match.group("name")
        if _applied_migration_blocked(migration_change_status, migration_present_in_main, migration_present_in_ledger):
            return Decision(
                capability_code=CAPABILITY_CODE,
                target_type=target,
                mode="BLOCK_APPLIED_MIGRATION_IMMUTABLE",
                executor="NONE",
                fallback_executor=None,
                migration_version=version,
                migration_name=name,
                route="NEW_MIGRATION_FAIL_FORWARD_VIA_MERGE_TRAIN",
                migration_change_status=migration_change_status,
                fail_closed=True,
                forbidden=("EDIT_RENAME_OR_DELETE_APPLIED_MIGRATION",),
                required_preconditions=("LEDGER_AND_MAIN_READBACK",),
                required_postconditions=("NEW_MIGRATION_FAIL_FORWARD_VIA_MERGE_TRAIN",),
            )
        return Decision(
            capability_code=CAPABILITY_CODE,
            target_type=target,
            mode=MIGRATION_MODE,
            executor=MIGRATION_PRIMARY,
            fallback_executor=None,
            migration_version=version,
            migration_name=name,
            route=AGENT_ROUTE_TRAIN,
            migration_change_status=migration_change_status,
            fail_closed=True,
            forbidden=(
                "SUPABASE_MCP_APPLY_MIGRATION",
                "MANUAL_LEDGER_DML",
                "DIRECT_MIGRATION_EXECUTOR_OUTSIDE_MERGE_TRAIN",
                "EDIT_RENAME_OR_DELETE_APPLIED_MIGRATION",
                "SERVER_SIDE_TIMESTAMP_REMINT",
                "POST_APPLY_RENAME_AS_NORMAL_FLOW",
                "MIGRATION_PARITY_BYPASS",
                "DB_APPLY_BEFORE_GIT_SOURCE_READBACK",
                "PASS_WITHOUT_MIGRATION_SAGA_CONSISTENT",
            ),
            required_preconditions=(
                "ROUTER_BINDING_ACTUALIZACION_DB_LF",
                "EKB_READBACK",
                "EXACT_SOURCE_PATH_BOUND",
                "GIT_SOURCE_PERSISTED_EXACT_HEAD",
                "GIT_SOURCE_READBACK",
                "MIGRATION_ORCHESTRATED_SAGA_READY_TO_APPLY",
                "MIGRATION_SOURCE_PARITY_PRECHECK",
                "ROLLBACK_OR_FAIL_FORWARD_PLAN",
            ),
            required_postconditions=(
                "EXACT_LEDGER_VERSION_NAME_READBACK",
                "MIGRATION_SOURCE_PARITY_RETEST",
                "MIGRATION_ORCHESTRATED_SAGA_CONSISTENT",
                "EXACT_HEAD_CI_PASS",
                "EKB_CLOSEOUT",
            ),
        )
    if target in {"DB", "FUNCTION", "TRIGGER", "CAPABILITY"}:
        raise ValueError(f"DIRECT_DB_WRITE_RETIRED_USE_ROUTER_AND_MERGE_TRAIN:{target}")
    raise ValueError(f"UNSUPPORTED_TARGET_TYPE:{target or 'EMPTY'}")


def self_test() -> None:
    m = select_transport("MIGRATION", "supabase/migrations/20260917191749_lf_example_v1.sql")
    assert m.mode == MIGRATION_MODE
    assert m.executor == MIGRATION_PRIMARY
    assert m.fallback_executor is None
    assert m.route == AGENT_ROUTE_TRAIN
    assert "SUPABASE_MCP_APPLY_MIGRATION" in m.forbidden
    assert "MANUAL_LEDGER_DML" in m.forbidden
    assert m.migration_version == "20260917191749"
    assert m.migration_name == "lf_example_v1"
    assert "GIT_SOURCE_PERSISTED_EXACT_HEAD" in m.required_preconditions
    assert "MIGRATION_ORCHESTRATED_SAGA_READY_TO_APPLY" in m.required_preconditions
    assert "MIGRATION_ORCHESTRATED_SAGA_CONSISTENT" in m.required_postconditions
    assert "PASS_WITHOUT_MIGRATION_SAGA_CONSISTENT" in m.forbidden
    for target in ("DB", "FUNCTION", "TRIGGER", "CAPABILITY"):
        try:
            select_transport(target)
        except ValueError as exc:
            assert str(exc).startswith("DIRECT_DB_WRITE_RETIRED_USE_ROUTER_AND_MERGE_TRAIN")
        else:
            raise AssertionError(f"direct transport still available: {target}")
    # Agent route: no Router execution -> redirect to Router.
    for target in sorted(AGENT_TARGET_TYPES):
        path = "supabase/migrations/20260917191749_lf_example_v1.sql" if target == "MIGRATION" else None
        for missing in (None, "", "UNKNOWN", "exec-lowercase", "N13-PAULO178-CLOSE"):
            r = select_route(target, path, missing)
            assert r.route == AGENT_ROUTE_REDIRECT, (target, missing)
            assert r.executor is None
            assert r.router_operation == ROUTER_OPERATION
        # Agent route with Router execution -> Merge Train only.
        r = select_route(target, path, "EXEC-DB-EXAMPLE-20261012-001")
        assert r.route == AGENT_ROUTE_TRAIN
        assert r.executor == AGENT_EXECUTOR
        assert "LABEL_READY_TO_MERGE" in r.steps
        assert "SUPABASE_MCP_APPLY_MIGRATION" in r.forbidden
        assert "SUPABASE_CLI_DB_PUSH_BY_AGENT" in r.forbidden
        assert r.executor not in (MIGRATION_PRIMARY, "SUPABASE_MCP")
    # Router resolution without execution -> Train route plus execution request.
    r = select_route("FUNCTION", None, None, "ACTUALIZACION_DB_LF")
    assert r.route == AGENT_ROUTE_TRAIN and r.router_execution_id is None
    assert r.execution_request == "NONE_TRAIN_RESERVES_AND_CLOSES_EXECUTION"
    assert "OWNER" not in r.execution_request
    assert "OPEN_PR_NOT_DRAFT" in r.steps and "ONE_TRAIN_AT_A_TIME_NO_OTHER_READY_TO_MERGE_IN_FLIGHT" in r.steps
    assert r.on_denied == ON_DENIED and "PRV-CI-009" in r.prevention_rules
    applied_edit = select_route("MIGRATION", "supabase/migrations/20260917191749_lf_example_v1.sql",
                                None, "ACTUALIZACION_DB_LF", "modified", True, False)
    assert applied_edit.route == "BLOCK_APPLIED_MIGRATION_IMMUTABLE"
    assert applied_edit.steps == ("NEW_MIGRATION_FAIL_FORWARD_VIA_MERGE_TRAIN",)
    applied_rename = select_route("MIGRATION", "supabase/migrations/20260917191750_lf_example_v1.sql",
                                  None, "ACTUALIZACION_DB_LF", "renamed", False, True)
    assert applied_rename.route == "BLOCK_APPLIED_MIGRATION_IMMUTABLE"
    added = select_route("MIGRATION", "supabase/migrations/20260917191751_lf_new_v1.sql",
                         None, "ACTUALIZACION_DB_LF", "added")
    assert added.route == AGENT_ROUTE_TRAIN
    assert select_transport("MIGRATION", "20260917191749_lf_example_v1.sql",
                            "modified", True, False).mode == "BLOCK_APPLIED_MIGRATION_IMMUTABLE"
    added_transport = select_transport("MIGRATION", "20260917191751_lf_new_v1.sql", "added")
    assert added_transport.mode == MIGRATION_MODE and added_transport.route == AGENT_ROUTE_TRAIN
    for wrong in ("ACTUALIZACION_PERFIL_LF", "", None):
        assert select_route("FUNCTION", None, None, wrong).route == AGENT_ROUTE_REDIRECT
    r = select_route("FUNCTION", None, "EXEC-X-1", None)
    assert r.execution_request is None
    r = select_route("MIGRATION", "supabase/migrations/20260917191749_lf_example_v1.sql", "EXEC-X-1")
    assert (r.migration_version, r.migration_name) == ("20260917191749", "lf_example_v1")
    try:
        select_route("MIGRATION", None, "EXEC-X-1")
    except ValueError as exc:
        assert str(exc) == "MIGRATION_PATH_REQUIRED"
    else:
        raise AssertionError("agent migration route without path accepted")
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
    for fn in (select_transport, select_route):
        try:
            fn("TABLE")
        except ValueError as exc:
            assert str(exc).startswith("UNSUPPORTED_TARGET_TYPE")
        else:
            raise AssertionError("unsupported target accepted")
    print("PASS_DB_WRITE_TRANSPORT_SELFTEST")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-type")
    parser.add_argument("--migration-path")
    parser.add_argument("--router-execution-id")
    parser.add_argument("--router-operation", help="operation_code returned by lf_router_resolve_v1")
    parser.add_argument("--migration-change-status", choices=sorted(MIGRATION_CHANGE_STATUSES))
    parser.add_argument("--migration-present-in-main", action="store_true")
    parser.add_argument("--migration-present-in-ledger", action="store_true")
    parser.add_argument(
        "--train-internal",
        action="store_true",
        help="Merge Train only: print the internal executor decision for an admitted migration.",
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.target_type:
        parser.error("--target-type is required unless --self-test is used")
    if args.train_internal:
        decision = select_transport(args.target_type, args.migration_path, args.migration_change_status,
                                    args.migration_present_in_main, args.migration_present_in_ledger)
        print(json.dumps(asdict(decision), sort_keys=True, separators=(",", ":")))
        return 0
    route = select_route(args.target_type, args.migration_path, args.router_execution_id, args.router_operation,
                         args.migration_change_status, args.migration_present_in_main,
                         args.migration_present_in_ledger)
    print(json.dumps(asdict(route), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
