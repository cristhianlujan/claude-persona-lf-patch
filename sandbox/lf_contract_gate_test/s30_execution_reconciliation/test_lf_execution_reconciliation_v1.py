#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from lf_execution_reconciliation_v1 import classify, reconcile

HERE = Path(__file__).resolve().parent


def main() -> int:
    inventory = json.loads((HERE / "live_zero_step_inventory_20260914.json").read_text(encoding="utf-8"))
    result = reconcile(inventory)
    assert result["inventory_count"] == 22
    assert result["decision_counts"] == {
        "LEGACY_NO_INIT_TOPOLOGY": 13,
        "OWNER_REVIEW_OPERATION_NOT_OPERATIONAL": 1,
        "OWNER_REVIEW_REQUEST_IDENTITY_MISSING": 1,
        "OWNER_REVIEW_TOPOLOGY_INCOMPLETE": 7,
    }
    assert result["replay_candidate_count"] == 0
    assert result["auto_close_allowed"] is False
    assert result["auto_backfill_allowed"] is False
    assert result["auto_replay_allowed"] is False

    base = {"execution_id":"X","operation_code":"OP","lifecycle":"OP_OPERATIONAL","init":[1,1,1,1],"lease":"NO_LEASE","checkpoint_seq":0,"idempotency":True,"request_sha":True,"effects":0}
    assert classify(dict(base, effects=1))[0] == "CONFLICT_EFFECT_EVIDENCE"
    assert classify(dict(base, lease="LEASE_ACTIVE"))[0] == "CONFLICT_ACTIVE_LEASE"
    assert classify(dict(base, checkpoint_seq=2))[0] == "CONFLICT_CHECKPOINT_WITH_ZERO_STEPS"
    assert classify(dict(base, init=[0,0,0,0]))[0] == "LEGACY_NO_INIT_TOPOLOGY"
    assert classify(dict(base, init=[1,0,1,1]))[0] == "OWNER_REVIEW_TOPOLOGY_INCOMPLETE"
    assert classify(dict(base, lifecycle="OP_CANDIDATE"))[0] == "OWNER_REVIEW_OPERATION_NOT_OPERATIONAL"
    assert classify(dict(base, idempotency=False))[0] == "OWNER_REVIEW_REQUEST_IDENTITY_MISSING"
    assert classify(base)[0] == "REPLAY_CANDIDATE_PRECHECK_ONLY"

    duplicate = {"rows":[dict(base, execution_id="D"),dict(base, execution_id="D")]}
    try:
        reconcile(duplicate)
    except ValueError as exc:
        assert str(exc) == "EXECUTION_ID_INVALID_OR_DUPLICATE"
    else:
        raise AssertionError("duplicate execution must block")

    print(json.dumps({"status":"PASS","live_rows":22,"live_replay_candidates":0,"negative_and_positive_cases":9}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
