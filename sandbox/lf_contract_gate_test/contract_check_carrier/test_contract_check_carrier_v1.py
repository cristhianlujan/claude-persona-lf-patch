#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_resolution"))

import contract_check_carrier_v1 as carrier
import contract_resolution_core_v1 as resolver


def typed_row() -> dict[str, Any]:
    return {
        "operation_code": "SAMPLE_OP",
        "contract_code": "CONTRACT-TYPED-v1",
        "contract_path": "supabase://contracts/CONTRACT-TYPED-v1",
        "contract_sha": "c" * 64,
        "required_before_write": [{"id": "ready", "predicate": {"op": "TRUE", "fact": "ready"}}],
        "allowed": [{"id": "mode", "predicate": {"op": "EQ", "fact": "mode", "value": "READ_ONLY"}}],
        "blocked": [{"id": "production", "predicate": {"op": "TRUE", "fact": "prod"}}],
        "required_after_write": [{"id": "readback", "predicate": {"op": "TRUE", "fact": "readback"}}],
        "status": "ACTIVE_ENFORCEMENT",
    }


def facts() -> dict[str, Any]:
    return {
        "ready": {"present": True, "value": True, "evidence_refs": ["evidence://ready"]},
        "mode": {"present": True, "value": "READ_ONLY", "evidence_refs": ["evidence://mode"]},
        "prod": {"present": True, "value": False, "evidence_refs": ["evidence://prod"]},
        "readback": {"present": True, "value": True, "evidence_refs": ["evidence://readback"]},
    }


def packet() -> dict[str, Any]:
    row = typed_row()
    resolution = resolver.resolve_contracts(operation_code="SAMPLE_OP", contracts=[row])
    return {
        "schema_version": carrier.INTEGRATION.INPUT_SCHEMA_VERSION,
        "phase": "CLOSURE",
        "resolution": resolution,
        "bindings": [{"contract_code": row["contract_code"], "source_mode": "TYPED"}],
        "facts": facts(),
    }


def run_cli(payload_text: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HERE / "contract_check_carrier_v1.py"), *args],
        input=payload_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=20,
    )


def expect_error(fn, error_type, token: str) -> None:
    try:
        fn()
    except error_type as exc:
        assert token in str(exc), (token, str(exc))
        return
    raise AssertionError(f"expected {error_type.__name__} containing {token}")


def case_run_pass() -> None:
    result = carrier.run(packet())
    assert result["verdict"] == "PASS", result
    assert result["stage"] == "COMPLETE"


def case_run_block() -> None:
    p = packet()
    p["facts"]["ready"]["value"] = False
    result = carrier.run(p)
    assert result["verdict"] == "BLOCK"
    assert result["stage"] == "CONTRACT_CHECK_CORE"


def case_packet_shape_rejected() -> None:
    expect_error(lambda: carrier.run([]), carrier.ContractCheckCarrierError, "FAIL_CONTRACT_CHECK_CARRIER_PACKET_SHAPE")


def case_upstream_evaluations_rejected() -> None:
    p = packet()
    p["evaluations"] = [{"verdict": "SATISFIED"}]
    expect_error(
        lambda: carrier.run(p),
        carrier.INTEGRATION.ContractCheckSemanticIntegrationInputError,
        "unexpected_top_level_keys:evaluations",
    )


def case_cli_pass_exit_zero() -> None:
    completed = run_cli(json.dumps(packet()), "--input", "-")
    assert completed.returncode == 0, completed.stderr
    assert json.loads(completed.stdout)["verdict"] == "PASS"


def case_cli_block_exit_two() -> None:
    p = packet()
    p["facts"]["prod"]["value"] = True
    completed = run_cli(json.dumps(p), "--input", "-")
    assert completed.returncode == 2, (completed.stdout, completed.stderr)
    assert json.loads(completed.stdout)["verdict"] == "BLOCK"


def case_cli_invalid_json_exit_three() -> None:
    completed = run_cli("{not-json", "--input", "-")
    assert completed.returncode == 3
    assert json.loads(completed.stderr)["error"] == "CARRIER_JSON_INVALID"


def case_cli_missing_file_exit_three() -> None:
    completed = run_cli("", "--input", str(HERE / "definitely-missing.json"))
    assert completed.returncode == 3
    assert json.loads(completed.stderr)["error"] == "CARRIER_INPUT_READ_ERROR"


def case_cli_invalid_packet_exit_three() -> None:
    completed = run_cli("[]", "--input", "-")
    assert completed.returncode == 3
    assert json.loads(completed.stderr)["error"] == "CARRIER_PACKET_INVALID"


def case_cli_pretty_is_valid_json() -> None:
    completed = run_cli(json.dumps(packet()), "--input", "-", "--pretty")
    assert completed.returncode == 0
    parsed = json.loads(completed.stdout)
    assert parsed["verdict"] == "PASS"
    assert "\n  \"" in completed.stdout


def case_delegation_is_exact() -> None:
    p = packet()
    assert carrier.run(copy.deepcopy(p)) == carrier.INTEGRATION.evaluate(copy.deepcopy(p))


def case_source_boundary_is_thin() -> None:
    source = (HERE / "contract_check_carrier_v1.py").read_text(encoding="utf-8")
    assert "contract_check_semantic_integration_v1.py" in source
    assert "contract_resolution_core_v1" not in source
    assert "legacy_contract_normalization_v1" not in source
    assert "contract_predicate_semantics_v1" not in source
    assert "contract_check_core_v1" not in source
    assert "requests." not in source
    assert "supabase." not in source.lower()


CASES = [
    case_run_pass,
    case_run_block,
    case_packet_shape_rejected,
    case_upstream_evaluations_rejected,
    case_cli_pass_exit_zero,
    case_cli_block_exit_two,
    case_cli_invalid_json_exit_three,
    case_cli_missing_file_exit_three,
    case_cli_invalid_packet_exit_three,
    case_cli_pretty_is_valid_json,
    case_delegation_is_exact,
    case_source_boundary_is_thin,
]


def main() -> None:
    passed = 0
    for case in CASES:
        case()
        passed += 1
    assert passed == 12
    print(f"PASS_CONTRACT_CHECK_FINAL_THIN_CARRIER_V1={passed}/{len(CASES)}")


if __name__ == "__main__":
    main()
