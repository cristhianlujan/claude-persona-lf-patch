\set ON_ERROR_STOP on

begin;
\ir OP24_LEARNING_EFFICIENCY_VERIFIER_V1.sql

do $test$
declare
  v_result jsonb;
begin
  -- Positive: independently recomputable precision/application rate.
  v_result := private.sbx_fn_lf_learning_efficiency_metrics_v1(
    '{"eligible_count":10,"retrieved_count":8,"relevant_retrieved":6,"applied_count":4,"retrieval_precision":0.75,"retrieval_recall":"NOT_OBSERVED","application_rate":0.666667,"repeat_error_rate":"NOT_OBSERVED","context_bytes_or_tokens":1200,"supabase_queries":3,"learning_lookup_latency":42}'::jsonb
  );
  if (v_result->>'valid')::boolean is distinct from true then
    raise exception 'EXPECTED_POSITIVE_METRICS_PASS: %',v_result;
  end if;

  -- Negative: tautological/wrong provided precision must be caught by independent recompute.
  v_result := private.sbx_fn_lf_learning_efficiency_metrics_v1(
    '{"eligible_count":10,"retrieved_count":8,"relevant_retrieved":6,"applied_count":4,"retrieval_precision":0.5,"retrieval_recall":"NOT_OBSERVED","application_rate":0.666667,"repeat_error_rate":"NOT_OBSERVED","context_bytes_or_tokens":1200,"supabase_queries":3,"learning_lookup_latency":42}'::jsonb
  );
  if (v_result->>'valid')::boolean is distinct from false
     or not (v_result->'errors' @> '["RETRIEVAL_PRECISION_RECOMPUTE_MISMATCH"]'::jsonb) then
    raise exception 'EXPECTED_RECOMPUTE_MISMATCH: %',v_result;
  end if;

  -- Zero denominator: derived metrics must be NULL, not zero or fabricated PASS.
  v_result := private.sbx_fn_lf_learning_efficiency_metrics_v1(
    '{"eligible_count":0,"retrieved_count":0,"relevant_retrieved":0,"applied_count":0,"retrieval_precision":null,"retrieval_recall":"NOT_OBSERVED","application_rate":null,"repeat_error_rate":"NOT_OBSERVED","context_bytes_or_tokens":0,"supabase_queries":0,"learning_lookup_latency":"NOT_OBSERVED"}'::jsonb
  );
  if (v_result->>'valid')::boolean is distinct from true
     or v_result#>'{recomputed,retrieval_precision}' <> 'null'::jsonb
     or v_result#>'{recomputed,application_rate}' <> 'null'::jsonb then
    raise exception 'EXPECTED_ZERO_DENOMINATOR_NULL: %',v_result;
  end if;

  -- Negative: unknown semantic may only be NULL or NOT_OBSERVED.
  v_result := private.sbx_fn_lf_learning_efficiency_metrics_v1(
    '{"eligible_count":0,"retrieved_count":0,"relevant_retrieved":0,"applied_count":0,"retrieval_precision":null,"retrieval_recall":"UNKNOWN","application_rate":null,"repeat_error_rate":"NOT_OBSERVED","context_bytes_or_tokens":0,"supabase_queries":0,"learning_lookup_latency":0}'::jsonb
  );
  if (v_result->>'valid')::boolean is distinct from false
     or not (v_result->'errors' @> '["retrieval_recall_INVALID_UNKNOWN_SEMANTIC"]'::jsonb) then
    raise exception 'EXPECTED_UNKNOWN_SEMANTIC_REJECTION: %',v_result;
  end if;

  -- Negative: all 11 canonical keys are mandatory.
  v_result := private.sbx_fn_lf_learning_efficiency_metrics_v1(
    '{"eligible_count":1,"retrieved_count":1,"relevant_retrieved":1,"applied_count":1}'::jsonb
  );
  if (v_result->>'valid')::boolean is distinct from false
     or not (v_result->'errors' @> '["REQUIRED_METRICS_MISSING"]'::jsonb) then
    raise exception 'EXPECTED_REQUIRED_METRICS_REJECTION: %',v_result;
  end if;
end
$test$;

rollback;

-- Postcondition: rollback-only test leaves no verifier behind.
do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_learning_efficiency_metrics_v1(jsonb)') is not null then
    raise exception 'METRICS_TEST_LEFT_FUNCTION_RESIDUE';
  end if;
end
$post$;
