from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ACTIVE = ROOT / "services/profile_runtime_api/scripts/hetzner_execution_only_queue_worker.py"
LEGACY = ROOT / "services/profile_runtime_api/scripts/hetzner_queue_worker.py"
SERVICE = ROOT / "services/profile_runtime_api/deploy/lf-profile-runtime-queue-worker.service"


def test_active_service_uses_execution_only_worker() -> None:
    service = SERVICE.read_text(encoding="utf-8")
    assert "hetzner_execution_only_queue_worker.py --daemon" in service
    assert "hetzner_queue_worker.py --daemon" not in service


def test_active_worker_does_not_resolve_router_or_discover_assets() -> None:
    source = ACTIVE.read_text(encoding="utf-8")
    forbidden = (
        "lf_router_resolve_v1",
        "v_lf_router_adapter_bindings",
        "from public.lf_activos",
        "metadata->'semantic_judge_binding'",
    )
    for token in forbidden:
        assert token not in source
    assert "LF_ROUTER_EXECUTION_ENVELOPE_V1" in source
    assert "router_execution_envelope_sha256" in source
    assert "_materialize_resolved_adapter_sources" in source


def test_runtime_only_reads_exact_router_resolved_capsule_refs() -> None:
    source = ACTIVE.read_text(encoding="utf-8")
    assert 'item.get("ref")' in source
    assert 'item.get("activation_source") != "ROUTER"' in source
    assert "HETZNER_RESOLVED_ADAPTER_CAPSULE_PATH_ESCAPE" in source
    assert "HETZNER_ROUTER_EXECUTION_PROFILE_CODE_MISMATCH" in source
    assert "HETZNER_ROUTER_EXECUTION_ENVELOPE_DIGEST_MISMATCH" in source


def test_legacy_resolver_is_not_the_active_systemd_entrypoint() -> None:
    legacy = LEGACY.read_text(encoding="utf-8")
    service = SERVICE.read_text(encoding="utf-8")
    # Historical implementation still exists for compatibility during the split,
    # but the active unit must never execute it directly.
    assert "public.lf_router_resolve_v1" in legacy
    assert "v_lf_router_adapter_bindings" in legacy
    assert "hetzner_execution_only_queue_worker.py" in service
