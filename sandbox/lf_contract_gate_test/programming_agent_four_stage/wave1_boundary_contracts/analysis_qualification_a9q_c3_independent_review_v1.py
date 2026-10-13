#!/usr/bin/env python3
"""A9Q_C3 adapter (independent-review receipt; mechanics only, see the common module for limits)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_c3_independent_review_common_v1 as common  # noqa: E402

SPEC = common.Spec(unit="A9")

if __name__ == "__main__":
    common.main(SPEC)
