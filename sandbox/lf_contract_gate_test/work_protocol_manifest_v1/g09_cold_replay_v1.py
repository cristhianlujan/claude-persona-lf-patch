#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[3]
VALIDATOR = ROOT / "gobernanza/judges/validate_work_protocol_manifest_v1.py"
MATRIX = Path(__file__).with_name("g09_selftest_matrix_v1.json")

spec = importlib.util.spec_from_file_location("wpm_g09", VALIDATOR)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def rebind_manifest(packet: dict[str, Any]) -> None:
    manifest = packet["manifest"]
    manifest["manifest_digest"] = mod.digest_without_self(manifest)
    packet["manifest_readback"] = copy.deepcopy(manifest)
    packet["persisted_manifest_digest"] = manifest["manifest_digest"]


def timeout_overlay(packet: dict[str, Any], step_id: str = "readback") -> None:
    packet["recovery_state"] = {
        "step_id": step_id,
        "condition": "TIMEOUT_RECOVERING",
        "attempt": 1,
        "strategy": "RESUME_CHECKPOINT" if step_id == "readback" else "REDUCE_UNIT",
        "checkpoint_ref": f"checkpoint://g09/{step_id}/1",
        "previous_work_unit": 100,
        "next_work_unit": 50,
    }


def assert_result(
    result: dict[str, Any],
    *,
    result_in: set[str] | None = None,
    error_contains: str | None = None,
    error_prefix: str | None = None,
    blocking_contains: str | None = None,
) -> None:
    if result_in is not None:
        assert result.get("result") in result_in, result
    errors = result.get("errors") or []
    blocking = result.get("blocking") or []
    if error_contains is not None:
        assert error_contains in errors, result
    if error_prefix is not None:
        assert any(str(e).startswith(error_prefix) for e in errors), result
    if blocking_contains is not None:
        assert blocking_contains in blocking, result


def integrated_pass() -> None:
    result = mod.evaluate(mod.valid_fixture())
    assert result["result"] == "PASS_WITH_EVIDENCE", result
    assert result["progress_percent"] == 100, result
    assert result["closure_controller"]["global_close_allowed"] is True, result


def probe_g00_timeout_overlay() -> None:
    p = mod.valid_fixture()
    del p["manifest"]["work_owner"]
    rebind_manifest(p)
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_contains="MANIFEST_FIELD_MISSING:work_owner")


def probe_g01_scope_bypass() -> None:
    p = mod.valid_fixture()
    p["manifest"]["authorized_scope"]["authorization_sha256"] = "9" * 64
    rebind_manifest(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_contains="AUTHORIZED_SCOPE_REQUEST_BINDING_MISMATCH")


def probe_g01_timeout_overlay() -> None:
    p = mod.valid_fixture()
    p["authority_readback"]["operation_revision_sha256"] = "9" * 64
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"STALE_AUTHORITY"}, error_contains="OPERATION_REVISION_DRIFT")


def probe_g02_timeout_overlay() -> None:
    p = mod.valid_fixture()
    p["persisted_manifest_digest"] = "9" * 64
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_contains="PERSISTED_MANIFEST_DIGEST_MISMATCH")


def probe_g03_timeout_overlay() -> None:
    p = mod.valid_fixture()
    del p["execution_steps"][0]["evidence"]["work_protocol_gate"]
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_prefix="GATE_PACKET_MISSING_OR_INVALID:WP-01")


def probe_g04_timeout_overlay() -> None:
    p = mod.valid_fixture()
    p["execution_steps"][0]["evidence"]["work_protocol_evidence"]["reproduction"]["reproduction_spec_sha256"] = "0" * 64
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_prefix="EVIDENCE_REPRODUCTION_SPEC_DIGEST_MISMATCH:WP-01")


def probe_g05_policy_drift() -> None:
    p = mod.valid_fixture()
    p["manifest"]["obligations"][0]["timeout_recovery_mode"] = "RESUME_CHECKPOINT"
    rebind_manifest(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_contains="EXECUTION_RECOVERY_CLASS_MISMATCH:WP-01")


def probe_g05_verified_step_timeout_bypass() -> None:
    p = mod.valid_fixture()
    p["recovery_state"] = {
        "step_id": "resolve",
        "condition": "TIMEOUT_RECOVERING",
        "attempt": 1,
        "strategy": "REDUCE_UNIT",
        "checkpoint_ref": "checkpoint://g09/resolve/1",
        "previous_work_unit": 100,
        "next_work_unit": 50,
    }
    r = mod.evaluate(p)
    assert_result(
        r,
        result_in={"BLOCKED"},
        error_contains="TIMEOUT_RECOVERY_ON_VERIFIED_STEP:WP-01",
        blocking_contains="RECOVERY_PROTOCOL:WP-01",
    )


def add_required_waiver(packet: dict[str, Any]) -> None:
    packet["manifest"]["waivers"] = [{
        "requirement_id": "WP-01",
        "reason": "G09 bypass probe must remain blocked.",
        "residual_risk": "Required authority resolution would be unproven.",
        "authorized_by": "HUMAN-G09-TEST",
        "authorization_ref": "human-approval://g09/waiver/wp-01",
        "authorization_sha256": "a" * 64,
        "expires_at": "2026-09-22T12:30:00Z",
    }]
    rebind_manifest(packet)


def probe_g06_timeout_overlay() -> None:
    p = mod.valid_fixture()
    add_required_waiver(p)
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_contains="WAIVER_REQUIRED_OBLIGATION_FORBIDDEN:WP-01")


