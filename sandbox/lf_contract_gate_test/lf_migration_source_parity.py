#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import io
import os
import pathlib
import re
import subprocess
import sys

_MODULE_DIR = pathlib.Path(__file__).resolve().parent
if str(_MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(_MODULE_DIR))

import migration_transport_normalization as transport

MANAGED_PREFIXES = (
    "pr93_",
    "lf_",
    "programacion_story_agent_task_",
    "programacion_task_sizing_",
    "programacion_task_dependency_",
    "programacion_agent_task_",
    "programacion_dependency_context_",
    "programacion_propagate_execution_",
    "programacion_deprecate_declared_independence_",
    "programacion_revoke_security_definer_",
    "programacion_worker_spec_",
    "programacion_prog017_",
)

MANAGED_EXACT_NAMES = {
    "promote_router_compact_jit_v1",
    "promote_card_deterministic_resolvers_safe_subset",
    "promote_card_github_read_resolvers",
    "fix_operation_execution_judge_binding_status_compatibility",
    "harden_operation_execution_views_security_invoker",
    "create_lf_cross_audit_control_plane_v1",
    "index_lf_cross_audit_foreign_keys_v1",
    "fix_operation_step_enforcement_status_compatibility",
    "materialize_router_enforcement_and_gate0_inventory",
    "fix_operation_judge_jsonb_shape_compatibility",
    "reconcile_card_depth_gate_order_v1",
    "fix_card_contract_judge_clean_status_v1",
    "programacion_f05_provenance_channel_v1",
    "programacion_f05_public_rpc_bridge_v1",
    "revoke_internal_pipeline_public_grants",
    "programacion_private_rls_hardening_v1",
    "fix_profile_creator_init_no_close_compat_v1",
    "profile_creator_step_recorder_v1",
    "profile_creator_step_status_contract_fix",
    "router_profile_execution_noncanonical_advisory_readonly",
    "isolate_authenticated_security_definer_rpcs",
    "s28_architecture_alert_dispatcher_fast_exit_v1",
}

CLASSIFIED_EXTERNAL_PREFIXES = (
    "input_governance_",
    "programacion_input_governance_",
    "gov_router_act0001_",
    "router_ui_capability_canary_",
    "router_keyword_verification_canary_",
    "router_generic_keyword_dispatch_",
    "router_generic_tie_break_",
)
CLASSIFIED_EXTERNAL_NAMES = {"retire_b2b_auth005_legacy_totp_screen"}
STRATEGY_MIGRATION_RE = re.compile(r"^s[1-9][0-9]*_[a-z0-9][a-z0-9_]*$")
FILENAME_RE = re.compile(r"^(\d{14})_(.+)\.sql$")
MARKER_RE = re.compile(
    r"^-- LF_MIGRATION_SOURCE_CHECKPOINT_V1 "
    r"cutover=(\d{14}) legacy_start=(\d{14}) legacy_end=(\d{14}) "
    r"legacy_count=(\d+) legacy_sha256=([0-9a-f]{64})$"
)
SHA_PROOF_RE = re.compile(r"^sha256:([0-9a-f]{64})$")
PG_ENV_NAMES = ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE")
POSTGRES_IMAGE = "postgres:17.6"


def managed(name: str) -> bool:
    return (
        name.startswith(MANAGED_PREFIXES)
        or name in MANAGED_EXACT_NAMES
        or STRATEGY_MIGRATION_RE.fullmatch(name) is not None
    )


def classified(name: str) -> bool:
    return managed(name) or name.startswith(CLASSIFIED_EXTERNAL_PREFIXES) or name in CLASSIFIED_EXTERNAL_NAMES


def canonical(sql: str) -> bytes:
    return transport.canonical(sql)


def fail(code: str, detail: str = "") -> None:
    suffix = f": {detail}" if detail else ""
    raise SystemExit(f"{code}{suffix}")


def remote_content_sha256(field: str, version: str) -> str:
    proof = SHA_PROOF_RE.fullmatch(field)
    if proof:
        return proof.group(1)
    if field.startswith("sha256:"):
        fail("FAIL_LF_MIGRATION_LEDGER_SHA_PROOF", f"version={version}")
    try:
        sql = bytes.fromhex(field).decode("utf-8")
    except (ValueError, UnicodeDecodeError) as exc:
        fail("FAIL_LF_MIGRATION_LEDGER_SQL", f"version={version} error={type(exc).__name__}")
    return hashlib.sha256(canonical(sql)).hexdigest()


