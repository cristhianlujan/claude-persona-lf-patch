#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ADAPTER = ROOT / "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
SOURCE = ROOT / "supabase/migrations/20260930133539_evidence_ledger_crossbind_hardening_v1.sql"
VERSION = "20260930133539"
NAME = "evidence_ledger_crossbind_hardening_v1"
EXPECTED_LEDGER_STATEMENT_SHA256 = "7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a"
OWNER_EXECUTION = "EXEC-DB-SOURCE-RECONCILE-EVIDENCE-133539-20260930-001"

spec = importlib.util.spec_from_file_location("lf_migration_source_parity_reconcile_check", ADAPTER)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

sql = SOURCE.read_text(encoding="utf-8")
assert mod.reconciliation_source_metadata(sql, version=VERSION, name=NAME)
payload = mod._reconciliation_payload_for_parity(version=VERSION, name=NAME, source_sql=sql)
assert hashlib.sha256(payload.encode("utf-8")).hexdigest() == EXPECTED_LEDGER_STATEMENT_SHA256
assert f"reconciliation_owner_execution_id={OWNER_EXECUTION}" in sql
assert "reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY" in sql
assert "source_authority=supabase_migrations.schema_migrations" in sql
assert "ddl_replayed" not in payload.lower()
print("EVIDENCE_LEDGER_CROSSBIND_SOURCE_RECONCILIATION_V1=PASS exact_ledger_payload=true ddl_replayed=false")
