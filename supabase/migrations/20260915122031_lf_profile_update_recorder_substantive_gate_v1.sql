-- LF_PROFILE_UPDATE_RECORDER_SUBSTANTIVE_GATE_V1
-- Patch the existing canonical recorder in place; do not create a parallel UPDATE recorder.
-- Replay fails closed if the expected canonical seam is absent or ambiguous.

do $migration$
declare
  v_def text;
  v_anchor text := E'  if v_block_code is not null then';
  v_injection text := E'  if v_block_code is null and v_execution.operation_code=\'ACTUALIZACION_PERFIL_LF\' then\n    v_block_code:=public.lf_profile_update_substantive_block_v1(p_execution_id,p_step_id,p_evidence_payload,v_execution.manifest);\n    if v_block_code is not null then v_block_details:=jsonb_build_object(\'reason\',\'Substantive Profile update/graduation evidence did not satisfy fail-closed contract\',\'graduation_contract\',v_execution.manifest->>\'graduation_contract\'); end if;\n  end if;\n';
begin
  select pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure) into v_def;
  if v_def is null then raise exception 'PROFILE_UPDATE_CANONICAL_RECORDER_MISSING'; end if;
  if position('lf_profile_update_substantive_block_v1' in v_def) > 0 then return; end if;
  if (length(v_def)-length(replace(v_def,v_anchor,'')))/length(v_anchor) <> 1 then
    raise exception 'PROFILE_UPDATE_CANONICAL_RECORDER_SUBSTANTIVE_SEAM_AMBIGUOUS';
  end if;
  v_def := replace(v_def,v_anchor,v_injection||v_anchor);
  execute v_def;
end;
$migration$;

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure) into v_def;
  if position('lf_profile_update_substantive_block_v1(p_execution_id,p_step_id,p_evidence_payload,v_execution.manifest)' in v_def)=0 then
    raise exception 'PROFILE_UPDATE_SUBSTANTIVE_GATE_NOT_BOUND';
  end if;
end;
$verify$;
