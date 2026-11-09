-- LF Lote 1 / IG predecision crosscheck: PRE-APPLY READ-ONLY CANARY
-- No DDL/DML. Re-read against the target DB immediately before Train apply.
SELECT 'executor_md5' control,
       md5(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure))='21f59a492708a3dee9037d9a40cba1a3' pass
UNION ALL
SELECT 'canonical_md5',
       md5(pg_get_functiondef('private.fn_lf_ig_human_decision_live_disposition_v1(bigint)'::regprocedure))='d79b4ff3dfe1c2da5c2fdf8929d1ea9c'
UNION ALL
SELECT 'helper_absent', to_regprocedure('programacion.fn_input_governance_predecision_crosscheck_v1(bigint)') IS NULL;
WITH d AS (SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure) s),
a(i,x) AS (VALUES
 (1,$re$v_internal_summary[[:space:]]+jsonb;[[:space:]]+v_eval[[:space:]]+jsonb;$re$),
 (2,$re$select[[:space:]]+count\(\*\)[[:space:]]+into[[:space:]]+v_human[[:space:]]+from[[:space:]]+programacion\.input_gap_proposals[[:space:]]+where[[:space:]]+run_id=v_run[[:space:]]+and[[:space:]]+status='HUMAN_DECISION_REQUIRED'[[:space:]]+and[[:space:]]+validator_outcome='PASS';[[:space:]]+v_internal:=coalesce\(\(v_internal_summary->>'internal_remediation_count'\)::integer,0\);$re$),
 (3,$re$elsif[[:space:]]+v_internal>0[[:space:]]+then$re$),
 (4,$re$'human_decision_required_count',v_human,'internal_remediation_required_count',v_internal,$re$),
 (5,$re$if[[:space:]]+coalesce\(\(v_stage->>'canonical_story_gate_pass'\)::boolean,false\)[[:space:]]+then$re$))
SELECT 'anchor_'||i control,(SELECT count(*) FROM regexp_matches(d.s,a.x,'g'))=1 pass FROM d,a ORDER BY i;
