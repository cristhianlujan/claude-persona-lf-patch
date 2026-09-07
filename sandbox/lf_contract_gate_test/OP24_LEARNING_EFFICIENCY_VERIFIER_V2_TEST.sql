\set ON_ERROR_STOP on

begin;
\ir OP24_LEARNING_EFFICIENCY_VERIFIER_V2.sql

do $test$
declare
  m jsonb;
  o jsonb;
  r jsonb;
begin
  m:=jsonb_build_object(
    'eligible_count',10,'retrieved_count',8,'relevant_retrieved',6,'applied_count',3,
    'retrieval_precision',0.75,'retrieval_recall',0.6,'application_rate',0.5,'repeat_error_rate',0.05,
    'context_bytes_or_tokens',1200,'supabase_queries',4,'learning_lookup_latency',12.5
  );
  o:=jsonb_build_object(
    'retrieval_recall',jsonb_build_object('relevant_total',10,'evidence_ref','gold://recall-1'),
    'repeat_error_rate',jsonb_build_object('repeat_error_count',1,'opportunity_count',20,'window_ref','window://1','evidence_ref','errors://1'),
    'context_bytes_or_tokens',jsonb_build_object('unit','TOKENS','measurement_method','tokenizer-v1','evidence_ref','context://1'),
    'supabase_queries',jsonb_build_object('measurement_scope','request://1','evidence_ref','queries://1'),
    'learning_lookup_latency',jsonb_build_object('unit','MS','measurement_method','monotonic-clock','evidence_ref','latency://1')
  );
  r:=private.sbx_fn_lf_learning_efficiency_metrics_v2(m,o);
  if coalesce((r->>'valid')::boolean,false) is not true or (r->>'observational_metrics_bound')::int<>5 then
    raise exception 'FULL_OBSERVATION_POSITIVE_MUST_PASS:%',r;
  end if;

  r:=private.sbx_fn_lf_learning_efficiency_metrics_v2(m,'{}'::jsonb);
  if coalesce((r->>'valid')::boolean,true) is not false
     or not (r->'errors' ? 'RETRIEVAL_RECALL_EVIDENCE_REQUIRED')
     or not (r->'errors' ? 'REPEAT_ERROR_RATE_EVIDENCE_WINDOW_REQUIRED')
     or not (r->'errors' ? 'CONTEXT_VOLUME_OBSERVATION_CONTRACT_REQUIRED')
     or not (r->'errors' ? 'SUPABASE_QUERIES_OBSERVATION_CONTRACT_REQUIRED')
     or not (r->'errors' ? 'LEARNING_LOOKUP_LATENCY_OBSERVATION_CONTRACT_REQUIRED') then
    raise exception 'UNBOUND_OBSERVATIONAL_NUMBERS_MUST_FAIL:%',r;
  end if;

  r:=private.sbx_fn_lf_learning_efficiency_metrics_v2(jsonb_set(m,'{retrieval_recall}','0.5'::jsonb),o);
  if not (r->'errors' ? 'RETRIEVAL_RECALL_RECOMPUTE_MISMATCH') then raise exception 'WRONG_RECALL_MUST_FAIL:%',r; end if;

  r:=private.sbx_fn_lf_learning_efficiency_metrics_v2(m,jsonb_set(o,'{context_bytes_or_tokens,unit}','"MIXED"'::jsonb));
  if not (r->'errors' ? 'CONTEXT_VOLUME_OBSERVATION_CONTRACT_REQUIRED') then raise exception 'AMBIGUOUS_CONTEXT_UNIT_MUST_FAIL:%',r; end if;

  r:=private.sbx_fn_lf_learning_efficiency_metrics_v2(jsonb_set(m,'{supabase_queries}','4.5'::jsonb),o);
  if not (r->'errors' ? 'SUPABASE_QUERIES_MUST_BE_NON_NEGATIVE_INTEGER') then raise exception 'FRACTIONAL_QUERY_COUNT_MUST_FAIL:%',r; end if;

  m:=jsonb_build_object(
    'eligible_count',0,'retrieved_count',0,'relevant_retrieved',0,'applied_count',0,
    'retrieval_precision',null,'retrieval_recall','NOT_OBSERVED','application_rate',null,'repeat_error_rate','NOT_OBSERVED',
    'context_bytes_or_tokens','NOT_OBSERVED','supabase_queries','NOT_OBSERVED','learning_lookup_latency','NOT_OBSERVED'
  );
  r:=private.sbx_fn_lf_learning_efficiency_metrics_v2(m,'{}'::jsonb);
  if coalesce((r->>'valid')::boolean,false) is not true then raise exception 'ZERO_DENOMINATOR_NOT_OBSERVED_MUST_PASS:%',r; end if;
end
$test$;

rollback;

do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_learning_efficiency_metrics_v2(jsonb,jsonb)') is not null then
    raise exception 'LEARNING_EFFICIENCY_V2_FUNCTION_RESIDUE';
  end if;
end
$post$;
