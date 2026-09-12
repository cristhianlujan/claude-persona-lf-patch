#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASELINE = ROOT / "BASELINE_CURRENT_199_V1_20260902.json"
ARTIFACT_SHA = "ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287"
OCR_SHA = "2483a0270d26bfdc9023b12cad2cd0c3385367b41a30ea5f601682a231fd49ef"

b = json.loads(BASELINE.read_text(encoding="utf-8"))
assert b["schema"] == "lf-profile-runtime-current-baseline/v1"
assert b["baseline_id"] == "B2B-CARGA-001_CURRENT_199_V1"
assert b["artifact"]["sha256"] == ARTIFACT_SHA
assert b["artifact"]["width_px"] == 1600 and b["artifact"]["height_px"] == 1000
assert b["source_evidence"]["ocr_observation_count"] == 199
assert b["source_evidence"]["ocr_observations_sha256"] == OCR_SHA
assert b["resolver_v3"]["input_count"] == 199
assert b["resolver_v3"]["residual_count"] == 18
assert b["targeted_reread"]["decision_equivalent_regions"] == "18/18"
assert b["targeted_reread"]["worse_regions"] == 0
assert b["quality"]["critical_regressions_count"] == 0
assert b["quality"]["historical_334_bbox_parity"] == "NOT_PROVEN"
assert b["quality"]["p02_p03_historical_334_parity"] == "NOT_PROVEN"
contract = b["comparability_contract"]
assert contract["may_compare_future_v2_v3_against_this_baseline"] is True
assert contract["may_claim_historical_334_parity"] is False
assert contract["same_artifact_required"] is True
assert contract["same_ocr_observation_sha_required"] is True
assert contract["semantic_utility_is_separate_gate"] is True
assert b["status"] == "IMMUTABLE_CANDIDATE_BASELINE"
print("CURRENT_199_BASELINE_GUARD_V3_PASS historical_334_parity=NOT_PROVEN future_same_input_comparison=ALLOWED")
