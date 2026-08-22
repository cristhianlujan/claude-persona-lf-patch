create or replace function programacion.fn_input_v58_build_assertions(
  p_new_run_id bigint,
  p_parent_run_id bigint,
  p_family_code text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $function$
declare
  v_pantalla_id integer;
  v_old jsonb;
  v_tpl jsonb;
  v_rebound jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  select pantalla_id into v_pantalla_id
  from programacion.input_readiness_runs where id=p_new_run_id;
  if v_pantalla_id is null then raise exception 'V58_ASSERTION_NEW_RUN_NOT_FOUND:%',p_new_run_id; end if;

  for v_old in
    select x.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.validator_evidence->'assertions') x(value)
    where a.run_id=p_parent_run_id and a.family_code=p_family_code
  loop
    if v_pantalla_id=51 and p_family_code='VISUAL_EVIDENCE'
       and v_old->'source_ref'->>'kind'='CURRENT_VISUAL_ARTIFACT' then
      v_tpl:=jsonb_build_object(
        'source_ref',jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',51),
        'path',jsonb_build_array('observed'),'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-DESKTOP-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-TABLET-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-MOBILE-LIGHT','canonical_canvas',true)))
        )
      );
    else
      v_tpl:=programacion.fn_input_v58_assertion_template(v_pantalla_id,p_family_code,v_old);
    end if;
    v_rebound:=programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl);
    if v_rebound->>'result'<>'PASS' then
      raise exception 'V58_REBOUND_ASSERTION_FAILED screen=% family=% source=% path=%',v_pantalla_id,p_family_code,v_rebound->'source_ref',v_rebound->'path';
    end if;
    v_out:=v_out || jsonb_build_array(v_rebound);
  end loop;

  if jsonb_array_length(v_out)=0 then raise exception 'V58_ASSERTION_SET_EMPTY:%:%',v_pantalla_id,p_family_code; end if;
  return v_out;
end;
$function$;

revoke all on function programacion.fn_input_v58_build_assertions(bigint,bigint,text) from public;
grant execute on function programacion.fn_input_v58_build_assertions(bigint,bigint,text) to postgres;