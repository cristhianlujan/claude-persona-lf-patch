begin;

do $m36_patch$
declare
  v_def text;
  v_old constant text := $old$when upper(coalesce(b.value->>'code','')) ~ '(MISSING|NOT_LINKED|SOURCE.*INCOMPLETE|SOURCE_IDENTIFICATION|CANONICAL.*MISSING|REQUIREMENT.*MISSING|REFERENCE_UNRESOLVED)'$old$;
  v_new constant text := $new$when upper(coalesce(b.value->>'code',''))='SCREEN_STATE_SET_EMPTY'
          then 'MISSING_SOURCE'
        when upper(coalesce(b.value->>'code','')) ~ '(MISSING|NOT_LINKED|SOURCE.*INCOMPLETE|SOURCE_IDENTIFICATION|CANONICAL.*MISSING|REQUIREMENT.*MISSING|REFERENCE_UNRESOLVED)'$new$;
  v_hits integer;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure
  ) into v_def;

  v_hits := (length(v_def) - length(replace(v_def,v_old,''))) / nullif(length(v_old),0);
  if v_hits <> 1 then
    raise exception 'IG_M36_SCREEN_STATE_EMPTY_PATCH_DRIFT: expected 1 exact mapper fragment, got %', v_hits;
  end if;

  execute replace(v_def,v_old,v_new);
end
$m36_patch$;

do $verify$
declare
  v jsonb;
  v_b jsonb;
begin
  v := programacion.fn_input_governance_bootstrap_classify_v2(1,'STATES',19);

  select value into v_b
  from jsonb_array_elements(coalesce(v->'blockers','[]'::jsonb))
  where value->>'code'='SCREEN_STATE_SET_EMPTY'
  limit 1;

  if v_b is null then
    raise exception 'IG_M36_SCREEN_STATE_EMPTY_REGRESSION_MISSING_BLOCKER:%',v;
  end if;
  if v_b->>'uncertainty_type' is distinct from 'MISSING_SOURCE' then
    raise exception 'IG_M36_SCREEN_STATE_EMPTY_REGRESSION_BAD_TYPE:%',v_b;
  end if;
  if nullif(v_b->>'state','') is null
     or nullif(v_b->>'blocking_stage','') is null
     or jsonb_typeof(v_b->'evidence') is distinct from 'object' then
    raise exception 'IG_M36_SCREEN_STATE_EMPTY_REGRESSION_UNTYPED:%',v_b;
  end if;
end
$verify$;

commit;
