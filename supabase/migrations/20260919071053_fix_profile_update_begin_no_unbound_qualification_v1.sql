-- FIX_PROFILE_UPDATE_BEGIN_NO_UNBOUND_QUALIFICATION_V1
-- ACTUALIZACION_PERFIL_LF has no active required OPERATION qualification suite
-- and its active contract does not require a qualification gate before update.
-- The transactional begin must not invent that dependency by copying the
-- CREACION_PERFIL_LF begin pattern.

do $patch$
declare
  v_def text;
  v_old text := $old$
  perform public.lf_operation_execution_qualification_guard_v1(
    'ACTUALIZACION_PERFIL_LF',x.started_at
  );
$old$;
begin
  select pg_get_functiondef(
    'public.lf_profile_update_begin_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure
  ) into v_def;

  if position(v_old in v_def)=0 then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_QUALIFICATION_PATCH_SOURCE_DRIFT';
  end if;

  v_def:=replace(
    v_def,
    v_old,
    E'\n  -- No qualification call here: this operation has no required qualification binding.\n'
  );
  execute v_def;
end;
$patch$;

do $verify$
declare
  v_def text;
  v_required integer;
begin
  select count(*) into v_required
  from public.lf_test_requirement_bindings b
  where b.subject_type='OPERATION'
    and (b.subject_code='*' or b.subject_code='ACTUALIZACION_PERFIL_LF')
    and b.status='ACTIVE'
    and b.required
    and b.effective_from<=clock_timestamp()
    and public.lf_test_requirement_applies_v1(
      b.binding_code,'OPERATION','ACTUALIZACION_PERFIL_LF'
    );

  if v_required<>0 then
    raise exception 'LF_PROFILE_UPDATE_QUALIFICATION_BINDING_NOW_EXISTS:%',v_required;
  end if;

  if exists(
    select 1
    from public.lf_operation_contracts
    where operation_code='ACTUALIZACION_PERFIL_LF'
      and status='ACTIVE_ENFORCEMENT'
      and (
        required_before_write @> '["operation_qualification"]'::jsonb
        or required_before_write @> '["qualification_current"]'::jsonb
      )
  ) then
    raise exception 'LF_PROFILE_UPDATE_CONTRACT_NOW_REQUIRES_QUALIFICATION';
  end if;

  select pg_get_functiondef(
    'public.lf_profile_update_begin_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure
  ) into v_def;

  if position('lf_operation_execution_qualification_guard_v1' in v_def)>0 then
    raise exception 'LF_PROFILE_UPDATE_UNBOUND_QUALIFICATION_GUARD_STILL_PRESENT';
  end if;
end;
$verify$;
