-- S30 requalification bootstrap v3.
-- The operation-neutral recorder requires server_assertions when trust_validation.valid=true.
-- This patch adds only the exact positive assertions already verified by the bootstrap RPC.

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
  WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-004';

  IF NOT FOUND
     OR x.operation_code<>'ACTUALIZACION_DB_LF'
     OR x.status<>'IN_PROGRESS'
     OR x.target_type<>'MIGRATION'
     OR x.target_code<>'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_SERVER_ASSERTIONS_V3'
     OR x.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR x.target_path IS DISTINCT FROM 'supabase/migrations/20260915104023_s30_strategy_requalification_bootstrap_server_assertions_v3.sql'
     OR coalesce(x.manifest->>'source_pr','')<>'840' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V3_DB_EXECUTION_BINDING_INVALID';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
    WHERE asset_type='MIGRATION' AND action_code='UPDATE'
      AND operation_code='ACTUALIZACION_DB_LF' AND status='ACTIVE' AND write_allowed
  ) THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V3_DB_ROUTE_NOT_ACTIVE';
  END IF;

  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V3_DB_POLICY_SNAPSHOT_MISSING';
  END IF;

  SELECT pg_get_functiondef('public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text)'::regprocedure)
    INTO f;
  before_sha:=encode(extensions.digest(convert_to(f,'UTF8'),'sha256'),'hex');
  IF before_sha<>'9a0de3154932b7e4d121498aa7a636a67f14a61bfc90c69482652f1e7e8d0fc7' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V3_SOURCE_DRIFT:%',before_sha;
  END IF;

  f2:=replace(
    f,
$old$      'code','STRATEGY_REQUALIFICATION_BOOTSTRAP_ROUTE_EXACT',
      'details',jsonb_build_object($old$,
$new$      'code','STRATEGY_REQUALIFICATION_BOOTSTRAP_ROUTE_EXACT',
      'server_assertions',jsonb_build_array(
        'r16_quality_bound','c05_reliability_bound','required_evidence_present',
        'authority_currentness_pass','runtime_activation_authorized','business_effect_dispatch_allowed'
      ),
      'server_hard_fails','[]'::jsonb,
      'details',jsonb_build_object($new$
  );

  IF f2=f OR strpos(f2,$probe$'server_assertions',jsonb_build_array$probe$)=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V3_PATCH_NOT_APPLIED';
  END IF;

  EXECUTE f2;

  SELECT pg_get_functiondef('public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text)'::regprocedure)
    INTO f2;
  after_sha:=encode(extensions.digest(convert_to(f2,'UTF8'),'sha256'),'hex');

  IF strpos(f2,$q$'server_assertions'$q$)=0
     OR strpos(f2,$q$'server_hard_fails'$q$)=0
     OR strpos(f2,'lf_record_operation_step_core_v1')=0
     OR strpos(f2,'UPDATE public.lf_strategy_snapshots')>0
     OR strpos(f2,'INSERT INTO public.lf_strategy_snapshots')>0
     OR strpos(f2,'DELETE FROM public.lf_strategy_snapshots')>0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V3_POSTCHECK_FAILED:%',after_sha;
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=clock_timestamp(),
      manifest=manifest||jsonb_build_object(
        'result','S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_SERVER_ASSERTIONS_V3_APPLIED',
        'prior_function_sha256',before_sha,
        'new_function_sha256',after_sha,
        'runtime_activation',false,
        'production_activation',false,
        'strategy_snapshot_mutation',false
      ),
      updated_by_execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-004'
  WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-004';
END
$patch$;
