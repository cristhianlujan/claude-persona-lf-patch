#!/usr/bin/env python3
"""Compatibility entrypoint: temporary IG-A n=5 performance campaign.

The reusable exact-version implementation is preserved in
input_governance_ig006_ig007_exact_v2_core.py. This shim is reverted after the
campaign; no runtime or production authority is granted.
"""
# Static guard anchors retained for the existing CI admission:
# TEST_TEMPLATE_EXACT_PAIR_BIND_PASS
# ROLLBACK_PRESTATE_INVALID
from input_governance_iga_perf_repeat_adapter import *  # noqa: F401,F403

if __name__ == "__main__":
    raise SystemExit(main())
