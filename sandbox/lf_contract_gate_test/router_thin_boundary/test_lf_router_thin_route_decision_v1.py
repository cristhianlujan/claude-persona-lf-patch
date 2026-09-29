from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
MIGRATION = REPO / "supabase/migrations/20260925152000_lf_router_thin_route_decision_v1.sql"


def _function_body(sql: str) -> str:
    start = sql.index("create or replace function public.lf_router_route_decision_v1")
    body_start = sql.index("as $function$", start)
    body_end = sql.index("$function$;", body_start)
    return sql[start:body_end].lower()


def test_thin_router_source_boundary() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    body = _function_body(sql)

    assert "lf_router_route_decision_v1" in body
    assert "lf_router_resolve_v1(" not in body
    assert "'status','routed'" in body
    assert "'router','act-0001'" in body
    assert "'route_binding_ref'" in body

    required_route_dependencies = (
        "public.v_lf_fuente_operativa_busqueda",
        "public.lf_router_action_registry",
        "public.lf_operation_registry",
    )
    for token in required_route_dependencies:
        assert token in body, token

    forbidden_execution_dependencies = (
        "lf_operation_contracts",
        "lf_operation_step_contracts",
        "v_lf_operation_policy_snapshot",
        "v_lf_router_adapter_bindings",
        "fn_lf_router_input_governance_resolve_v1",
        "lf_test_requirement_bindings",
        "lf_qualification_current_v1",
        "public.lf_activos",
        "downstream_execution_allowed",
        "next_step",
        "contract_refs",
        "policy_refs",
        "input_governance",
        "semantic_judge",
        "runtime_request_envelope",
        "router_execution_envelope",
    )
    for token in forbidden_execution_dependencies:
        assert token not in body, token


def test_thin_router_output_is_route_not_execution_readiness() -> None:
    sql = MIGRATION.read_text(encoding="utf-8").lower()
    body = _function_body(sql)

    assert "'schema','lf_router_route_decision_v1'" in body
    assert "'status','routed'" in body
    assert "'asset_type',v_type_hint" in body
    assert "'action_code',v_action" in body
    assert "'operation_code'" in body
    assert "'target'" in body

    # A route decision must not claim that execution is ready or allowed.
    assert "ready_to_execute" not in body
    assert "ready_inspection" not in body
    assert "downstream_execution_allowed" not in body


def test_thin_router_does_not_own_controls_or_context() -> None:
    body = _function_body(MIGRATION.read_text(encoding="utf-8"))

    forbidden_ownership_terms = (
        "context_pack",
        "profile_research_baseline",
        "execute_profile",
        "required_policy_count",
        "resolved_policy_count",
        "adapter_runtime_authority_source",
        "composition_order",
        "precedence",
    )
    for token in forbidden_ownership_terms:
        assert token not in body, token
