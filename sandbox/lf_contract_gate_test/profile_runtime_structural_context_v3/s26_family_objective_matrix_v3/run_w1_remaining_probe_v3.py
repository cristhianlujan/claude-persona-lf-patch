#!/usr/bin/env python3
from __future__ import annotations

import run_w1_remaining_probe_v2 as harness

needle = 'SOURCE_AUTHORITY_COMMIT = os.environ["S26_SOURCE_AUTHORITY_COMMIT"]\n'
replacement = needle + 'FINAL_SHA = os.environ["S26_FINAL_CANDIDATE_SHA"]\n'
if needle not in harness.CHILD:
    raise SystemExit("BLOCK_W1_V3_PATCH_POINT_MISSING")
harness.CHILD = harness.CHILD.replace(needle, replacement, 1)

if __name__ == "__main__":
    raise SystemExit(harness.main())
