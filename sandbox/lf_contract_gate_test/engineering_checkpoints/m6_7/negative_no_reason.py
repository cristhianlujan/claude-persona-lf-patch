#!/usr/bin/env python3
"""ENG_M6_7_NEGATIVE_NO_REASON: live, rollback-clean integration test.

Requires an authorized READ/transactional test DB connection in LF sandbox:
  IG_M67_TEST_DATABASE_URL (or DATABASE_URL).

Tests the real trigger and three producer functions. The test creates no
persistent readiness runs and never writes a signed provenance receipt.
"""
import json
import os
import sys

TEST_CODE = "ENG_M6_7_NEGATIVE_NO_REASON"
DSN = os.environ.get("IG_M67_TEST_DATABASE_URL") or os.environ.get("DATABASE_URL")
if not DSN:
    raise RuntimeError("LIVE_TEST_DATABASE_URL_REQUIRED (no simulated pass)")

try:
    import psycopg
except ImportError as exc:
    raise RuntimeError("psycopg v3 required for live transactional test") from exc

BASE = """
INSERT INTO programacion.input_readiness_runs
(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,
 universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
VALUES (%s,%s,%s,%s,'CURATING',%s::jsonb,%s,%s,%s,%s,%s)
RETURNING id,scope
"""


def probe(cur, name, params, expected_error=None):
    cur.execute("SAVEPOINT m67_case")
    try:
        cur.execute(BASE, params)
        row = cur.fetchone()
        if expected_error:
            raise AssertionError(f"{name}: unexpected INSERT success; expected {expected_error}")
        assert row is not None
        result = row
    except psycopg.Error as exc:
        if expected_error is None or expected_error not in str(exc):
            raise AssertionError(f"{name}: unexpected SQL error: {exc}") from exc
        result = None
    finally:
        cur.execute("ROLLBACK TO SAVEPOINT m67_case")
        cur.execute("RELEASE SAVEPOINT m67_case")
    return result


def main():
    observed = {}
    with psycopg.connect(DSN, autocommit=False) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id,version_id,pantalla_id,universe_rule_id,scope,
                       universe_snapshot_sha256,family_count,contract_version,
                       curator_identity,curator_component_id,source_snapshot_sha256
                FROM programacion.input_readiness_runs
                WHERE status='COMPLETED'
                  AND source_snapshot_sha256 ~ '^[0-9a-f]{64}$'
                ORDER BY id DESC LIMIT 1
            """)
            p = cur.fetchone()
            if p is None:
                raise AssertionError("CANONICAL_PARENT_NOT_FOUND")
            (run_id, version, screen, rule, scope, universe_sha,
             family_count, contract, curator, component, parent_source_sha) = p
            params = [version, screen, rule, run_id, None,
                      universe_sha, family_count, contract, curator, component]

            base_scope = dict(scope)
            base_scope.update(parent_run_id=run_id)
            base_scope.pop("reason", None)
            base_scope.pop("supersession_reason", None)
            base_scope.pop("successor_strategy", None)
            params[4] = json.dumps(base_scope)
            probe(cur, "missing_reason", params, "IG_SUCCESSOR_REASON_REQUIRED")
            observed["missing_reason_rejected"] = True

            base_scope["reason"] = "ASSERTION_REBIND"
            params[4] = json.dumps(base_scope)
            probe(cur, "missing_strategy", params, "IG_SUCCESSOR_STRATEGY_REQUIRED")
            observed["missing_strategy_rejected"] = True

            base_scope["successor_strategy"] = "PARENT_ASSERTION_REUSE"
            base_scope["parent_run_id"] = -1
            params[4] = json.dumps(base_scope)
            probe(cur, "wrong_parent", params, "IG_SUCCESSOR_PARENT_BINDING_REQUIRED")
            observed["wrong_parent_rejected"] = True

            base_scope["parent_run_id"] = run_id
            params[4] = json.dumps(base_scope)
            inserted = probe(cur, "valid_successor", params)
            child_scope = inserted[1]
            binding = child_scope["lineage_binding_v1"]
            assert binding["parent_run_id"] == run_id
            assert binding["parent_source_snapshot_sha256"] == parent_source_sha
            assert binding["reason"] == "ASSERTION_REBIND"
            assert binding["successor_strategy"] == "PARENT_ASSERTION_REUSE"
            assert isinstance(child_scope.get("lineage_binding_sha256"), str)
            assert len(child_scope["lineage_binding_sha256"]) == 64
            observed["positive_binding_produced"] = True

            cur.execute("""
                SELECT count(*) total,
                       count(*) FILTER (WHERE scope ? 'lineage_binding_v1') governed,
                       count(*) FILTER (
                           WHERE supersedes_run_id IS NOT NULL
                             AND coalesce(nullif(scope->>'reason',''),
                                          nullif(scope->>'supersession_reason','')) IS NULL
                       ) legacy_unknown
                FROM programacion.input_readiness_runs
            """)
            total, governed, legacy_unknown = cur.fetchone()
            observed.update(current_governed=governed,
                            legacy_unknown_preserved=legacy_unknown,
                            baseline_total=total)
        conn.rollback()
    print(json.dumps({
        "status": "PASS", "test_code": TEST_CODE,
        "observed": {
            "test_passed": True, "test_exit_code": 0,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            "test_data_cleanup": "ROLLBACK_CLEAN",
            **observed,
        },
    }, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "test_code": TEST_CODE,
                          "error": str(exc)}), file=sys.stderr)
        raise
