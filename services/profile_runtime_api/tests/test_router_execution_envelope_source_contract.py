from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260923023500_lf_profile_runtime_router_envelope_freeze_v1.sql"
WORKER = ROOT / "services/profile_runtime_api/scripts/hetzner_queue_worker.py"


def test_queue_ingress_freezes_router_resolution_before_runtime() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "LF_ROUTER_EXECUTION_ENVELOPE_V1" in sql
    assert "public.lf_router_resolve_v1" in sql
    assert "activation_source','ROUTER'" in sql
    assert "resolved_runtime_adapters" in sql
    assert "router_execution_envelope_sha256" in sql
    assert "PROFILE_RUNTIME_ROUTER_ENVELOPE_IMMUTABLE" in sql
    assert "before insert on private.lf_profile_runtime_queue_v1" in sql.lower()


def test_ingress_envelope_binds_exact_profile_identity() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    for token in (
        "'profile_code',new.profile_code",
        "'profile_slug',new.profile_slug",
        "'profile_source_paths',new.profile_source_paths",
        "HETZNER_ROUTER_ENVELOPE_REQUIRED_ADAPTER_NOT_RESOLVED",
        "HETZNER_ROUTER_ENVELOPE_SUPPLIED_DIGEST_MISMATCH",
    ):
        assert token in sql


def test_runtime_cleanup_is_required_as_separate_followup() -> None:
    worker = WORKER.read_text(encoding="utf-8")
    # This PR is source-first control-plane materialization only. The next isolated
    # runtime PR must remove these two discovery paths before deployment.
    assert "public.lf_router_resolve_v1" in worker
    assert "public.v_lf_router_adapter_bindings" in worker
