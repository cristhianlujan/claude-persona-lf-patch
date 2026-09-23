#!/usr/bin/env python3
import sys

CODE = "WORK_PROTOCOL_V1_DEPRECATED_DO_NOT_USE"

if __name__ == "__main__":
    print(CODE, file=sys.stderr)
    raise SystemExit(2)
