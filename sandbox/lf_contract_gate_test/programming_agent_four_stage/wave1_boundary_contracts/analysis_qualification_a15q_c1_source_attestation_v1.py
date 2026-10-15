#!/usr/bin/env python3
"""A15Q_C1 source-attestation adapter (mechanics only; see the common module for limits).

The stage validator is the A15 freeze validator: it recomputes every bundle blob from the
CURRENT file bytes and blocks while the refreeze lacks an independent_confirmation_ref.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_c1_source_attestation_common_v1 as common  # noqa: E402
import validate_analysis_v1_freeze_manifest_v1 as freeze  # noqa: E402


def validate(manifest) -> None:
    verdict, details = freeze.validate(manifest)
    if verdict != "PASS_FREEZE_CURRENT":
        raise ValueError(verdict + (":" + ",".join(details) if details else ""))


def load():
    return json.loads(freeze.MANIFEST.read_text(encoding="utf-8"))


SPEC = common.Spec(unit="A15", source_name="analysis_v1_freeze_manifest_v1.json",
                   callable_name="validate", validate=validate, structural_object=load)

if __name__ == "__main__":
    common.main(SPEC)
