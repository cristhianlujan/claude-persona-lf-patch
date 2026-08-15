#!/usr/bin/env python3
"""Compatibility entrypoint for the current multiscreen structural gate.

V8 preserves V7 and adds glyph-independent source-bound visual obscuration
regressions for AUD-03.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SCRIPT_ROOT = ROOT.parent / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(ROOT))

from P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V8 import main


if __name__ == "__main__":
    raise SystemExit(main())
