#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/lf-input-governance-recurate.yml"
CALLER = ROOT / "supabase/functions/lf-profiles-governance-caller-v1/index.ts"


def main() -> int:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    caller = CALLER.read_text(encoding="utf-8")
    checks = 0

    assert "  workflow_call:\n" in workflow
    assert "workflow_dispatch:" not in workflow
    assert "fail-fast: false" in workflow
    assert "max-parallel: 1" in workflow
    assert "id-token: write" in workflow
    checks += 5

    assert "profile_creator_init_v1" not in workflow
    assert "input_readiness_recurate_v1" in workflow
    assert "programacion.fn_input_readiness_run_is_current" in workflow
    checks += 3

    assert "job_workflow_ref" in caller
    assert "GITHUB_ACTIONS_OIDC_INPUT_GOV_RECURATION_REUSABLE_V1" in caller
    assert "lf/ig-cv-n2-recuration-run-20261001" in caller
    assert "GITHUB_ACTIONS_OIDC_INPUT_GOV_RECURATION_BOOTSTRAP_PUSH_V1" in caller
    assert "eventName: \"push\"" in caller
    assert "OIDC_ACTION_SCOPE_MISMATCH" in caller
    assert "RECURATION_CALLER_IDENTITY_REQUIRED" in caller
    checks += 7

    print(f"PASS_N2_WORKFLOW_CALL_STANDARD_V1={checks}/{checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
