-- IG M10.13 CP3 | Inventario bidireccional ligado a RUN gobernado real
-- Scope: ZERO_LEGACY_CALLERS. Solo SELECT; 0 changes a Router, IG, ACL, reglas, M10.4 o checkpoints.
-- EKB: IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001,
--      IG-M104-LEGACY-ACTIVE-FREEZE-SCOPE-001, GOV-ASSET-RETIREMENT-GOVERNANCE-V1-001.
-- Evidence: B2B-AUTH-001 via ACT-0001 -> PERFIL-PRODUCT-DIRECTOR-LF ->
--           input_validate -> programacion.fn_input_governance_execute -> IG RUN 951.
-- IMPORTANT: edges are conservative lexical matches for qualified/unqualified fn_/lf_ calls,
-- not a PostgreSQL runtime profiler. Dynamic invocation, Edge, external RPC, trigger and
-- other surfaces require separate evidence. NEVER infer zero actual invocations from
-- a zero graph path or NULL function stats. Current track_functions='none'.
WITH RECURSIVE
run_link AS (
 SELECT e.execution_id,e.status AS profile_status,
        s.status AS input_validate_status,
        s.evidence_payload->'input_governance' AS ig,
        s.evidence_payload#>>'{input_governance,governance_result,run_id}' AS ig_run
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps s ON s.execution_id=e.execution_id
 WHERE e.execution_id='EXEC-PROFILE-GATE2-6FBA871B254F838684B84663'
   AND e.operation_code='EJECUCION_PERFIL_LF'
   AND s.step_id='input_validate'
),
fn AS (
 SELECT n.nspname||'.'||p.proname AS name,
        p.oid::regprocedure::text AS signature,
        md5(p.prosrc) AS source_md5,
        p.prosrc
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','programacion','lf_ops')
),
tokens AS (
 SELECT f.name AS caller,m[1] AS token
 FROM fn f CROSS JOIN LATERAL regexp_matches(
   f.prosrc,
   '((?:(?:programacion|public|lf_ops)[.])?(?:fn_[a-z_0-9]+|lf_[a-z_0-9]+))[[:space:]]*[(]',
   'g') m
),
edges AS (
 SELECT DISTINCT t.caller,f.name AS callee
 FROM tokens t JOIN fn f
 ON CASE WHEN strpos(t.token,'.')>0 THEN f.name=t.token
         ELSE split_part(f.name,'.',2)=t.token END
),
reachable(node) AS (
 SELECT 'programacion.fn_input_governance_execute'::text COLLATE "C"
 UNION
 SELECT e.callee FROM edges e JOIN reachable r ON e.caller=r.node
),
risk AS (
 SELECT f.name, f.prosrc ~* '(^|[^a-z_])EXECUTE[[:space:]]' AS dynamic_sql
 FROM fn f JOIN reachable r ON f.name=r.node
),
subjects(subject,role) AS (
 VALUES
 ('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2'::text,'LEGACY_CLASSIFIER'),
 ('programacion.fn_input_run_semantic_revalidation_v1'::text,'LEGACY_CONSUMER')
)
SELECT
 now() AS sampled_at,s.role,f.signature,f.source_md5,
 (SELECT x->>'class' FROM public.lf_eventos ev
    CROSS JOIN LATERAL jsonb_array_elements(ev.payload->'matrix') x
   WHERE ev.id=20193 AND split_part(x->>'item_identity','(',1)=s.subject
   LIMIT 1) AS historical_class,
 (SELECT coalesce(jsonb_agg(DISTINCT e.caller),'[]'::jsonb)
  FROM edges e WHERE e.callee=s.subject) AS direct_sql_callers,
 (SELECT coalesce(jsonb_agg(DISTINCT e.callee),'[]'::jsonb)
  FROM edges e WHERE e.caller=s.subject) AS direct_sql_callees,
 EXISTS(SELECT 1 FROM reachable r WHERE r.node=s.subject) AS statically_reachable_from_ig,
 (SELECT count(*) FROM reachable) AS total_ig_reachable_functions,
 (SELECT count(*) FROM risk WHERE dynamic_sql) AS reachable_dynamic_sql_mentions,
 (SELECT count(*) FROM fn) AS indexed_function_names,
 (SELECT count(*) FROM edges) AS indexed_potential_edges,
 (SELECT ig->>'status' FROM run_link LIMIT 1) AS observed_profile_ig_status,
 (SELECT ig#>>'{governance_result,status}' FROM run_link LIMIT 1) AS observed_governance_status,
 (SELECT ig_run FROM run_link LIMIT 1) AS observed_ig_run,
 (SELECT profile_status FROM run_link LIMIT 1) AS observed_profile_status,
 current_setting('track_functions') AS track_functions,
 NULL::bigint AS measured_runtime_invocations,
 'STATIC_GRAPH_PLUS_GOVERNED_READBACK_NOT_FULL_RUNTIME_TRACE'::text AS proof_type,
 (SELECT status FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') AS checkpoint_status
FROM subjects s JOIN fn f ON f.name=s.subject
ORDER BY s.role;
