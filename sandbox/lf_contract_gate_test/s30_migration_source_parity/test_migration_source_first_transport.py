#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE = Path(__file__).with_name("migration_source_first_transport.py")
spec = importlib.util.spec_from_file_location("migration_source_first_transport", MODULE)
assert spec and spec.loader
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def must_block(fn, code: str) -> None:
    try:
        fn()
    except m.GuardError as exc:
        assert str(exc).startswith(code), (code, str(exc))
    else:
        raise AssertionError(f"expected block {code}")


version, name = m.parse_target("supabase/migrations/20260914194432_s30_guard_v1.sql")
assert version == "20260914194432"
assert name == "s30_guard_v1"
must_block(lambda: m.parse_target("sandbox/20260914194432_s30_guard_v1.sql"), "BLOCK_MIGRATION_TARGET_PATH")

m.validate_source_sql("select 1;\n")
must_block(lambda: m.validate_source_sql("BEGIN;\nselect 1;\nCOMMIT;\n"), "BLOCK_MIGRATION_SOURCE_TRANSACTION_CONTROL")
must_block(lambda: m.validate_source_sql("\\i other.sql\n"), "BLOCK_MIGRATION_SOURCE_PSQL_META_COMMAND")

sha40 = "a" * 40
m.validate_main_binding(sha40, sha40, sha40)
must_block(lambda: m.validate_main_binding(sha40, "b" * 40, sha40), "BLOCK_MIGRATION_CHECKOUT_NOT_EXACT_MAIN")
must_block(lambda: m.validate_main_binding(sha40, sha40, "b" * 40), "BLOCK_MIGRATION_REMOTE_MAIN_MOVED")

m.validate_preapply_shape(local_managed={"1", "2", "3"}, remote_managed={"1", "2"}, target_version="3")
must_block(
    lambda: m.validate_preapply_shape(local_managed={"1", "2", "3"}, remote_managed={"1", "2", "9"}, target_version="3"),
    "BLOCK_MIGRATION_REMOTE_ONLY",
)
must_block(
    lambda: m.validate_preapply_shape(local_managed={"1", "2", "3", "4"}, remote_managed={"1", "2"}, target_version="4"),
    "BLOCK_MIGRATION_PREEXISTING_LOCAL_ONLY",
)

source = "create table if not exists public.s30_transport_selftest(id integer);\n"
source_hash = m.source_sha256(source)
row = {
    "execution_id": "EXEC-S30-TRANSPORT-SELFTEST-001",
    "operation_code": "ACTUALIZACION_DB_LF",
    "target_type": "MIGRATION",
    "target_path": "supabase/migrations/20260914194432_s30_guard_v1.sql",
    "status": "IN_PROGRESS",
    "manifest": {
        "source_first": True,
        "main_merge_sha": sha40,
        "migration_version": "20260914194432",
        "migration_name": "s30_guard_v1",
        "source_sha256": source_hash,
        "exact_version_transport": m.TRANSPORT_CODE,
        "apply_migration_forbidden_for_this_lane": True,
        "source_parity_state": "PREAPPLY_READY",
    },
}
m.validate_execution(
    row,
    execution_id=row["execution_id"],
    path=row["target_path"],
    main_sha=sha40,
    version="20260914194432",
    name="s30_guard_v1",
    sha256=source_hash,
)
bad = {**row, "manifest": {**row["manifest"], "main_merge_sha": "b" * 40}}
must_block(
    lambda: m.validate_execution(
        bad,
        execution_id=row["execution_id"],
        path=row["target_path"],
        main_sha=sha40,
        version="20260914194432",
        name="s30_guard_v1",
        sha256=source_hash,
    ),
    "BLOCK_MIGRATION_EXECUTION_BINDING",
)

rendered = m.render_atomic_sql(
    source=source,
    path=row["target_path"],
    execution_id=row["execution_id"],
    main_sha=sha40,
)
assert rendered.startswith("\\set ON_ERROR_STOP on\nBEGIN;")
assert "pg_advisory_xact_lock" in rendered
assert "ACTUALIZACION_DB_LF" in rendered
assert "APPLIED_PENDING_POSTREADBACK" in rendered
assert "INSERT INTO supabase_migrations.schema_migrations" in rendered
assert rendered.rstrip().endswith("COMMIT;")
print("PASS_S30_MIGRATION_SOURCE_FIRST_TRANSPORT_SELFTEST")
