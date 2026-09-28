#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import contract_resolution_carrier_v1 as carrier


def row(code: str, *, op: str = "OP_ALPHA", status: str = "ACTIVE_ENFORCEMENT") -> dict:
    return {
        "operation_code": op,
        "contract_code": code,
        "contract_path": f"supabase://public/lf_operation_contracts/{op}/{code}",
        "contract_sha": None,
        "required_before_write": [],
        "allowed": {},
        "blocked": [],
        "required_after_write": [],
        "status": status,
    }


def packet(contracts=None, **overrides):
    value = {
        "schema_version": "lf-contract-resolution-request/v1",
        "operation_code": "OP_ALPHA",
        "authority_source": "public.lf_operation_contracts",
        "contracts": [row("B"), row("A")] if contracts is None else contracts,
    }
    value.update(overrides)
    return value


checks = 0


def check(name: str, condition: bool):
    global checks
    assert condition, name
    checks += 1


result = carrier.run(packet())
check("sorts_all_active", [r["contract_code"] for r in result["resolved_contracts"]] == ["A", "B"])
check("count", result["contract_count"] == 2)
check("caller_operation_preserved", result["operation_code"] == "OP_ALPHA")
check("core_schema_preserved", result["schema_version"] == "lf-contract-resolution-result/v1")
check("resolution_basis_preserved", result["resolution_basis"] == "ALL_ACTIVE_CONTRACTS_FOR_OPERATION")
check("carrier_does_not_modify_core_result", "carrier" not in result)
check(
    "core_result_shape_preserved",
    set(result) == {
        "schema_version",
        "operation_code",
        "resolution_basis",
        "active_statuses",
        "contract_count",
        "resolved_contracts",
        "resolution_sha256",
    },
)

try:
    carrier.run(packet(authority_source="other.table"))
except carrier.ContractResolutionCarrierError as exc:
    check("rejects_other_source", str(exc) == "FAIL_CONTRACT_RESOLUTION_CARRIER_AUTHORITY_SOURCE")
else:
    raise AssertionError("rejects_other_source")

try:
    carrier.run(packet(operation_code=""))
except carrier.ContractResolutionCarrierError as exc:
    check("rejects_missing_operation", str(exc) == "FAIL_CONTRACT_RESOLUTION_CARRIER_OPERATION_CODE")
else:
    raise AssertionError("rejects_missing_operation")

try:
    carrier.run(packet(contracts=[]))
except Exception as exc:
    check("zero_active_blocks", str(exc) == "BLOCK_ACTIVE_CONTRACT_MISSING:OP_ALPHA")
else:
    raise AssertionError("zero_active_blocks")

try:
    carrier.run(packet(contracts=[row("A"), row("A")]))
except Exception as exc:
    check("duplicate_blocks", str(exc) == "FAIL_CONTRACT_RESOLUTION_DUPLICATE_ACTIVE_CONTRACT:A")
else:
    raise AssertionError("duplicate_blocks")

inactive = carrier.run(packet(contracts=[row("X", status="INACTIVE"), row("A")]))
check("inactive_excluded", [r["contract_code"] for r in inactive["resolved_contracts"]] == ["A"])

other = carrier.run(packet(contracts=[row("X", op="OP_OTHER"), row("A")]))
check("other_operation_excluded", [r["contract_code"] for r in other["resolved_contracts"]] == ["A"])

with tempfile.TemporaryDirectory() as td:
    p = Path(td) / "packet.json"
    p.write_text(json.dumps(packet()), encoding="utf-8")
    proc = subprocess.run(
        [sys.executable, str(HERE / "contract_resolution_carrier_v1.py"), "--input", str(p)],
        capture_output=True,
        text=True,
    )
    check("file_exit_zero", proc.returncode == 0 and json.loads(proc.stdout)["contract_count"] == 2)

proc = subprocess.run(
    [sys.executable, str(HERE / "contract_resolution_carrier_v1.py")],
    input=json.dumps(packet()),
    capture_output=True,
    text=True,
)
check("stdin_exit_zero", proc.returncode == 0 and json.loads(proc.stdout)["operation_code"] == "OP_ALPHA")

proc = subprocess.run(
    [sys.executable, str(HERE / "contract_resolution_carrier_v1.py")],
    input="{",
    capture_output=True,
    text=True,
)
check("bad_json_exit_three", proc.returncode == 3 and json.loads(proc.stderr)["error"] == "CARRIER_JSON_INVALID")

proc = subprocess.run(
    [sys.executable, str(HERE / "contract_resolution_carrier_v1.py")],
    input=json.dumps(packet(contracts=[])),
    capture_output=True,
    text=True,
)
check("block_exit_two", proc.returncode == 2 and json.loads(proc.stderr)["error"] == "CONTRACT_RESOLUTION_BLOCKED")

print(f"PASS_CONTRACT_RESOLUTION_CARRIER_V1={checks}/{checks}")
