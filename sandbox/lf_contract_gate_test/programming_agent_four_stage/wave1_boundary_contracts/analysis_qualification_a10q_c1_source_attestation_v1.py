#!/usr/bin/env python3
"""A10Q_C1 source-attestation adapter (mechanics only; see the common module for limits)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_c1_source_attestation_common_v1 as common  # noqa: E402
import validate_analysis_evaluation_campaign_v1 as stage  # noqa: E402

# The campaign validator checks the campaign-contract form (A10-A14 share it);
# the unit's own canonical source is attested by hash/subject/currentness.
SPEC = common.Spec(
    unit="A10",
    source_name="analysis_evaluation_campaign_contract_v1.json",
    callable_name="validate",
    validate=stage.validate,
    structural_object=stage.load,
)

if __name__ == "__main__":
    common.main(SPEC)