def controller_drift_packet() -> dict[str, Any]:
    p = mod.valid_fixture()
    p["manifest"]["obligations"][0]["controller_order"] = 11
    rebind_manifest(p)
    return p


def probe_g07_controller_authority_drift() -> None:
    r = mod.evaluate(controller_drift_packet())
    assert_result(r, result_in={"BLOCKED"}, error_contains="CONTROLLER_AUTHORITY_MISMATCH:resolve:controller_order")


def probe_g07_timeout_overlay() -> None:
    p = controller_drift_packet()
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert_result(r, result_in={"BLOCKED"}, error_contains="CONTROLLER_AUTHORITY_MISMATCH:resolve:controller_order")


def probe_g08_timeout_overlay() -> None:
    p = mod.valid_fixture()
    assert len(p["closure_ledger_readback"]) >= 2
    p["closure_ledger_readback"][1]["previous_unit_receipt_sha256"] = "9" * 64
    timeout_overlay(p)
    r = mod.evaluate(p)
    assert r["result"] == "BLOCKED", r
    assert r["closure_controller"]["reopen_required_count"] > 0, r
    assert r["closure_controller"]["global_close_allowed"] is False, r
    assert "TIMEOUT_RECOVERY_ON_VERIFIED_STEP:WP-02" in (r.get("errors") or []), r


PROBES: dict[str, Callable[[], None]] = {
    "integrated_pass": integrated_pass,
    "probe_g00_timeout_overlay": probe_g00_timeout_overlay,
    "probe_g01_scope_bypass": probe_g01_scope_bypass,
    "probe_g01_timeout_overlay": probe_g01_timeout_overlay,
    "probe_g02_timeout_overlay": probe_g02_timeout_overlay,
    "probe_g03_timeout_overlay": probe_g03_timeout_overlay,
    "probe_g04_timeout_overlay": probe_g04_timeout_overlay,
    "probe_g05_policy_drift": probe_g05_policy_drift,
    "probe_g05_verified_step_timeout_bypass": probe_g05_verified_step_timeout_bypass,
    "probe_g06_timeout_overlay": probe_g06_timeout_overlay,
    "probe_g07_controller_authority_drift": probe_g07_controller_authority_drift,
    "probe_g07_timeout_overlay": probe_g07_timeout_overlay,
    "probe_g08_timeout_overlay": probe_g08_timeout_overlay,
}


def run_once() -> dict[str, Any]:
    matrix = json.loads(MATRIX.read_text(encoding="utf-8"))
    assert matrix["schema_version"] == "LF_WORK_PROTOCOL_G09_SELFTEST_MATRIX_V1"
    dimensions = matrix["required_dimensions"]
    assert dimensions == ["positive", "negative", "drift", "bypass", "timeout"], dimensions
    gates = matrix["gates"]
    assert list(gates) == [f"G{i:02d}" for i in range(9)], list(gates)

    validator_cases = mod.self_test()
    assert validator_cases and set(validator_cases.values()) == {"PASS"}

    results: dict[str, dict[str, str]] = {}
    for gate_id, gate in gates.items():
        assert set(gate) == {"name", *dimensions}, gate
        results[gate_id] = {}
        for dimension in dimensions:
            ref = gate[dimension]
            if ref in validator_cases:
                assert validator_cases[ref] == "PASS", (gate_id, dimension, ref)
            else:
                probe = PROBES.get(ref)
                assert probe is not None, (gate_id, dimension, ref)
                probe()
            results[gate_id][dimension] = "PASS"

    assert sum(len(v) for v in results.values()) == 45
    return {
        "status": "PASS",
        "gate_count": len(gates),
        "dimension_count": len(dimensions),
        "matrix_case_count": 45,
        "matrix_results": results,
        "matrix_sha256": canonical_sha(matrix),
        "validator_self_test_case_count": len(validator_cases),
        "validator_self_test_sha256": canonical_sha(validator_cases),
    }


def cold_replay() -> dict[str, Any]:
    outputs: list[dict[str, Any]] = []
    raw_canonical: list[str] = []
    for seed in ("11", "97"):
        env = dict(os.environ)
        env["PYTHONHASHSEED"] = seed
        proc = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "--once"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
        if proc.returncode != 0:
            raise AssertionError({
                "code": "G09_COLD_REPLAY_CHILD_FAILED",
                "seed": seed,
                "returncode": proc.returncode,
                "stdout": proc.stdout[-4000:],
                "stderr": proc.stderr[-4000:],
            })
        payload = json.loads(proc.stdout)
        canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        outputs.append(payload)
        raw_canonical.append(canonical)

    assert raw_canonical[0] == raw_canonical[1], {
        "code": "G09_COLD_REPLAY_NONDETERMINISTIC",
        "sha_a": hashlib.sha256(raw_canonical[0].encode()).hexdigest(),
        "sha_b": hashlib.sha256(raw_canonical[1].encode()).hexdigest(),
    }
    report = outputs[0]
    report["cold_replay"] = {
        "status": "PASS",
        "fresh_process_count": 2,
        "pythonhashseed_values": ["11", "97"],
        "byte_equivalent_canonical_json": True,
        "replay_sha256": hashlib.sha256(raw_canonical[0].encode()).hexdigest(),
    }
    return report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()
    result = run_once() if args.once else cold_replay()
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
