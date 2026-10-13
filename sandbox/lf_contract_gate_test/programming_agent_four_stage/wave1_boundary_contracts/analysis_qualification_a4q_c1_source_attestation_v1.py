#!/usr/bin/env python3
"""A4Q_C1 source-attestation adapter (mechanics only; see the common module for limits)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_c1_source_attestation_common_v1 as common  # noqa: E402
import validate_wave1_boundary_contracts_v1 as stage  # noqa: E402

SPEC = common.Spec(
    unit="A4",
    source_name="shared_change_impact_contract_v1.json",
    callable_name="validate_shared_impact",
    validate=stage.validate_shared_impact,
    structural_object=lambda: stage.load("shared_change_impact_contract_v1.json"),
)

if __name__ == "__main__":
    common.main(SPEC)
