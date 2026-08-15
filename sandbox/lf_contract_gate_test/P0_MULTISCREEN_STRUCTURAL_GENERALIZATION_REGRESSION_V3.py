#!/usr/bin/env python3
"""Compatibility entrypoint for the current multiscreen structural gate.

V9 preserves V8 and makes structured visual preflight mandatory, pixel-derived,
observation-bound and adversarially tested across legitimate geometry, scale,
inversion, touching components, evidence replay and re-sealing attacks.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SCRIPT_ROOT = ROOT.parent / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(ROOT))

from P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V9 import main


if __name__ == "__main__":
    raise SystemExit(main())
