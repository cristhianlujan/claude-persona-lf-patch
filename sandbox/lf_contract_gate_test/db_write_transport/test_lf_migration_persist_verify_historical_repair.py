#!/usr/bin/env python3
from __future__ import annotations

from lf_migration_persist_verify import evaluate


def payload(*, git_persisted: bool, parity_status: str):
    return {
        "schema_version": "lf-migration-persist-verify/v1",
        "operation_code": "ACTUALIZACION_DB_LF",
        "execution_id": "EXEC-MIGRATION-SOURCE-REPAIR-TEST-001",
        "effect_scope": "MIGRATION:20260923013150",
        "target_path": "supabase/migrations/20260923013150_restrict_profile_semantic_judge_trust_validator_acl.sql",
        "migration_version": "20260923013150",
        "migration_name": "restrict_profile_semantic_judge_trust_validator_acl",
        "source_sha256": "a" * 64,
        "git": {
            "path": "supabase/migrations/20260923013150_restrict_profile_semantic_judge_trust_validator_acl.sql",
            "source_sha256": "a" * 64,
            "head_sha": "b" * 40,
            "blob_sha1": "c" * 40,
            "persisted": git_persisted,
            "readback": git_persisted,
        },
        "supabase": {
            "applied": True,
            "readback": True,
            "ledger_version": "20260923013150",
            "ledger_name": "restrict_profile_semantic_judge_trust_validator_acl",
            "ddl_replayed": False,
        },
        "parity": {
            "source_path": "supabase/migrations/20260923013150_restrict_profile_semantic_judge_trust_validator_acl.sql",
            "migration_version": "20260923013150",
            "migration_name": "restrict_profile_semantic_judge_trust_validator_acl",
            "status": parity_status,
        },
    }


def main() -> None:
    before = evaluate(payload(git_persisted=False, parity_status="FAIL"))
    assert before.status == "BLOCKED"
    assert before.code == "BLOCK_GIT_SOURCE_NOT_DURABLE"

    repaired_but_not_reverified = evaluate(payload(git_persisted=True, parity_status="FAIL"))
    assert repaired_but_not_reverified.status == "BLOCKED"
    assert repaired_but_not_reverified.code == "BLOCK_DUAL_SURFACE_PARITY_NOT_PASS"

    after = evaluate(payload(git_persisted=True, parity_status="PASS"))
    assert after.status == "CONSISTENT"
    assert after.consistent is True
    assert after.ready_to_apply is False
    print("PASS_MIGRATION_PERSIST_VERIFY_HISTORICAL_SOURCE_ONLY_REPAIR")


if __name__ == "__main__":
    main()
