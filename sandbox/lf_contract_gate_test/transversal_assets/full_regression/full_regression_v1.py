#!/usr/bin/env python3
"""FULL_REGRESSION transversal consumer.

Consumes a governed CI plan and canonical carrier receipts. It never determines
applicability and never executes a control owned by a carrier.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping

ASSET_CODE = "FULL_REGRESSION"
CANONICAL_NAME = "TRANSVERSAL_FULL_REGRESSION"
RECEIPT_SCHEMA = "lf-full-regression-receipt/v1"
CARRIER_RECEIPT_SCHEMA = "lf-ci-carrier-receipt/v1"
EXECUTION_ID = "EXEC-FULL-REGRESSION-TRANSVERSAL-V1-20260923-001"
HERE = Path(__file__).resolve().parent
PLAN_PATH = HERE.parents[1] / "s28_ci_lane_router" / "lf_ci_execution_plan_v2.py"

_spec = importlib.util.spec_from_file_location("lf_ci_execution_plan_v2_full_regression_consumer", PLAN_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"BLOCK_FULL_REGRESSION_PLAN_AUTHORITY_LOAD:{PLAN_PATH}")
PLAN = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = PLAN
_spec.loader.exec_module(PLAN)

CANONICAL_CARRIERS = frozenset(PLAN.CANONICAL_CARRIERS)


class FullRegressionError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _carrier_receipt_payload(receipt: Mapping[str, Any]) -> dict[str, Any]:
    keys = (
        "schema_version",
        "carrier",
        "plan_sha256",
        "source_revision",
        "executed_controls",
        "control_results",
        "status",
    )
    if any(key not in receipt for key in keys):
        raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_FIELDS")
    return {key: receipt[key] for key in keys}


def build_carrier_receipt(
    *,
    carrier: str,
    plan_sha256: str,
    source_revision: str,
    executed_controls: Iterable[str],
    control_results: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    controls = sorted(set(executed_controls))
    if carrier not in CANONICAL_CARRIERS:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_CARRIER_UNRESOLVED", carrier)
    results = dict(control_results or {control: "PASS" for control in controls})
    receipt: dict[str, Any] = {
        "schema_version": CARRIER_RECEIPT_SCHEMA,
        "carrier": carrier,
        "plan_sha256": plan_sha256,
        "source_revision": source_revision,
        "executed_controls": controls,
        "control_results": dict(sorted(results.items())),
        "status": "PASS" if controls and all(v == "PASS" for v in results.values()) else "NOT_APPLICABLE" if not controls else "FAIL",
    }
    receipt["receipt_sha256"] = _sha(_carrier_receipt_payload(receipt))
    return receipt


def validate_carrier_receipt(receipt: Mapping[str, Any]) -> None:
    if not isinstance(receipt, Mapping) or receipt.get("schema_version") != CARRIER_RECEIPT_SCHEMA:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_SCHEMA")
    carrier = receipt.get("carrier")
    if carrier not in CANONICAL_CARRIERS:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_CARRIER_UNRESOLVED", str(carrier))
    controls = receipt.get("executed_controls")
    results = receipt.get("control_results")
    if not isinstance(controls, list) or controls != sorted(controls) or len(controls) != len(set(controls)):
        raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_CONTROLS", carrier)
    if not isinstance(results, Mapping) or sorted(results) != controls:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_RESULTS", carrier)
    if any(value != "PASS" for value in results.values()):
        raise FullRegressionError("BLOCK_FULL_REGRESSION_CONTROL_NOT_PASS", carrier)
    expected_status = "NOT_APPLICABLE" if not controls else "PASS"
    if receipt.get("status") != expected_status:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_STATUS", carrier)
    if receipt.get("receipt_sha256") != _sha(_carrier_receipt_payload(receipt)):
        raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_SHA", carrier)


def _base_output(plan: Mapping[str, Any], status: str) -> dict[str, Any]:
    return {
        "schema_version": RECEIPT_SCHEMA,
        "asset_code": ASSET_CODE,
        "canonical_name": CANONICAL_NAME,
        "execution_id": EXECUTION_ID,
        "status": status,
        "plan_sha256": plan["plan_sha256"],
        "applicability_decision": plan["applicability_decision"],
        "full_regression_semantics": "CONSUME_GOVERNED_PLAN_ONLY",
        "execution_ownership": "CANONICAL_CARRIERS_ONLY",
        "local_applicability_decisions": 0,
        "unplanned_executions": 0,
        "duplicate_control_executions": 0,
        "retired_control_executions": 0,
        "parallel_active_paths": 0,
        "fail_open_cases": 0,
    }


def consume(
    plan: Mapping[str, Any],
    carrier_receipts: Iterable[Mapping[str, Any]],
    *,
    expected_source_revision: str | None = None,
    retired_controls: Iterable[str] = (),
) -> dict[str, Any]:
    if not isinstance(plan, Mapping):
        raise FullRegressionError("BLOCK_FULL_REGRESSION_PLAN_MISSING")
    try:
        PLAN.validate_plan_contract(plan)
    except Exception as exc:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_PLAN_INVALID", str(exc)) from exc

    source_authority = plan.get("source_authority")
    if source_authority is not None:
        if not isinstance(source_authority, Mapping) or source_authority.get("ready") is not True:
            raise FullRegressionError("BLOCK_FULL_REGRESSION_PLAN_STALE_OR_UNREADY")
    if expected_source_revision is not None:
        head = plan.get("head_sha")
        if head is not None and head != expected_source_revision:
            raise FullRegressionError("BLOCK_FULL_REGRESSION_PLAN_SOURCE_REVISION")

    required = list(plan["required_controls"])
    receipts = list(carrier_receipts)
    retired = set(retired_controls)
    if retired & set(required):
        raise FullRegressionError(
            "BLOCK_FULL_REGRESSION_RETIRED_CONTROL_PLANNED",
            ",".join(sorted(retired & set(required))),
        )

    if not required:
        if receipts:
            raise FullRegressionError("BLOCK_FULL_REGRESSION_UNPLANNED_RECEIPT")
        output = _base_output(plan, "NOT_APPLICABLE")
        output.update(
            {
                "planned_controls": [],
                "executed_controls": [],
                "consumed_receipts": [],
                "receipt_sha256": "",
            }
        )
        payload = dict(output)
        payload.pop("receipt_sha256", None)
        output["receipt_sha256"] = _sha(payload)
        return output

    expected_by_carrier = {carrier: list(controls) for carrier, controls in plan["carrier_controls"].items()}
    for carrier in expected_by_carrier:
        if carrier not in CANONICAL_CARRIERS:
            raise FullRegressionError("BLOCK_FULL_REGRESSION_CARRIER_UNRESOLVED", carrier)

    by_carrier: dict[str, Mapping[str, Any]] = {}
    for receipt in receipts:
        validate_carrier_receipt(receipt)
        carrier = str(receipt["carrier"])
        if carrier in by_carrier:
            raise FullRegressionError("BLOCK_FULL_REGRESSION_DUPLICATE_CARRIER_RECEIPT", carrier)
        by_carrier[carrier] = receipt

    missing = sorted(set(expected_by_carrier) - set(by_carrier))
    extra = sorted(set(by_carrier) - set(expected_by_carrier))
    if missing:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_MISSING", ",".join(missing))
    if extra:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_UNPLANNED_CARRIER_RECEIPT", ",".join(extra))

    executed: list[str] = []
    consumed: list[dict[str, Any]] = []
    for carrier, planned_controls in sorted(expected_by_carrier.items()):
        receipt = by_carrier[carrier]
        if receipt.get("plan_sha256") != plan["plan_sha256"]:
            raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_PLAN_SHA", carrier)
        if expected_source_revision is not None and receipt.get("source_revision") != expected_source_revision:
            raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_SOURCE_REVISION", carrier)
        if plan.get("head_sha") and receipt.get("source_revision") != plan.get("head_sha"):
            raise FullRegressionError("BLOCK_FULL_REGRESSION_RECEIPT_HEAD_MISMATCH", carrier)
        actual = list(receipt["executed_controls"])
        if actual != planned_controls:
            unplanned = sorted(set(actual) - set(planned_controls))
            missing_controls = sorted(set(planned_controls) - set(actual))
            detail = f"{carrier}:unplanned={unplanned}:missing={missing_controls}"
            raise FullRegressionError("BLOCK_FULL_REGRESSION_PLANNED_EXECUTED_MISMATCH", detail)
        executed.extend(actual)
        consumed.append(
            {
                "carrier": carrier,
                "receipt_sha256": receipt["receipt_sha256"],
                "executed_controls": actual,
            }
        )

    if len(executed) != len(set(executed)):
        raise FullRegressionError("BLOCK_FULL_REGRESSION_DUPLICATE_CONTROL_EXECUTION")
    if retired & set(executed):
        raise FullRegressionError(
            "BLOCK_FULL_REGRESSION_RETIRED_CONTROL_EXECUTED",
            ",".join(sorted(retired & set(executed))),
        )
    if sorted(executed) != required:
        raise FullRegressionError("BLOCK_FULL_REGRESSION_PLANNED_EXECUTED_MISMATCH")

    output = _base_output(plan, "PASS")
    output.update(
        {
            "planned_controls": required,
            "executed_controls": sorted(executed),
            "consumed_receipts": consumed,
            "receipt_sha256": "",
        }
    )
    payload = dict(output)
    payload.pop("receipt_sha256", None)
    output["receipt_sha256"] = _sha(payload)
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--carrier-receipt", action="append", default=[], type=Path)
    parser.add_argument("--expected-source-revision")
    parser.add_argument("--retired-control", action="append", default=[])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    receipts = [json.loads(path.read_text(encoding="utf-8")) for path in args.carrier_receipt]
    result = consume(
        plan,
        receipts,
        expected_source_revision=args.expected_source_revision,
        retired_controls=args.retired_control,
    )
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
