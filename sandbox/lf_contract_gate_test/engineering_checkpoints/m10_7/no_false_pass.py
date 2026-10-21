#!/usr/bin/env python3
"""M10.7 NO_FALSE_PASS material verifier.

This file is the exact bounded checkpoint test for
IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.7 / NO_FALSE_PASS.

It validates a frozen, read-only operational sample against the historical
M9.11 SOAK_OBSERVATION_HISTORY_V2 receipt. It never queries credentials,
changes runtime state, creates new Input Governance runs, or grants production
authority.

Material PASS requires:
- verified historical receipt (13 screens, 47 families, >=2 observations,
  zero known false-pass signals, zero unresolved D4);
- a frozen operational sample of >=3 exact run ids;
- every sample run current under CURRENTNESS_AUTHORITY;
- 47/47 validator PASS, measured duration >0 and <=150000 ms;
- zero explicit timeout signals;
- deterministic adversarial negatives executed by this test;
- execution by an authorized external runner that supplies a real evidence ref.

Self-test proves only verifier logic and can never produce a material PASS.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any, Iterable

TEST_CODE = "ENG_M10_7_NO_FALSE_PASS"
SUITE_CODE = "INPUT_GOVERNANCE_REGRESSION"
SCHEMA_VERSION = "M10_7_NO_FALSE_PASS_RESULT_V2"
INPUT_SCHEMA = "M10_7_NO_FALSE_PASS_INPUT_V2"
COHORT = {1, 2, 3, 5, 43, 51, 52, 53, 54, 55, 56, 57, 58}
FAMILY_COUNT = 47
LIMIT_MS = 150_000
MIN_OPERATIONAL_SAMPLE = 3
RECEIPT_SHA = "17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972"
RECEIPT_SCHEMA = "SOAK_OBSERVATION_HISTORY_V2"
SAMPLE_POLICY = "RUN_HISTORY_EFFECTIVENESS_SAMPLE_V1"


class EvidenceError(ValueError):
    """Raised when supplied material evidence cannot satisfy the checkpoint."""


def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256_json(value: Any) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def _as_int(value: Any, field: str) -> int:
    if isinstance(value, bool):
        raise EvidenceError(f"{field}:bool_not_int")
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise EvidenceError(f"{field}:invalid_int") from exc


def _as_bool(value: Any, field: str) -> bool:
    if value is True:
        return True
    if value is False:
        return False
    raise EvidenceError(f"{field}:invalid_bool")


def _require_nonempty_text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EvidenceError(f"{field}:missing")
    return value.strip()


def _validate_receipt(receipt: dict[str, Any]) -> None:
    if receipt.get("receipt_sha256") != RECEIPT_SHA:
        raise EvidenceError("receipt:sha")
    payload = receipt.get("payload")
    if not isinstance(payload, dict):
        raise EvidenceError("receipt:payload")
    expected = {
        "schema_version": RECEIPT_SCHEMA,
        "verification_status": "VERIFIED",
        "pass": True,
        "screens_total": 13,
        "families_total": FAMILY_COUNT,
        "screens_below_2": 0,
        "families_below_2": 0,
        "known_false_pass_signals": 0,
        "unresolved_d4": 0,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise EvidenceError(f"receipt:{key}")
    if _as_int(payload.get("min_screen_observations"), "receipt:min_screen_observations") < 2:
        raise EvidenceError("receipt:min_screen_observations")
    if _as_int(payload.get("min_family_observations"), "receipt:min_family_observations") < 2:
        raise EvidenceError("receipt:min_family_observations")


def _run_identity(row: dict[str, Any]) -> tuple[int, int]:
    return _as_int(row.get("run_id"), "run_id"), _as_int(row.get("pantalla_id"), "pantalla_id")


def _frozen_run_projection(rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    projected: list[dict[str, Any]] = []
    for row in rows:
        run_id, screen_id = _run_identity(row)
        projected.append(
            {
                "run_id": run_id,
                "pantalla_id": screen_id,
                "status": row.get("status"),
                "validator_duration_ms": row.get("validator_duration_ms"),
                "family_count": row.get("family_count"),
                "validator_pass_count": row.get("validator_pass_count"),
                "explicit_timeout_signal": row.get("explicit_timeout_signal"),
                "currentness_authority": row.get("currentness_authority"),
                "source_current": row.get("source_current"),
                "lifecycle_current": row.get("lifecycle_current"),
                "source_manifest_current": row.get("source_manifest_current"),
                "execution_policy_current": row.get("execution_policy_current"),
                "readiness_contract_current": row.get("readiness_contract_current"),
                "source_snapshot_sha256": row.get("source_snapshot_sha256"),
                "universe_snapshot_sha256": row.get("universe_snapshot_sha256"),
            }
        )
    return sorted(projected, key=lambda item: item["run_id"])


def compute_window_sha256(rows: list[dict[str, Any]]) -> str:
    """Digest the exact evidence projection that the material verdict consumes."""
    return _sha256_json(_frozen_run_projection(rows))


def _validate_window(window: dict[str, Any], rows: list[dict[str, Any]]) -> None:
    if window.get("status") != "FROZEN_VERIFIED":
        raise EvidenceError("window:not_frozen_verified")
    if window.get("sample_policy") != SAMPLE_POLICY:
        raise EvidenceError("window:sample_policy")
    _require_nonempty_text(window.get("source_ref"), "window:source_ref")
    frozen_ids = window.get("frozen_run_ids")
    if not isinstance(frozen_ids, list):
        raise EvidenceError("window:frozen_run_ids")
    normalized_ids = [_as_int(value, "window:frozen_run_id") for value in frozen_ids]
    if len(normalized_ids) < MIN_OPERATIONAL_SAMPLE:
        raise EvidenceError("window:sample_too_small")
    if len(normalized_ids) != len(set(normalized_ids)):
        raise EvidenceError("window:duplicate_run_id")
    row_ids = sorted(_run_identity(row)[0] for row in rows)
    if sorted(normalized_ids) != row_ids:
        raise EvidenceError("window:run_id_mismatch")
    expected_sha = compute_window_sha256(rows)
    if window.get("sha256") != expected_sha:
        raise EvidenceError("window:sha256")


def _validate_run(row: dict[str, Any]) -> None:
    run_id, screen_id = _run_identity(row)
    if run_id <= 0:
        raise EvidenceError("run_id:nonpositive")
    if screen_id not in COHORT:
        raise EvidenceError(f"run:{run_id}:screen_outside_cohort")
    if row.get("status") != "COMPLETED":
        raise EvidenceError(f"run:{run_id}:not_completed")
    if _as_int(row.get("family_count"), f"run:{run_id}:family_count") != FAMILY_COUNT:
        raise EvidenceError(f"run:{run_id}:family_count")
    if _as_int(row.get("validator_pass_count"), f"run:{run_id}:validator_pass_count") != FAMILY_COUNT:
        raise EvidenceError(f"run:{run_id}:validator_pass_count")
    duration = _as_int(row.get("validator_duration_ms"), f"run:{run_id}:validator_duration_ms")
    if duration <= 0:
        raise EvidenceError(f"run:{run_id}:duration_unmeasured")
    if duration > LIMIT_MS:
        raise EvidenceError(f"run:{run_id}:budget_breach")
    if _as_bool(row.get("explicit_timeout_signal"), f"run:{run_id}:explicit_timeout_signal"):
        raise EvidenceError(f"run:{run_id}:timeout")
    if row.get("currentness_authority") != "CURRENTNESS_AUTHORITY":
        raise EvidenceError(f"run:{run_id}:currentness_authority")
    for field in (
        "source_current",
        "lifecycle_current",
        "source_manifest_current",
        "execution_policy_current",
        "readiness_contract_current",
    ):
        if not _as_bool(row.get(field), f"run:{run_id}:{field}"):
            raise EvidenceError(f"run:{run_id}:{field}")
    for field in ("source_snapshot_sha256", "universe_snapshot_sha256"):
        value = _require_nonempty_text(row.get(field), f"run:{run_id}:{field}")
        if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value.lower()):
            raise EvidenceError(f"run:{run_id}:{field}:sha256")


def _evaluate_core(data: dict[str, Any]) -> dict[str, Any]:
    if data.get("schema_version") != INPUT_SCHEMA:
        raise EvidenceError("input:schema_version")
    receipt = data.get("historical_receipt")
    window = data.get("window")
    rows = data.get("runs")
    if not isinstance(receipt, dict):
        raise EvidenceError("input:historical_receipt")
    if not isinstance(window, dict):
        raise EvidenceError("input:window")
    if not isinstance(rows, list) or not rows:
        raise EvidenceError("input:runs")
    if not all(isinstance(row, dict) for row in rows):
        raise EvidenceError("input:runs_item")

    _validate_receipt(receipt)
    _validate_window(window, rows)
    for row in rows:
        _validate_run(row)

    historical = receipt["payload"]
    return {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": False,
        "budget_breach_count": 0,
        "unmeasured_duration_count": 0,
        "timeout_signal_count": 0,
        "known_false_pass_signals": _as_int(
            historical.get("known_false_pass_signals"), "receipt:known_false_pass_signals"
        ),
        "unresolved_d4": _as_int(historical.get("unresolved_d4"), "receipt:unresolved_d4"),
        "frozen_window_verified": True,
        "frozen_run_ids": sorted(_as_int(x, "window:frozen_run_id") for x in window["frozen_run_ids"]),
        "frozen_window_sha256": window["sha256"],
        "historical_receipt_sha256": receipt["receipt_sha256"],
        "sample_policy": SAMPLE_POLICY,
    }


def _expect_rejected(data: dict[str, Any], mutate) -> None:
    candidate = copy.deepcopy(data)
    mutate(candidate)
    try:
        _evaluate_core(candidate)
    except EvidenceError:
        return
    raise AssertionError("negative_case_false_pass")


def run_adversarial_negatives(data: dict[str, Any]) -> None:
    """Required negative cases; none may be admitted by the material verifier."""
    _expect_rejected(
        data,
        lambda d: d["runs"][0].__setitem__("validator_duration_ms", LIMIT_MS + 1),
    )
    _expect_rejected(
        data,
        lambda d: d["runs"][0].__setitem__("validator_duration_ms", 0),
    )
    _expect_rejected(
        data,
        lambda d: d["runs"][0].__setitem__("explicit_timeout_signal", True),
    )
    _expect_rejected(
        data,
        lambda d: d["runs"][0].__setitem__("source_current", False),
    )
    _expect_rejected(
        data,
        lambda d: d["historical_receipt"]["payload"].__setitem__(
            "known_false_pass_signals", 1
        ),
    )
    _expect_rejected(
        data,
        lambda d: d["historical_receipt"]["payload"].__setitem__("unresolved_d4", 1),
    )
    _expect_rejected(
        data,
        lambda d: d["window"].__setitem__("sha256", "0" * 64),
    )
    _expect_rejected(
        data,
        lambda d: d["window"].__setitem__("frozen_run_ids", d["window"]["frozen_run_ids"][:-1]),
    )


def adjudicate(data: dict[str, Any]) -> dict[str, Any]:
    observed = _evaluate_core(data)
    run_adversarial_negatives(data)
    observed["adversarial_case_executed"] = True
    return observed


def _fixture() -> dict[str, Any]:
    rows = []
    for idx, (run_id, screen_id, duration) in enumerate(
        [(930, 58, 115_551), (931, 1, 120_015), (944, 43, 124_635)]
    ):
        rows.append(
            {
                "run_id": run_id,
                "pantalla_id": screen_id,
                "status": "COMPLETED",
                "validator_duration_ms": duration,
                "family_count": FAMILY_COUNT,
                "validator_pass_count": FAMILY_COUNT,
                "explicit_timeout_signal": False,
                "currentness_authority": "CURRENTNESS_AUTHORITY",
                "source_current": True,
                "lifecycle_current": True,
                "source_manifest_current": True,
                "execution_policy_current": True,
                "readiness_contract_current": True,
                "source_snapshot_sha256": hashlib.sha256(f"source-{idx}".encode()).hexdigest(),
                "universe_snapshot_sha256": hashlib.sha256(f"universe-{idx}".encode()).hexdigest(),
            }
        )
    receipt = {
        "receipt_sha256": RECEIPT_SHA,
        "payload": {
            "schema_version": RECEIPT_SCHEMA,
            "verification_status": "VERIFIED",
            "pass": True,
            "screens_total": 13,
            "families_total": FAMILY_COUNT,
            "screens_below_2": 0,
            "families_below_2": 0,
            "min_screen_observations": 4,
            "min_family_observations": 189,
            "known_false_pass_signals": 0,
            "unresolved_d4": 0,
        },
    }
    window = {
        "status": "FROZEN_VERIFIED",
        "sample_policy": SAMPLE_POLICY,
        "source_ref": "fixture://self-test-only",
        "frozen_run_ids": [row["run_id"] for row in rows],
    }
    window["sha256"] = compute_window_sha256(rows)
    return {
        "schema_version": INPUT_SCHEMA,
        "historical_receipt": receipt,
        "window": window,
        "runs": rows,
    }


def self_test() -> None:
    fixture = _fixture()
    observed = adjudicate(fixture)
    assert observed["test_passed"] is True
    assert observed["test_exit_code"] == 0
    assert observed["adversarial_case_executed"] is True
    assert observed["budget_breach_count"] == 0
    assert observed["unmeasured_duration_count"] == 0
    assert observed["timeout_signal_count"] == 0
    assert observed["known_false_pass_signals"] == 0
    assert observed["unresolved_d4"] == 0
    assert observed["frozen_window_verified"] is True
    assert fixture["window"]["source_ref"].startswith("fixture://")


def _default_evidence_ref() -> str | None:
    server = os.environ.get("GITHUB_SERVER_URL")
    repo = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT")
    if server and repo and run_id:
        suffix = f"/attempts/{attempt}" if attempt else ""
        return f"{server}/{repo}/actions/runs/{run_id}{suffix}"
    return None


def _load_input(path: str) -> dict[str, Any]:
    if path == "-":
        value = json.load(sys.stdin)
    else:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise EvidenceError("input:not_object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--input", help="Material read-only evidence JSON; use - for stdin")
    parser.add_argument("--output", help="Write material result JSON to this path")
    parser.add_argument("--evidence-ref", help="Authorized runner evidence reference")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        print("PASS_LOGIC_SELF_TEST_ONLY material_pass=false checkpoint_done=false")
        return 0

    if not args.input:
        parser.error("--input is required outside --self-test")

    evidence_ref = args.evidence_ref or _default_evidence_ref()
    if not evidence_ref or evidence_ref.startswith("fixture://"):
        print(
            _canonical_json(
                {
                    "schema_version": SCHEMA_VERSION,
                    "status": "BLOCKED",
                    "test_code": TEST_CODE,
                    "reason": "AUTHORIZED_RUNNER_EVIDENCE_REF_REQUIRED",
                }
            )
        )
        return 2

    try:
        data = _load_input(args.input)
        if str(data.get("window", {}).get("source_ref", "")).startswith("fixture://"):
            raise EvidenceError("material:fixture_source_forbidden")
        observed = adjudicate(data)
    except (EvidenceError, AssertionError, json.JSONDecodeError, OSError) as exc:
        result = {
            "schema_version": SCHEMA_VERSION,
            "status": "FAIL",
            "test_code": TEST_CODE,
            "suite_code": SUITE_CODE,
            "reason": str(exc),
            "observed": {
                "test_passed": False,
                "test_exit_code": 2,
                "semantic_authority_bound": False,
                "adversarial_case_executed": False,
                "budget_breach_count": None,
                "unmeasured_duration_count": None,
                "timeout_signal_count": None,
                "known_false_pass_signals": None,
                "unresolved_d4": None,
                "frozen_window_verified": False,
            },
            "evidence_ref": evidence_ref,
        }
        text = _canonical_json(result)
        if args.output:
            Path(args.output).write_text(text + "\n", encoding="utf-8")
        print(text)
        return 2

    result = {
        "schema_version": SCHEMA_VERSION,
        "status": "PASS",
        "test_code": TEST_CODE,
        "suite_code": SUITE_CODE,
        "observed": observed,
        "evidence_ref": evidence_ref,
    }
    text = _canonical_json(result)
    if args.output:
        Path(args.output).write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
