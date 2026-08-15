#!/usr/bin/env python3
"""Compatibility entrypoint for the current multiscreen structural gate.

V7 preserves V6 and adds fresh independent-audit regressions for evidence
carriers with missing identity and cross-family stable-ID conflicts.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SCRIPT_ROOT = ROOT.parent / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(ROOT))

from P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V7 import main


if __name__ == "__main__":
    raise SystemExit(main())
