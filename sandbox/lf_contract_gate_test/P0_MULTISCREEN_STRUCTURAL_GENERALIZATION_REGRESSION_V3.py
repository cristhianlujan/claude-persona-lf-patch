#!/usr/bin/env python3
"""Compatibility entrypoint for the current multiscreen structural gate.

V10 preserves V9 and consolidates PR166 at the cause boundary: local geometry,
2-component masking, ROI-padding invariance, UI false-positive separation,
three-state visual observability, evidence mutation resistance and a 5,120-case
deterministic generative campaign.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SCRIPT_ROOT = ROOT.parent / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(ROOT))

from P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V10 import main


if __name__ == "__main__":
    raise SystemExit(main())
