#!/usr/bin/env python3
"""Compatibility entrypoint for the current multiscreen structural gate.

The V4 implementation replaces the experimental single-blob fixture transport
with bounded lossless text chunks while preserving the V3 routing contract.
"""
from P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V4 import main


if __name__ == "__main__":
    raise SystemExit(main())
