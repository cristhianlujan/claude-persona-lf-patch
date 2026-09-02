from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CALLER = ROOT / "supabase/functions/lf-profile-creator-governance-caller-v1/index.ts"
WORKFLOW = ROOT / ".github/workflows/lf-customer-profile-creator-governance-caller.yml"

caller = CALLER.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")

checks = {
    "exclusive_branch": 'lf/profiles/profile-creator-customer-caller-20260902' in caller and 'lf/profiles/profile-creator-customer-caller-20260902' in workflow,
    "exclusive_workflow": 'LF Customer Profile Creator Governance Caller' in caller and 'LF Customer Profile Creator Governance Caller' in workflow,
    "oidc_exact_repo": 'OIDC_REPOSITORY_MISMATCH' in caller and 'OIDC_REF_MISMATCH' in caller and 'OIDC_WORKFLOW_MISMATCH' in caller,
    "only_profile_creator_actions": 'profile_creator_init_v1' in caller and 'profile_creator_record_step_v1' in caller,
    "no_input_governance_actions": 'input_readiness_' not in caller and 'input-governance-agent-v1' not in caller,
    "no_adapter_actions": 'adapter' not in caller.lower(),
    "customer_allowlist": all(code in caller for code in [
        'CUSTOMER_FINANCIAL_UX_DECISIONING',
        'CUSTOMER_TRUST_CLARITY_VULNERABILITY',
        'CUSTOMER_PAYMENTS_RECOVERY',
        'CUSTOMER_IDENTITY_CONSENT_PRIVACY',
    ]),
    "runtime_delegate_only": 'run-creacion-perfil-lf' in caller and 'lf_record_creacion_perfil_step_v1' not in caller,
    "no_manual_db_step_write": 'lf_operation_execution_steps' not in caller and '.from(' not in caller,
    "source_only_dispatch": 'source_canary_only' in workflow and 'NON_CANARY_PROFILE_CREATION_EXECUTED=false' in workflow,
    "no_customer_receipt_fabrication": 'LF_OPERATION_CONTRACT_RECEIPT' not in caller and 'LF_OPERATION_CONTRACT_RECEIPT' not in workflow,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit(f"FAIL_PROFILE_CREATOR_CUSTOMER_CALLER_SOURCE:{','.join(failed)}")
print(f"PASS_PROFILE_CREATOR_CUSTOMER_CALLER_SOURCE={sum(checks.values())}/{len(checks)}")
