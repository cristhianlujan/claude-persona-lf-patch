#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
POLICY = ROOT / "docs/migrations/POLICY_MIGRATION_APPLY_V1.md"

text = POLICY.read_text(encoding="utf-8")
required = (
    "EXACT_VERSION_SOURCE_FIRST",
    "Supabase MCP apply_migration",
    "SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML",
    "SUPABASE_CLI_DB_PUSH_LINKED",
    "gitblob:<exact Git blob SHA>",
    "CI-MIGRATION-SOURCE-PARITY-001",
    "Never retimestamp after apply",
)
lower = text.lower()
assert "apply_migration" in lower
for marker in required[:-1]:
    assert marker in text, marker
assert required[-1].lower() in lower or "never retimestamp after apply" in lower
assert "created_by = 'SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML'" in text
assert "DDL and ledger registration must succeed or roll back together." in text
print("PASS_POLICY_MIGRATION_APPLY_V1")
