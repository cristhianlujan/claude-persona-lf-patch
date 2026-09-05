#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from profile_context_budget_v1 import build_report

report = build_report()
assert report["schema"] == "lf-profile-runtime-context-budget/v1"
assert report["stale_marketplace_context_exists"] is False
current = report["current_marketplace_context"]
assert current["path"] == "cards/marketplace_lf/decision_product_experience/context_pack.md"
assert current["bytes"] > 0 and current["chars"] > 0
assert len(current["sha256"]) == 64
assert set(report["profiles"]) == {"product_director_lf", "ui_architect", "quality_pack"}
for slug, metrics in report["profiles"].items():
    profile = metrics["profile"]
    assert profile["bytes"] > 0 and profile["chars"] > 0, slug
    assert len(profile["sha256"]) == 64, slug
    assert metrics["combined_source_chars"] == profile["chars"] + current["chars"], slug
    assert metrics["combined_source_bytes"] == profile["bytes"] + current["bytes"], slug
print("PROFILE_CONTEXT_BUDGET_V1_PASS " + json.dumps(report, sort_keys=True, separators=(",", ":")))
