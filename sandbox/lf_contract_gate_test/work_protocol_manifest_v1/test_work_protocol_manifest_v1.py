#!/usr/bin/env python3
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "gobernanza/contratos/work_protocol_manifest_v1.md"
SCHEMA = ROOT / "gobernanza/contratos/work_protocol_manifest_v1.schema.json"
SQL = Path(__file__).with_name("candidate_work_protocol_manifest_v1.sql")
CODE = "WORK_PROTOCOL_V1_DEPRECATED_DO_NOT_USE"

contract = CONTRACT.read_text(encoding="utf-8")
schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
sql = SQL.read_text(encoding="utf-8")

assert "DEPRECATED" in contract
assert CODE in contract
assert schema.get("not") == {}
assert CODE in schema.get("description", "")
assert CODE in sql
assert "RAISE EXCEPTION" in sql

print(json.dumps({"status": "PASS", "assertion": "WORK_PROTOCOL_V1_DEPRECATED", "blocking_code": CODE}, sort_keys=True))
