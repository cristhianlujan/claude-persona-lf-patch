#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml

VERSION = "v1.0"
CONTRACT_VERSION = "STRATEGY_PROGRESS_CONTRACT_V1"
REQUIRED_KEYS = {
    "contract_version",
    "strategy_number",
    "strategy_id",
    "strategy_code",
    "strategy_version",
    "snapshot_status",
    "runtime_state",
    "impact_policy",
    "progress_state",
    "completion",
    "current_stage",
    "current_action",
    "next_gate",
    "blockers",
    "safe_parallel_work",
    "material_this_run",
    "terminal_currentness",
    "claim_ceiling",
    "parent_currentness",
    "payload_sha256",
    "source_updated_at",
    "source_updated_by_execution_id",
    "last_material_execution_id",
    "last_material_at",
    "updated_by_execution_id",
    "updated_at",
}
COMPLETION_KEYS = {"percent", "basis", "numerator", "denominator", "confidence"}
MATERIAL_KEYS = {"state", "units_completed", "execution_id"}
PARENT_KEYS = {"state", "checked_at"}
ALLOWED_MATERIAL_STATES = {
    "NO_NEW_MATERIAL",
    "MATERIAL_PROGRESS",
    "PROGRESS_CONTRACT_NORMALIZATION_ONLY",
}
ALLOWED_PARENT_STATES = {
    "CURRENT",
    "CURRENT_AT_CLOSE",
    "RECHECK_REQUIRED_BEFORE_DEPENDENT_WRITE",
    "STALE_PARENT",
    "NOT_APPLICABLE_WITH_REASON",
}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
STRATEGY_NUMBER = re.compile(r"^S\d+$")


