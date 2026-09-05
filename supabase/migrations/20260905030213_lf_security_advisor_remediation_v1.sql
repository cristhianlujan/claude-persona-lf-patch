-- LF security advisor remediation v1
-- Governed source-first remediation for internal public RLS tables and privileged LF functions.
-- Scope is intentionally explicit. Supabase-managed auth/storage objects and private-schema
-- zero-policy tables are out of scope because their current no-client-grant state is intentional.

DO $lf$
DECLARE
  v_table text;
  v_tables text[] := ARRAY[
    'audit_skill_protocols_no_bypass_marker',
    'lf_b2b_pricing_config',
    'lf_operation_policy_bindings',
    'lf_policy_versions',
    'lf_product_rule_sets',
    'lf_product_rules',
    'lf_router_action_registry',
    'lf_test_artifacts',
    'lf_test_assertion_results',
    'lf_test_judge_results',
    'lf_test_runs',
    'lf_test_suite_cases',
    'lf_test_suite_runs',
    'lf_test_suites',
    'lf_user_stories',
    'sbx_competitive_alerts',
    'sbx_competitive_competitors',
    'sbx_competitive_engagement_snapshots',
    'sbx_competitive_insight_sources',
    'sbx_competitive_insights',
    'sbx_competitive_observations',
    'sbx_competitive_public_comments',
    'sbx_competitive_runs',
    'sbx_competitive_source_state',
    'sbx_competitive_sources',
    'sbx_competitive_weekly_reports',
    'sbx_lf_validation_engine_execution_probe',
    'sbx_lf_validation_engine_protocols',
    'sbx_lf_validation_engine_qa_results',
    'sbx_lf_validation_engine_runs',
    'sbx_lf_validation_engine_steps',
    'sbx_mod_8_13_1_audits',
    'sbx_mod_8_13_1_blocks',
    'sbx_mod_8_13_1_candidates',
    'sbx_mod_8_13_1_inventory',
    'sbx_mod_8_13_1_judge',
    'sbx_test_probe_2'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass(format('public.%I', v_table)) IS NULL THEN
      RAISE EXCEPTION 'SECURITY_REMEDIATION_TARGET_MISSING:%', v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = v_table
        AND c.relkind = 'r'
        AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'SECURITY_REMEDIATION_RLS_NOT_ENABLED:%', v_table;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_policy p
      JOIN pg_class c ON c.oid = p.polrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = v_table
    ) THEN
      RAISE EXCEPTION 'SECURITY_REMEDIATION_POLICY_DRIFT:%', v_table;
    END IF;

    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM anon, authenticated', v_table);
    EXECUTE format(
      'CREATE POLICY lf_internal_client_deny ON public.%I AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)',
      v_table
    );
  END LOOP;
END
$lf$;

-- Trigger-only privileged guard: direct client execution is unnecessary.
REVOKE EXECUTE ON FUNCTION public.fn_lf_operation_provenance_guard_v1() FROM PUBLIC, anon, authenticated;
ALTER FUNCTION public.fn_lf_operation_provenance_guard_v1() SET search_path TO pg_catalog;

-- Session-context RPC remains intentionally callable by authenticated/service_role because
-- lf_client.client_accounts is server-only under RLS. Harden namespace resolution only.
ALTER FUNCTION public.fn_lf_client_session_context() SET search_path TO pg_catalog;

DO $lf_verify$
DECLARE
  v_table text;
  v_tables text[] := ARRAY[
    'audit_skill_protocols_no_bypass_marker',
    'lf_b2b_pricing_config',
    'lf_operation_policy_bindings',
    'lf_policy_versions',
    'lf_product_rule_sets',
    'lf_product_rules',
    'lf_router_action_registry',
    'lf_test_artifacts',
    'lf_test_assertion_results',
    'lf_test_judge_results',
    'lf_test_runs',
    'lf_test_suite_cases',
    'lf_test_suite_runs',
    'lf_test_suites',
    'lf_user_stories',
    'sbx_competitive_alerts',
    'sbx_competitive_competitors',
    'sbx_competitive_engagement_snapshots',
    'sbx_competitive_insight_sources',
    'sbx_competitive_insights',
    'sbx_competitive_observations',
    'sbx_competitive_public_comments',
    'sbx_competitive_runs',
    'sbx_competitive_source_state',
    'sbx_competitive_sources',
    'sbx_competitive_weekly_reports',
    'sbx_lf_validation_engine_execution_probe',
    'sbx_lf_validation_engine_protocols',
    'sbx_lf_validation_engine_qa_results',
    'sbx_lf_validation_engine_runs',
    'sbx_lf_validation_engine_steps',
    'sbx_mod_8_13_1_audits',
    'sbx_mod_8_13_1_blocks',
    'sbx_mod_8_13_1_candidates',
    'sbx_mod_8_13_1_inventory',
    'sbx_mod_8_13_1_judge',
    'sbx_test_probe_2'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF has_table_privilege('anon', format('public.%I', v_table), 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       OR has_table_privilege('authenticated', format('public.%I', v_table), 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
      RAISE EXCEPTION 'SECURITY_REMEDIATION_CLIENT_GRANT_REMAINS:%', v_table;
    END IF;

    IF NOT has_table_privilege('service_role', format('public.%I', v_table), 'SELECT') THEN
      RAISE EXCEPTION 'SECURITY_REMEDIATION_SERVICE_ROLE_REGRESSION:%', v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = v_table
        AND policyname = 'lf_internal_client_deny'
        AND permissive = 'PERMISSIVE'
        AND cmd = 'ALL'
        AND qual = 'false'
        AND with_check = 'false'
    ) THEN
      RAISE EXCEPTION 'SECURITY_REMEDIATION_DENY_POLICY_MISSING:%', v_table;
    END IF;
  END LOOP;

  IF has_function_privilege('anon', 'public.fn_lf_operation_provenance_guard_v1()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.fn_lf_operation_provenance_guard_v1()', 'EXECUTE')
     OR has_function_privilege('public', 'public.fn_lf_operation_provenance_guard_v1()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_REMEDIATION_TRIGGER_GUARD_EXECUTE_STILL_PUBLIC';
  END IF;

  IF NOT has_function_privilege('service_role', 'public.fn_lf_operation_provenance_guard_v1()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_REMEDIATION_TRIGGER_GUARD_SERVICE_ROLE_REGRESSION';
  END IF;

  IF has_function_privilege('anon', 'public.fn_lf_client_session_context()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.fn_lf_client_session_context()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.fn_lf_client_session_context()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_REMEDIATION_SESSION_RPC_GRANT_REGRESSION';
  END IF;
END
$lf_verify$;
