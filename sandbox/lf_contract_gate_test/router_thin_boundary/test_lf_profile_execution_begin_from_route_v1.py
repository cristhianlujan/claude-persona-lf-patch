from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260925160500_lf_profile_execution_begin_from_route_v1.sql"
SQL = MIGRATION.read_text(encoding="utf-8")
LOWER = SQL.lower()
FUNCTION_BODY = LOWER.split("as $function$", 1)[1].split("$function$", 1)[0]


def test_receiver_delegates_to_canonical_profile_begin() -> None:
    assert "create or replace function public.lf_profile_execution_begin_from_route_v1" in LOWER
    assert "public.lf_profile_execution_begin_v1(" in LOWER
    assert "p_route_decision#>>'{target,codigo_activo}'" in SQL


def test_receiver_requires_exact_thin_router_identity() -> None:
    for token in (
        "LF_ROUTER_ROUTE_DECISION_V1",
        "ACT-0001",
        "PROFILE_EXECUTION",
        "EJECUCION_PERFIL_LF",
        "public.lf_router_action_registry:PERFIL:PROFILE_EXECUTION",
    ):
        assert token in SQL


def test_receiver_does_not_reroute_or_resolve_downstream_work() -> None:
    forbidden = (
        "lf_router_resolve_v1",
        "lf_router_route_decision_v1",
        "lf_operation_contracts",
        "lf_operation_step_contracts",
        "v_lf_operation_policy_snapshot",
        "v_lf_router_adapter_bindings",
        "fn_lf_router_input_governance_resolve_v1",
        "lf_activos",
        "v_lf_fuente_operativa_busqueda",
        "runtime_request_envelope",
    )
    for token in forbidden:
        assert token not in FUNCTION_BODY


def test_receiver_binds_route_provenance_into_manifest() -> None:
    for token in (
        "route_decision_schema",
        "route_decision_router",
        "route_decision_binding_ref",
        "route_decision_sha256",
        "route_decision",
    ):
        assert token in FUNCTION_BODY


def test_foreign_operation_fails_before_reservation() -> None:
    assert "BLOCK_ROUTE_OPERATION_MISMATCH" in SQL
    assert "SHOULD-NOT-RESERVE" in SQL
    post = LOWER.split("do $post$", 1)[1]
    assert post.index("block_route_operation_mismatch") < post.index("negative_side_effect")
