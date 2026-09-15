-- S30 R15: make the ACTUALIZACION_ESTRATEGIA_LF pre-write sequence physically non-skippable.
-- Scope: public.lf_strategy_update_write_v1 only. No Strategy snapshot data mutation in this migration.
-- Source-first owner execution: EXEC-S30-R15-STRATEGY-UPDATE-SEQUENCE-GUARD-20260914-001.

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
