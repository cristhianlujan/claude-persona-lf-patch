#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import validate_s26_governance_ekb_gate as base

CONTRACT_DEFAULT = base.CONTRACT_DEFAULT
REPO_ROOT = base.REPO_ROOT


def _card_path_exists(ref: Any) -> bool:
    if not isinstance(ref, str) or not ref.startswith("cards/") or not ref.strip():
        return False
    raw = REPO_ROOT / ref
    if raw.is_symlink():
        return False
    candidate = raw.resolve()
    cards_root = (REPO_ROOT / "cards").resolve()
    try:
        candidate.relative_to(cards_root)
    except ValueError:
        return False
    return candidate.is_file()


def evaluate(contract: dict[str, Any], receipt: Any) -> dict[str, Any]:
    out = base.evaluate(contract, receipt)
    blockers = list(out.get("blockers") or [])

    if isinstance(receipt, dict):
        card = receipt.get("card_resolution")
        if isinstance(card, dict) and card.get("state") in {"EXACT", "COMPATIBLE"}:
            candidates = card.get("candidate_refs")
            if isinstance(candidates, list):
                for idx, ref in enumerate(candidates):
                    if not _card_path_exists(ref):
                        blockers.append(f"CARD_CANDIDATE_REF_UNRESOLVED:{idx}")
            selected = card.get("selected_card_ref")
            if isinstance(selected, str) and not _card_path_exists(selected):
                blockers.append("SELECTED_CARD_REF_UNRESOLVED")

    if blockers:
        out["result"] = "FAIL_CLOSED"
        out["execution_allowed"] = False
        out["manual_allowed"] = False
        out["manual_avoided"] = False
        out["blockers"] = blockers
    elif out.get("result") == "FAIL_CLOSED":
        out["manual_allowed"] = False
        out["manual_avoided"] = False

    return out


def self_test(contract: dict[str, Any]) -> dict[str, Any]:
    base_result = base.self_test(contract)
    assert base_result["status"] == "PASS" and base_result["cases_passed"] == 20, base_result

    missing_card = base._base_receipt(contract)
    missing_card["card_resolution"] = {
        "state": "EXACT",
        "selected_card_ref": "cards/nonexistent/CARD.md",
        "candidate_refs": ["cards/nonexistent/CARD.md"],
        "resolver_evidence_ref": "repo://sandbox/lf_contract_gate_test/s26_governance_ekb/s26_e_preexecution_evidence_v2.json",
    }
    missing_card_out = evaluate(contract, missing_card)
    assert missing_card_out["result"] == "FAIL_CLOSED", missing_card_out
    assert "SELECTED_CARD_REF_UNRESOLVED" in missing_card_out["blockers"], missing_card_out

    manual_bad_evidence = base._base_receipt(contract)
    manual_bad_evidence["card_resolution"] = {
        "state": "NONE",
        "resolver_evidence_ref": "repo://sandbox/lf_contract_gate_test/s26_governance_ekb/s26_e_preexecution_evidence_v2.json",
    }
    manual_bad_evidence["fallback"] = {
        "attempts": [
            {"kind": "CONTRACT_SCHEMA", "status": "FAIL", "reason": "self-test", "evidence_ref": "repo://sandbox/lf_contract_gate_test/s26_governance_ekb/s26_e_preexecution_evidence_v2.json"},
            {"kind": "GENERIC_CAPABILITY", "status": "FAIL", "reason": "self-test", "evidence_ref": "repo://sandbox/lf_contract_gate_test/s26_governance_ekb/s26_e_preexecution_evidence_v2.json"},
            {"kind": "SAFE_COMPOSITION", "status": "FAIL", "reason": "self-test", "evidence_ref": "repo://sandbox/lf_contract_gate_test/s26_governance_ekb/does_not_exist.json"},
        ],
        "selected": None,
        "manual_required": True,
    }
    manual_bad_out = evaluate(contract, manual_bad_evidence)
    assert manual_bad_out["result"] == "FAIL_CLOSED", manual_bad_out
    assert manual_bad_out["manual_allowed"] is False, manual_bad_out

    return {
        "status": "PASS",
        "base_cases_passed": 20,
        "strict_cases_passed": 2,
        "cases_passed": 22,
        "strict_cases": [
            {"case": "21_nonexistent_card_ref", "result": missing_card_out["result"]},
            {"case": "22_manual_unresolved_evidence", "result": manual_bad_out["result"], "manual_allowed": manual_bad_out["manual_allowed"]},
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, default=CONTRACT_DEFAULT)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    contract = base.load_json(args.contract)
    output: dict[str, Any] = {}
    if args.self_test:
        output["self_test"] = self_test(contract)
    if args.input:
        output["evaluation"] = evaluate(contract, base.load_json(args.input))
    if not output:
        parser.error("use --self-test and/or --input")
    print(json.dumps(output, indent=2, sort_keys=True))
    if args.input and output["evaluation"]["result"] == "FAIL_CLOSED":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
