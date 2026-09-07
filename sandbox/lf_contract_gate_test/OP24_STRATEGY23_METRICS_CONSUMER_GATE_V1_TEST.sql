\set ON_ERROR_STOP on

begin;
\ir OP24_LEARNING_EFFICIENCY_VERIFIER_V2.sql
\ir OP24_STRATEGY23_METRICS_CONSUMER_GATE_V1.sql

do $test$
declare
  m jsonb := jsonb_build_object(
    'eligible_count',10,'retrieved_count',8,'relevant_retrieved',6,'applied_count',4,
    'retrieval_precision',0.75,'retrieval_recall',0.6,'application_rate',0.666667,
    'repeat_error_rate',0.1,'context_bytes_or_tokens',900,'supabase_queries',3,'learning_lookup_latency',12.5
  );
  o jsonb := jsonb_build_object(
    'retrieval_recall',jsonb_build_object('relevant_total',10,'evidence_ref','oracle://gold'),
    'repeat_error_rate',jsonb_build_object('repeat_error_count',1,'opportunity_count',10,'window_ref','window://frozen','evidence_ref','errors://fixture'),
    'context_bytes_or_tokens',jsonb_build_object('unit','TOKENS','measurement_method','frozen-tokenizer','evidence_ref','context://receipt'),
    'supabase_queries',jsonb_build_object('measurement_scope','strategy23-run','evidence_ref','sql://counter'),
    'learning_lookup_latency',jsonb_build_object('unit','MS','measurement_method','monotonic-clock','evidence_ref','timer://retrieval')
  );
  r jsonb;
  bad jsonb;
begin
  r := private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(m,o,'v0.3','v0.3','S26-FAMILY-E2E-FP-TEST','FIXTURE-FP-TEST');
  if coalesce((r->>'consumer_gate_pass')::boolean,false) is not true then
    raise exception 'EXPECTED_CONSUMER_GATE_PASS:%',r;
  end if;
  if coalesce((r->>'strategy23_execution_authorized')::boolean,true) is not false
     or coalesce((r->>'experiment_result_persistence_authorized')::boolean,true) is not false then
    raise exception 'SANDBOX_GATE_MUST_NOT_AUTHORIZE_EXECUTION_OR_PERSISTENCE:%',r;
  end if;

  bad := private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(m,o,'v0.2','v0.3','S26-FAMILY-E2E-FP-TEST','FIXTURE-FP-TEST');
  if coalesce((bad->>'consumer_gate_pass')::boolean,true) is not false or not (bad->'errors' ? 'PARENT_STRATEGY_VERSION_NOT_V03') then
    raise exception 'EXPECTED_PARENT_VERSION_BLOCK:%',bad;
  end if;

  bad := private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(m,o,'v0.3','v0.3','','FIXTURE-FP-TEST');
  if coalesce((bad->>'consumer_gate_pass')::boolean,true) is not false or not (bad->'errors' ? 'STRATEGY26_FAMILY_E2E_FINGERPRINT_REQUIRED') then
    raise exception 'EXPECTED_S26_FINGERPRINT_BLOCK:%',bad;
  end if;

  bad := private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(m,o,'v0.3','v0.3','S26-FAMILY-E2E-FP-TEST','');
  if coalesce((bad->>'consumer_gate_pass')::boolean,true) is not false or not (bad->'errors' ? 'FROZEN_FIXTURE_FINGERPRINT_REQUIRED') then
    raise exception 'EXPECTED_FIXTURE_FINGERPRINT_BLOCK:%',bad;
  end if;

  m := jsonb_set(m,'{retrieval_precision}','0.5'::jsonb);
  bad := private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(m,o,'v0.3','v0.3','S26-FAMILY-E2E-FP-TEST','FIXTURE-FP-TEST');
  if coalesce((bad->>'consumer_gate_pass')::boolean,true) is not false or not (bad->'errors' ? 'LEARNING_EFFICIENCY_METRICS_INVALID') then
    raise exception 'EXPECTED_METRICS_VERIFIER_BLOCK:%',bad;
  end if;
end
$test$;

rollback;

do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_learning_efficiency_metrics_v2(jsonb,jsonb)') is not null then
    raise exception 'VERIFIER_V2_RESIDUE';
  end if;
  if to_regprocedure('private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(jsonb,jsonb,text,text,text,text)') is not null then
    raise exception 'CONSUMER_GATE_RESIDUE';
  end if;
end
$post$;
