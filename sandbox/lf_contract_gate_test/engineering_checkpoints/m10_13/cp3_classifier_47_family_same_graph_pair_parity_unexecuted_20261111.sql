-- LF IG M10.13 CP3 | 47-family same-graph classifier parity
-- NOT EXECUTED. Intended for an authorized isolated Supabase/Postgres clone
-- containing an exact readback of RUN 951 and permission to EXECUTE both functions.
-- READ ONLY: compares the frozen legacy classifier against active ctx on ONE graph.
-- Do not interpret 47/47 classifier equality as semantic-oracle independence.
-- This deliberately surfaces every mismatch and stored-curator drift.
WITH
run AS MATERIALIZED (
 SELECT r.id,r.pantalla_id,r.version_id,r.status,r.invalidated_at,r.family_count
 FROM programacion.input_readiness_runs r
 WHERE r.id=951
),
graph AS MATERIALIZED (
 SELECT r.id AS run_id, r.pantalla_id,r.version_id,
        programacion.fn_input_screen_canonical_graph(r.pantalla_id,r.version_id) AS canonical_graph
 FROM run r
),
family AS MATERIALIZED (
 SELECT a.run_id,a.family_code,
        a.curator_evidence->>'bootstrap_classifier_sha256' AS stored_sha256
 FROM programacion.input_family_assessments a
 WHERE a.run_id=951
),
classifications AS MATERIALIZED (
 SELECT f.run_id,f.family_code,f.stored_sha256,
        programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
          g.pantalla_id,f.family_code,g.version_id,g.canonical_graph) AS frozen_result,
        programacion.fn_input_governance_bootstrap_classify_v2_ctx(
          g.pantalla_id,f.family_code,g.version_id,g.canonical_graph) AS active_result
 FROM family f JOIN graph g ON g.run_id=f.run_id
),
diff AS MATERIALIZED (
 SELECT c.*,
        c.frozen_result->>'classifier_sha256' AS frozen_sha256,
        c.active_result->>'classifier_sha256' AS active_sha256,
        (c.frozen_result IS NOT DISTINCT FROM c.active_result) AS exact_equal,
        (c.frozen_result->>'classifier_sha256'
           IS NOT DISTINCT FROM c.active_result->>'classifier_sha256') AS classifier_sha_equal,
        (c.stored_sha256 IS NOT DISTINCT FROM c.frozen_result->>'classifier_sha256') AS stored_to_frozen_equal,
        (c.stored_sha256 IS NOT DISTINCT FROM c.active_result->>'classifier_sha256') AS stored_to_active_equal
 FROM classifications c
)
SELECT
 (SELECT id FROM run) AS run_id,
 (SELECT status FROM run) AS run_status,
 (SELECT invalidated_at FROM run) AS run_invalidated_at,
 (SELECT family_count FROM run) AS expected_family_count,
 (SELECT count(*) FROM graph) AS canonical_graph_build_cte_rows,
 count(*)::integer AS observed_family_count,
 count(*) FILTER(WHERE exact_equal)::integer AS exact_equal_count,
 count(*) FILTER(WHERE classifier_sha_equal)::integer AS sha_equal_count,
 count(*) FILTER(WHERE stored_to_frozen_equal)::integer AS stored_frozen_match_count,
 count(*) FILTER(WHERE stored_to_active_equal)::integer AS stored_active_match_count,
 coalesce(jsonb_agg(jsonb_build_object(
       'family',family_code,'frozen_sha',frozen_sha256,
       'active_sha',active_sha256,'stored_sha',stored_sha256,
       'exact_equal',exact_equal,'sha_equal',classifier_sha_equal,
       'stored_frozen',stored_to_frozen_equal,
       'stored_active',stored_to_active_equal)
       ORDER BY family_code)
       FILTER(WHERE NOT exact_equal OR NOT classifier_sha_equal
                   OR NOT stored_to_frozen_equal OR NOT stored_to_active_equal),
       '[]'::jsonb) AS differences,
 CASE WHEN count(*)=47 AND bool_and(exact_equal)
            AND bool_and(classifier_sha_equal)
            AND bool_and(stored_to_frozen_equal)
            AND bool_and(stored_to_active_equal)
            AND (SELECT status FROM run)='COMPLETED'
            AND (SELECT invalidated_at FROM run) IS NULL
      THEN 'PASS_CLASSIFIER_PAIR_PARITY_ONLY'
      ELSE 'BLOCK_PARITY_OR_SOURCE_CURRENTNESS' END AS verdict,
 'NOT_INDEPENDENT_SEMANTIC_ORACLE'::text AS proof_scope
FROM diff;
