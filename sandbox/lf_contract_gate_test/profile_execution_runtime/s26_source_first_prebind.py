#!/usr/bin/env python3
"""Fail-closed prebind gate for fresh S26 source-first executions.

A fresh S26 material run is not allowed to produce raw/composer/artifact output until
its execution contract, source-fidelity contract, source model and governed build
plan are mutually bound and valid.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from profile_execution_contract import (
    canonical_json_sha256,
    validate_execution_contract,
    validate_source_fidelity_contract,
)
from s26_source_first_runtime import (
    SOURCE_FIRST_MODE,
    validate_governed_build_plan,
    validate_source_model,
)

PREBIND_SCHEMA = "S26_SOURCE_FIRST_PREBIND_RECEIPT_V1"
REQUIRED_JSON_FILES = {
    "execution_contract": "execution_contract.json",
    "source_fidelity_contract": "source_fidelity_contract.json",
    "source_model": "source_model.json",
    "governed_build_plan": "governed_build_plan.json",
}
MATERIAL_OUTPUT_FILENAMES = (
    "raw_output.json",
    "artifact_payload.json",
    "composer_payload.json",
)


class SourceFirstPrebindError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        self.detail = detail
        super().__init__(code if not detail else f"{code}:{detail}")


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SourceFirstPrebindError("PREBIND_REQUIRED_FILE_MISSING", path.name) from exc
    except json.JSONDecodeError as exc:
        raise SourceFirstPrebindError("PREBIND_JSON_INVALID", f"{path.name}:{exc.msg}") from exc


def _file_sha256(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_prebind(evidence_dir: Path) -> dict[str, Any]:
    evidence_dir = evidence_dir.resolve()
    if not evidence_dir.is_dir():
        raise SourceFirstPrebindError("PREBIND_EVIDENCE_DIR_MISSING", str(evidence_dir))

    material_present = [name for name in MATERIAL_OUTPUT_FILENAMES if (evidence_dir / name).exists()]
    if material_present:
        raise SourceFirstPrebindError(
            "PREBIND_MATERIAL_OUTPUT_ALREADY_PRESENT",
            ",".join(sorted(material_present)),
        )

    paths = {key: evidence_dir / name for key, name in REQUIRED_JSON_FILES.items()}
    payloads = {key: _load_json(path) for key, path in paths.items()}

    execution_contract = payloads["execution_contract"]
    fidelity = payloads["source_fidelity_contract"]
    source_model = payloads["source_model"]
    build_plan = payloads["governed_build_plan"]

    contract_errors = validate_execution_contract(execution_contract)
    if contract_errors:
        raise SourceFirstPrebindError("PREBIND_EXECUTION_CONTRACT_INVALID", ",".join(contract_errors))

    fidelity_errors = validate_source_fidelity_contract(fidelity)
    if fidelity_errors:
        raise SourceFirstPrebindError("PREBIND_SOURCE_FIDELITY_INVALID", ",".join(fidelity_errors))

    run_id = execution_contract["run_id"]
    if execution_contract.get("source_fidelity_contract_ref") != fidelity.get("source_ref"):
        raise SourceFirstPrebindError("PREBIND_SOURCE_FIDELITY_REF_MISMATCH")
    if execution_contract.get("source_fidelity_contract_sha256") != fidelity.get("contract_sha256"):
        raise SourceFirstPrebindError("PREBIND_SOURCE_FIDELITY_SHA_MISMATCH")

    source_model_errors = validate_source_model(
        source_model,
        run_id=run_id,
        source_fidelity_contract=fidelity,
    )
    if source_model_errors:
        raise SourceFirstPrebindError("PREBIND_SOURCE_MODEL_INVALID", ",".join(source_model_errors))

    plan_errors = validate_governed_build_plan(
        build_plan,
        run_id=run_id,
        source_model=source_model,
        source_fidelity_contract=fidelity,
    )
    if plan_errors:
        raise SourceFirstPrebindError("PREBIND_GOVERNED_BUILD_PLAN_INVALID", ",".join(plan_errors))

    receipt: dict[str, Any] = {
        "schema": PREBIND_SCHEMA,
        "mode": SOURCE_FIRST_MODE,
        "run_id": run_id,
        "profile_code": execution_contract["profile_code"],
        "execution_contract_sha256": execution_contract["contract_sha256"],
        "source_fidelity_contract_sha256": fidelity["contract_sha256"],
        "source_model_sha256": source_model["source_model_sha256"],
        "governed_build_plan_sha256": build_plan["governed_build_plan_sha256"],
        "input_file_sha256": {key: _file_sha256(path) for key, path in sorted(paths.items())},
        "material_output_absent": True,
        "next_phase": "MATERIAL_BUILD",
        "golden_declared": False,
        "promotion_authorized": False,
    }
    receipt["prebind_receipt_sha256"] = canonical_json_sha256(receipt)
    return receipt


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", type=Path)
    args = parser.parse_args()
    try:
        receipt = validate_prebind(args.evidence_dir)
    except SourceFirstPrebindError as exc:
        print(json.dumps({"valid": False, "code": exc.code, "detail": exc.detail}, ensure_ascii=False))
        return 1
    print(json.dumps({"valid": True, "receipt": receipt}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
