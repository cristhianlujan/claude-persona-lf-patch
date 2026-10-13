#!/usr/bin/env python3
"""A7Q_C1 source-attestation adapter (mechanics only; see the common module for limits)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_c1_source_attestation_common_v1 as common  # noqa: E402
import validate_wave1_boundary_contracts_v1 as stage  # noqa: E402

SPEC = common.Spec(
    unit="A7",
    source_name="analysis_material_front_coverage_contract_v1.json",
    callable_name="validate_material_front_coverage",
    validate=stage.validate_material_front_coverage,
    structural_object=lambda: stage.load("analysis_material_front_coverage_contract_v1.json"),
)

if __name__ == "__main__":
    common.main(SPEC)
