#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260929173500_pase_control_system_qualification_authority_v1.sql"


def main() -> int:
    text = MIGRATION.read_text(encoding="utf-8")
    required = [
        "public.lf_qualification_receipts",
        "'CONTROL_SYSTEM'::text",
        "PASE_CONTROL_QUALIFICATION_V1",
        "lf_control_system_qualification_revision_sha256_v1",
        "lf_record_control_system_qualification_v1",
        "lf_control_system_qualification_readback_v1",
        "lf-control-system-qualification-record/v1",
        "lf-control-system-qualification-readback/v1",
        "START_QUALIFICATION",
        "PASS_QUALIFICATION",
        "status','MISSING'",
        "status','QUALIFIED'",
        "qualification_input",
        "qualification_result",
        "source_execution_id",
        "uq_lf_qualification_receipts_control_system_current",
    ]
    missing = [item for item in required if item not in text]
    assert not missing, f"missing authority invariants: {missing}"
    assert "CREATE TABLE" not in text, "must extend canonical ledger, not create a parallel table"
    assert "target_type = 'PASE_CONTROL_QUALIFICATION'" not in text, "must not invent a synthetic operation target type"
    assert "'CONTROL_SYSTEM',p_candidate_id" in text, "producer must write the canonical CONTROL_SYSTEM subject"
    assert "lifecycle_state_code=v_qualifying" in text and "lifecycle_state_code=v_qualified" in text, "producer must traverse canonical qualification lifecycle"
    print("PASS_PASE_CONTROL_SYSTEM_QUALIFICATION_AUTHORITY_V1 checks=20")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
