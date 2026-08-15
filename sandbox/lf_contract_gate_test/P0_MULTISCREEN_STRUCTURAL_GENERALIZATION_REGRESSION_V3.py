#!/usr/bin/env python3
"""Compatibility entrypoint for the current multiscreen structural gate.

V5 keeps the source-bound chunk transport and applies crop completeness only
after isolating the target text ROI from the bordered input container.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SCRIPT_ROOT = ROOT.parent / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(ROOT))

from P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V5 import main


if __name__ == "__main__":
    raise SystemExit(main())
