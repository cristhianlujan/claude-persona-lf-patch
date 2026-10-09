do $patch$
declare
  v_oid oid;
  v_src text;
  v_old text;
  v_new text;
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_engineering_execution_packet_from_spec_v1'
    and pg_get_function_identity_arguments(p.oid)='p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_execution_input jsonb';

  if v_oid is null then
    raise exception 'ENGINEERING_PACKET_FUNCTION_NOT_FOUND';
  end if;

  v_src := pg_get_functiondef(v_oid);

  if position('fn_engineering_packet_apply_exact_write_v1' in v_src)>0 then
    return;
  end if;

  v_old := E'  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1_legacy(\n    p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec,p_execution_input\n  );';
  v_new := v_old || E'\n  v_packet:=programacion.fn_engineering_packet_apply_exact_write_v1(v_packet,p_action_spec);';

  v_src := replace(v_src,v_old,v_new);

  if position('fn_engineering_packet_apply_exact_write_v1' in v_src)=0 then
    raise exception 'ENGINEERING_PACKET_PATCH_ANCHOR_NOT_FOUND';
  end if;

  execute v_src;
end
$patch$;