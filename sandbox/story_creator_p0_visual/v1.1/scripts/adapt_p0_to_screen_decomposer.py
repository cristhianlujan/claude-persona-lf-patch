#!/usr/bin/env python3
"""Map a governed P0 effective handoff into the Screen Decomposer input contract."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from validate_p0_j02_handoff import canonical_sha, load, positive_fixture, validate


def strip_classification(item: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in item.items() if key != "classification"}


def adapt(payload: dict[str, Any]) -> dict[str, Any]:
    gate = validate(payload)
    if gate["result"] != "PASS_WITH_EVIDENCE":
        raise ValueError("p0_j02_handoff_blocked:" + ",".join(gate["blocking_assertions"]))
    decision = payload["effective_decision"]
    provenance = payload["provenance"]
    return {
        "worker_profile": "PERFIL_SCREEN_DECOMPOSER_LF",
        "target_screen_code": payload["target_screen_code"],
        "source_snapshot": {
            "screen_code": payload["target_screen_code"],
            "version": payload["source_version"],
            "sha256": payload["source_snapshot_sha256"],
            "source_refs": provenance["source_refs"],
        },
        "context_inventory": [strip_classification(item) for item in payload["context_inventory"]],
        "field_inventory": [strip_classification(item) for item in payload["field_inventory"]],
        "permission_inventory": [strip_classification(item) for item in payload["permission_inventory"]],
        "transition_inventory": [strip_classification(item) for item in payload["transition_inventory"]],
        "action_inventory": [strip_classification(item) for item in payload["action_inventory"]],
        "pending_decisions": payload["pending_decisions"],
        "p0_provenance": {
            "handoff_schema_version": payload["schema_version"],
            "handoff_sha256": canonical_sha(payload),
            "p0_execution_id": provenance["p0_execution_id"],
            "effective_decision_id": decision["decision_id"],
            "effective_judge": decision["judge_code"],
            "effective_result": decision["result"],
            "visual_output_sha256": payload["visual_output_sha256"],
            "architecture_source_sha256": provenance["architecture_source_sha256"],
            "evidence_refs": payload["evidence_refs"],
        },
        "next_step": "SCREEN_DECOMPOSITION",
        "next_judge": "J02_SCREEN_DECOMPOSITION",
    }


def self_test() -> int:
    good = positive_fixture()
    out = adapt(good)
    checks = {
        "target_preserved": out["target_screen_code"] == good["target_screen_code"],
        "source_hash_preserved": out["source_snapshot"]["sha256"] == good["source_snapshot_sha256"],
        "decision_preserved": out["p0_provenance"]["effective_decision_id"] == good["effective_decision"]["decision_id"],
        "visual_hash_preserved": out["p0_provenance"]["visual_output_sha256"] == good["visual_output_sha256"],
        "classification_not_leaked": all("classification" not in item for key in ("context_inventory", "field_inventory", "permission_inventory", "transition_inventory", "action_inventory") for item in out[key]),
        "routes_to_j02": out["next_judge"] == "J02_SCREEN_DECOMPOSITION",
    }
    blocked = dict(good); blocked["effective_decision"] = dict(good["effective_decision"], is_current=False)
    rejects_stale = False
    try:
        adapt(blocked)
    except ValueError:
        rejects_stale = True
    passed = all(checks.values()) and rejects_stale
    print(json.dumps({"checks": checks, "rejects_stale": rejects_stale, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    try:
        output = adapt(load(args.input))
    except ValueError as exc:
        print(json.dumps({"result": "BLOCKED", "error": str(exc)}, sort_keys=True))
        return 2
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
