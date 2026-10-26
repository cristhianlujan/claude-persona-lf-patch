-- Draft 2F.P: one non-dispatchable Router row. D8 owner GO is pending.
-- Future application only through ACTUALIZACION_DB_LF + authorized Merge Train.
-- No operation contract, execution runtime, grants, READY promotion or D7 storage.
DO $candidate$
DECLARE
  v_actor text;
  v_actor_count integer;
  v_existing public.lf_router_action_registry%rowtype;
BEGIN
  -- Reuse the real Train execution opened before apply; never mint an execution
  -- or borrow the historical bootstrap actor of the Edge deployment operation.
  -- Match the stable migration name so Train retimestamping remains supported.
  SELECT count(*), min(e.execution_id)
    INTO v_actor_count, v_actor
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code ~ '^[0-9]{14}_lf_programming_code_operation_candidate_v1$'
    AND e.status='IN_PROGRESS'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest#>>'{router_authority_receipt,operation_code}'='ACTUALIZACION_DB_LF'
    AND e.manifest#>>'{router_authority_receipt,target_repo}'='cristhianlujan/claude-persona-lf-patch'
    AND e.manifest#>>'{router_authority_receipt,target_path}'=
        'supabase/migrations/'||e.target_code||'.sql';
  IF v_actor_count<>1 THEN
    RAISE EXCEPTION 'PG01_2FP_TRAIN_EXECUTION_REQUIRED';
  END IF;

  SELECT * INTO v_existing FROM public.lf_router_action_registry
  WHERE asset_type='REPOSITORY_ARTIFACT' AND action_code='CODE_DEVELOPMENT';
  IF FOUND THEN
    IF v_existing.operation_code IS DISTINCT FROM 'DESARROLLO_CODIGO_AGENTE_LF'
      OR v_existing.operation_resolution IS DISTINCT FROM 'STATIC'
      OR v_existing.status IS DISTINCT FROM 'CANDIDATO_READ_ONLY'
      OR v_existing.write_allowed IS DISTINCT FROM false
      OR v_existing.requires_existing_target IS DISTINCT FROM false
      OR v_existing.requires_missing_target IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'PG01_2FP_ROUTER_ROW_CONFLICT';
    END IF;
    RETURN; -- Exact candidate replay: preserve original row, author and times.
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_router_action_registry
             WHERE operation_code='DESARROLLO_CODIGO_AGENTE_LF') THEN
    RAISE EXCEPTION 'PG01_2FP_OPERATION_ROUTE_CONFLICT';
  END IF;

  INSERT INTO public.lf_router_action_registry(
    asset_type,action_code,operation_code,operation_resolution,
    requires_existing_target,requires_missing_target,write_allowed,status,notes,
    created_by_execution_id,updated_by_execution_id
  ) VALUES (
    'REPOSITORY_ARTIFACT','CODE_DEVELOPMENT','DESARROLLO_CODIGO_AGENTE_LF','STATIC',
    false,false,false,'CANDIDATO_READ_ONLY',
    '2F.P draft candidate only; D8 GO and complete operation contract pending. Target identity and admission remain separate PG-01 gates. No dispatch, execution, deployment or receipt persistence.',
    v_actor,v_actor
  );
END
$candidate$;
