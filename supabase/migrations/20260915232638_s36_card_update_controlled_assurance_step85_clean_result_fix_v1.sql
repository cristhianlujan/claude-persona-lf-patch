begin;

do $fix$
declare
  d text;
  patched text;
begin
  d:=pg_get_functiondef('public.lf_run_card_update_controlled_assurance_e2e_v1(text,text)'::regprocedure);
  patched:=replace(
    d,
    $old$and step_id='expertise_quality_gate' and step_order=85 and status='STEP_PASS_WITH_EVIDENCE'$old$,
    $new$and step_id='expertise_quality_gate' and step_order=85 and status=(select clean_result_value from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_CARD_LF' and step_id='expertise_quality_gate' and step_order=85 and status='CANDIDATO_READ_ONLY')$new$
  );
  if patched=d then
    raise exception 'S36_CARD_ASSURANCE_STEP85_PATCH_ANCHOR_NOT_FOUND';
  end if;
  execute patched;
end $fix$;

do $assert$
declare d text;
begin
  d:=pg_get_functiondef('public.lf_run_card_update_controlled_assurance_e2e_v1(text,text)'::regprocedure);
  if position($p$clean_result_value from public.lf_operation_step_judge_bindings$p$ in d)=0
     or position($p$step_id='expertise_quality_gate'$p$ in d)=0 then
    raise exception 'S36_CARD_ASSURANCE_STEP85_PATCH_ASSERTION_FAILED';
  end if;
end $assert$;

commit;