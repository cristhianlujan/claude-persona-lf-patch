-- S30 R15: make the ACTUALIZACION_ESTRATEGIA_LF pre-write sequence physically non-skippable.
-- Scope: public.lf_strategy_update_write_v1 only. No Strategy snapshot data mutation in this migration.
-- Source-first owner execution: EXEC-S30-R15-STRATEGY-UPDATE-SEQUENCE-GUARD-20260914-001.

DO $pre$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_route jsonb;
  v_def text;
  v_sha text;
BEGIN
  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S30-R15-STRATEGY-UPDATE-SEQUENCE-GUARD-20260914-001';

  IF NOT FOUND
     OR v_exec.operation_code<>'ACTUALIZACION_DB_LF'
     OR v_exec.status<>'IN_PROGRESS'
     OR v_exec.target_type<>'FUNCTION'
     OR v_exec.target_code<>'LF_STRATEGY_UPDATE_WRITE_V1_REQUIRED_STEP_SEQUENCE_GUARD_V1'
     OR v_exec.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR v_exec.target_path IS DISTINCT FROM 'supabase/migrations/20260915013230_s30_strategy_update_required_step_sequence_guard_v1.sql' THEN
    RAISE EXCEPTION 'S30_R15_DB_EXECUTION_BINDING_INVALID';
  END IF;

  IF coalesce(v_exec.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(v_exec.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'S30_R15_DB_POLICY_SNAPSHOT_MISSING';
  END IF;

  v_route:=public.lf_router_resolve_v1(
    'Patch lf_strategy_update_write_v1 required prewrite sequence',
    'LF_STRATEGY_UPDATE_WRITE_V1_REQUIRED_STEP_SEQUENCE_GUARD_V1',
    'UPDATE','FUNCTION',NULL
  );
  IF coalesce(v_route->>'status','')<>'READY_TO_EXECUTE'
     OR coalesce(v_route->>'operation_code','')<>'ACTUALIZACION_DB_LF'
     OR coalesce(v_route->>'action_code','')<>'UPDATE'
     OR coalesce(v_route->>'asset_type','')<>'FUNCTION' THEN
    RAISE EXCEPTION 'S30_R15_DB_ROUTE_INVALID:%',v_route;
  END IF;

  SELECT pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure) INTO v_def;
  v_sha:=encode(extensions.digest(convert_to(v_def,'UTF8'),'sha256'),'hex');
  IF v_sha<>'7d7d5984d7b6e806641d19b92f677427b9f1e867af9cf4ff0e038cd7b524dcce' THEN
    RAISE EXCEPTION 'S30_R15_WRITER_SOURCE_DRIFT:%',v_sha;
  END IF;
END
$pre$;

DO $s30_r15$
DECLARE
  v_def text;
  v_new text;
  v_decl_old text := '  expected_claim_ceiling text;';
  v_decl_new text := E'  expected_claim_ceiling text;\n  write_execution_order integer;\n  prior_required_not_clean integer;';
  v_anchor text := '  new_metadata:=coalesce(s.metadata,''{}''::jsonb)||coalesce(p_patch->''metadata_merge'',''{}''::jsonb);';
  v_guard text := $guard$
  select coalesce(st.execution_order,st.step_order)
    into write_execution_order
  from public.lf_operation_steps st
  where st.operation_code='ACTUALIZACION_ESTRATEGIA_LF'
    and st.step_id='supabase_write'
    and st.active is true;
  if write_execution_order is null then
    raise exception 'LF_STRATEGY_UPDATE_SUPABASE_WRITE_STEP_NOT_ACTIVE';
  end if;

  select count(*)
    into prior_required_not_clean
  from public.lf_operation_steps st
  where st.operation_code='ACTUALIZACION_ESTRATEGIA_LF'
    and st.required is true
    and st.active is true
    and coalesce(st.execution_order,st.step_order)<write_execution_order
    and not exists (
      select 1
      from public.lf_operation_execution_steps es
      join public.lf_operation_step_judge_bindings b
        on b.operation_code=st.operation_code
       and b.step_id=st.step_id
       and b.step_order=st.step_order
       and b.status='ACTIVE_ENFORCEMENT'
      where es.execution_id=p_execution_id
        and es.step_order=st.step_order
        and es.step_id=st.step_id
        and es.status=b.clean_result_value
        and (
          (st.step_id='init_execution'
             and es.evidence_payload->>'recorded_by_rpc'='lf_strategy_update_begin_v1')
          or
          (st.step_id<>'init_execution'
             and es.evidence_payload->>'core_recorder'='lf_record_operation_step_core_v1')
        )
    );
  if prior_required_not_clean>0 then
    raise exception 'LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN:%',prior_required_not_clean;
  end if;
$guard$;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure)
    INTO v_def;

  IF position('LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN' in v_def)>0 THEN
    RAISE EXCEPTION 'S30_R15_GUARD_ALREADY_PRESENT';
  END IF;
  IF position(v_decl_old in v_def)=0 THEN
    RAISE EXCEPTION 'S30_R15_DECLARATION_ANCHOR_NOT_FOUND';
  END IF;
  IF position(v_anchor in v_def)=0 THEN
    RAISE EXCEPTION 'S30_R15_WRITE_ANCHOR_NOT_FOUND';
  END IF;

  v_new := replace(v_def,v_decl_old,v_decl_new);
  v_new := replace(v_new,v_anchor,v_guard||E'\n'||v_anchor);

  IF v_new=v_def THEN
    RAISE EXCEPTION 'S30_R15_NO_FUNCTION_DELTA';
  END IF;

  EXECUTE v_new;
