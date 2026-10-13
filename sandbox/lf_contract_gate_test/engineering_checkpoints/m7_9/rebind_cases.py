#!/usr/bin/env python3
"""M7.9 real, rollback-only integration cases. Never produces PASS without DB execution.

Runner: SentinelX on the exact merged Git SHA. Expects a secure DSN and a
pre-provisioned, isolated manifest. No credentials or fixture IDs in Git.
"""
import json
import os
import sys

SUITE = "INPUT_GOVERNANCE_REGRESSION"
TEST_CODE = "ENG_M7_9_REBIND_CASES"
CASES = (
    "M7_9_REBIND_ELIGIBLE",
    "M7_9_REBIND_INELIGIBLE",
    "M7_9_REBIND_RESOLUTION_ERROR",
    "M7_9_REBIND_COPY_PENDING",
)
EXIT = "casos 264→265/266 cubiertos"


def stop(code, message, observed=None):
    print(json.dumps({
        "test_code": TEST_CODE, "status": "BLOCKED" if code == 2 else "FAIL",
        "test_passed": False, "test_exit_code": code,
        "reason": message, "observed": observed or {},
        "canonical_exit_criterion": EXIT,
    }, sort_keys=True))
    sys.exit(code)


def one(cur, sql, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def capture_run(cur, screen):
    return int(one(cur,
        "select count(*) from programacion.input_readiness_runs where pantalla_id=%s",
        (int(screen),)))


def verify_catalog(cur):
    cur.execute("""
      select test_code, status
      from public.lf_test_suite_cases
      where suite_code=%s and test_code=any(%s)
    """, (SUITE, list(CASES)))
    rows = dict(cur.fetchall())
    assert set(rows) == set(CASES), ("missing catalog cases", rows)
    assert all(v in ("CANDIDATO", "ACTIVE", "ACTIVO") for v in rows.values()), rows


def execute_rebind(cur, fx, force):
    return one(cur,
        """select programacion.fn_input_governance_curator_rebind_v1(
              %s::integer,%s::text,%s::text,%s::boolean)""",
        (int(fx["pantalla_id"]), fx["consumer"], fx["curator_identity"], force))


def test_eligible_and_copy(cur, fx):
    cur.execute("SAVEPOINT m79_eligible")
    try:
        before = capture_run(cur, fx["pantalla_id"])
        result = execute_rebind(cur, fx, True)
        assert isinstance(result, dict), ("non-json result", result)
        assert result.get("status") == "VALIDATOR_RUNTIME_REQUIRED", result
        assert result.get("write_performed") is True, result
        run_id = int(result["run_id"])
        parent_id = int(result["parent_run_id"])
        assert run_id != parent_id
        parent_n = one(cur,
            "select count(*) from programacion.input_family_assessments where run_id=%s",
            (parent_id,))
        cur.execute("""
          select count(*),count(*) filter(where validator_outcome='PENDING'),
                 count(*) filter(where curator_evidence->>'parent_run_id'=%s)
          from programacion.input_family_assessments where run_id=%s
        """, (str(parent_id), run_id))
        cloned, pending, traced = cur.fetchone()
        assert parent_n > 0 and cloned == parent_n, (parent_n, cloned)
        assert pending == cloned and traced == cloned, (pending, traced, cloned)
        after = capture_run(cur, fx["pantalla_id"])
        assert after == before + 1, (before, after)
        return {
            CASES[0]: {"pass": True, "new_run": run_id, "parent": parent_id},
            CASES[3]: {"pass": True, "families": cloned,
                       "pending": pending, "parent_trace": traced},
        }
    finally:
        cur.execute("ROLLBACK TO SAVEPOINT m79_eligible")
        cur.execute("RELEASE SAVEPOINT m79_eligible")


def test_ineligible(cur, fx):
    cur.execute("SAVEPOINT m79_ineligible")
    try:
        before = capture_run(cur, fx["pantalla_id"])
        result = execute_rebind(cur, fx, False)
        assert isinstance(result, dict), result
        expected = fx["expected_status"]
        assert result.get("status") == expected, (result, expected)
        assert result.get("write_performed") is not True, result
        assert capture_run(cur, fx["pantalla_id"]) == before
        return {CASES[1]: {"pass": True, "status": expected, "new_runs": 0}}
    finally:
        cur.execute("ROLLBACK TO SAVEPOINT m79_ineligible")
        cur.execute("RELEASE SAVEPOINT m79_ineligible")


def test_resolution_error(cur, fx):
    cur.execute("SAVEPOINT m79_resolution_error")
    before = capture_run(cur, fx["pantalla_id"])
    rejected = False
    reason = None
    try:
        # The fixture must genuinely expose a governed RESOLUTION_ERROR source.
        result = one(cur,
            """select programacion.fn_input_governance_curator_materialize_v1(
                  %s::integer,%s::text,%s::text,true)""",
            (int(fx["pantalla_id"]), fx["consumer"], fx["curator_identity"]))
        reason = json.dumps(result)
        rejected = result.get("status") == "BLOCKED" and "RESOLUTION_ERROR" in reason
    except Exception as exc:
        reason = str(exc)
        rejected = "RESOLUTION_ERROR" in reason
    finally:
        cur.execute("ROLLBACK TO SAVEPOINT m79_resolution_error")
        cur.execute("RELEASE SAVEPOINT m79_resolution_error")
    assert rejected, ("wrong rejection or unexpected success", reason)
    assert capture_run(cur, fx["pantalla_id"]) == before
    return {CASES[2]: {"pass": True, "reason": reason[:180], "new_runs": 0}}


def main():
    dsn = os.environ.get("LF_IG_M7_9_TEST_DSN")
    fixtures_text = os.environ.get("LF_IG_M7_9_FIXTURES_JSON")
    if not dsn or not fixtures_text:
        stop(2, "Missing governed test-only DSN or isolated fixture manifest")
    try:
        import psycopg
    except ImportError:
        stop(2, "psycopg driver unavailable on operational runner")
    try:
        fixtures = json.loads(fixtures_text)
        assert set(("eligible", "ineligible", "resolution_error")) <= set(fixtures)
        for name in ("eligible", "ineligible", "resolution_error"):
            fx = fixtures[name]
            assert all(fx.get(k) for k in ("pantalla_id", "consumer", "curator_identity"))
        assert fixtures["ineligible"].get("expected_status")
        assert fixtures.get("rollback_only") is True
    except Exception as exc:
        stop(2, "Missing isolated, typed fixture proof: " + str(exc))
    observed = {}
    conn = None
    try:
        conn = psycopg.connect(dsn, connect_timeout=10)
        with conn.cursor() as cur:
            # No commit in any code path. All test mutations are transaction-local.
            cur.execute("set local statement_timeout='45s'")
            verify_catalog(cur)
            observed.update(test_eligible_and_copy(cur, fixtures["eligible"]))
            observed.update(test_ineligible(cur, fixtures["ineligible"]))
            observed.update(test_resolution_error(cur, fixtures["resolution_error"]))
            assert set(observed) == set(CASES)
        conn.rollback()
        print(json.dumps({
            "test_code": TEST_CODE, "status": "PASS", "test_passed": True,
            "test_exit_code": 0, "semantic_authority_bound": True,
            "scenario_count": 4, "fixture_mode": "ROLLBACK_ONLY",
            "canonical_exit_criterion": EXIT,
            "observed": observed, "rollback_clean": True,
        }, sort_keys=True))
    except Exception as exc:
        if conn:
            conn.rollback()
        stop(1, "Live integration failed: " + type(exc).__name__ +
             ": " + str(exc)[:250], observed)
    finally:
        if conn:
            conn.close()


if __name__ == "__main__":
    main()
