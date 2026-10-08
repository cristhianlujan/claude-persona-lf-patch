#!/usr/bin/env python3
"""M7.12 exact read-only assurance: a judge receipt must not alter Validator.

Workflow:
  1. Print the bounded SQL with --emit-sql and execute it via governed Supabase.
     The SQL performs a real candidate judge insertion and compares every
     assessment's validator outcome and applicability within a rollback block.
  2. Pass live before/after readbacks with the successful SQL execution proof
     to --verify-json on an operational Python runner (no DB secrets needed).

No suite promotion, production use, Validator writes, or persistent test data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys

TEST_CODE = "ENG_M7_12_JUDGE_NON_DECISIONAL"
PROBE_SQL = r"""
DO $m712_isolation$
DECLARE
  v_before text;
  v_after text;
  v_prior_judges bigint;
  v_with_probe bigint;
  v_test_run uuid;
  v_error text;
BEGIN
  BEGIN
    SELECT md5(string_agg(
      id::text || ':' || coalesce(validator_outcome,'<NULL>') || ':' ||
      coalesce(applicability,'<NULL>'), '|'
      ORDER BY id
    )) INTO v_before FROM programacion.input_family_assessments;
    SELECT count(*) INTO v_prior_judges FROM public.lf_test_judge_results;
    SELECT test_run_id INTO v_test_run
      FROM public.lf_test_judge_results ORDER BY created_at DESC LIMIT 1;
    IF v_test_run IS NULL OR v_before IS NULL THEN
      RAISE EXCEPTION 'M712_MISSING_CURRENT_TEST_OR_VALIDATOR';
    END IF;

    INSERT INTO public.lf_test_judge_results
      (test_run_id,judge_code,judge_type,verdict,metadata,created_by_execution_id)
    VALUES
      (v_test_run,'ENG_M7_12_JUDGE_NON_DECISIONAL_PROBE',
       'NON_DECISIONAL_PROBE','PASS',
       '{"test_code":"ENG_M7_12_JUDGE_NON_DECISIONAL","ephemeral":true,"candidate_only":true}'::jsonb,
       'IG_M7_12_ROLLBACK_PROBE');

    SELECT md5(string_agg(
      id::text || ':' || coalesce(validator_outcome,'<NULL>') || ':' ||
      coalesce(applicability,'<NULL>'), '|'
      ORDER BY id
    )) INTO v_after FROM programacion.input_family_assessments;
    SELECT count(*) INTO v_with_probe FROM public.lf_test_judge_results;

    IF v_before IS DISTINCT FROM v_after OR v_with_probe<>v_prior_judges+1 THEN
      RAISE EXCEPTION 'M712_JUDGE_ALTERED_VALIDATOR_OR_NOT_RECORDED';
    END IF;

    -- Deliberate exception rolls back the real judge insert.
    RAISE EXCEPTION 'M712_ROLLBACK_SENTINEL_VERIFIED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error<>'M712_ROLLBACK_SENTINEL_VERIFIED' THEN
      RAISE;
    END IF;
  END;
END;
$m712_isolation$;
""".strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-sql", action="store_true")
    parser.add_argument("--verify-json", default=None)
    args = parser.parse_args()
    if args.emit_sql:
        print(PROBE_SQL)
        return 0
    if not args.verify_json:
        parser.error("--verify-json required unless --emit-sql")
    data = json.loads(args.verify_json)
    required = {"source_merged": True, "sql_executed": True,
                "sql_rolled_back": True, "suite_read_only": True,
                "suite_candidate": True, "judge_linked_sha": True}
    for key, expected in required.items():
        if data.get(key) is not expected:
            raise AssertionError(f"Missing machine evidence: {key}")
    if data.get("sql_sha256") != hashlib.sha256(PROBE_SQL.encode()).hexdigest():
        raise AssertionError("The SQL execution proof must match exact merged test source")
    if data.get("validator_before") != data.get("validator_after"):
        raise AssertionError("Validator outcomes/applicability changed across judge probe")
    if not isinstance(data.get("validator_before"), list) or not data["validator_before"]:
        raise AssertionError("Missing live validator outcome data")
    if data.get("judge_count_before") != data.get("judge_count_after"):
        raise AssertionError("Transient judge probe was not cleaned")
    if not isinstance(data.get("judge_count_before"), int):
        raise AssertionError("Judge count was not numeric")
    print(json.dumps({
        "test_code": TEST_CODE, "status": "PASS",
        "observed": {"test_passed": True, "test_exit_code": 0,
                     "semantic_authority_bound": True},
        "evidence": {"rollback_clean": True,
                     "judge_count": data["judge_count_after"],
                     "validator_groups": len(data["validator_after"]),
                     "probe_sql_sha256": data["sql_sha256"]},
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"test_code": TEST_CODE, "status": "FAIL",
                          "reason": str(exc)}), file=sys.stderr)
        sys.exit(1)
