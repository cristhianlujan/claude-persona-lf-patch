-- Input Governance: focal specialist objection is NOT permission to
-- recurate just one family. READ-ONLY regression of live run data and
-- exact deployed function definitions. No DDL, DML, grants or runtime calls.
-- run_id 949 / family SESSION are immutable *audit fixtures only*.
-- Operational readers must derive these IDs from a bound profile receipt.
WITH params AS MATERIALIZED(
 SELECT 949::bigint AS run_id, 'SESSION'::text AS focus_family
), parent AS MATERIALIZED(
 SELECT r.* FROM programacion.input_readiness_runs r
 JOIN params p ON p.run_id=r.id
), focal AS MATERIALIZED(
 SELECT a.* FROM programacion.input_family_assessments a
 JOIN params p ON p.run_id=a.run_id AND p.focus_family=a.family_code
), focal_refs AS MATERIALIZED(
 SELECT v.value AS ref FROM focal f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f.source_refs,'[]'::jsonb)) v(value)
), family_ref_impact AS MATERIALIZED(
 SELECT DISTINCT a.family_code
 FROM programacion.input_family_assessments a
 JOIN params p ON p.run_id=a.run_id
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) v(value)
 WHERE EXISTS(SELECT 1 FROM focal_refs f WHERE f.ref=v.value)
), stats AS MATERIALIZED(
 SELECT
 (SELECT count(*) FROM parent) AS run_rows,
 (SELECT count(*) FROM focal) AS focus_rows,
 (SELECT count(*) FROM focal_refs) AS focus_ref_count,
 (SELECT count(*) FROM family_ref_impact) AS shared_source_families,
 (SELECT count(*) FROM programacion.input_family_assessments a
    JOIN params p ON p.run_id=a.run_id) AS family_rows,
 (SELECT r.family_count FROM parent r) AS expected_families,
 (SELECT r.status FROM parent r) AS run_status,
 (SELECT r.invalidated_at FROM parent r) AS invalidated_at,
 (SELECT r.supersedes_run_id FROM parent r) AS superseded_parent,
 (SELECT count(*) FROM programacion.input_family_assessments a
    JOIN params p ON p.run_id=a.run_id
    WHERE jsonb_array_length(coalesce(a.source_refs,'[]'::jsonb))=1
      AND a.source_refs @> jsonb_build_array(jsonb_build_object(
           'kind','SCREEN_CANONICAL_GRAPH','pantalla_id',(SELECT pantalla_id FROM parent)
      ))) AS graph_only_families,
 (SELECT count(*) FROM programacion.input_family_assessments a
    JOIN params p ON p.run_id=a.run_id WHERE a.validator_outcome='PASS') AS validator_pass_families,
 (SELECT count(*) FROM programacion.input_family_assessments a
    JOIN params p ON p.run_id=a.run_id
    WHERE a.family_code IN ('SECURITY','MFA_OTP_SSO')
      AND a.family_code IN (SELECT family_code FROM family_ref_impact)) AS shared_security_mfa_count,
 (SELECT pg_get_functiondef(
    'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure
 )) AS recurate_def,
 (SELECT pg_get_functiondef(
    'programacion.fn_input_freshness_delta(bigint)'::regprocedure
 )) AS freshness_def
), checks AS MATERIALIZED(
 SELECT 'RUN_RECEIPT_PRESENT' test,run_rows=1 pass FROM stats
 UNION ALL SELECT 'RUN_CURRENT_BASELINE',run_status='COMPLETED' AND invalidated_at IS NULL FROM stats
 UNION ALL SELECT 'TARGET_FAMILY_SINGLE_RECORD',focus_rows=1 FROM stats
 UNION ALL SELECT 'TARGET_SOURCE_REFS_EXIST',focus_ref_count>0 FROM stats
 UNION ALL SELECT 'HISTORICAL_SUCCESSOR_LINK_EXISTS',superseded_parent IS NOT NULL FROM stats
 UNION ALL SELECT 'FAMILY_UNIVERSE_PRESERVED',family_rows=expected_families FROM stats
 UNION ALL SELECT 'VALIDATOR_UNIVERSE_PASSED',validator_pass_families=family_rows FROM stats
 UNION ALL SELECT 'FOCAL_SOURCE_SHARED_WITH_OTHER_FAMILIES',shared_source_families>1 FROM stats
 UNION ALL SELECT 'CANONICAL_GRAPH_NOT_FINE_GRAINED',graph_only_families>1 FROM stats
 UNION ALL SELECT 'SECURITY_MFA_SHARE_FOCAL_SOURCE',shared_security_mfa_count=2 FROM stats
 UNION ALL SELECT 'SOURCE_STALE_RECURATION_LOOPS_ALL_FAMILIES',
   position('for v_family in select value from jsonb_array_elements_text' in recurate_def)>0
     AND position('if v_count<>47' in lower(recurate_def))>0 FROM stats
 UNION ALL SELECT 'FRESHNESS_USES_SHARED_CANONICAL_GRAPH',
    position('SCREEN_CANONICAL_GRAPH' in freshness_def)>0
      AND position('family_impacts' in freshness_def)>0 FROM stats
)
SELECT c.test,CASE WHEN c.pass IS TRUE THEN 'PASS' ELSE 'FAIL' END verdict,
 CASE
  WHEN c.test='FOCAL_SOURCE_SHARED_WITH_OTHER_FAMILIES' THEN 'shared_families='||(SELECT shared_source_families FROM stats)
  WHEN c.test='CANONICAL_GRAPH_NOT_FINE_GRAINED' THEN 'graph_only_families='||(SELECT graph_only_families FROM stats)
  WHEN c.test='FAMILY_UNIVERSE_PRESERVED' THEN 'total_families='||(SELECT family_rows FROM stats)
  ELSE NULL END observation
FROM checks c ORDER BY c.test;
