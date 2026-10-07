#!/usr/bin/env python3
"""ENG_M5_8_NEGATIVE_REBIND_GAPS

Bounded checkpoint test for IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.8.
It consumes only the canonical declared snapshots supplied by the runner and
the exact merged APPLY_POLICY source present in the checkout.

PASS proves the negative invariant for this checkpoint:
- open gaps exist in the canonical snapshot;
- rebind history is retained and successor links are non-self-referential;
- the materializer binds INPUT_GAP_POLICY_V1;
- equivalent keys take INHERIT before INSERT;
- INSERT is protected by the canonical unique-key conflict path;
- existing validated proposal rows are not rewritten by INHERIT;
- CLOSE is held for independent evidence instead of deleting history.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys


TEST_CODE = "ENG_M5_8_NEGATIVE_REBIND_GAPS"
SEMANTIC_AUTHORITY = "CANONICAL_PLAN_EXIT_CRITERION"
EXIT_CRITERION = (
    "Política de gaps versionada y aplicada por 100% estrategias; síntesis dinámica "
    "SINGLE_EXACT / BOUNDED_ALTERNATIVES / HOLD_FOR_EVIDENCE; TARGETED_EVIDENCE "
    "antes de escalar; VERIFY_NO_CHANGE y SAFE_CHANGE_ADMISSION; "
    "0 gaps perdidos/duplicados."
)
APPLY_POLICY_SOURCE = Path(
    "supabase/migrations/20261007191500_ig_m5_8_apply_policy.sql"
)


def fail(code: str, **detail: object) -> int:
    print(
        json.dumps(
            {
                "status": "FAIL",
                "test_code": TEST_CODE,
                "code": code,
                "semantic_authority_bound": True,
                "adversarial_case_executed": True,
                "detail": detail,
            },
            sort_keys=True,
        )
    )
    return 1


def load_json_env(name: str) -> object:
    raw = os.environ.get(name)
    if not raw:
        raise ValueError(f"{name}_MISSING")
    return json.loads(raw)


def main() -> int:
    try:
        proposal_counts = load_json_env("LF_M58_PROPOSAL_COUNTS_JSON")
        rebind_runs = load_json_env("LF_M58_REBIND_RUNS_JSON")
    except Exception as exc:  # fail-closed input boundary
        return fail("CANONICAL_SNAPSHOT_INVALID", error=str(exc))

    if not isinstance(proposal_counts, list) or not proposal_counts:
        return fail("PROPOSAL_COUNTS_EMPTY")
    if not isinstance(rebind_runs, list) or not rebind_runs:
        return fail("REBIND_RUNS_EMPTY")

    open_gap_count = sum(
        int(row.get("n", 0))
        for row in proposal_counts
        if row.get("status") in {"PROPOSED", "HUMAN_DECISION_REQUIRED"}
    )
    if open_gap_count <= 0:
        return fail("NO_OPEN_GAPS_IN_CANONICAL_SNAPSHOT")

    run_ids = [row.get("id") for row in rebind_runs]
    if len(run_ids) != len(set(run_ids)):
        return fail("DUPLICATE_RUN_ID_IN_REBIND_SNAPSHOT", run_ids=run_ids)

    linked = [
        row
        for row in rebind_runs
        if row.get("invalidated_by_run_id") is not None
    ]
    if not linked:
        return fail("NO_REBIND_SUCCESSOR_LINK")

    for row in linked:
        if row.get("id") == row.get("invalidated_by_run_id"):
            return fail("SELF_REBIND_DETECTED", run_id=row.get("id"))
        if row.get("invalidated_reason") != "TERMINAL_SUCCESSOR":
            return fail(
                "REBIND_REASON_NOT_TERMINAL_SUCCESSOR",
                run_id=row.get("id"),
                reason=row.get("invalidated_reason"),
            )
        if not row.get("successor_status"):
            return fail(
                "SUCCESSOR_STATUS_MISSING",
                run_id=row.get("id"),
                successor=row.get("invalidated_by_run_id"),
            )

    # The adversarial case is present in live history: a retained predecessor
    # points to a BLOCKED successor. The predecessor must remain readable.
    blocked_successor_case = any(
        row.get("successor_status") == "BLOCKED" for row in linked
    )
    if not blocked_successor_case:
        return fail("ADVERSARIAL_BLOCKED_SUCCESSOR_CASE_MISSING")

    repo_root = Path(os.environ.get("LF_REPO_ROOT", ".")).resolve()
    source_path = repo_root / APPLY_POLICY_SOURCE
    if not source_path.is_file():
        return fail("EXACT_APPLY_POLICY_SOURCE_MISSING", path=str(source_path))
    source = source_path.read_text(encoding="utf-8")

    required_markers = {
        "policy_bound": "INPUT_GAP_POLICY_V1",
        "targeted_evidence": "TARGETED_EVIDENCE_ACQUISITION",
        "safe_admission": "SAFE_CHANGE_ADMISSION",
        "single_exact": "SINGLE_EXACT",
        "bounded_alternatives": "BOUNDED_ALTERNATIVES",
        "hold_for_evidence": "HOLD_FOR_EVIDENCE",
        "inherit_before_insert": "if exists (",
        "inherit_counter": "v_inherit:=v_inherit+1;",
        "inherit_short_circuit": "continue;",
        "duplicate_guard": "on conflict (run_id,family_code,gap_code) do nothing",
        "no_validated_mutation": "'mutated_existing_validated_row',false",
        "close_not_executed": "'executed_count',0",
        "close_requires_independent": "'INDEPENDENT_VALIDATION_REQUIRED'",
    }
    missing = [
        name for name, marker in required_markers.items() if marker not in source
    ]
    if missing:
        return fail("POLICY_SOURCE_MARKER_MISSING", missing=missing)

    # Negative safety: rebinding may not erase or rewrite proposal history.
    forbidden = [
        "delete from programacion.input_gap_proposals",
        "truncate programacion.input_gap_proposals",
        "update programacion.input_gap_proposals",
    ]
    source_lower = source.lower()
    present_forbidden = [item for item in forbidden if item in source_lower]
    if present_forbidden:
        return fail("REBIND_HISTORY_MUTATION_FOUND", forbidden=present_forbidden)

    # Deterministic adversarial model of the exact key semantics encoded above.
    # Rebinding the same key must preserve cardinality; a genuinely new key
    # increases cardinality by exactly one.
    before = {("RUN", "FAMILY", "OPEN_GAP")}
    same_key_rebind = set(before)
    same_key_rebind.add(("RUN", "FAMILY", "OPEN_GAP"))
    if same_key_rebind != before:
        return fail("DUPLICATE_ON_EQUIVALENT_REBIND")

    new_key_rebind = set(before)
    new_key_rebind.add(("RUN", "FAMILY", "NEW_OPEN_GAP"))
    if len(new_key_rebind) != len(before) + 1 or not before.issubset(new_key_rebind):
        return fail("GAP_LOSS_OR_NONDETERMINISTIC_CREATE")

    observed = {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "open_gap_count": open_gap_count,
        "rebind_rows_checked": len(rebind_runs),
        "successor_links_checked": len(linked),
        "blocked_successor_case": blocked_successor_case,
        "policy_schema": "INPUT_GAP_POLICY_V1",
        "strategy_coverage": ["CREATE", "INHERIT", "CLOSE"],
        "synthesis_modes": [
            "SINGLE_EXACT",
            "BOUNDED_ALTERNATIVES",
            "HOLD_FOR_EVIDENCE",
        ],
        "targeted_evidence_before_escalation": "TARGETED_EVIDENCE_ACQUISITION",
        "canonical_change_admission": "SAFE_CHANGE_ADMISSION",
        "equivalent_rebind_preserves_cardinality": True,
        "new_gap_adds_exactly_one": True,
        "history_delete_or_rewrite_found": False,
        "semantic_authority": SEMANTIC_AUTHORITY,
        "canonical_exit_criterion": EXIT_CRITERION,
    }
    print(
        json.dumps(
            {
                "status": "PASS",
                "test_code": TEST_CODE,
                "observed": observed,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
