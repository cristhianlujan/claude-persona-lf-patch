from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = (ROOT / ".github/workflows/lf-edge-deploy-credential-readback.yml").read_text(encoding="utf-8")


def test_governed_environment_and_fixed_target():
    assert "environment: lf-edge-deploy" in WF
    assert "EDGE_FUNCTION_SLUG: lf-profiles-governance-caller-v1" in WF
    assert "function_slug:" not in WF
    assert "ref: refs/heads/main" in WF
    assert 'test "${GITHUB_REF}" = "refs/heads/main"' in WF


def test_no_database_or_service_role_credentials():
    forbidden = (
        "LF_SUPABASE_DB_PASSWORD",
        "PGPASSWORD",
        "SUPABASE_SERVICE_ROLE_KEY",
        "DATABASE_URL",
    )
    for value in forbidden:
        assert value not in WF


def test_deploy_is_single_function_and_preserves_oidc_jwt_mode():
    assert 'supabase functions deploy "${EDGE_FUNCTION_SLUG}"' in WF
    assert "--project-ref" in WF
    assert "--no-verify-jwt" in WF
    assert "--use-api" in WF
    assert "supabase functions deploy --project-ref" not in WF


def test_cli_and_rollback_are_pinned():
    assert "uses: supabase/setup-cli@v1" in WF
    assert "version: 2.48.3" in WF
    assert "ROLLBACK_COMMIT: c9be66afa6d73727c760878fce0e1a9362e33106" in WF
    assert "Roll back caller if postdeploy verification failed" in WF


def test_pre_and_post_management_readback_are_mandatory():
    assert "Predeploy Management API readback" in WF
    assert "Postdeploy Management API readback" in WF
    assert WF.count("edge_management_credential_canary_v1.py") >= 3


def test_deploy_lane_runs_for_caller_source_push_or_manual_dispatch():
    deploy_start = WF.index("  deploy-caller:")
    deploy_block = WF[deploy_start:]
    assert "github.event_name == 'push'" in deploy_block
    assert "github.event_name == 'workflow_dispatch'" in deploy_block
    assert "inputs.action == 'deploy-caller'" in deploy_block
    for path in (
        "supabase/functions/lf-profiles-governance-caller-v1/index.ts",
        "supabase/functions/lf-profiles-governance-caller-v1/caller.ts",
        "supabase/functions/lf-profiles-governance-caller-v1/cp2_edge_bridge.ts",
    ):
        assert path in WF


def test_push_deploy_remains_exact_main_only():
    assert "branches: [main]" in WF
    assert "ref: refs/heads/main" in WF
    assert 'test "${GITHUB_REF}" = "refs/heads/main"' in WF
    assert 'test "${MAIN_SHA}" = "${GITHUB_SHA}"' in WF


def _runtime_block():
    start = WF.index("  deploy-profile-runtime:")
    return WF[start:]


def test_profile_runtime_lane_is_dispatch_only_and_approval_gated():
    block = _runtime_block()
    assert "github.event_name == 'workflow_dispatch' && inputs.action == 'deploy-profile-runtime'" in block
    assert "github.event_name == 'push'" not in block.split("steps:")[0]
    assert "environment: lf-edge-deploy" in block
    assert "- deploy-profile-runtime" in WF


def test_profile_runtime_lane_has_fixed_target_and_exact_main():
    block = _runtime_block()
    assert "PROFILE_RUNTIME_SLUG: run-creacion-perfil-lf" in block
    assert 'test "${GITHUB_REF}" = "refs/heads/main"' in block
    assert 'test "${MAIN_SHA}" = "${GITHUB_SHA}"' in block
    assert 'supabase functions deploy "${PROFILE_RUNTIME_SLUG}"' in block
    assert "supabase functions deploy --project-ref" not in block
    assert "function_slug:" not in block


def test_profile_runtime_lane_preserves_jwt_mode():
    block = _runtime_block()
    assert "--no-verify-jwt" not in block  # run-creacion-perfil-lf requires verify_jwt=true
    assert "edge_profile_runtime_readback_v1.py" in block


def test_profile_runtime_lane_has_pre_post_readback_and_rollback():
    block = _runtime_block()
    assert "Predeploy Management API readback" in block
    assert "Postdeploy Management API readback" in block
    assert "Roll back profile runtime if postdeploy verification failed" in block
    assert "PROFILE_RUNTIME_ROLLBACK_COMMIT: b7be59551f72e7b6a02bd4e849ab64bfcaa44cdc" in block
    assert block.count("edge_profile_runtime_readback_v1.py") >= 3


def test_profile_runtime_lane_has_no_db_credentials_and_no_expression_in_shell():
    block = _runtime_block()
    for value in ("LF_SUPABASE_DB_PASSWORD", "PGPASSWORD", "SUPABASE_SERVICE_ROLE_KEY", "DATABASE_URL"):
        assert value not in block
    assert "NEXT=$(( ${{" not in block