def load_document(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("document root must be an object")
    return data


def _err(errors: list[dict[str, str]], code: str, path: str, message: str) -> None:
    errors.append({"code": code, "path": path, "message": message})


def _sha(result: dict[str, Any]) -> str:
    payload = dict(result)
    payload.pop("results_sha256", None)
    return hashlib.sha256(
        json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def validate(data: dict[str, Any], mode: str = "readback") -> dict[str, Any]:
    errors: list[dict[str, str]] = []
    row = data.get("row")
    progress = data.get("progress")

    if not isinstance(row, dict):
        _err(errors, "ROW_MISSING", "row", "row context is required")
        row = {}
    if not isinstance(progress, dict):
        _err(errors, "PROGRESS_MISSING", "progress", "progress object is required")
        progress = {}

    missing = sorted(REQUIRED_KEYS - set(progress))
    extra = sorted(set(progress) - REQUIRED_KEYS)
    if missing:
        _err(errors, "PROGRESS_KEYSET_MISSING", "progress", f"missing keys: {missing}")
    if extra:
        _err(errors, "PROGRESS_KEYSET_EXTRA", "progress", f"unexpected keys: {extra}")

    if progress.get("contract_version") != CONTRACT_VERSION:
        _err(errors, "PROGRESS_CONTRACT_VERSION_INVALID", "progress.contract_version", "unexpected contract version")
    if not isinstance(progress.get("strategy_number"), str) or not STRATEGY_NUMBER.fullmatch(progress.get("strategy_number", "")):
        _err(errors, "STRATEGY_NUMBER_INVALID", "progress.strategy_number", "strategy_number must match S<integer>")

    expected = {
        "strategy_id": row.get("id"),
        "strategy_code": row.get("snapshot_code"),
        "strategy_version": row.get("version"),
        "snapshot_status": row.get("status"),
        "runtime_state": row.get("runtime_state"),
        "impact_policy": row.get("impact_policy"),
        "payload_sha256": row.get("payload_sha256"),
    }
    for key, value in expected.items():
        if value is None:
            _err(errors, "ROW_CONTEXT_INCOMPLETE", f"row.{key}", f"row context for {key} is required")
        elif progress.get(key) != value:
            _err(errors, "PROGRESS_ROW_STATE_MISMATCH", f"progress.{key}", f"expected {value!r}, found {progress.get(key)!r}")

    payload_sha = progress.get("payload_sha256")
    if not isinstance(payload_sha, str) or not HEX64.fullmatch(payload_sha):
        _err(errors, "PROGRESS_PAYLOAD_SHA_INVALID", "progress.payload_sha256", "payload_sha256 must be 64 lowercase hex chars")

    completion = progress.get("completion")
    if not isinstance(completion, dict):
        _err(errors, "COMPLETION_INVALID", "progress.completion", "completion must be an object")
        completion = {}
    else:
        if set(completion) != COMPLETION_KEYS:
            _err(errors, "COMPLETION_KEYSET_INVALID", "progress.completion", f"expected keys {sorted(COMPLETION_KEYS)}")
    percent = completion.get("percent")
    numerator = completion.get("numerator")
    denominator = completion.get("denominator")
    basis = completion.get("basis")
    if percent is None:
        if numerator is not None or denominator is not None:
            _err(errors, "COMPLETION_NULL_WITH_COUNTS", "progress.completion", "null percent requires null numerator and denominator")
        if basis != "NOT_DETERMINISTICALLY_MATERIALIZED":
            _err(errors, "COMPLETION_NULL_BASIS_INVALID", "progress.completion.basis", "null percent requires NOT_DETERMINISTICALLY_MATERIALIZED")
    else:
        if not isinstance(percent, (int, float)) or isinstance(percent, bool) or not 0 <= float(percent) <= 100:
            _err(errors, "COMPLETION_PERCENT_INVALID", "progress.completion.percent", "percent must be numeric in [0,100]")
        if not isinstance(numerator, int) or isinstance(numerator, bool) or numerator < 0:
            _err(errors, "COMPLETION_NUMERATOR_INVALID", "progress.completion.numerator", "numerator must be a non-negative integer")
        if not isinstance(denominator, int) or isinstance(denominator, bool) or denominator <= 0:
            _err(errors, "COMPLETION_DENOMINATOR_INVALID", "progress.completion.denominator", "denominator must be a positive integer")
        if isinstance(numerator, int) and isinstance(denominator, int) and denominator > 0:
            expected_percent = 100.0 * numerator / denominator
            if abs(float(percent) - expected_percent) > 0.01:
                _err(errors, "COMPLETION_PERCENT_MATH_MISMATCH", "progress.completion", "percent must match numerator/denominator")
        if float(percent) == 100.0 and str(progress.get("terminal_currentness", "")).upper().find("CLOSED") < 0:
            _err(errors, "COMPLETION_100_WITHOUT_TERMINAL_READBACK", "progress.terminal_currentness", "100 percent requires CLOSED terminal currentness")

    material = progress.get("material_this_run")
    if not isinstance(material, dict) or set(material) != MATERIAL_KEYS:
        _err(errors, "MATERIAL_THIS_RUN_INVALID", "progress.material_this_run", f"expected keys {sorted(MATERIAL_KEYS)}")
    else:
        state = material.get("state")
        units = material.get("units_completed")
        if state not in ALLOWED_MATERIAL_STATES:
            _err(errors, "MATERIAL_STATE_INVALID", "progress.material_this_run.state", "unsupported material state")
        if not isinstance(units, int) or isinstance(units, bool) or units < 0:
            _err(errors, "MATERIAL_UNITS_INVALID", "progress.material_this_run.units_completed", "units_completed must be non-negative integer")
        if state in {"NO_NEW_MATERIAL", "PROGRESS_CONTRACT_NORMALIZATION_ONLY"} and units != 0:
            _err(errors, "PRIOR_EVIDENCE_COUNTED_AS_CURRENT_WORK", "progress.material_this_run.units_completed", "non-material states require units_completed=0")
        if state == "MATERIAL_PROGRESS" and units == 0:
            _err(errors, "MATERIAL_PROGRESS_WITH_ZERO_UNITS", "progress.material_this_run.units_completed", "MATERIAL_PROGRESS requires units_completed>0")
        if not isinstance(material.get("execution_id"), str) or not material.get("execution_id"):
            _err(errors, "MATERIAL_EXECUTION_ID_MISSING", "progress.material_this_run.execution_id", "execution_id is required")

    parent = progress.get("parent_currentness")
    if not isinstance(parent, dict) or set(parent) != PARENT_KEYS:
        _err(errors, "PARENT_CURRENTNESS_INVALID", "progress.parent_currentness", f"expected keys {sorted(PARENT_KEYS)}")
    else:
        if parent.get("state") not in ALLOWED_PARENT_STATES:
            _err(errors, "PARENT_CURRENTNESS_STATE_INVALID", "progress.parent_currentness.state", "unsupported parent currentness state")
        if not parent.get("checked_at"):
            _err(errors, "PARENT_CURRENTNESS_TIME_MISSING", "progress.parent_currentness.checked_at", "checked_at is required")

    for key in ("blockers", "safe_parallel_work"):
        if not isinstance(progress.get(key), list):
            _err(errors, "PROGRESS_LIST_INVALID", f"progress.{key}", f"{key} must be a list")

    for key in ("current_stage", "current_action", "next_gate", "progress_state", "terminal_currentness", "claim_ceiling", "updated_by_execution_id", "updated_at"):
        if not isinstance(progress.get(key), str) or not progress.get(key):
            _err(errors, "PROGRESS_REQUIRED_TEXT_MISSING", f"progress.{key}", f"{key} must be non-empty text")

    result = {
        "validator_version": VERSION,
        "mode": mode,
        "valid": not errors,
        "blocking_codes": sorted({e["code"] for e in errors}),
        "errors": errors,
    }
    result["results_sha256"] = _sha(result)
    return result


def _valid_fixture() -> dict[str, Any]:
    sha = "a" * 64
    return {
        "row": {
            "id": 45,
            "snapshot_code": "LF_STRATEGY_FACTORY_SELF_HOSTED_CANARY_V032_20260907",
            "version": "v0.1",
            "status": "CANDIDATO_READ_ONLY",
            "runtime_state": "PLAN_ONLY",
            "impact_policy": "BLOQUEADO",
            "payload_sha256": sha,
        },
        "progress": {
            "contract_version": CONTRACT_VERSION,
            "strategy_number": "S32",
            "strategy_id": 45,
            "strategy_code": "LF_STRATEGY_FACTORY_SELF_HOSTED_CANARY_V032_20260907",
            "strategy_version": "v0.1",
            "snapshot_status": "CANDIDATO_READ_ONLY",
            "runtime_state": "PLAN_ONLY",
            "impact_policy": "BLOQUEADO",
            "progress_state": "CLOSED_VERIFIED_CANDIDATE",
            "completion": {"percent": 100, "basis": "EXPLICIT_STAGE_TERMINAL_AND_CLOSED_FRONTIER", "numerator": 2, "denominator": 2, "confidence": "HIGH"},
            "current_stage": "TERMINAL",
            "current_action": "NONE",
            "next_gate": "NONE",
            "blockers": [],
            "safe_parallel_work": [],
            "material_this_run": {"state": "NO_NEW_MATERIAL", "units_completed": 0, "execution_id": "EXEC-TEST"},
            "terminal_currentness": "CLOSED_CURRENT_AT_LAST_READBACK",
            "claim_ceiling": "CANARY_ONLY",
            "parent_currentness": {"state": "CURRENT_AT_CLOSE", "checked_at": "2026-09-07T06:00:00Z"},
            "payload_sha256": sha,
            "source_updated_at": "2026-09-07T05:00:00Z",
            "source_updated_by_execution_id": "EXEC-SOURCE",
            "last_material_execution_id": None,
            "last_material_at": None,
            "updated_by_execution_id": "EXEC-TEST",
            "updated_at": "2026-09-07T06:00:00Z",
        },
    }


def self_test() -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], bool, str | None]] = []
    good = _valid_fixture()
    cases.append(("positive_terminal", good, True, None))

    bad_key = json.loads(json.dumps(good))
    bad_key["progress"].pop("next_gate")
    cases.append(("missing_key", bad_key, False, "PROGRESS_KEYSET_MISSING"))

    bad_state = json.loads(json.dumps(good))
    bad_state["progress"]["runtime_state"] = "NO_HABILITADO"
    cases.append(("row_state_mismatch", bad_state, False, "PROGRESS_ROW_STATE_MISMATCH"))

    bad_sha = json.loads(json.dumps(good))
    bad_sha["progress"]["payload_sha256"] = "b" * 64
    cases.append(("payload_sha_mismatch", bad_sha, False, "PROGRESS_ROW_STATE_MISMATCH"))

    bad_prior = json.loads(json.dumps(good))
    bad_prior["progress"]["material_this_run"] = {"state": "NO_NEW_MATERIAL", "units_completed": 1, "execution_id": "EXEC-TEST"}
    cases.append(("prior_evidence_current_work", bad_prior, False, "PRIOR_EVIDENCE_COUNTED_AS_CURRENT_WORK"))

    bad_percent = json.loads(json.dumps(good))
    bad_percent["progress"]["completion"] = {"percent": 80, "basis": "STAGES", "numerator": None, "denominator": None, "confidence": "HIGH"}
    cases.append(("percent_without_denominator", bad_percent, False, "COMPLETION_NUMERATOR_INVALID"))

    bad_100 = json.loads(json.dumps(good))
    bad_100["progress"]["terminal_currentness"] = "CURRENT_MATERIAL_WORK_OPEN"
    cases.append(("hundred_without_close", bad_100, False, "COMPLETION_100_WITHOUT_TERMINAL_READBACK"))

    bad_parent = json.loads(json.dumps(good))
    bad_parent["progress"]["parent_currentness"]["state"] = "ASSUMED_CURRENT"
    cases.append(("invalid_parent_state", bad_parent, False, "PARENT_CURRENTNESS_STATE_INVALID"))

    results = []
    all_pass = True
    for name, payload, should_valid, expected_code in cases:
        result = validate(payload, "readback")
        ok = result["valid"] is should_valid and (expected_code is None or expected_code in result["blocking_codes"])
        all_pass = all_pass and ok
        results.append({"name": name, "pass": ok, "blocking_codes": result["blocking_codes"]})
    return {"validator_version": VERSION, "case_count": len(results), "all_pass": all_pass, "cases": results}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", type=Path)
    parser.add_argument("--mode", choices=["prewrite_projection", "readback"], default="readback")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = self_test()
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if result["all_pass"] else 1
    if args.path is None:
        parser.error("path is required unless --self-test is used")
    try:
        result = validate(load_document(args.path), args.mode)
    except Exception as exc:
        result = {
            "validator_version": VERSION,
            "valid": False,
            "errors": [{"code": "MALFORMED_INPUT", "path": "$", "message": str(exc)}],
            "blocking_codes": ["MALFORMED_INPUT"],
        }
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result.get("valid") else 1


if __name__ == "__main__":
    sys.exit(main())
