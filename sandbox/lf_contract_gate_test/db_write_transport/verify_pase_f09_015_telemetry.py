#!/usr/bin/env python3
"""Read-only fixture verifier for PASE-ATOM-F09-015 telemetry records."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from pase_f09_015_telemetry import retry_chains, verify_execution


def verify_document(document: dict) -> dict:
    executions = document.get("executions") or []
    return {"executions": [verify_execution(item) for item in executions],
            "retry_chains": retry_chains(executions)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="JSON snapshot exported read-only from existing Train records")
    args = parser.parse_args()
    report = verify_document(json.loads(Path(args.input).read_text(encoding="utf-8")))
    print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
