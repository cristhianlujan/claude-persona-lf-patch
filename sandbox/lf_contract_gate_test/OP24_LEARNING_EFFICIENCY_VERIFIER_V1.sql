-- OP24 Learning Efficiency Verifier V1 — sandbox candidate source
-- Source-first candidate only. Not a Supabase migration. No production authorization.
-- Verifies the draft LEARNING_EFFICIENCY_METRICS_V1 semantics without writing data.

create or replace function private.sbx_fn_lf_learning_efficiency_metrics_v1(
  p_metrics jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'private'
as $function$
declare
  v_required text[] := array[
    'eligible_count',
    'retrieved_count',
    'relevant_retrieved',
    'applied_count',
    'retrieval_precision',
    'retrieval_recall',
    'application_rate',
    'repeat_error_rate',
    'context_bytes_or_tokens',
    'supabase_queries',
    'learning_lookup_latency'
  ];
  v_errors jsonb := '[]'::jsonb;
  v_eligible numeric;
  v_retrieved numeric;
  v_relevant numeric;
  v_applied numeric;
  v_precision numeric;
  v_application numeric;
  v_observed_precision numeric;
  v_observed_application numeric;
  v_key text;
  v_node jsonb;
begin
  if p_metrics is null or jsonb_typeof(p_metrics) <> 'object' then
    return jsonb_build_object('valid', false, 'errors', jsonb_build_array('METRICS_OBJECT_REQUIRED'));
  end if;

  if not (p_metrics ?& v_required) then
    v_errors := v_errors || jsonb_build_array('REQUIRED_METRICS_MISSING');
  end if;

  begin
    v_eligible := (p_metrics->>'eligible_count')::numeric;
    v_retrieved := (p_metrics->>'retrieved_count')::numeric;
    v_relevant := (p_metrics->>'relevant_retrieved')::numeric;
    v_applied := (p_metrics->>'applied_count')::numeric;
  exception when others then
    v_errors := v_errors || jsonb_build_array('COUNT_METRICS_MUST_BE_NUMERIC');
  end;

  if v_eligible is not null and v_eligible < 0
     or v_retrieved is not null and v_retrieved < 0
     or v_relevant is not null and v_relevant < 0
     or v_applied is not null and v_applied < 0 then
    v_errors := v_errors || jsonb_build_array('COUNT_METRICS_MUST_BE_NON_NEGATIVE');
  end if;

  if v_eligible is not null and v_retrieved is not null and v_retrieved > v_eligible then
    v_errors := v_errors || jsonb_build_array('RETRIEVED_EXCEEDS_ELIGIBLE');
  end if;
  if v_retrieved is not null and v_relevant is not null and v_relevant > v_retrieved then
    v_errors := v_errors || jsonb_build_array('RELEVANT_EXCEEDS_RETRIEVED');
  end if;
  if v_relevant is not null and v_applied is not null and v_applied > v_relevant then
    v_errors := v_errors || jsonb_build_array('APPLIED_EXCEEDS_RELEVANT');
  end if;

  v_precision := case when coalesce(v_retrieved, 0) > 0 then round(v_relevant / v_retrieved, 6) else null end;
  v_application := case when coalesce(v_relevant, 0) > 0 then round(v_applied / v_relevant, 6) else null end;

  if jsonb_typeof(p_metrics->'retrieval_precision') = 'number' then
    v_observed_precision := (p_metrics->>'retrieval_precision')::numeric;
    if v_precision is distinct from round(v_observed_precision, 6) then
      v_errors := v_errors || jsonb_build_array('RETRIEVAL_PRECISION_RECOMPUTE_MISMATCH');
    end if;
  elsif p_metrics->'retrieval_precision' <> 'null'::jsonb
        and p_metrics->>'retrieval_precision' <> 'NOT_OBSERVED' then
    v_errors := v_errors || jsonb_build_array('RETRIEVAL_PRECISION_INVALID_UNKNOWN_SEMANTIC');
  elsif v_precision is not null then
    v_errors := v_errors || jsonb_build_array('RETRIEVAL_PRECISION_CANNOT_BE_UNKNOWN_WHEN_RECOMPUTABLE');
  end if;

  if jsonb_typeof(p_metrics->'application_rate') = 'number' then
    v_observed_application := (p_metrics->>'application_rate')::numeric;
    if v_application is distinct from round(v_observed_application, 6) then
      v_errors := v_errors || jsonb_build_array('APPLICATION_RATE_RECOMPUTE_MISMATCH');
    end if;
  elsif p_metrics->'application_rate' <> 'null'::jsonb
        and p_metrics->>'application_rate' <> 'NOT_OBSERVED' then
    v_errors := v_errors || jsonb_build_array('APPLICATION_RATE_INVALID_UNKNOWN_SEMANTIC');
  elsif v_application is not null then
    v_errors := v_errors || jsonb_build_array('APPLICATION_RATE_CANNOT_BE_UNKNOWN_WHEN_RECOMPUTABLE');
  end if;

  foreach v_key in array array[
    'retrieval_recall',
    'repeat_error_rate',
    'context_bytes_or_tokens',
    'supabase_queries',
    'learning_lookup_latency'
  ] loop
    v_node := p_metrics->v_key;
    if v_node is null then
      continue;
    end if;
    if jsonb_typeof(v_node) = 'number' then
      if (v_node #>> '{}')::numeric < 0 then
        v_errors := v_errors || jsonb_build_array(v_key || '_MUST_BE_NON_NEGATIVE');
      end if;
    elsif v_node <> 'null'::jsonb and v_node #>> '{}' <> 'NOT_OBSERVED' then
      v_errors := v_errors || jsonb_build_array(v_key || '_INVALID_UNKNOWN_SEMANTIC');
    end if;
  end loop;

  return jsonb_build_object(
    'valid', jsonb_array_length(v_errors) = 0,
    'errors', v_errors,
    'recomputed', jsonb_build_object(
      'retrieval_precision', v_precision,
      'application_rate', v_application
    ),
    'unknown_semantics', 'NULL_OR_NOT_OBSERVED'
  );
end;
$function$;

revoke all on function private.sbx_fn_lf_learning_efficiency_metrics_v1(jsonb)
  from public, anon, authenticated, service_role;

comment on function private.sbx_fn_lf_learning_efficiency_metrics_v1(jsonb) is
  'OP24 sandbox-only independent verifier candidate for LEARNING_EFFICIENCY_METRICS_V1.';
