#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess

import run_s26_real_bundle_certification as real_certification
from s26_strict_zip_certification import certify_zip_strict

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

    # Pull-request GITHUB_SHA can be a synthetic merge SHA. After proving the
    # checkout is exactly the reviewed source head, pin the underlying builder
    # to that source commit and replace its certification entrypoint with the
    # strict archive guard. This blocks duplicate/case-colliding paths,
    # traversal, symlinks and encrypted entries before any extraction/replay.
    os.environ["GITHUB_SHA"] = expected
    real_certification.certify_zip = certify_zip_strict
    return real_certification.main()


if __name__ == "__main__":
    raise SystemExit(run())
