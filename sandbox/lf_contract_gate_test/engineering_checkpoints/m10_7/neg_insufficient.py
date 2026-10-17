#!/usr/bin/env python3
"""M10.7 negative coverage guard. Diagnostics only; no checkpoint closure.

A JSON supplied by a caller is not a signed Supabase receipt. Even an observed
negative cannot promote a checkpoint; material authority remains in Supabase.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

TEST_CODE = "ENG_M10_7_NEG_INSUFFICIENT"
SCREEN_IDS = frozenset((1, 2, 3, 5, 43, 51, 52, 53, 54, 55, 56, 57, 58))
RECEIPT_SHA = "17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972"


def assess(snapshot: object) -> dict:
    if not isinstance(snapshot, dict):
        raise ValueError("SNAPSHOT_NOT_OBJECT")
    receipt = snapshot.get("receipt")
    if not isinstance(receipt, dict) or not (
        receipt.get("id") == 38
        and receipt.get("receipt_sha256") == RECEIPT_SHA
        and receipt.get("schema_version") == "SOAK_OBSERVATION_HISTORY_V2"
        and receipt.get("verification_status") == "VERIFIED"
        and receipt.get("pass") is True
        and receipt.get("screens_total") == 13
        and receipt.get("families_total") == 47
    ):
        raise ValueError("HISTORICAL_RECEIPT_MISSING_OR_MISMATCHED")
    screens, families = snapshot.get("screens"), snapshot.get("families")
    if not isinstance(screens, list) or not isinstance(families, list):
        raise ValueError("OBSERVATION_COLLECTIONS_REQUIRED")
    if len(screens) != 13 or len(families) != 47:
        raise ValueError("UNIVERSE_CARDINALITY_MISMATCH")
    if any(not isinstance(s, dict) for s in screens) or any(not isinstance(f, dict) for f in families):
        raise ValueError("OBSERVATION_ROW_NOT_OBJECT")
    ids = [s.get("pantalla_id") for s in screens]
    codes = [f.get("family_code") for f in families]
    if len(set(ids)) != len(ids) or set(ids) != SCREEN_IDS:
        raise ValueError("SCREEN_UNIVERSE_MISMATCH")
    if any(not isinstance(v, str) or not v.strip() for v in codes) or len(set(codes)) != 47:
        raise ValueError("FAMILY_UNIVERSE_MISMATCH")
    if any(type(r.get("eligible_count")) is not int or r["eligible_count"] < 0 for r in screens + families):
        raise ValueError("ELIGIBLE_COUNT_UNKNOWN")
    underscreens = sorted(s["pantalla_id"] for s in screens if s["eligible_count"] < 2)
    underfamilies = sorted(f["family_code"] for f in families if f["eligible_count"] < 2)
    return {
        "test_code": TEST_CODE,
        "verdict": "REJECT_INSUFFICIENT" if underscreens or underfamilies else "NEGATIVE_NOT_TRIGGERED",
        "screens_under_2": underscreens, "families_under_2": underfamilies,
        "historical_receipt_is_current_proof": False,
        "snapshot_provider_authenticated": False,
        "checkpoint_done": False, "machine_assertion_recorded": False,
    }


def selftest() -> dict:
    receipt = {"id": 38, "receipt_sha256": RECEIPT_SHA,
               "schema_version": "SOAK_OBSERVATION_HISTORY_V2",
               "verification_status": "VERIFIED", "pass": True,
               "screens_total": 13, "families_total": 47}
    clean = {"receipt": receipt,
             "screens": [{"pantalla_id": x, "eligible_count": 2} for x in sorted(SCREEN_IDS)],
             "families": [{"family_code": f"F{i:02d}", "eligible_count": 2} for i in range(47)]}
    assert assess(clean)["verdict"] == "NEGATIVE_NOT_TRIGGERED"
    a = json.loads(json.dumps(clean))
    a["screens"][0]["eligible_count"] = 1
    assert assess(a)["verdict"] == "REJECT_INSUFFICIENT"
    b = json.loads(json.dumps(clean))
    b["families"][0]["eligible_count"] = 0
    assert assess(b)["verdict"] == "REJECT_INSUFFICIENT"
    for key, mutation in (
        ("duplicate_screen", lambda x: x["screens"].__setitem__(1, x["screens"][0])),
        ("missing_family", lambda x: x["families"].pop()),
        ("unknown_count", lambda x: x["screens"][0].update(eligible_count=None)),
        ("historical_receipt_drift", lambda x: x["receipt"].update(receipt_sha256="0" * 64)),
    ):
        x = json.loads(json.dumps(clean))
        mutation(x)
        try:
            assess(x)
        except (ValueError, TypeError):
            continue
        raise AssertionError(f"FAIL_OPEN:{key}")
    return {"test_code": TEST_CODE, "status": "NEGATIVE_SELF_TEST_PASS",
            "cases_passed": 7, "checkpoint_done": False}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--snapshot", type=Path)
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(selftest(), sort_keys=True))
        return 0
    if not args.snapshot:
        print(json.dumps({"test_code": TEST_CODE, "verdict": "BLOCKED",
                          "reason": "READ_ONLY_SNAPSHOT_REQUIRED", "checkpoint_done": False}))
        return 2
    try:
        result = assess(json.loads(args.snapshot.read_text(encoding="utf-8")))
    except (ValueError, TypeError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"test_code": TEST_CODE, "verdict": "FAIL_CLOSED",
                          "reason": str(exc), "checkpoint_done": False}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0 if result["verdict"] == "REJECT_INSUFFICIENT" else 2


if __name__ == "__main__":
    raise SystemExit(main())
