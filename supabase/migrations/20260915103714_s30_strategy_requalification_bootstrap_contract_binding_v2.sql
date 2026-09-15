-- S30 requalification bootstrap v2.
-- Narrow fail-closed repair after the first governed invocation proved the reserver requires
-- contract_code in the execution manifest. The previously applied v1 migration is immutable.

DO $patch$
DECLARE
  x public.lf_operation_execution%rowtype;
  f text;
  f2 text;
  before_sha text;
  after_sha text;
BEGIN
  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-003';

  IF NOT FOUND
     OR x.operation_code<>'ACTUALIZACION_DB_LF'
     OR x.status<>'IN_PROGRESS'
     OR x.target_type<>'MIGRATION'
     OR x.target_code<>'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_CONTRACT_BINDING_V2'
     OR x.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR x.target_path IS DISTINCT FROM 'supabase/migrations/20260915103714_s30_strategy_requalification_bootstrap_contract_binding_v2.sql'
     OR coalesce(x.manifest->>'source_pr','')<>'840' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V2_DB_EXECUTION_BINDING_INVALID';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_router_action_registry
    WHERE asset_type='MIGRATION'
      AND action_code='UPDATE'
      AND operation_code='ACTUALIZACION_DB_LF'
      AND status='ACTIVE'
      AND write_allowed
  ) THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V2_DB_ROUTE_NOT_ACTIVE';
  END IF;

  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V2_DB_POLICY_SNAPSHOT_MISSING';
  END IF;

  SELECT pg_get_functiondef('public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text)'::regprocedure)
    INTO f;
  before_sha:=encode(extensions.digest(convert_to(f,'UTF8'),'sha256'),'hex');
  IF before_sha<>'08ebdc424982a76086462c936a776c044244e78a3dce049c0ee9106b371fdd15' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V2_SOURCE_DRIFT:%',before_sha;
  END IF;

  f2:=replace(
    f,
    E"jsonb_build_object(\n      'mode','STRATEGY_REQUALIFICATION_BOOTSTRAP_ONLY',",
    E"jsonb_build_object(\n      'contract_code',(SELECT oc.contract_code FROM public.lf_operation_contracts oc WHERE oc.operation_code='EJECUCION_ESTRATEGIA_LF' AND oc.status='ACTIVE_ENFORCEMENT' ORDER BY oc.contract_code LIMIT 1),\n      'mode','STRATEGY_REQUALIFICATION_BOOTSTRAP_ONLY',"
  );

  IF f2=f OR strpos(f2,"'contract_code',(SELECT oc.contract_code")=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V2_PATCH_NOT_APPLIED';
  END IF;

  EXECUTE f2;

  SELECT pg_get_functiondef('public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text)'::regprocedure)
    INTO f2;
  after_sha:=encode(extensions.digest(convert_to(f2,'UTF8'),'sha256'),'hex');

  IF strpos(f2,"'contract_code'")=0
     OR strpos(f2,"operation_code='EJECUCION_ESTRATEGIA_LF'")=0
     OR strpos(f2,"status='ACTIVE_ENFORCEMENT'")=0
     OR strpos(f2,'lf_strategy_execution_qualification_guard_v1')>0
     OR strpos(f2,'UPDATE public.lf_strategy_snapshots')>0
     OR strpos(f2,'INSERT INTO public.lf_strategy_snapshots')>0
     OR strpos(f2,'DELETE FROM public.lf_strategy_snapshots')>0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V2_POSTCHECK_FAILED:%',after_sha;
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=clock_timestamp(),
      manifest=manifest||jsonb_build_object(
        'result','S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_CONTRACT_BINDING_V2_APPLIED',
        'prior_function_sha256',before_sha,
        'new_function_sha256',after_sha,
        'runtime_activation',false,
        'production_activation',false,
        'strategy_snapshot_mutation',false
      ),
      updated_by_execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-003'
  WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-003';
END
$patch$;
