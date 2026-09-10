#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess

from run_s26_real_bundle_certification import main

SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def checked_out_head() -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True
    ).strip()


def run() -> int:
    expected = os.environ.get("S26_C_HEAD_SHA", "").strip()
    if SHA_RE.fullmatch(expected) is None:
        raise SystemExit(f"FAIL_S26_C_EXPECTED_HEAD_SHA_INVALID:{expected}")

    actual = checked_out_head()
    if actual != expected:
        raise SystemExit(
            f"FAIL_S26_C_CHECKOUT_HEAD_MISMATCH:expected={expected}:actual={actual}"
        )

    # The underlying builder uses GITHUB_SHA as its source revision. On a
    # pull_request event GitHub defines GITHUB_SHA as the synthetic merge SHA,
    # not the reviewed source head. Pin it here only after proving the checkout
    # itself is exactly the reviewed source commit.
    os.environ["GITHUB_SHA"] = expected
    return main()


if __name__ == "__main__":
    raise SystemExit(run())
