#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import os
import pathlib
import re
import sys

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
FILENAME_RE = re.compile(r"^(\d{14})_(.+)\.sql$")
MARKER_RE = re.compile(
    r"^-- LF_MIGRATION_SOURCE_CHECKPOINT_V1 "
    r"cutover=(\d{14}) legacy_start=(\d{14}) legacy_end=(\d{14}) "
    r"legacy_count=(\d+) legacy_sha256=([0-9a-f]{64})$"
)


def managed(name: str) -> bool:
    return name.startswith(MANAGED_PREFIXES) or name in MANAGED_EXACT_NAMES


def classified(name: str) -> bool:
    return managed(name) or name.startswith(CLASSIFIED_EXTERNAL_PREFIXES) or name in CLASSIFIED_EXTERNAL_NAMES


def canonical(sql: str) -> bytes:
    sql = sql.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line for line in sql.split("\n") if not line.lstrip().startswith("--")]
    return "\n".join(lines).rstrip("\n").encode("utf-8")


def fail(code: str, detail: str = "") -> None:
    suffix = f": {detail}" if detail else ""
    raise SystemExit(f"{code}{suffix}")


def read_single_row(path: pathlib.Path, expected_columns: int, code: str) -> list[str]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if len(rows) != 1 or len(rows[0]) != expected_columns:
        fail(code, repr(rows))
    return rows[0]


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
        fail("FAIL_CI009_SELFTEST_PROFILE_CREATOR_STEP_STATUS_CONTRACT_FIX")
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
    with remote_file.open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            if len(row) != 3:
                fail("FAIL_LF_MIGRATION_LEDGER_ROW", repr(row))
            version, name, sql_hex = row
            if version > classification_baseline_end and not classified(name):
                fail("FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION", f"remote={version}_{name}")
            remote_all[version] = (name, sql_hex)

    local: dict[str, tuple[str, str]] = {}
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
        local[version] = (name, hashlib.sha256(canonical(path.read_text(encoding="utf-8"))).hexdigest())

    remote: dict[str, tuple[str, str]] = {}
    for version, (name, sql_hex) in remote_all.items():
        if not managed(name):
            continue
        sql = bytes.fromhex(sql_hex).decode("utf-8")
        remote[version] = (name, hashlib.sha256(canonical(sql)).hexdigest())

    if set(local) != set(remote):
        fail("FAIL_LF_MIGRATION_VERSION_PARITY", f"git={sorted(local)} remote={sorted(remote)}")
    mismatches = [version for version in sorted(local) if local[version] != remote[version]]
    if mismatches:
        fail("FAIL_LF_MIGRATION_CONTENT_PARITY", repr(mismatches))

    print(
        f"PASS_LF_MIGRATION_SOURCE_PARITY: checkpoint={checkpoint_path.name} post_cutover={len(local)} "
        f"legacy={legacy_count} sha256={legacy_sha} grandfathered={grandfathered_count}/{grandfathered_sha} "
        f"classification_baseline_end={classification_baseline_end}"
    )
    print("PASS_CI009_MIGRATION_CLASSIFICATION_SELFTEST=19/19")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())