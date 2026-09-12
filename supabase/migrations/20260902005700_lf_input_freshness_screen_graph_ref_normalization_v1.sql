do $migration$
declare
  v_def text;
  v_sha text;
  v_old text := $$where x.value->'ref'=sr.value$$;
  v_new text := $$where x.value->'ref'=sr.value
         or (
           x.value->'ref'->>'kind'='SCREEN_CANONICAL_GRAPH'
           and sr.value->>'kind'='SCREEN_CANONICAL_GRAPH'
           and coalesce(sr.value->>'pantalla_id',v_run.pantalla_id::text)=v_run.pantalla_id::text
         )$$;
  v_occurrences integer;
begin
  select pg_get_functiondef('programacion.fn_input_freshness_delta(bigint)'::regprocedure),
         encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_freshness_delta(bigint)'::regprocedure),'UTF8'),'sha256'),'hex')
    into v_def,v_sha;

  if v_sha <> 'b15540f8ff12867ad3f130d84ac4078097705cd92b89d19a00e8ac6e1cda4032' then
    raise exception 'INPUT_FRESHNESS_DELTA_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  v_occurrences := (length(v_def)-length(replace(v_def,v_old,''))) / nullif(length(v_old),0);
  if v_occurrences <> 1 then
    raise exception 'INPUT_FRESHNESS_DELTA_SCREEN_GRAPH_MATCHER_COUNT:%',v_occurrences;
  end if;

  execute replace(v_def,v_old,v_new);
end;
$migration$;
