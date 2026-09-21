#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20260921062500_lf_profile_execution_semantic_judge_enforcement_v1.sql"
text=MIG.read_text(encoding="utf-8")
checks={
    "migration_exists": MIG.is_file(),
    "governed_actor_marker": "LF_CI_ROLLBACK_GOVERNED_ACTOR_V1: ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF" in text,
    "semantic_branch": "elsif p_step_id='semantic_judge' then" in text,
    "pass_required": "semantic_judge_result,status}' is distinct from 'PASS'" in text,
    "unsupported_claims_must_be_array": "jsonb_typeof(p_evidence_payload->'unsupported_claims')='array'" in text and "else true" in text,
    "unsupported_claims_must_be_empty": "jsonb_array_length(p_evidence_payload->'unsupported_claims')<>0" in text,
    "ci_actor_preferred_in_rollback": "ci_candidate_rollback_actor" in text and "v_ci_actor" in text,
    "predecessor_required": "output_validate_predecessor_not_clean" in text,
    "semantic_fail_code": "semantic_judge_not_pass" in text,
    "production_actor_required": "production_apply_authorized" in text,
    "profile_agnostic": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF" not in text and "PERFIL-UI-ARCHITECT" not in text,
}
failed=[k for k,v in checks.items() if not v]
if failed:
    raise SystemExit("FAIL_PROFILE_EXECUTION_SEMANTIC_JUDGE_ENFORCEMENT:"+",".join(failed))
print("PASS_PROFILE_EXECUTION_SEMANTIC_JUDGE_ENFORCEMENT")
