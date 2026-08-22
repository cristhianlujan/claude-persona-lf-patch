create or replace function programacion.fn_input_rebind_assertion(p_run_id bigint, p_family_code text, p_assertion jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_pantalla_id integer; v_version_id bigint; v_source_ref jsonb; v_receipt jsonb; v_graph jsonb;
  v_path text[]; v_actual jsonb; v_candidate jsonb; v_eval jsonb;
begin
  select r.pantalla_id,r.version_id into v_pantalla_id,v_version_id from programacion.input_readiness_runs r where r.id=p_run_id;
  if v_pantalla_id is null then raise exception 'ASSERTION_REBIND_RUN_NOT_FOUND:%',p_run_id; end if;
  v_source_ref:=p_assertion->'source_ref';
  if v_source_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
    v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
    v_receipt:=jsonb_build_object('ref',v_source_ref,'observed',v_graph,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph));
  else
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
  end if;
  select array_agg(x.value order by x.ord) into v_path from jsonb_array_elements_text(p_assertion->'path') with ordinality x(value,ord);
  v_actual:=v_receipt #> v_path;
  if v_actual is null then raise exception 'ASSERTION_REBIND_PATH_NOT_RESOLVABLE:%:%',p_family_code,p_assertion->'path'; end if;
  v_candidate:=(p_assertion - 'actual' - 'result' - 'source_observed_sha256') || jsonb_build_object('actual',v_actual);
  v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_candidate);
  return v_candidate || jsonb_build_object(
    'result',case when coalesce((v_eval->>'passed')::boolean,false) then 'PASS' else 'FAIL' end,
    'source_observed_sha256',v_eval->>'source_observed_sha256'
  );
end;
$$;
