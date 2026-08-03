#!/usr/bin/env python3
"""Legacy E.13 verification entry point disabled by LOTE-E.14."""
from __future__ import annotations
import sys
sys.dont_write_bytecode = True

def main() -> int:
    print("E14_VERIFY_REQUIRED: use PR93_LOTE_E14_VERIFY.py", file=sys.stderr)
    return 20

if __name__ == "__main__":
    raise SystemExit(main())
