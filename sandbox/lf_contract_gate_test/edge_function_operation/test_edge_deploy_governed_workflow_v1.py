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
    assert "ROLLBACK_COMMIT: cbaecd8d154b593f7d16126e9f3097797f31a7aa" in WF
    assert "Roll back caller if postdeploy verification failed" in WF


def test_pre_and_post_management_readback_are_mandatory():
    assert "Predeploy Management API readback" in WF
    assert "Postdeploy Management API readback" in WF
    assert WF.count("edge_management_credential_canary_v1.py") >= 3


def test_deploy_lane_is_manual_only():
    assert "github.event_name == 'workflow_dispatch' && inputs.action == 'deploy-caller'" in WF
    deploy_start = WF.index("  deploy-caller:")
    deploy_block = WF[deploy_start:]
    assert "github.event_name == 'workflow_dispatch'" in deploy_block
