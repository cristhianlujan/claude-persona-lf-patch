-- PASE plan structural projection: read-only, source-backed pre/post comparison.
-- This is NOT the canonical plan_digest expected by PLAN_DELTA_AUTHORITY_READBACK.
-- No application/authorization; no implicit migration replay or control activation.
WITH
d6 AS (
  SELECT payload
  FROM public.lf_eventos
  WHERE id=20583 AND entidad_codigo='PASE-ATOM-F07-X02'
    AND evento_tipo='PLAN_SNAPSHOT_DETALLADO'
),
scope AS (
  SELECT pu.unit_code,w.id AS work_item_id,w.work_code,pu.disposition
  FROM programacion.engineering_plan_units pu
  JOIN programacion.engineering_work_items w ON w.id=pu.work_item_id
  WHERE pu.plan_code='LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1'
    AND pu.disposition='ASSIGNED'
),
baseline_nodes AS (
  SELECT unit_code FROM scope
),
proposed_nodes AS (
  SELECT unit_code FROM baseline_nodes
  UNION ALL SELECT 'PASE-ATOM-F09-X17'
),
baseline_edges AS (
  SELECT s.unit_code AS consumer,dep.work_code AS predecessor,
         d.relation_type AS relation
  FROM scope s
  JOIN programacion.engineering_work_dependencies d ON d.work_item_id=s.work_item_id
  JOIN programacion.engineering_work_items dep ON dep.id=d.depends_on_work_item_id
  WHERE d.relation_type='REQUIRES'
),
d6_debt_edges AS (
  SELECT 'PASE-ATOM-F07-X02' AS consumer,
         'PASE-ATOM-F07-X02-'||j.code AS predecessor
  FROM d6
  CROSS JOIN LATERAL jsonb_array_elements_text(d6.payload->'declared_debt') AS j(code)
),
proposed_edges AS (
  SELECT consumer,predecessor,relation
  FROM baseline_edges b
  WHERE NOT EXISTS (
    SELECT 1 FROM d6_debt_edges x
    WHERE x.consumer=b.consumer AND x.predecessor=b.predecessor
  )
  UNION ALL
  SELECT 'PASE-ATOM-F09-X17',predecessor,'REQUIRES'
  FROM (VALUES ('PASE-ATOM-F07-X01'),
               ('PASE-ATOM-F07-X02'),
               ('PASE-ATOM-F07-X03'),
               ('PASE-ATOM-F09-015')) v(predecessor)
  UNION ALL
  SELECT 'PASE-ATOM-F09-016','PASE-ATOM-F09-X17','REQUIRES'
),
baseline AS (
  SELECT jsonb_build_object(
    'plan_code','LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1',
    'unit_codes',coalesce((SELECT jsonb_agg(unit_code ORDER BY unit_code) FROM baseline_nodes),'[]'::jsonb),
    'edges',coalesce((SELECT jsonb_agg(jsonb_build_object('from',consumer,'to',predecessor,'relation',relation)
      ORDER BY consumer,predecessor,relation) FROM baseline_edges),'[]'::jsonb)
  ) document
),
proposal AS (
  SELECT jsonb_build_object(
    'plan_code','LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1',
    'unit_codes',coalesce((SELECT jsonb_agg(unit_code ORDER BY unit_code) FROM proposed_nodes),'[]'::jsonb),
    'edges',coalesce((SELECT jsonb_agg(jsonb_build_object('from',consumer,'to',predecessor,'relation',relation)
      ORDER BY consumer,predecessor,relation) FROM proposed_edges),'[]'::jsonb)
  ) document
),
proof AS (
  SELECT
    (SELECT count(*) FROM d6)=1
      AND (SELECT payload->>'migration_source_parity_pass_prerequisite' FROM d6)='PASE-ATOM-F09-X16'
      AND (SELECT (payload->>'r01_required')::boolean FROM d6)
      AND (SELECT (payload->>'debt_outside_global07_critical_path')::boolean FROM d6)
      AS decision_bound,
    (SELECT count(*) FROM d6_debt_edges x JOIN baseline_edges b
      ON x.consumer=b.consumer AND x.predecessor=b.predecessor)=3
      AND EXISTS(SELECT 1 FROM proposed_edges WHERE consumer='PASE-ATOM-F07-X02'
        AND predecessor='PASE-ATOM-F07-X02-R01')
      AND NOT EXISTS(SELECT 1 FROM proposed_edges WHERE consumer='PASE-ATOM-F07-X02'
        AND predecessor IN ('PASE-ATOM-F07-X02-R02','PASE-ATOM-F07-X02-R03','PASE-ATOM-F07-X02-R04'))
      AS debt_edges_scoped,
    (SELECT count(*) FROM proposed_edges WHERE consumer='PASE-ATOM-F09-X17')=4
      AND EXISTS(SELECT 1 FROM proposed_edges WHERE consumer='PASE-ATOM-F09-016'
        AND predecessor='PASE-ATOM-F09-X17')
      AS late_gate_fanin_scoped
)
SELECT
  'PASE_STRUCTURAL_PROJECTION_ONLY_V1' AS schema_version,
  (SELECT count(*) FROM baseline_nodes) AS current_plan_units,
  (SELECT count(*) FROM proposed_nodes) AS candidate_plan_units,
  (SELECT count(*) FROM baseline_edges) AS current_requires,
  (SELECT count(*) FROM proposed_edges) AS candidate_requires,
  encode(extensions.digest(convert_to((SELECT document::text FROM baseline),'UTF8'),'sha256'),'hex')
    AS current_structural_projection_sha256,
  encode(extensions.digest(convert_to((SELECT document::text FROM proposal),'UTF8'),'sha256'),'hex')
    AS candidate_structural_projection_sha256,
  decision_bound, debt_edges_scoped, late_gate_fanin_scoped,
  decision_bound AND debt_edges_scoped AND late_gate_fanin_scoped
    AS projection_consistent,
  false AS plan_delta_authorized,
  'COMPARE_ONLY_NO_AUTHORITY_DIGEST_NO_MUTATION' AS disposition
FROM proof;
