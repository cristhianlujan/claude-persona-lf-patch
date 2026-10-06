create or replace function programacion.fn_engineering_packet_apply_exact_write_v1(p_packet jsonb,p_action_spec jsonb)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog'
as $fn$
declare
  v_plan jsonb;
  v_op jsonb;
  v_overlay jsonb;
  v_i integer;
begin
  if p_packet is null or coalesce(p_packet->>'execution_capability','') <> 'WRITE_DB' then
    return p_packet;
  end if;

  v_overlay := jsonb_strip_nulls(jsonb_build_object(
    'entrypoint', nullif(btrim(coalesce(p_action_spec->>'canonical_entrypoint','')),''),
    'call_template', nullif(btrim(coalesce(p_action_spec->>'call_template','')),''),
    'exact_sql', nullif(coalesce(p_action_spec->>'exact_sql',''),''),
    'mutation_sql', nullif(coalesce(p_action_spec->>'mutation_sql',''),''),
    'canonical_mutation_mode', nullif(btrim(coalesce(p_action_spec->>'canonical_mutation_mode','')),'')
  ));

  if v_overlay = '{}'::jsonb then
    return p_packet;
  end if;

  v_plan := coalesce(p_packet->'connector_plan','[]'::jsonb);
  if jsonb_typeof(v_plan) <> 'array' or jsonb_array_length(v_plan)=0 then
    return p_packet;
  end if;

  for v_i in 0..jsonb_array_length(v_plan)-1 loop
    if v_plan->v_i->>'operation'='WRITE_DB' then
      v_op := (v_plan->v_i) || v_overlay;
      v_plan := jsonb_set(v_plan, array[v_i::text], v_op, true);
      return jsonb_set(p_packet,'{connector_plan}',v_plan,true);
    end if;
  end loop;

  return p_packet;
end
$fn$;