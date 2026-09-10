#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

from s26_hp001.gate_c_card_selection import GateCCardSelectionBlocked, evaluate_card_selection, resolve_card_policy

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SOURCE_FIXTURE = HERE / "s26_hp001" / "card_fixture" / "CARD.md"
EPHEMERAL_CARD_REF = "cards/_s26_test_runtime/CARD.md"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def base_context(candidates, *, required=False):
    return {
        "surface_code": "UI_SCREEN_DESIGN",
        "task_code": "CREATE_NEW",
        "card_required": required,
        "card_candidates": candidates,
    }


def input_fields():
    return {
        "profile_slug": "ui_architect",
        "task_mode": "CREATE_NEW",
        "output_contract_version": "UI_PRODUCTION_SPEC_V6",
        "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
    }


def candidate(card_id: str, card_path: Path):
    return {
        "card_id": card_id,
        "ref": EPHEMERAL_CARD_REF,
        "sha256": sha256(card_path),
        "surface_codes": ["UI_SCREEN_DESIGN"],
        "task_codes": ["CREATE_NEW"],
        "required_input_fields": [
            "profile_slug",
            "task_mode",
            "output_contract_version",
            "domain_scope",
        ],
    }


def main() -> int:
    hp001 = evaluate_card_selection()
    if hp001["decision"] != "NO_CARD_GOVERNED" or hp001["candidate_count"] != 0:
        raise RuntimeError("HP001_NO_CARD_BRANCH_FAILED")

    no_card = resolve_card_policy(base_context([], required=False), input_fields())
    if no_card.get("status") != "FALLBACK" or no_card.get("mode") != "NO_CARD_GOVERNED":
        raise RuntimeError("OPTIONAL_NO_CARD_DID_NOT_PASS")

    with tempfile.TemporaryDirectory(prefix="s26-card-bound-") as td:
        temp_repo = Path(td)
        ephemeral_card = temp_repo / EPHEMERAL_CARD_REF
        ephemeral_card.parent.mkdir(parents=True, exist_ok=True)
        ephemeral_card.write_bytes(SOURCE_FIXTURE.read_bytes())
        test_candidate = candidate("S26_TEST_CARD_BOUND_V1", ephemeral_card)

        one = resolve_card_policy(base_context([test_candidate]), input_fields(), repo_root=temp_repo)
        if one.get("status") != "RESOLVED" or one.get("mode") != "CARD_BOUND":
            raise RuntimeError("ONE_APPLICABLE_CARD_DID_NOT_BIND")
        if one.get("card_id") != "S26_TEST_CARD_BOUND_V1":
            raise RuntimeError("CARD_BOUND_WRONG_CARD")

        ambiguous_blocked = False
        try:
            resolve_card_policy(
                base_context([
                    test_candidate,
                    candidate("S26_TEST_CARD_BOUND_V2", ephemeral_card),
                ]),
                input_fields(),
                repo_root=temp_repo,
            )
        except Exception as exc:
            ambiguous_blocked = getattr(exc, "code", None) == "RUNTIME_CARD_AMBIGUOUS"
        if not ambiguous_blocked:
            raise RuntimeError("MULTIPLE_APPLICABLE_CARDS_NOT_BLOCKED")

    required_missing_blocked = False
    try:
        resolve_card_policy(base_context([], required=True), input_fields())
    except GateCCardSelectionBlocked as exc:
        required_missing_blocked = str(exc) == "GATE_C_REQUIRED_CARD_MISSING"
    if not required_missing_blocked:
        raise RuntimeError("REQUIRED_CARD_MISSING_NOT_BLOCKED")

    print(json.dumps({
        "gate": "S26_GATE_C_BRANCH_MATRIX_V2",
        "result": "PASS",
        "cases": {
            "zero_optional": "PASS_NO_CARD_GOVERNED",
            "one_applicable": "PASS_CARD_BOUND",
            "multiple_applicable": "BLOCKED_CARD_AMBIGUOUS",
            "zero_required": "BLOCKED_REQUIRED_CARD_MISSING"
        },
        "fixture_source_ref": "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/card_fixture/CARD.md",
        "ephemeral_runtime_ref": EPHEMERAL_CARD_REF,
        "fixture_sha256": sha256(SOURCE_FIXTURE),
        "governed_cards_namespace_mutated": False,
        "production_effect": False
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
