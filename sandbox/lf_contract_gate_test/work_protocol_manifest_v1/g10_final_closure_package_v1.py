#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

CODE = "WORK_PROTOCOL_V1_DEPRECATED_DO_NOT_USE"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ci-plan")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    payload = {
        "schema_version": "LF_WORK_PROTOCOL_G10_DEPRECATION_RECEIPT_V1",
        "result": "DEPRECATED_DO_NOT_USE",
        "blocking_code": CODE,
        "runtime_activation_allowed": False,
        "production_activation_allowed": False,
        "rollout_allowed": False
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
