-- PE10 E2 — Generic read-only reverse-consumer census.
-- Extraction algorithm adapted from the established M0.3 live call graph source:
-- sandbox/lf_contract_gate_test/input_governance_incremental/m03_live_call_graph_v1.sql
-- Input: replace __SOURCE_EVENT_ID__ only with the frozen P0 event_id supplied by the experiment.
-- Not a new persistent graph engine. No hardcoded finding names/answers.
-- All pg_proc results are CURRENT static call candidates, never historical/current runtime proof.
-- This regex may see mentions inside PL/pgSQL comments or string literals; candidates
-- require lexical context/independent readback before any confirmed dependency claim.

WITH
p0 AS (
  SELECT x->>'caller' caller, j.callee historical_callee
  FROM public.lf_eventos e
  CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x
  CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') j(callee)
  WHERE e.id=__SOURCE_EVENT_ID__
),
seed_names AS (
  SELECT lower(historical_callee) AS proname FROM p0
  UNION
  SELECT lower(split_part(caller,'.',2)) FROM p0
),
all_functions AS (
  SELECT p.oid, n.nspname AS schema_name, p.proname,
         pg_get_function_identity_arguments(p.oid) AS identity_args,
         p.prosrc AS body
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema')
    AND n.nspname !~ '^pg_'
    AND p.prokind IN ('f','p')
),
call_tokens AS (
  SELECT DISTINCT f.oid caller_oid, f.schema_name caller_schema,
         f.proname caller_name, f.identity_args caller_args,
         nullif(m.parts[3],'') called_schema, lower(m.parts[4]) called_name
  FROM all_functions f
  CROSS JOIN LATERAL regexp_matches(
    f.body,
    '(^|[^A-Za-z0-9_])(([A-Za-z_][A-Za-z0-9_]*)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
    'g'
  ) m(parts)
  WHERE lower(m.parts[4]) IN (SELECT proname FROM seed_names)
),
resolved AS (
 SELECT t.*, count(c.oid) AS candidate_count,
        COALESCE(jsonb_agg(
            jsonb_build_object('oid',c.oid::text,'schema',c.schema_name,
              'name',c.proname,'signature_args',c.identity_args)
            ORDER BY c.schema_name,c.proname,c.identity_args
          ) FILTER(WHERE c.oid IS NOT NULL),'[]'::jsonb) AS callee_candidates
 FROM call_tokens t
 LEFT JOIN all_functions c ON lower(c.proname)=t.called_name
      AND (t.called_schema IS NULL OR c.schema_name=t.called_schema)
 GROUP BY t.caller_oid,t.caller_schema,t.caller_name,t.caller_args,
          t.called_schema,t.called_name
)
SELECT caller_schema||'.'||caller_name||'('||caller_args||')' AS consumer_identity,
       called_schema,called_name,candidate_count,callee_candidates,
       CASE WHEN EXISTS (
         SELECT 1 FROM p0 h WHERE lower(h.caller)=lower(r.caller_schema||'.'||r.caller_name)
             AND lower(h.historical_callee)=r.called_name
       ) THEN 'HISTORICAL_EDGE_DECLARED'
       WHEN EXISTS (
         SELECT 1 FROM p0 h WHERE lower(h.caller)=lower(r.caller_schema||'.'||r.caller_name)
       ) THEN 'CURRENT_EDGE_NOT_IN_P0'
       ELSE 'CURRENT_CONSUMER_OUTSIDE_P0'
       END AS historical_comparison,
       CASE WHEN candidate_count=1 THEN 'STATIC_CALL_CANDIDATE_RESOLVED'
            WHEN candidate_count=0 THEN 'STATIC_CALL_TARGET_UNRESOLVED'
            ELSE 'AMBIGUOUS_STATIC_CALLEE_IDENTITY'
       END AS resolution_status,
       'CURRENT_BODY_NOT_HISTORICAL_EXECUTION' AS observation_scope
FROM resolved r
ORDER BY called_name,consumer_identity;
