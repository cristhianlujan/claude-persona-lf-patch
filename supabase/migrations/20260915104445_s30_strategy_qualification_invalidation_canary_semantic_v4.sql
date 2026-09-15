-- S30 qualification invalidation canary semantic alignment.
-- #839 intentionally excludes generic operational metadata from Strategy semantic currentness.
-- S12 must mutate a truly semantic field in its rollback-only canary; content_payload is canonical semantic material.

DO $patch$
DECLARE
  x public.lf_operation_execution%rowtype;
  f text;
  f2 text;
  before_sha text;
  after_sha text;
  canary jsonb;
BEGIN
  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-005';

  IF NOT FOUND
     OR x.operation_code<>'ACTUALIZACION_DB_LF'
     OR x.status<>'IN_PROGRESS'
     OR x.target_type<>'MIGRATION'
     OR x.target_code<>'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_SEMANTIC_V4'
     OR x.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR x.target_path IS DISTINCT FROM 'supabase/migrations/20260915104402_s30_strategy_qualification_invalidation_canary_semantic_v4.sql'
     OR coalesce(x.manifest->>'source_pr','')<>'840' THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_V4_DB_EXECUTION_BINDING_INVALID';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
    WHERE asset_type='MIGRATION' AND action_code='UPDATE'
      AND operation_code='ACTUALIZACION_DB_LF' AND status='ACTIVE' AND write_allowed
  ) THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_V4_DB_ROUTE_NOT_ACTIVE';
  END IF;

  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_V4_DB_POLICY_SNAPSHOT_MISSING';
  END IF;

  SELECT pg_get_functiondef('public.lf_canary_strategy_material_change_invalidates_qualification_v1(bigint)'::regprocedure)
    INTO f;
  before_sha:=encode(extensions.digest(convert_to(f,'UTF8'),'sha256'),'hex');
  IF before_sha<>'d16714b64559470a3a79b36e6e695ceb6a9c65076a00afa365eea8763df2bd33' THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_V4_SOURCE_DRIFT:%',before_sha;
  END IF;

  f2:=replace(
    f,
$old$UPDATE public.lf_strategy_snapshots SET metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('__qualification_invalidation_canary',clock_timestamp()::text) WHERE id=s.id;$old$,
$new$UPDATE public.lf_strategy_snapshots SET content_payload=coalesce(content_payload,'{}'::jsonb)||jsonb_build_object('__qualification_invalidation_canary',clock_timestamp()::text) WHERE id=s.id;$new$
  );

  IF f2=f OR strpos(f2,$probe$SET content_payload=coalesce(content_payload$probe$)=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_V4_PATCH_NOT_APPLIED';
  END IF;

  EXECUTE f2;

  SELECT pg_get_functiondef('public.lf_canary_strategy_material_change_invalidates_qualification_v1(bigint)'::regprocedure)
    INTO f2;
  after_sha:=encode(extensions.digest(convert_to(f2,'UTF8'),'sha256'),'hex');

  IF strpos(f2,'content_payload')=0 OR strpos(f2,$q$SET metadata=coalesce(metadata$q$)>0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_V4_POSTCHECK_FAILED:%',after_sha;
  END IF;

  canary:=public.lf_canary_strategy_material_change_invalidates_qualification_v1(35);
  IF coalesce((canary->>'passed')::boolean,false) IS DISTINCT FROM true
     OR coalesce((canary->>'persistent_mutation')::boolean,true) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_V4_RUNTIME_PROBE_FAILED:%',canary;
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=clock_timestamp(),
      manifest=manifest||jsonb_build_object(
        'result','S30_STRATEGY_QUALIFICATION_INVALIDATION_CANARY_SEMANTIC_V4_APPLIED',
        'prior_function_sha256',before_sha,
        'new_function_sha256',after_sha,
        'canary_readback',canary,
        'runtime_activation',false,
        'production_activation',false,
        'strategy_snapshot_mutation',false
      ),
      updated_by_execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-005'
  WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-005';
END
$patch$;
