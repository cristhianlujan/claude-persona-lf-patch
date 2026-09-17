#!/usr/bin/env python3
import importlib.util
from pathlib import Path

path = Path(__file__).with_name("qualify_wf_diagnostic_claim_v1.py")
spec = importlib.util.spec_from_file_location("claim_qualifier", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

assert module.REQUIRED_CLOSURE == {
    "test_identity",
    "assertion_or_error",
    "expected_actual",
    "durable_artifact",
    "correlation",
    "owner_repair_resume",
}
assert len(module.REQUIRED_OBLIGATIONS) == 6
assert len(module.REQUIRED_DEFEATERS) == 4

sql = module.CATALOG_SQL.lower()
assert "insert into" not in sql
assert "update " not in sql
assert "delete " not in sql
print("WF_DIAGNOSTIC_CLAIM_QUALIFIER_SELFTEST_PASS")
