#!/usr/bin/env python3
"""Fail-closed tombstone for deprecated LF Work Protocol Manifest V1."""
from __future__ import annotations

import sys

DEPRECATION_CODE = "WORK_PROTOCOL_V1_DEPRECATED_DO_NOT_USE"


def validate(*_args, **_kwargs):
    raise RuntimeError(DEPRECATION_CODE)


def main() -> int:
    print(DEPRECATION_CODE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
