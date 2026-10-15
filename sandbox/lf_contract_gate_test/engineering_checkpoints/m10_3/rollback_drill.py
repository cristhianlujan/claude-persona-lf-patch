#!/usr/bin/env python3
"""M10.3 CP3 source guard: real executed DB proof is in governed Train SQL."""
import json
from pathlib import Path

TEST_CODE = "ENG_M10_3_ROLLBACK_DRILL"
root = Path(__file__).resolve().parents[4]
paths = list((root / "supabase/migrations").glob("*_lf_ig_m103_cp3_rollback_drill_v1.sql"))
required = (
    "BLOCK_CURRENTNESS_MISMATCH",
    "PROMOTED_CURRENT",
    "ROLLBACK_AFTER_M103_CP3",
    "CP3_CANARY_RESIDUE",
    "fn_engineering_checkpoint_assertion_record_v1",
    "fn_engineering_checkpoint_transition_v1",
)
if len(paths) != 1:
    raise SystemExit("FAIL_M103_CP3_SOURCE_NOT_EXACTLY_ONE")
source = paths[0].read_text(encoding="utf-8")
positive = all(term in source for term in required)
mutated = source.replace("BLOCK_CURRENTNESS_MISMATCH", "PROMOTED_CURRENT")
negative = not all(term in mutated for term in required)
if not (positive and negative):
    raise SystemExit("FAIL_M103_CP3_SOURCE_GUARD")
print(json.dumps({
    "test_code": TEST_CODE,
    "status": "PASS_STATIC_ONLY",
    "negative_mutation_rejected": True,
    "db_material_proof": "TRAIN_SQL_REQUIRED",
}, sort_keys=True))
