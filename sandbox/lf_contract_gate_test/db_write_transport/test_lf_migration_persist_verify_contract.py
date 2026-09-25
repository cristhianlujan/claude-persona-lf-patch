#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_db_write_transport.py"

spec = importlib.util.spec_from_file_location("lf_db_write_transport", TARGET)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

d = mod.select_transport("MIGRATION", "supabase/migrations/20260925000000_lf_example_v1.sql")
assert "GIT_SOURCE_DURABLE_READBACK" in d.required_preconditions
assert "APPLY_BEFORE_GIT_SOURCE_READBACK" in d.forbidden
assert "GIT_SUPABASE_DUAL_SURFACE_READBACK" in d.required_postconditions
assert "MIGRATION_PERSIST_VERIFY_CONSISTENT" in d.required_postconditions
print("PASS_MIGRATION_PERSIST_VERIFY_TRANSPORT_CONTRACT")
