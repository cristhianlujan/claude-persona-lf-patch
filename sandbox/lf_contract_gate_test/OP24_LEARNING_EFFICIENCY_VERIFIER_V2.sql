-- OP24 Learning Efficiency Verifier V2 — sandbox candidate only.
-- Prevents observational metrics from becoming trusted merely because they are numeric/non-negative.
-- No Strategy 23 execution. No production/runtime authorization.

create or replace function private.sbx_fn_lf_learning_efficiency_metrics_v2(
  p_metrics jsonb,
  p_observations jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'private'
as $function$
declare
  v_required text[] := array[
    'eligible_count','retrieved_count','relevant_retrieved','applied_count',
    'retrieval_precision','retrieval_recall','application_rate','repeat_error_rate',
    'context_bytes_or_tokens','supabase_queries','learning_lookup_latency'
  ];
  v_errors jsonb := '[]'::jsonb;
  v_eligible numeric; v_retrieved numeric; v_relevant numeric; v_applied numeric;
  v_precision numeric; v_application numeric; v_recall numeric; v_repeat_rate numeric;
  v_observed numeric; v_den numeric; v_num numeric;
  v_key text; v_node jsonb; v_obs jsonb;
  v_observed_bound integer := 0;
begin
  if p_metrics is null or jsonb_typeof(p_metrics)<>'object' then
    return jsonb_build_object('valid',false,'errors',jsonb_build_array('METRICS_OBJECT_REQUIRED'));
  end if;
  if p_observations is null or jsonb_typeof(p_observations)<>'object' then
    return jsonb_build_object('valid',false,'errors',jsonb_build_array('OBSERVATIONS_OBJECT_REQUIRED'));
  end if;
  if not (p_metrics ?& v_required) then
    v_errors:=v_errors||jsonb_build_array('REQUIRED_METRICS_MISSING');
  end if;

  begin
    v_eligible:=(p_metrics->>'eligible_count')::numeric;
    v_retrieved:=(p_metrics->>'retrieved_count')::numeric;
    v_relevant:=(p_metrics->>'relevant_retrieved')::numeric;
    v_applied:=(p_metrics->>'applied_count')::numeric;
  exception when others then
    v_errors:=v_errors||jsonb_build_array('COUNT_METRICS_MUST_BE_NUMERIC');
  end;

  if v_eligible<0 or v_retrieved<0 or v_relevant<0 or v_applied<0 then
    v_errors:=v_errors||jsonb_build_array('COUNT_METRICS_MUST_BE_NON_NEGATIVE');
  end if;
  if v_retrieved>v_eligible then v_errors:=v_errors||jsonb_build_array('RETRIEVED_EXCEEDS_ELIGIBLE'); end if;
  if v_relevant>v_retrieved then v_errors:=v_errors||jsonb_build_array('RELEVANT_EXCEEDS_RETRIEVED'); end if;
  if v_applied>v_relevant then v_errors:=v_errors||jsonb_build_array('APPLIED_EXCEEDS_RELEVANT'); end if;

  v_precision:=case when coalesce(v_retrieved,0)>0 then round(v_relevant/v_retrieved,6) else null end;
  v_application:=case when coalesce(v_relevant,0)>0 then round(v_applied/v_relevant,6) else null end;

  foreach v_key in array array['retrieval_precision','application_rate'] loop
    v_node:=p_metrics->v_key;
    if v_key='retrieval_precision' then v_observed:=v_precision; else v_observed:=v_application; end if;
    if jsonb_typeof(v_node)='number' then
      if v_observed is distinct from round((v_node#>>'{}')::numeric,6) then
        v_errors:=v_errors||jsonb_build_array(upper(v_key)||'_RECOMPUTE_MISMATCH');
      end if;
    elsif v_node='null'::jsonb or v_node#>>'{}'='NOT_OBSERVED' then
      if v_observed is not null then v_errors:=v_errors||jsonb_build_array(upper(v_key)||'_CANNOT_BE_UNKNOWN_WHEN_RECOMPUTABLE'); end if;
    else
      v_errors:=v_errors||jsonb_build_array(upper(v_key)||'_INVALID_UNKNOWN_SEMANTIC');
    end if;
  end loop;

  -- Recall is only independently recomputable when the gold relevant-total denominator is bound to evidence.
  v_node:=p_metrics->'retrieval_recall'; v_obs:=p_observations->'retrieval_recall';
  if jsonb_typeof(v_node)='number' then
    if jsonb_typeof(v_obs)<>'object' or coalesce(v_obs->>'evidence_ref','')='' then
      v_errors:=v_errors||jsonb_build_array('RETRIEVAL_RECALL_EVIDENCE_REQUIRED');
    else
      begin v_den:=(v_obs->>'relevant_total')::numeric; exception when others then v_den:=null; end;
      if coalesce(v_den,0)<=0 then
        v_errors:=v_errors||jsonb_build_array('RETRIEVAL_RECALL_DENOMINATOR_REQUIRED');
      else
        v_recall:=round(v_relevant/v_den,6);
        if v_recall is distinct from round((v_node#>>'{}')::numeric,6) then v_errors:=v_errors||jsonb_build_array('RETRIEVAL_RECALL_RECOMPUTE_MISMATCH'); end if;
        v_observed_bound:=v_observed_bound+1;
      end if;
    end if;
  elsif v_node<>'null'::jsonb and v_node#>>'{}'<>'NOT_OBSERVED' then
    v_errors:=v_errors||jsonb_build_array('RETRIEVAL_RECALL_INVALID_UNKNOWN_SEMANTIC');
  end if;

  -- Repeat-error rate requires explicit numerator, denominator, window and evidence.
  v_node:=p_metrics->'repeat_error_rate'; v_obs:=p_observations->'repeat_error_rate';
  if jsonb_typeof(v_node)='number' then
    if jsonb_typeof(v_obs)<>'object' or coalesce(v_obs->>'evidence_ref','')='' or coalesce(v_obs->>'window_ref','')='' then
      v_errors:=v_errors||jsonb_build_array('REPEAT_ERROR_RATE_EVIDENCE_WINDOW_REQUIRED');
    else
      begin v_num:=(v_obs->>'repeat_error_count')::numeric; v_den:=(v_obs->>'opportunity_count')::numeric; exception when others then v_num:=null; v_den:=null; end;
      if v_num is null or coalesce(v_den,0)<=0 or v_num<0 or v_num>v_den then
        v_errors:=v_errors||jsonb_build_array('REPEAT_ERROR_RATE_COUNTS_INVALID');
      else
        v_repeat_rate:=round(v_num/v_den,6);
        if v_repeat_rate is distinct from round((v_node#>>'{}')::numeric,6) then v_errors:=v_errors||jsonb_build_array('REPEAT_ERROR_RATE_RECOMPUTE_MISMATCH'); end if;
        v_observed_bound:=v_observed_bound+1;
      end if;
    end if;
  elsif v_node<>'null'::jsonb and v_node#>>'{}'<>'NOT_OBSERVED' then
    v_errors:=v_errors||jsonb_build_array('REPEAT_ERROR_RATE_INVALID_UNKNOWN_SEMANTIC');
  end if;

  -- Context volume must state whether the numeric value is BYTES or TOKENS and how it was measured.
  v_node:=p_metrics->'context_bytes_or_tokens'; v_obs:=p_observations->'context_bytes_or_tokens';
  if jsonb_typeof(v_node)='number' then
    if (v_node#>>'{}')::numeric<0 then v_errors:=v_errors||jsonb_build_array('CONTEXT_VOLUME_MUST_BE_NON_NEGATIVE'); end if;
    if jsonb_typeof(v_obs)<>'object' or coalesce(v_obs->>'evidence_ref','')='' or coalesce(v_obs->>'measurement_method','')='' or coalesce(v_obs->>'unit','') not in('BYTES','TOKENS') then
      v_errors:=v_errors||jsonb_build_array('CONTEXT_VOLUME_OBSERVATION_CONTRACT_REQUIRED');
    else v_observed_bound:=v_observed_bound+1; end if;
  elsif v_node<>'null'::jsonb and v_node#>>'{}'<>'NOT_OBSERVED' then v_errors:=v_errors||jsonb_build_array('CONTEXT_VOLUME_INVALID_UNKNOWN_SEMANTIC'); end if;

  -- Supabase query count must be an observed integer tied to a measurement scope.
  v_node:=p_metrics->'supabase_queries'; v_obs:=p_observations->'supabase_queries';
  if jsonb_typeof(v_node)='number' then
    v_observed:=(v_node#>>'{}')::numeric;
    if v_observed<0 or trunc(v_observed)<>v_observed then v_errors:=v_errors||jsonb_build_array('SUPABASE_QUERIES_MUST_BE_NON_NEGATIVE_INTEGER'); end if;
    if jsonb_typeof(v_obs)<>'object' or coalesce(v_obs->>'evidence_ref','')='' or coalesce(v_obs->>'measurement_scope','')='' then
      v_errors:=v_errors||jsonb_build_array('SUPABASE_QUERIES_OBSERVATION_CONTRACT_REQUIRED');
    else v_observed_bound:=v_observed_bound+1; end if;
  elsif v_node<>'null'::jsonb and v_node#>>'{}'<>'NOT_OBSERVED' then v_errors:=v_errors||jsonb_build_array('SUPABASE_QUERIES_INVALID_UNKNOWN_SEMANTIC'); end if;

  -- Lookup latency is normalized to milliseconds and tied to evidence/method.
  v_node:=p_metrics->'learning_lookup_latency'; v_obs:=p_observations->'learning_lookup_latency';
  if jsonb_typeof(v_node)='number' then
    if (v_node#>>'{}')::numeric<0 then v_errors:=v_errors||jsonb_build_array('LEARNING_LOOKUP_LATENCY_MUST_BE_NON_NEGATIVE'); end if;
    if jsonb_typeof(v_obs)<>'object' or coalesce(v_obs->>'evidence_ref','')='' or coalesce(v_obs->>'measurement_method','')='' or coalesce(v_obs->>'unit','')<>'MS' then
      v_errors:=v_errors||jsonb_build_array('LEARNING_LOOKUP_LATENCY_OBSERVATION_CONTRACT_REQUIRED');
    else v_observed_bound:=v_observed_bound+1; end if;
  elsif v_node<>'null'::jsonb and v_node#>>'{}'<>'NOT_OBSERVED' then v_errors:=v_errors||jsonb_build_array('LEARNING_LOOKUP_LATENCY_INVALID_UNKNOWN_SEMANTIC'); end if;

  return jsonb_build_object(
    'valid',jsonb_array_length(v_errors)=0,
    'errors',v_errors,
    'recomputed',jsonb_build_object('retrieval_precision',v_precision,'application_rate',v_application,'retrieval_recall',v_recall,'repeat_error_rate',v_repeat_rate),
    'observational_metrics_bound',v_observed_bound,
    'unknown_semantics','NULL_OR_NOT_OBSERVED',
    'production_authorized',false
  );
end
$function$;

revoke all on function private.sbx_fn_lf_learning_efficiency_metrics_v2(jsonb,jsonb)
  from public, anon, authenticated, service_role;
