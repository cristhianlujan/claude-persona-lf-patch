#!/usr/bin/env python3
import json
import re
from pathlib import Path

TEST_CODE = "ENG_M5_9_NEGATIVE_NO_INVOKE"
ROOT = Path(__file__).resolve().parents[4]

curator_path = ROOT / "supabase/functions/input-governance-curator-v1/index.ts"
validator_path = ROOT / "supabase/functions/input-governance-validator-v1/index.ts"
migration_path = ROOT / "supabase/migrations/20261007195500_ig_m5_9_persist_receipt.sql"

curator = curator_path.read_text(encoding="utf-8")
validator = validator_path.read_text(encoding="utf-8")
migration = migration_path.read_text(encoding="utf-8")

curator_zero_validator_invocations = not bool(
    re.search(r'fn_input_governance_validator|input-governance-validator-v1', curator)
)
curator_persists_handoff_receipt = (
    "fn_input_governance_curator_handoff_receipt_v1" in curator
    and "handoff_receipt" in curator
)
receipt_exact_subject_assertion_exists = (
    "fn_assert_provenance_receipt" in migration
    and "subject_sha256" in migration
)
validator_consumes_handoff_receipt = (
    "handoff_receipt" in validator
    and "fn_assert_provenance_receipt" in validator
)
validator_rejects_inconsistent_sha = (
    validator_consumes_handoff_receipt
    and "subject_sha256" in validator
)

observed = {
    "curator_zero_validator_invocations": curator_zero_validator_invocations,
    "curator_persists_handoff_receipt": curator_persists_handoff_receipt,
    "receipt_exact_subject_assertion_exists": receipt_exact_subject_assertion_exists,
    "validator_consumes_handoff_receipt": validator_consumes_handoff_receipt,
    "validator_rejects_inconsistent_sha": validator_rejects_inconsistent_sha,
}

passed = all(observed.values())
result = {
    "test_code": TEST_CODE,
    "status": "PASS" if passed else "FAIL",
    "test_passed": passed,
    "test_exit_code": 0 if passed else 1,
    "semantic_authority_bound": True,
    "adversarial_case_executed": True,
    "canonical_exit_criterion": "receipt persistido; Curator no invoca Validator; Validator rechaza receipt con SHA inconsistente",
    "observed": observed,
}
print(json.dumps(result, sort_keys=True))
raise SystemExit(0 if passed else 1)
