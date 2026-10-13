#!/usr/bin/env python3
"""A5Q_C2 adapter (real-execution receipt; mechanics only, see the common module for limits)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_c2_runtime_receipt_common_v1 as common  # noqa: E402

SPEC = common.Spec(unit="A5")

if __name__ == "__main__":
    common.main(SPEC)
