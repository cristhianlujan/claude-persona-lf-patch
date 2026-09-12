#!/usr/bin/env python3
"""Blocked paid-provider entrypoint for governed profile execution.

The repository's active runtime policy is ZERO_COST_ONLY. This file remains as
an explicit tombstone for the former OpenAI live entrypoint so existing callers
fail closed instead of silently consuming billable API usage.
"""

from __future__ import annotations

import sys


def main() -> int:
    print(
        "BLOCK PAID_PROVIDER_DISABLED_BY_ZERO_COST_POLICY: "
        "OpenAI API live execution is not allowed. Use an approved zero-cost/local runtime.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
