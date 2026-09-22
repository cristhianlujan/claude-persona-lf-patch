#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

EXACT_INIT = [1, 1, 1, 1]


def classify(row: dict[str, Any]) -> tuple[str, list[str]]:
    reasons: list[str] = []
    if int(row.get("effects") or 0) > 0:
        return "CONFLICT_EFFECT_EVIDENCE", ["EFFECT_GUARD_PRESENT"]
    if row.get("lease") == "LEASE_ACTIVE":
        return "CONFLICT_ACTIVE_LEASE", ["ACTIVE_LEASE_PRESENT"]
    if int(row.get("checkpoint_seq") or 0) > 0:
        return "CONFLICT_CHECKPOINT_WITH_ZERO_STEPS", ["CHECKPOINT_WITHOUT_RECORDED_STEP"]

    init = row.get("init") or []
    if init == [0, 0, 0, 0]:
        return "LEGACY_NO_INIT_TOPOLOGY", ["NO_ACTIVE_INIT_TOPOLOGY", "HISTORICAL_SEMANTICS_NOT_REWRITABLE"]
    if init != EXACT_INIT:
        return "OWNER_REVIEW_TOPOLOGY_INCOMPLETE", [f"INIT_TOPOLOGY_COUNTS={init}"]
    if row.get("lifecycle") != "OP_OPERATIONAL":
        return "OWNER_REVIEW_OPERATION_NOT_OPERATIONAL", [f"LIFECYCLE={row.get('lifecycle')}"]
    if not row.get("idempotency") or not row.get("request_sha"):
        missing = []
        if not row.get("idempotency"):
            missing.append("IDEMPOTENCY_KEY")
        if not row.get("request_sha"):
            missing.append("REQUEST_SHA256")
        return "OWNER_REVIEW_REQUEST_IDENTITY_MISSING", ["MISSING=" + ",".join(missing)]

    return "REPLAY_CANDIDATE_PRECHECK_ONLY", ["ALL_STATIC_REPLAY_PREREQUISITES_PRESENT", "OWNER_CURRENTNESS_REVIEW_STILL_REQUIRED"]


def reconcile(inventory: dict[str, Any]) -> dict[str, Any]:
    rows = inventory.get("rows") or []
    if not isinstance(rows, list):
        raise ValueError("INVENTORY_ROWS_INVALID")
    seen: set[str] = set()
    results: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("INVENTORY_ROW_INVALID")
        eid = row.get("execution_id")
        if not isinstance(eid, str) or not eid or eid in seen:
            raise ValueError("EXECUTION_ID_INVALID_OR_DUPLICATE")
        seen.add(eid)
        decision, reasons = classify(row)
        results.append({
            "execution_id": eid,
            "operation_code": row.get("operation_code"),
            "decision": decision,
            "reasons": reasons,
            "mutation_allowed": False,
        })

    counts = Counter(r["decision"] for r in results)
    replay_candidates = [r["execution_id"] for r in results if r["decision"] == "REPLAY_CANDIDATE_PRECHECK_ONLY"]
    return {
        "schema_version": "LF_EXECUTION_RECONCILIATION_RECEIPT_V1",
        "status": "CLASSIFIED_READ_ONLY",
        "inventory_count": len(results),
        "decision_counts": dict(sorted(counts.items())),
        "replay_candidate_count": len(replay_candidates),
        "replay_candidate_execution_ids": replay_candidates,
        "results": results,
        "auto_close_allowed": False,
        "auto_backfill_allowed": False,
        "auto_replay_allowed": False,
        "next_gate": "OWNER_AND_CURRENTNESS_REVIEW_BEFORE_ANY_MUTATION",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only LF zero-step execution reconciler.")
    ap.add_argument("--inventory", type=Path, required=True)
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()
    result = reconcile(json.loads(ns.inventory.read_text(encoding="utf-8")))
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
