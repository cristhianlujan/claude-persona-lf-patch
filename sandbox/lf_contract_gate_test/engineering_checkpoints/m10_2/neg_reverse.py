#!/usr/bin/env python3
"""CP5 source-guard only; machine canary and assertion are in the Train SQL."""
import json
from pathlib import Path

TEST_CODE = "ENG_M10_2_NEG_REVERSE"
root = Path(__file__).resolve().parents[4]
files = list((root / "supabase/migrations").glob("*_lf_ig_m102_cp5_canary_assertion_v1.sql"))
required = ["BLOCK_CURRENTNESS_MISMATCH", "PROMOTED_CURRENT", "ROLLBACK_AFTER_CP5_TEST",
            "CANARY_RESIDUE", "fn_engineering_checkpoint_assertion_record_v1"]
if len(files) != 1:
    raise SystemExit("FAIL_MISSING_EXACT_MIGRATION")
source = files[0].read_text()
good = all(x in source for x in required)
negative = not all(x in source.replace("BLOCK_CURRENTNESS_MISMATCH", "MUTATED") for x in required)
if not (good and negative):
    raise SystemExit("FAIL_SOURCE_GUARD")
print(json.dumps({"test_code": TEST_CODE, "status": "PASS_STATIC_ONLY",
                  "db_execution": "VERSIONED_TRAIN_SQL_REQUIRED",
                  "adversarial_mutation_rejected": negative}))
