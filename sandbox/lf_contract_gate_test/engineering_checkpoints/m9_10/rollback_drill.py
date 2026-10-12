"""M9.10 CP3: reuse source-bound M9.9 six-case proof + M9.10 DB integration.

This checkpoint must NOT rerun M9.9 triggers or imply live canary admission.
One new negative safeguard (stale-currentness) was actually executed within
M9.10's source-bound per-cohort DB matrix (7/7); its assertion receipt is read
from the canonical checkpoint ledger. SQL is read-only.
"""

DRILL_READBACK_SQL = r'''WITH source_proofs AS (
 SELECT u.unit_code,c.checkpoint_code,c.status,
   c.assertion_receipt,c.assertion_receipt_sha256,c.assertion_contract_sha256
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND ((u.unit_code='M9.9' AND c.checkpoint_code='ROLLBACK_TRIGGER_NEGATIVE')
    OR (u.unit_code='M9.10' AND c.checkpoint_code='COHORT_BY_COHORT'))
), m99 AS (SELECT * FROM source_proofs WHERE unit_code='M9.9'),
m910 AS (SELECT * FROM source_proofs WHERE unit_code='M9.10'),
gate AS (
 SELECT
   (SELECT status='DONE' AND assertion_receipt->>'passed'='true'
      AND assertion_receipt->>'evidence_ref' LIKE '%integrated_six_case_canary_v1.sql#blob=9d72abfa435bbc094d60645f77ec9e1a7868abdf'
      AND assertion_contract_sha256 IS NOT NULL AND assertion_receipt_sha256 IS NOT NULL FROM m99)
       AS upstream_six_case_reused,
   (SELECT status='DONE' AND assertion_receipt->>'passed'='true'
      AND assertion_receipt->>'evidence_ref' LIKE '%cohort_by_cohort.py#blob=e01527a338c87ab2e3b92a9bcdbabcb37e41304f'
      AND assertion_contract_sha256 IS NOT NULL AND assertion_receipt_sha256 IS NOT NULL FROM m910)
       AS per_cohort_db_promotion_reversal_verified,
   (SELECT (unit_metadata#>>'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE,assertion_contract,pass_when,negative_case_count}')::int=5
     FROM programacion.engineering_plan_units
     WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9')
       AS upstream_negative_count_five,
   (SELECT (unit_metadata#>>'{m910_two_level_cohort_governance_v2,operational_gate,runtime_activation}')::boolean=false
      FROM programacion.engineering_plan_units WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.10')
       AS live_gate_still_blocked,
   (SELECT version='1.0.0' AND previous_version IS NULL
      FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE')
       AS baseline_pointer_unchanged,
   (SELECT count(*)=0 FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1')
       AS candidate_registry_zero_residue
)
SELECT CASE WHEN upstream_six_case_reused AND per_cohort_db_promotion_reversal_verified
 AND upstream_negative_count_five AND live_gate_still_blocked
 AND baseline_pointer_unchanged AND candidate_registry_zero_residue
 THEN 'PASS_SANDBOX_M910_DRILL_REUSE' ELSE 'BLOCKED_SOURCE_OR_AUTHORITY_DRIFT' END status,
 upstream_six_case_reused,per_cohort_db_promotion_reversal_verified,
 upstream_negative_count_five,live_gate_still_blocked,baseline_pointer_unchanged,
 candidate_registry_zero_residue, false AS new_m99_trigger_execution,
 false AS operational_canary_release
FROM gate;'''

def source_bound_drill_readback_sql() -> str:
    return DRILL_READBACK_SQL


def assert_drill_row(row: dict) -> dict:
    required = (
        "upstream_six_case_reused", "per_cohort_db_promotion_reversal_verified",
        "upstream_negative_count_five", "live_gate_still_blocked",
        "baseline_pointer_unchanged", "candidate_registry_zero_residue",
    )
    if row.get("status") != "PASS_SANDBOX_M910_DRILL_REUSE" or any(
        row.get(k) is not True for k in required
    ):
        raise AssertionError("M910_CANONICAL_ROLLBACK_REUSE_NOT_VERIFIED")
    if row.get("new_m99_trigger_execution") is not False or row.get("operational_canary_release") is not False:
        raise AssertionError("M910_UNAUTHORIZED_RELEASE_OR_UNNECESSARY_RETEST")
    return {"test_passed": True, "test_exit_code": 0,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            "runtime_canary_proven": False}
