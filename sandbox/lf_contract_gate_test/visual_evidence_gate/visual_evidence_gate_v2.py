#!/usr/bin/env python3
"""Evidence-only candidate for VISUAL_EVIDENCE_GATE.

This candidate consumes an already-produced, source-bound convergence receipt.
It validates evidence integrity and fail-closed pass conditions only.

Boundary:
- does not decide applicability or repository/path admission;
- does not execute OCR, visual parsing/reconciliation, graders or producer regressions;
- does not execute or persist Human Review decisions;
- does not own exact-head transport or durable persistence;
- does not authorize runtime, merge or production.

The current v1 remains untouched until this candidate is independently verified,
registered as a new capability version and cut over in a separate sequential lot.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

SCHEMA_VERSION = "lf-visual-evidence-gate/v2"
CONTROL_ID = "VISUAL_EVIDENCE_GATE"
LEGACY_ORCHESTRATION_ALIAS = "P0_VISUAL_RUNTIME"
ACCEPTED_RECEIPT_SCHEMA = "p0-convergence-receipt-v4/v2"
REPO_ROOT = Path(__file__).resolve().parents[3]
CONVERGENCE_CONTRACT = (
    REPO_ROOT / "sandbox/story_creator_p0_visual/v1.1/scripts/p0_visual_convergence_v4.py"
)

REQUIRED_GATE_PROOFS = (
    "regression_suite",
    "adversarial_suite",
    "source_sha_binding",
    "artifact_hash_chain",
)
ZERO_COUNT_FIELDS = (
    "critical",
    "high",
    "unresolved_medium",
    "suspicious_confirmed",
    "contradictions",
    "unsupported_claims",
    "critical_omissions",
)
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")

OWNERSHIP = {
    "visual_evidence_validation": True,
    "applicability": False,
    "path_admission": False,
    "visual_producer_execution": False,
    "human_decision_persistence": False,
    "exact_head_transport": False,
    "durable_evidence_persistence": False,
    "runtime_or_production_authorization": False,
}


class VisualEvidenceGateV2Error(RuntimeError):
    pass


def _load_convergence_contract():
    if not CONVERGENCE_CONTRACT.is_file():
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_CONVERGENCE_CONTRACT_MISSING")
    spec = importlib.util.spec_from_file_location(
        "visual_evidence_gate_v2_convergence_contract", CONVERGENCE_CONTRACT
    )
    if spec is None or spec.loader is None:
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_CONVERGENCE_CONTRACT_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _require_digest(value: Any, *, width: int, field: str) -> str:
    pattern = HEX64 if width == 64 else HEX40
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise VisualEvidenceGateV2Error(f"FAIL_VISUAL_EVIDENCE_V2_BAD_DIGEST:{field}")
    return value


def validate_receipt(receipt: Any) -> Mapping[str, object]:
    if not isinstance(receipt, dict):
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_RECEIPT_NOT_OBJECT")
    if receipt.get("schema_version") != ACCEPTED_RECEIPT_SCHEMA:
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_RECEIPT_SCHEMA")

    source_sha256 = _require_digest(receipt.get("source_sha256"), width=64, field="source_sha256")
    code_head_sha = _require_digest(receipt.get("code_head_sha"), width=40, field="code_head_sha")
    configuration_sha256 = _require_digest(
        receipt.get("configuration_sha256"), width=64, field="configuration_sha256"
    )

    clean_passes = receipt.get("clean_passes")
    if not isinstance(clean_passes, list) or len(clean_passes) < 2:
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_CLEAN_PASSES")
    if receipt.get("grader_coverage_percent") != 100.0:
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_GRADER_COVERAGE")

    nonzero = {
        field: receipt.get(field)
        for field in ZERO_COUNT_FIELDS
        if receipt.get(field) != 0
    }
    if nonzero:
        raise VisualEvidenceGateV2Error(
            "FAIL_VISUAL_EVIDENCE_V2_OPEN_FINDINGS:" + ",".join(sorted(nonzero))
        )

    proofs = receipt.get("gate_proofs")
    if not isinstance(proofs, dict) or set(proofs) != set(REQUIRED_GATE_PROOFS):
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_GATE_PROOFS_SHAPE")

    contract = _load_convergence_contract()
    for gate in REQUIRED_GATE_PROOFS:
        valid = contract.validate_gate_proof(
            proofs.get(gate),
            gate=gate,
            source_sha256=source_sha256,
            code_head_sha=code_head_sha,
            configuration_sha256=configuration_sha256,
        )
        if valid is not True:
            raise VisualEvidenceGateV2Error(
                f"FAIL_VISUAL_EVIDENCE_V2_GATE_PROOF:{gate}"
            )

    if receipt.get("result") != "PASS_P0_V4_CLOSED_LOOP":
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_UPSTREAM_RESULT")

    return {
        "schema_version": SCHEMA_VERSION,
        "control_id": CONTROL_ID,
        "result": "PASS",
        "source_sha256": source_sha256,
        "code_head_sha": code_head_sha,
        "configuration_sha256": configuration_sha256,
        "validated_gate_proofs": list(REQUIRED_GATE_PROOFS),
    }


def load_receipt(path: Path) -> Mapping[str, object]:
    try:
        raw = path.read_text(encoding="utf-8")
        receipt = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise VisualEvidenceGateV2Error(
            f"FAIL_VISUAL_EVIDENCE_V2_RECEIPT_READ:{type(exc).__name__}"
        ) from exc
    return validate_receipt(receipt)


def self_test() -> Mapping[str, object]:
    if CONTROL_ID == LEGACY_ORCHESTRATION_ALIAS:
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_ID_NOT_DURABLE")
    if not CONVERGENCE_CONTRACT.is_file():
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_CONVERGENCE_CONTRACT_MISSING")
    if set(OWNERSHIP) != {
        "visual_evidence_validation",
        "applicability",
        "path_admission",
        "visual_producer_execution",
        "human_decision_persistence",
        "exact_head_transport",
        "durable_evidence_persistence",
        "runtime_or_production_authorization",
    }:
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_OWNERSHIP_SHAPE")
    if OWNERSHIP["visual_evidence_validation"] is not True:
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_OWNER_MISSING")
    if any(value for key, value in OWNERSHIP.items() if key != "visual_evidence_validation"):
        raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_FOREIGN_OWNER")
    print("PASS_VISUAL_EVIDENCE_GATE_V2_SELFTEST=1/1")
    return {
        "schema_version": SCHEMA_VERSION,
        "control_id": CONTROL_ID,
        "ownership": dict(OWNERSHIP),
        "accepted_receipt_schema": ACCEPTED_RECEIPT_SCHEMA,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--receipt")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            self_test()
        else:
            if not args.receipt:
                raise VisualEvidenceGateV2Error("FAIL_VISUAL_EVIDENCE_V2_RECEIPT_REQUIRED")
            result = load_receipt(Path(args.receipt))
            print(
                "PASS_VISUAL_EVIDENCE_GATE_V2="
                + f"{len(result['validated_gate_proofs'])}/{len(REQUIRED_GATE_PROOFS)}"
            )
    except VisualEvidenceGateV2Error as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
