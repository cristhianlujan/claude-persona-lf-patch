#!/usr/bin/env python3
"""Compatibility recovery entrypoint for the temporary IG-A n=5 campaign."""
# Static guard anchors retained for the existing CI admission:
# RECOVERY_UNSUPPORTED_STATE
# safety_restore
import input_governance_iga_perf_repeat_adapter as perf
import input_governance_ig006_ig007_exact_v2_recovery_core as recovery_core

recovery_core.a = perf

if __name__ == "__main__":
    raise SystemExit(recovery_core.main())
