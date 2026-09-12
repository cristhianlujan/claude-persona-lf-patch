#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from product_director_compact_context_v1 import build_candidate

report = build_candidate()
assert report["schema"] == "lf-product-director-compact-context/v1"
assert report["activation_status"] == "CANDIDATE_NOT_ACTIVE"
assert report["requirement_retention"] == "PASS_MARKER_AND_SECTION_BOUND"
assert report["authority_retention"] == "PASS_MARKER_AND_SECTION_BOUND"
assert report["candidate_source_chars"] < report["original_source_chars"]
assert report["reduction_pct"] > 0
assert report["candidate_token_proxy_chars_div_4"] < report["original_token_proxy_chars_div_4"]
for marker in report["required_authority_markers"]:
    assert marker in report["compact_profile"], marker
for title in report["kept_sections"]:
    assert f"## {title}" in report["compact_profile"], title
assert "profiles/shared_context/marketplace_context_pack.md" not in report["compact_profile"]
print("PRODUCT_DIRECTOR_COMPACT_CONTEXT_V1_PASS " + json.dumps({key:value for key,value in report.items() if key != "compact_profile"}, sort_keys=True, separators=(",", ":")))
