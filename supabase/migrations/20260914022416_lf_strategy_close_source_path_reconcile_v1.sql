-- Reconcile STRATEGY_CLOSE governance source references to the real Supabase migration version.
INSERT INTO public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
)
VALUES(
  'EXEC-BOOTSTRAP-CIERRE-ESTRATEGIA-SOURCE-RECONCILE-20260914-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR',
  'CIERRE_ESTRATEGIA_LF',
  'IN_PROGRESS',
  '{"mode":"STRATEGY_CLOSE_SOURCE_PATH_RECONCILE","governance_bootstrap":true,"bootstrap_operation_code":"CIERRE_ESTRATEGIA_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false,"runtime_activation":false,"strategy_mutation":false}'::jsonb,
  'EXEC-BOOTSTRAP-CIERRE-ESTRATEGIA-SOURCE-RECONCILE-20260914-001',
  'EXEC-BOOTSTRAP-CIERRE-ESTRATEGIA-SOURCE-RECONCILE-20260914-001'
);

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version='20260914022303' AND name='lf_strategy_close_transversal_v1'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_SOURCE_RECONCILE_LEDGER_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='CIERRE_ESTRATEGIA_LF'
      AND source_paths->>0='supabase/migrations/20260914020000_lf_strategy_close_transversal_v1.sql'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_SOURCE_RECONCILE_REGISTRY_PRECONDITION';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='CIERRE_ESTRATEGIA_LF'
      AND contract_path='supabase/migrations/20260914020000_lf_strategy_close_transversal_v1.sql'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_SOURCE_RECONCILE_CONTRACT_PRECONDITION';
  END IF;
END $pre$;

UPDATE public.lf_operation_registry
SET source_paths=jsonb_set(
      source_paths,
      '{0}',
      to_jsonb('supabase/migrations/20260914022303_lf_strategy_close_transversal_v1.sql'::text),
      false
    ),
    updated_at=now(),
    updated_by_execution_id='EXEC-BOOTSTRAP-CIERRE-ESTRATEGIA-SOURCE-RECONCILE-20260914-001'
WHERE operation_code='CIERRE_ESTRATEGIA_LF';

UPDATE public.lf_operation_contracts
SET contract_path='supabase/migrations/20260914022303_lf_strategy_close_transversal_v1.sql',
    updated_at=now(),
    updated_by_execution_id='EXEC-BOOTSTRAP-CIERRE-ESTRATEGIA-SOURCE-RECONCILE-20260914-001'
WHERE operation_code='CIERRE_ESTRATEGIA_LF';

DO $post$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='CIERRE_ESTRATEGIA_LF'
      AND source_paths->>0='supabase/migrations/20260914022303_lf_strategy_close_transversal_v1.sql'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_SOURCE_RECONCILE_REGISTRY_POSTCONDITION';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='CIERRE_ESTRATEGIA_LF'
      AND contract_path='supabase/migrations/20260914022303_lf_strategy_close_transversal_v1.sql'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_SOURCE_RECONCILE_CONTRACT_POSTCONDITION';
  END IF;
END $post$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=now(),
    updated_at=now(),
    updated_by_execution_id='EXEC-BOOTSTRAP-CIERRE-ESTRATEGIA-SOURCE-RECONCILE-20260914-001',
    manifest=manifest||'{"result":"STRATEGY_CLOSE_SOURCE_PATH_RECONCILED","canonical_source_path":"supabase/migrations/20260914022303_lf_strategy_close_transversal_v1.sql"}'::jsonb
WHERE execution_id='EXEC-BOOTSTRAP-CIERRE-ESTRATEGIA-SOURCE-RECONCILE-20260914-001';