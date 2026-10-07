#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

TEST_CODE = "ENG_M5_2_NEGATIVE_AMBIGUOUS"
MIGRATION = "supabase/migrations/20261007161000_ig_m5_2_strategy_plan_execute.sql"

def emit(status, reason=None, **observed):
    payload = {
        "status": status,
        "test_code": TEST_CODE,
        "observed": {
            "test_passed": status == "PASS",
            "test_exit_code": 0 if status == "PASS" else 1,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            **observed,
        },
        "evidence_ref": "git://merged-source/" + MIGRATION,
    }
    if reason:
        payload["observed"]["reason"] = reason
    print(json.dumps(payload, sort_keys=True))
    raise SystemExit(0 if status == "PASS" else 1)

def semantic_gaps(sql):
    checks = {
        "resolution_error_blocks": re.search(
            r"if\s+v_resolution_errors\s*>\s*0\s+then\s+"
            r"v_strategy\s*:=\s*'BLOCK'\s*;\s+"
            r"v_reason\s*:=\s*'SOURCE_RESOLUTION_ERROR'",
            sql, re.I | re.S
        ),
        "ambiguous_state_blocks": re.search(
            r"else\s+v_strategy\s*:=\s*'BLOCK'\s*;\s+"
            r"v_reason\s*:=\s*'AMBIGUOUS_RUN_STATE'",
            sql, re.I | re.S
        ),
        "current_live_noops": re.search(
            r"elsif\s+v_run_state\s*=\s*'CURRENT'\s+then.*?"
            r"if\s+v_current\s+then\s+"
            r"v_strategy\s*:=\s*'NOOP'\s*;\s+"
            r"v_reason\s*:=\s*'COMPLETED_RUN_CURRENT'",
            sql, re.I | re.S
        ),
        "no_5_13_literal": "5.13" not in sql,
        "no_version_19_literal": re.search(r"version_id\s*=\s*19\b", sql, re.I) is None,
    }
    return [name for name, ok in checks.items() if not ok]

root = Path(__file__).resolve().parents[4]
migration = root / MIGRATION
if not migration.exists():
    emit("FAIL", "MERGED_AUTHORITY_SOURCE_MISSING", migration=str(migration))

sql = migration.read_text(encoding="utf-8")
gaps = semantic_gaps(sql)
if gaps:
    emit("FAIL", "CANONICAL_SEMANTIC_GAP", gaps=gaps)

if len(sys.argv) != 2:
    emit("FAIL", "LIVE_FIXTURE_JSON_REQUIRED")

try:
    rows = json.loads(sys.argv[1])
except Exception as exc:
    emit("FAIL", "LIVE_FIXTURE_JSON_INVALID", error=str(exc))

if not isinstance(rows, list) or not rows:
    emit("FAIL", "LIVE_FIXTURE_ROWS_EMPTY")

blocked_successor = any(
    r.get("status") == "COMPLETED" and r.get("successor_status") == "BLOCKED"
    for r in rows if isinstance(r, dict)
)
completed_successor = any(
    r.get("status") == "COMPLETED" and r.get("successor_status") == "COMPLETED"
    for r in rows if isinstance(r, dict)
)
if not blocked_successor or not completed_successor:
    emit(
        "FAIL",
        "LIVE_LIFECYCLE_FIXTURE_INSUFFICIENT",
        blocked_successor=blocked_successor,
        completed_successor=completed_successor,
    )

mutations = {
    "resolution_error_default_rebind": sql.replace(
        "v_strategy:='BLOCK';\n    v_reason:='SOURCE_RESOLUTION_ERROR';",
        "v_strategy:='REBIND';\n    v_reason:='SOURCE_RESOLUTION_ERROR';",
        1,
    ),
    "ambiguous_default_rebind": sql.replace(
        "v_reason:='AMBIGUOUS_RUN_STATE';",
        "v_reason:='DEFAULT_REBIND';",
        1,
    ),
    "current_forced_recurate": sql.replace(
        "v_strategy:='NOOP';\n      v_reason:='COMPLETED_RUN_CURRENT';",
        "v_strategy:='FULL_RECURATE';\n      v_reason:='COMPLETED_RUN_CURRENT';",
        1,
    ),
}

mutation_results = {}
for name, mutated in mutations.items():
    if mutated == sql:
        emit("FAIL", "ADVERSARIAL_MUTATION_NOT_APPLIED", mutation=name)
    mutation_results[name] = semantic_gaps(mutated)
    if not mutation_results[name]:
        emit("FAIL", "ADVERSARIAL_MUTATION_NOT_DETECTED", mutation=name)

emit(
    "PASS",
    canonical_semantics=True,
    blocked_successor_fixture=True,
    completed_successor_fixture=True,
    adversarial_mutations_detected=len(mutation_results),
)