END
$s30_r15$;

COMMENT ON FUNCTION public.lf_strategy_update_write_v1(text,bigint,text,jsonb) IS
'S30 R15: Strategy Update writer requires every active required pre-write step to be clean and canonically recorded before snapshot mutation.';

DO $post$
DECLARE
  v_def text;
  v_guard_pos integer;
  v_write_pos integer;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure) INTO v_def;
  v_guard_pos:=strpos(v_def,'LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN');
  v_write_pos:=strpos(v_def,'new_metadata:=coalesce(s.metadata');
  IF v_guard_pos=0 OR v_write_pos=0 OR v_guard_pos>=v_write_pos THEN
    RAISE EXCEPTION 'S30_R15_POST_GUARD_ORDER_INVALID:%:%',v_guard_pos,v_write_pos;
  END IF;
  IF strpos(v_def,"st.required is true")=0
     OR strpos(v_def,"st.active is true")=0
     OR strpos(v_def,"es.status=b.clean_result_value")=0
     OR strpos(v_def,"recorded_by_rpc'='lf_strategy_update_begin_v1")=0
     OR strpos(v_def,"core_recorder'='lf_record_operation_step_core_v1")=0 THEN
    RAISE EXCEPTION 'S30_R15_POST_CANONICAL_SEQUENCE_GUARD_INCOMPLETE';
  END IF;
END
$post$;

UPDATE public.lf_operation_execution
SET manifest=manifest || jsonb_build_object(
      'result','S30_R15_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_GUARD_APPLIED',
      'target_function','public.lf_strategy_update_write_v1(text,bigint,text,jsonb)',
      'required_prior_steps_enforced',true,
      'canonical_init_recorder','lf_strategy_update_begin_v1',
      'canonical_step_recorder','lf_record_operation_step_core_v1',
      'strategy_snapshot_mutation',false,
      'runtime_activation',false,
      'production_activation',false
    ),
    status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-R15-STRATEGY-UPDATE-SEQUENCE-GUARD-20260914-001',
    updated_at=clock_timestamp()
WHERE execution_id='EXEC-S30-R15-STRATEGY-UPDATE-SEQUENCE-GUARD-20260914-001';

DO $readback$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='EXEC-S30-R15-STRATEGY-UPDATE-SEQUENCE-GUARD-20260914-001'
      AND operation_code='ACTUALIZACION_DB_LF'
      AND status='COMPLETED'
      AND manifest->>'result'='S30_R15_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_GUARD_APPLIED'
      AND coalesce((manifest->>'runtime_activation')::boolean,false)=false
      AND coalesce((manifest->>'production_activation')::boolean,false)=false
  ) THEN
    RAISE EXCEPTION 'S30_R15_DB_EXECUTION_CLOSE_READBACK_FAILED';
  END IF;
  IF strpos(pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure),'LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN')=0 THEN
    RAISE EXCEPTION 'S30_R15_WRITER_GUARD_READBACK_FAILED';
  END IF;
END
$readback$;
