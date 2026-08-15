#!/usr/bin/env python3
"""Compatibility entrypoint for the current multiscreen structural gate.

V6 preserves the source-bound language-profile/crop invariants and adds the
fail-closed masked structured-value regression from an independent real source.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SCRIPT_ROOT = ROOT.parent / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(ROOT))

from P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V6 import main


if __name__ == "__main__":
    raise SystemExit(main())
