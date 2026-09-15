#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import io
import json
import subprocess
import tarfile
import tempfile
from pathlib import Path
from typing import Any

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FROZEN_S26_REF = "48916fd36bcaff8eadd60944848e81adbea55c54"
S26_MATRIX_REF = "794a86fc8ea7fe3921a17bb31b9087c097a01cef"
VALIDATOR_PATH = "profiles/ui_architect/validators/validate_composer_payload_boundary.py"
BASE_OUTPUT_PATH = HERE / "R02C_LANGGRAPH_FUNCTIONAL_OUTPUT.json"
MATRIX_PATH = HERE / "R02D_W0_HISTORICAL_MATRIX.json"


def load_frozen_boundary() -> Any:
    frozen_root = Path(tempfile.mkdtemp(prefix="lf-r02d-frozen-"))
    proc = subprocess.run(
        ["git", "archive", FROZEN_S26_REF, VALIDATOR_PATH],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    with tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r:*") as archive:
        archive.extractall(frozen_root)
    path = frozen_root / VALIDATOR_PATH
    spec = importlib.util.spec_from_file_location("r02d_frozen_composer_boundary", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("R02D_FROZEN_BOUNDARY_IMPORT_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mutate(base: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    data = copy.deepcopy(base)
    mutation = case["mutation"]
    if mutation == "NONE":
        return data
    if mutation == "REMOVE_COMPOSER_PAYLOAD":
        data.pop("composer_payload", None)
        return data
    if mutation == "DIVERGE_COMPOSER_FROM_DETERMINISTIC_PROJECTION":
        data["composer_payload"]["screen_definition"]["purpose"] = "R02D intentionally divergent purpose"
        return data
    if mutation == "INJECT_GITHUB_REF_IN_COMPOSER_PAYLOAD":
        data["composer_payload"]["risk_controls"].append("github://owner/repo@deadbeef/path")
        return data
    if mutation == "REINSERT_GOVERNANCE_CONTEXT_IN_DELIVERABLE":
        data["deliverable_created"]["governance_context"] = copy.deepcopy(
            data["governance_envelope"]["context"]
        )
        return data
    if mutation == "POINT_HANDOFF_TO_DELIVERABLE_INSTEAD_OF_COMPOSER_PAYLOAD":
        data["handoff_to_next"]["payload_ref"] = "deliverable_created"
        return data
    raise RuntimeError(f"R02D_UNKNOWN_MUTATION:{mutation}")


def evaluate(boundary: Any, base: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    mutated = mutate(base, case)
    errors = boundary.validate(mutated)
    return {
        "case_id": case["case_id"],
        "valid": not errors,
        "codes": [item.get("code") for item in errors],
        "errors": errors,
    }


def main() -> int:
    boundary = load_frozen_boundary()
    base = json.loads(BASE_OUTPUT_PATH.read_text(encoding="utf-8"))
    matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))

    base_errors = boundary.validate(base)
    if base_errors:
        raise RuntimeError(f"R02D_BASE_OUTPUT_NOT_VALID:{base_errors}")

    @task(name="lf_r02d_frozen_composer_boundary_validate")
    def validate_task(payload: dict[str, Any]) -> dict[str, Any]:
        return evaluate(boundary, base, payload["case"])

    @entrypoint(checkpointer=InMemorySaver())
    def functional(payload: dict[str, Any]) -> dict[str, Any]:
        return validate_task(payload).result()

    results: list[dict[str, Any]] = []
    for index, case in enumerate(matrix["cases"], start=1):
        direct = evaluate(boundary, base, case)
        wrapped = functional.invoke(
            {"case": case},
            config={"configurable": {"thread_id": f"r02d-{index:02d}-{case['case_id'].lower()}"}},
        )
        expected_codes = case["expected_codes"]
        parity = direct == wrapped
        expected_match = direct["codes"] == expected_codes
        results.append(
            {
                "case_id": case["case_id"],
                "kind": case["kind"],
                "mapped_s26_objectives": case["mapped_s26_objectives"],
                "expected_codes": expected_codes,
                "direct": direct,
                "functional": wrapped,
                "direct_equals_functional": parity,
                "expected_codes_match_exactly": expected_match,
                "status": "PASS" if parity and expected_match else "FAIL",
            }
        )

    status = "PASS" if all(item["status"] == "PASS" for item in results) else "FAIL"
    report = {
        "schema": "LF_LANGGRAPH_R02D_W0_HISTORICAL_PARITY_REPORT_V1",
        "gate": "R02-D",
        "mode": "W0_PREBUILD_NOW_HISTORICAL_REPLAY",
        "final_certification": False,
        "final_rerun_required": True,
        "frozen_s26_ref": FROZEN_S26_REF,
        "s26_matrix_ref": S26_MATRIX_REF,
        "profile": "ui_architect",
        "langgraph_api": "FUNCTIONAL_API",
        "model_called": False,
        "network_calls": 0,
        "production_effect": False,
        "case_count": len(results),
        "pass_count": sum(1 for item in results if item["status"] == "PASS"),
        "cases": results,
        "status": status,
        "claim_ceiling": "HISTORICAL_W0_PARITY_ENGINEERING_EVIDENCE_ONLY_NOT_FINAL_S26_CERTIFICATION_NOT_MIGRATION_AUTHORIZATION",
    }
    print(json.dumps(report, sort_keys=True))
    if status != "PASS":
        raise RuntimeError("R02D_W0_HISTORICAL_PARITY_FAILED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
