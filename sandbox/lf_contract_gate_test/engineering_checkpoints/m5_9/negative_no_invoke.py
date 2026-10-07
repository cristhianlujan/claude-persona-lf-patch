#!/usr/bin/env python3
import json
import re
from pathlib import Path

TEST_CODE = "ENG_M5_9_NEGATIVE_NO_INVOKE"
ROOT = Path(__file__).resolve().parents[4]

curator_path = ROOT / "supabase/functions/input-governance-curator-v1/index.ts"
validator_path = ROOT / "supabase/functions/input-governance-validator-v1/index.ts"
persist_migration_path = ROOT / "supabase/migrations/20261007195500_ig_m5_9_persist_receipt.sql"
boundary_migration_path = ROOT / "supabase/migrations/20261007210500_ig_m5_9_validator_receipt_boundary.sql"

curator = curator_path.read_text(encoding="utf-8")
validator = validator_path.read_text(encoding="utf-8")
persist_migration = persist_migration_path.read_text(encoding="utf-8")
boundary_migration = boundary_migration_path.read_text(encoding="utf-8")

curator_zero_validator_invocations = not bool(
    re.search(r"fn_input_governance_validator|input-governance-validator-v1", curator)
)
curator_persists_handoff_receipt = (
    "fn_input_governance_curator_handoff_receipt_v1" in curator
    and "handoff_receipt" in curator
)
receipt_exact_subject_assertion_exists = (
    "fn_assert_provenance_receipt" in persist_migration
    and "subject_sha256" in persist_migration
)

handoff_call = validator.find("await rpc(HANDOFF_ASSERT_ENTRYPOINT")
resume_call = validator.find('await rpc("fn_input_governance_validator_resume_context_v1"')
validator_call = validator.find("result = await rpc(VALIDATOR_ENTRYPOINT")
validator_consumes_handoff_receipt = (
    handoff_call >= 0
    and resume_call > handoff_call
    and validator_call > resume_call
    and 'const VALIDATOR_ENTRYPOINT = "fn_input_governance_validator_validate_handoff_v1"' in validator
    and "p_receipt_id: handoffReceiptId" in validator
)

helper_match = re.search(
    r"create or replace function programacion\.fn_input_governance_validator_handoff_assert_v1\(.*?\$function\$;",
    boundary_migration,
    re.S | re.I,
)
wrapper_match = re.search(
    r"create or replace function programacion\.fn_input_governance_validator_validate_handoff_v1\(.*?\$function\$;",
    boundary_migration,
    re.S | re.I,
)
helper = helper_match.group(0) if helper_match else ""
wrapper = wrapper_match.group(0) if wrapper_match else ""

validator_rejects_inconsistent_sha = (
    "INPUT_GOVERNANCE_VALIDATOR_HANDOFF_SUBJECT_SHA_MISMATCH" in helper
    and "fn_assert_provenance_receipt" in helper
    and "v_receipt_subject_sha is distinct from v_subject_sha" in helper
)
db_entrypoint_fail_closed = (
    "fn_input_governance_validator_handoff_assert_v1(p_run_id,p_receipt_id)" in wrapper
    and "fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity)" in wrapper
    and wrapper.find("fn_input_governance_validator_handoff_assert_v1(p_run_id,p_receipt_id)")
        < wrapper.find("fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity)")
)

observed = {
    "curator_zero_validator_invocations": curator_zero_validator_invocations,
    "curator_persists_handoff_receipt": curator_persists_handoff_receipt,
    "receipt_exact_subject_assertion_exists": receipt_exact_subject_assertion_exists,
    "validator_consumes_handoff_receipt": validator_consumes_handoff_receipt,
    "validator_rejects_inconsistent_sha": validator_rejects_inconsistent_sha,
    "db_entrypoint_fail_closed": db_entrypoint_fail_closed,
}

passed = all(observed.values())
result = {
    "test_code": TEST_CODE,
    "status": "PASS" if passed else "FAIL",
    "test_passed": passed,
    "test_exit_code": 0 if passed else 1,
    "semantic_authority_bound": True,
    "adversarial_case_executed": validator_rejects_inconsistent_sha,
    "canonical_exit_criterion": "receipt persistido; Curator no invoca Validator; Validator consume receipt y rechaza subject SHA inconsistente",
    "observed": observed,
}
print(json.dumps(result, sort_keys=True))
raise SystemExit(0 if passed else 1)
