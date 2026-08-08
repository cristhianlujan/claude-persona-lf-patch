-- PR93 · Production readiness P0
-- Make public views execute with the querying role instead of the view owner.
-- View definitions and grants remain unchanged.

begin;

alter view public.v_lf_artifact_destination_registry set (security_invoker=true);
alter view public.v_lf_artifact_pack_template_registry set (security_invoker=true);
alter view public.v_lf_fuente_operativa_busqueda set (security_invoker=true);
alter view public.v_lf_operation_contract set (security_invoker=true);
alter view public.v_lf_operation_execution_checklist set (security_invoker=true);
alter view public.v_lf_operation_execution_judge set (security_invoker=true);
alter view public.v_lf_operation_judge_definition set (security_invoker=true);
alter view public.v_lf_operation_step_contract_judge_coverage set (security_invoker=true);
alter view public.v_lf_operation_step_contracts set (security_invoker=true);
alter view public.v_lf_operation_steps set (security_invoker=true);
alter view public.v_lf_operation_steps_with_contracts set (security_invoker=true);
alter view public.v_lf_product_rules_current set (security_invoker=true);
alter view public.v_lf_profile_runtime_protocol set (security_invoker=true);
alter view public.v_lf_reporte_salida set (security_invoker=true);
alter view public.v_lf_strategy_events set (security_invoker=true);
alter view public.v_lf_strategy_latest set (security_invoker=true);
alter view public.v_lf_test_run_observability set (security_invoker=true);
alter view public.v_lf_test_suite_observability set (security_invoker=true);
alter view public.v_sbx_competitive_observation_summary set (security_invoker=true);
alter view public.v_sbx_mod_8_13_1_dashboard set (security_invoker=true);
alter view public.v_sbx_mod_8_13_1_matriz set (security_invoker=true);

commit;