def read_single_row(path: pathlib.Path, expected_columns: int, code: str) -> list[str]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if len(rows) != 1 or len(rows[0]) != expected_columns:
        fail(code, repr(rows))
    return rows[0]


def _parse_statement_count_rows(text: str, *, source: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in csv.reader(io.StringIO(text)):
        if not row:
            continue
        if len(row) != 2:
            fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_ROW", f"source={source} row={row!r}")
        version, raw_count = row
        if not re.fullmatch(r"20\d{12}", version):
            fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_VERSION", f"source={source} version={version}")
        try:
            count = int(raw_count)
        except ValueError as exc:
            fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_VALUE", f"source={source} version={version} value={raw_count!r}")
            raise AssertionError from exc
        if count < 1:
            fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_VALUE", f"source={source} version={version} value={count}")
        if version in counts:
            fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_DUPLICATE", f"source={source} version={version}")
        counts[version] = count
    return counts


def query_remote_statement_counts(versions: list[str]) -> dict[str, int]:
    if not versions:
        return {}
    if any(not re.fullmatch(r"20\d{12}", version) for version in versions):
        fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_VERSION_SET")
    missing = [name for name in PG_ENV_NAMES if not os.environ.get(name)]
    if missing:
        fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_ENV_MISSING", ",".join(missing))

    pg_array = "{" + ",".join(versions) + "}"
    sql = (
        "select version,coalesce(cardinality(statements),0)::text "
        "from supabase_migrations.schema_migrations "
        f"where version=any('{pg_array}'::text[]) order by version"
    )
    command = ["docker", "run", "--rm"]
    for name in PG_ENV_NAMES:
        command.extend(["-e", name])
    command.extend(
        [
            POSTGRES_IMAGE,
            "psql",
            "-X",
            "-v",
            "ON_ERROR_STOP=1",
            "--csv",
            "-t",
            "-c",
            sql,
        ]
    )
    try:
        proc = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_QUERY", type(exc).__name__)
        raise AssertionError from exc
    if proc.returncode != 0:
        stderr_sha = hashlib.sha256(proc.stderr.encode("utf-8", "replace")).hexdigest()
        fail(
            "FAIL_LF_MIGRATION_STATEMENT_COUNT_QUERY",
            f"exit={proc.returncode} stderr_sha256={stderr_sha}",
        )
    return _parse_statement_count_rows(proc.stdout, source="remote-ledger")


def evaluate_managed_transport(
    local: dict[str, tuple[str, str, str]],
    remote: dict[str, tuple[str, str]],
    statement_counts: dict[str, int],
) -> tuple[int, int, dict[str, transport.Comparison]]:
    if set(statement_counts) != set(remote):
        fail(
            "FAIL_LF_MIGRATION_STATEMENT_COUNT_SET",
            f"missing={sorted(set(remote)-set(statement_counts))} extra={sorted(set(statement_counts)-set(remote))}",
        )

    name_mismatches = [
        version
        for version in sorted(local)
        if local[version][0] != remote[version][0]
    ]
    if name_mismatches:
        fail("FAIL_LF_MIGRATION_NAME_PARITY", repr(name_mismatches))

    comparisons: dict[str, transport.Comparison] = {}
    failures: list[tuple[str, str]] = []
    for version in sorted(local):
        name, source_sha, source_sql = local[version]
        remote_name, remote_sha = remote[version]
        try:
            comparisons[version] = transport.compare_exact_source(
                version=version,
                source_name=name,
                source_sql=source_sql,
                remote_name=remote_name,
                remote_sha256=remote_sha,
                remote_statement_count=statement_counts[version],
            )
        except transport.TransportNormalizationError as exc:
            failures.append((version, str(exc)))
            continue
        if comparisons[version].direct_sha256 != source_sha:
            failures.append((version, "LOCAL_DIRECT_SHA_INTERNAL_MISMATCH"))
    if failures:
        fail("FAIL_LF_MIGRATION_CONTENT_PARITY", repr(failures))

    direct_count = sum(
        item.representation == "DIRECT_SOURCE" for item in comparisons.values()
    )
    cli_count = sum(
        item.representation == "CLI_STATEMENT_STORAGE"
        for item in comparisons.values()
    )
    return direct_count, cli_count, comparisons


def transport_self_test() -> None:
    direct_sql = "select 1;\n"
    direct = transport.compare_exact_source(
        version="20260907010101",
        source_name="lf_transport_selftest_direct",
        source_sql=direct_sql,
        remote_name="lf_transport_selftest_direct",
        remote_sha256=transport.direct_source_hash(direct_sql),
        remote_statement_count=1,
    )
    if direct.representation != "DIRECT_SOURCE":
        fail("FAIL_LF_MIGRATION_TRANSPORT_DIRECT_SELFTEST")

    cli_sql = "-- header\n\nselect 1;\n"
    cli = transport.compare_exact_source(
        version="20260907010102",
        source_name="lf_transport_selftest_cli",
        source_sql=cli_sql,
        remote_name="lf_transport_selftest_cli",
        remote_sha256=transport.cli_statement_storage_hash(cli_sql),
        remote_statement_count=1,
    )
    if cli.representation != "CLI_STATEMENT_STORAGE":
        fail("FAIL_LF_MIGRATION_TRANSPORT_CLI_SELFTEST")

    valid = "select 1;\nselect 2;"
    mutated = "select 1\nselect 2;"
    if transport.cli_statement_storage_hash(valid) != transport.cli_statement_storage_hash(mutated):
        fail("FAIL_LF_MIGRATION_TRANSPORT_COLLISION_FIXTURE")
    try:
        transport.compare_exact_source(
            version="20260907010103",
            source_name="lf_transport_selftest_boundary",
            source_sql=mutated,
            remote_name="lf_transport_selftest_boundary",
            remote_sha256=transport.cli_statement_storage_hash(valid),
            remote_statement_count=2,
        )
    except transport.TransportNormalizationError:
        return
    fail("FAIL_LF_MIGRATION_TRANSPORT_BOUNDARY_SELFTEST")


def main() -> int:
    if len(sys.argv) != 5:
        fail("FAIL_LF_MIGRATION_PARITY_USAGE", "expected migrations remote_csv grandfather_csv legacy_csv")
    migrations = pathlib.Path(sys.argv[1])
    remote_file = pathlib.Path(sys.argv[2])
    grandfather_file = pathlib.Path(sys.argv[3])
    legacy_file = pathlib.Path(sys.argv[4])
    cutover = os.environ["LF_MIGRATION_CUTOVER"]
    classification_baseline_end = os.environ["LF_MIGRATION_CLASSIFICATION_BASELINE_END"]
    grandfathered_count = os.environ["LF_MIGRATION_GRANDFATHERED_COUNT"]
    grandfathered_sha = os.environ["LF_MIGRATION_GRANDFATHERED_SHA256"]

    parser_probe_sql = "select 1;\n"
    parser_probe_sha = hashlib.sha256(canonical(parser_probe_sql)).hexdigest()
    if remote_content_sha256("sha256:" + parser_probe_sha, "SELFTEST") != parser_probe_sha:
        fail("FAIL_CI009_COMPACT_SHA_PARSER_SELFTEST")
    if remote_content_sha256(parser_probe_sql.encode("utf-8").hex(), "SELFTEST") != parser_probe_sha:
        fail("FAIL_CI009_LEGACY_HEX_PARSER_SELFTEST")
    transport_self_test()

    if not managed("promote_router_compact_jit_v1"):
        fail("FAIL_CI009_SELFTEST_MANAGED_EXACT")
    if not managed("create_lf_cross_audit_control_plane_v1"):
        fail("FAIL_CI009_SELFTEST_CROSS_AUDIT_CONTROL_PLANE")
    if not managed("index_lf_cross_audit_foreign_keys_v1"):
        fail("FAIL_CI009_SELFTEST_CROSS_AUDIT_FK_INDEXES")
    if not managed("fix_operation_step_enforcement_status_compatibility"):
        fail("FAIL_CI009_SELFTEST_OPERATION_STEP_ENFORCEMENT_COMPATIBILITY")
    if not managed("materialize_router_enforcement_and_gate0_inventory"):
        fail("FAIL_CI009_SELFTEST_ROUTER_ENFORCEMENT_GATE0_INVENTORY")
    if not managed("fix_operation_judge_jsonb_shape_compatibility"):
        fail("FAIL_CI009_SELFTEST_OPERATION_JUDGE_JSONB_SHAPE_COMPATIBILITY")
    if not managed("reconcile_card_depth_gate_order_v1"):
        fail("FAIL_CI009_SELFTEST_CARD_DEPTH_ORDER_RECONCILIATION")
    if not managed("fix_card_contract_judge_clean_status_v1"):
        fail("FAIL_CI009_SELFTEST_CARD_CONTRACT_JUDGE_CLEAN_STATUS")
    if not managed("programacion_f05_provenance_channel_v1"):
        fail("FAIL_CI009_SELFTEST_F05_PROVENANCE_CHANNEL")
    if not managed("programacion_f05_public_rpc_bridge_v1"):
        fail("FAIL_CI009_SELFTEST_F05_PUBLIC_RPC_BRIDGE")
    if not managed("revoke_internal_pipeline_public_grants"):
        fail("FAIL_CI009_SELFTEST_RLS_INTERNAL_GRANTS")
    if not managed("programacion_private_rls_hardening_v1"):
        fail("FAIL_CI009_SELFTEST_PROGRAMACION_PRIVATE_RLS")
    if not managed("fix_profile_creator_init_no_close_compat_v1"):
        fail("FAIL_CI009_SELFTEST_PROFILE_CREATOR_INIT_COMPAT")
    if not managed("profile_creator_step_recorder_v1"):
        fail("FAIL_CI009_SELFTEST_PROFILE_CREATOR_STEP_RECORDER")
    if not managed("profile_creator_step_status_contract_fix"):
        fail("FAIL_CI009_SELFTEST_PROFILE_CREATOR_STEP_STATUS_CONTRACT")
    if not managed("router_profile_execution_noncanonical_advisory_readonly"):
        fail("FAIL_CI009_SELFTEST_PROFILE_EXECUTION_NONCANONICAL_ADVISORY")
    if not managed("isolate_authenticated_security_definer_rpcs"):
        fail("FAIL_CI009_SELFTEST_RPC_ISOLATION")
    if not managed("s28_architecture_alert_dispatcher_fast_exit_v1"):
        fail("FAIL_CI009_SELFTEST_S28_DISPATCHER_FAST_EXIT")
    if not managed("s26_profile_runtime_readiness_v1"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_S26_FAMILY")
    if not managed("s30_c05_generic_execution_reliability_v1"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_S30_FAMILY")
    if not managed("s31_future_strategy_contract_v1"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_FUTURE_FAMILY")
    if not classified("s30_c05_effect_guard_acl_hardening_v1"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_FAMILY_CLASSIFIED")
    if managed("s0_invalid_strategy"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_ZERO_ACCEPTED")
    if managed("s01_leading_zero_strategy"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_LEADING_ZERO_ACCEPTED")
    if managed("s30-invalid-strategy"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_HYPHEN_ACCEPTED")
    if managed("S30_uppercase_strategy"):
        fail("FAIL_CI009_SELFTEST_STRATEGY_UPPERCASE_ACCEPTED")
    if managed("create_lf_unreviewed_future_change"):
        fail("FAIL_CI009_SELFTEST_MANAGED_PREFIX_TOO_BROAD")
    if not classified("programacion_worker_spec_probe"):
        fail("FAIL_CI009_SELFTEST_MANAGED_WORKER_SPEC")
    if not classified("input_governance_probe"):
        fail("FAIL_CI009_SELFTEST_EXTERNAL_OWNER")
    if classified("totally_unknown_future_migration"):
        fail("FAIL_CI009_SELFTEST_UNKNOWN_ACCEPTED")

    markers: list[tuple[pathlib.Path, re.Match[str]]] = []
    for path in sorted(migrations.glob("*.sql")):
        first = path.read_text(encoding="utf-8").splitlines()[0] if path.stat().st_size else ""
        match = MARKER_RE.fullmatch(first)
        if match:
            markers.append((path, match))
    if len(markers) != 1:
        fail("FAIL_LF_MIGRATION_CHECKPOINT_COUNT", str(len(markers)))
    checkpoint_path, marker = markers[0]
    marker_cutover, _legacy_start, _legacy_end, legacy_count, legacy_sha = marker.groups()
    if marker_cutover != cutover:
        fail("FAIL_LF_MIGRATION_CHECKPOINT_CUTOVER")

    observed_count, observed_sha = read_single_row(legacy_file, 2, "FAIL_LF_MIGRATION_LEGACY_ROW_COUNT")
    if observed_count != legacy_count or observed_sha != legacy_sha:
        fail("FAIL_LF_MIGRATION_LEGACY_ATTESTATION")
    observed_grandfathered_count, observed_grandfathered_sha = read_single_row(
        grandfather_file, 2, "FAIL_LF_MIGRATION_GRANDFATHER_BASELINE_ROW"
    )
    if observed_grandfathered_count != grandfathered_count or observed_grandfathered_sha != grandfathered_sha:
        fail(
            "FAIL_LF_MIGRATION_GRANDFATHER_BASELINE",
            f"expected={grandfathered_count}/{grandfathered_sha} observed={observed_grandfathered_count}/{observed_grandfathered_sha}",
        )

    remote_all: dict[str, tuple[str, str]] = {}
    inline_counts: dict[str, int] = {}
    with remote_file.open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            if len(row) not in (3, 4):
                fail("FAIL_LF_MIGRATION_LEDGER_ROW", repr(row))
            version, name, content_proof = row[:3]
            if version > classification_baseline_end and not classified(name):
                fail("FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION", f"remote={version}_{name}")
            remote_all[version] = (name, content_proof)
            if len(row) == 4 and managed(name):
                try:
                    count = int(row[3])
                except ValueError:
                    fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_VALUE", f"version={version} value={row[3]!r}")
                if count < 1:
                    fail("FAIL_LF_MIGRATION_STATEMENT_COUNT_VALUE", f"version={version} value={count}")
                inline_counts[version] = count

    local: dict[str, tuple[str, str, str]] = {}
    for path in sorted(migrations.glob("*.sql")):
        match = FILENAME_RE.fullmatch(path.name)
        if not match:
            continue
        version, name = match.groups()
        if version <= cutover:
            continue
        if not managed(name):
            if version > classification_baseline_end and not classified(name):
                fail("FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION", f"git={path.name}")
            continue
        source_sql = path.read_text(encoding="utf-8")
        local[version] = (
            name,
            hashlib.sha256(canonical(source_sql)).hexdigest(),
            source_sql,
        )

    remote: dict[str, tuple[str, str]] = {}
    for version, (name, content_proof) in remote_all.items():
        if not managed(name):
            continue
        remote[version] = (name, remote_content_sha256(content_proof, version))

    if set(local) != set(remote):
        fail("FAIL_LF_MIGRATION_VERSION_PARITY", f"git={sorted(local)} remote={sorted(remote)}")

    if inline_counts:
        if set(inline_counts) != set(remote):
            fail(
                "FAIL_LF_MIGRATION_STATEMENT_COUNT_SET",
                f"inline_missing={sorted(set(remote)-set(inline_counts))} inline_extra={sorted(set(inline_counts)-set(remote))}",
            )
        statement_counts = inline_counts
    else:
        counts_file = os.environ.get("LF_MIGRATION_STATEMENT_COUNTS_CSV", "").strip()
        if counts_file:
            statement_counts = _parse_statement_count_rows(
                pathlib.Path(counts_file).read_text(encoding="utf-8"),
                source=counts_file,
            )
        else:
            statement_counts = query_remote_statement_counts(sorted(remote))

    direct_count, cli_count, _comparisons = evaluate_managed_transport(
        local, remote, statement_counts
    )

    print(
        f"PASS_LF_MIGRATION_SOURCE_PARITY: checkpoint={checkpoint_path.name} post_cutover={len(local)} "
        f"legacy={legacy_count} sha256={legacy_sha} grandfathered={grandfathered_count}/{grandfathered_sha} "
        f"classification_baseline_end={classification_baseline_end} direct={direct_count} "
        f"cli_statement_storage={cli_count}"
    )
    print("PASS_LF_MIGRATION_TRANSPORT_SELFTEST=3/3")
    print("PASS_CI009_MIGRATION_CLASSIFICATION_SELFTEST=30/30")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())