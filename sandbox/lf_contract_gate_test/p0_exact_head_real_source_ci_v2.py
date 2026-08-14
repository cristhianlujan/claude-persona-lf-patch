#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import sys

import p0_exact_head_real_source_ci_v1 as legacy

BROKER_ENV = "P0_EXACT_HEAD_BROKER_URL"
GOVERNED_REF_RE = re.compile(r"^refs/heads/lf/p0-[A-Za-z0-9._/-]+$")


def governed_ref(ref: str) -> bool:
    return ref == "refs/heads/main" or bool(GOVERNED_REF_RE.fullmatch(ref or ""))


def self_test() -> int:
    checks = {
        "main_allowed": governed_ref("refs/heads/main"),
        "p0_branch_allowed": governed_ref("refs/heads/lf/p0-exact-head-real-source-v2"),
        "arbitrary_feature_blocked": not governed_ref("refs/heads/feature/arbitrary"),
        "non_p0_lf_blocked": not governed_ref("refs/heads/lf/not-p0"),
        "tag_blocked": not governed_ref("refs/tags/v1"),
    }
    print(json.dumps({"gate": "PASS_P0_EXACT_HEAD_RUNNER_POLICY_V2" if all(checks.values()) else "FAIL", "checks": checks}, sort_keys=True))
    return 0 if all(checks.values()) else 2


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()

    github_ref = os.environ.get("GITHUB_REF", "").strip()
    if not governed_ref(github_ref):
        legacy.die("FAIL_P0_EXACT_HEAD_REF_NOT_GOVERNED", github_ref or "<missing>")

    broker_url = os.environ.get(BROKER_ENV, "").strip()
    if not broker_url.startswith("https://"):
        legacy.die("FAIL_P0_EXACT_HEAD_BROKER_URL_MISSING_OR_INVALID")

    legacy.EXPECTED_REF = github_ref
    legacy.BROKER_URL = broker_url
    return legacy.main()


if __name__ == "__main__":
    raise SystemExit(main())
