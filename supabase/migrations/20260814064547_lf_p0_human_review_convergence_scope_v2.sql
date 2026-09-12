-- Human Review Convergence v2: source-derived scope and explicit HUMAN_DEBT_CONVERGENCE metric.
CREATE OR REPLACE FUNCTION private.fn_lf_p0_semantic_fingerprint_from_visual_v1(p_content bytea)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public, private, extensions
AS $$
WITH j AS (SELECT convert_from(p_content,'UTF8')::jsonb AS doc),
els AS (
  SELECT CASE WHEN jsonb_typeof(doc->'elements')='array' THEN doc->'elements' ELSE coalesce(doc#>'{final_reader,elements}','[]'::jsonb) END AS a FROM j
), norm AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'element_id',e->>'element_id','element_type',e->>'element_type','region',e->'region','visible_text',e->>'visible_text',
    'ocr_consensus_text',e->>'ocr_consensus_text','classification',e->>'classification','semantic_role',e->>'semantic_role',
    'subcomponent_role',e->>'subcomponent_role','parent_id',e->>'parent_id','state',e->>'state'
  ) ORDER BY e->>'element_id'),'[]'::jsonb) AS v FROM els,jsonb_array_elements(a) e
)
SELECT encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex') FROM norm;
$$;

DROP VIEW IF EXISTS private.v_lf_p0_human_debt_convergence_v1;
DROP VIEW IF EXISTS private.v_lf_p0_human_review_active_queue_v1;
DROP VIEW IF EXISTS private.v_lf_p0_human_review_challenge_state_v1;

CREATE VIEW private.v_lf_p0_human_review_challenge_state_v1 AS
WITH evidence AS (
  SELECT c.*,
         src.content_sha256 AS observed_source_sha256,
         vis.content_sha256 AS observed_visual_sha256,
         man.content_sha256 AS observed_manifest_sha256,
         br.content_sha256 AS observed_browser_sha256,
         br.source_head_sha AS browser_head_sha,
         vis.content AS visual_content,
         coalesce(
           c.source_sha256,
           CASE WHEN vis.mime_type='application/json' THEN coalesce(convert_from(vis.content,'UTF8')::jsonb->>'source_sha256',convert_from(vis.content,'UTF8')::jsonb#>>'{final_reader,source_sha256}') END
         ) AS scope_source_sha256
  FROM private.lf_p0_human_review_challenges_v1 c
  LEFT JOIN private.lf_p0_review_evidence_objects_v1 src ON src.evidence_object_id=c.source_evidence_object_id AND src.object_role='SOURCE_IMAGE'
  LEFT JOIN LATERAL (
    SELECT e.* FROM private.lf_p0_review_evidence_objects_v1 e
    WHERE e.object_role='VISUAL_OUTPUT' AND (e.evidence_object_id=c.visual_output_object_id OR e.content_sha256=c.visual_output_sha256)
    ORDER BY (e.evidence_object_id=c.visual_output_object_id) DESC,e.created_at DESC LIMIT 1
  ) vis ON true
  LEFT JOIN private.lf_p0_review_evidence_objects_v1 man ON man.evidence_object_id=c.packet_manifest_object_id AND man.object_role='PACKET_MANIFEST'
  LEFT JOIN private.lf_p0_review_evidence_objects_v1 br ON br.evidence_object_id=c.browser_review_object_id AND br.object_role='BROWSER_REVIEW'
), ranked AS (
  SELECT evidence.*,
         coalesce(scope_source_sha256,'subject:'||review_subject) AS review_scope_key,
         row_number() OVER (PARTITION BY review_lane,coalesce(scope_source_sha256,'subject:'||review_subject) ORDER BY issued_at DESC,created_at DESC,challenge_id DESC) AS lifecycle_rank
  FROM evidence
)
SELECT ranked.*,
       CASE
         WHEN lifecycle_rank > 1 THEN 'SUPERSEDED'
         WHEN expires_at <= now() THEN 'EXPIRED'
         WHEN review_lane <> 'P0-4' THEN 'NOT_REVIEW_READY'
         WHEN source_evidence_object_id IS NULL OR source_sha256 IS NULL OR source_sha256 <> observed_source_sha256 THEN 'NOT_REVIEW_READY'
         WHEN visual_output_object_id IS NULL OR visual_output_sha256 <> observed_visual_sha256 THEN 'NOT_REVIEW_READY'
         WHEN packet_manifest_object_id IS NULL OR packet_manifest_sha256 <> observed_manifest_sha256 THEN 'NOT_REVIEW_READY'
         WHEN browser_review_object_id IS NULL OR browser_review_sha256 <> observed_browser_sha256 OR source_head_sha <> browser_head_sha THEN 'NOT_REVIEW_READY'
         WHEN semantic_fingerprint IS NULL OR element_count IS NULL OR uncertain_count IS NULL OR inferred_count IS NULL OR changed_count IS NULL OR pending_human_count IS NULL OR delta IS NULL OR review_mode IS NULL THEN 'NOT_REVIEW_READY'
         ELSE 'ACTIVE'
       END AS lifecycle_state
FROM ranked;

CREATE VIEW private.v_lf_p0_human_review_active_queue_v1 AS
SELECT * FROM private.v_lf_p0_human_review_challenge_state_v1 WHERE lifecycle_state='ACTIVE';

CREATE VIEW private.v_lf_p0_human_debt_convergence_v1 AS
WITH s AS (
  SELECT * FROM private.v_lf_p0_human_review_challenge_state_v1
), cur AS (
  SELECT * FROM s WHERE lifecycle_rank=1
), prev AS (
  SELECT * FROM s WHERE lifecycle_rank=2
)
SELECT cur.review_lane,cur.review_scope_key,cur.challenge_id,cur.source_head_sha,
       prev.challenge_id AS previous_challenge_id,prev.source_head_sha AS previous_head_sha,
       cur.semantic_fingerprint AS current_semantic_fingerprint,
       coalesce(prev.semantic_fingerprint,CASE WHEN prev.visual_content IS NOT NULL THEN private.fn_lf_p0_semantic_fingerprint_from_visual_v1(prev.visual_content) END) AS previous_semantic_fingerprint,
       cur.pending_human_count AS current_pending_human_count,
       coalesce(prev.pending_human_count,prev.element_count,CASE WHEN prev.visual_content IS NOT NULL THEN jsonb_array_length(CASE WHEN jsonb_typeof(convert_from(prev.visual_content,'UTF8')::jsonb->'elements')='array' THEN convert_from(prev.visual_content,'UTF8')::jsonb->'elements' ELSE coalesce(convert_from(prev.visual_content,'UTF8')::jsonb#>'{final_reader,elements}','[]'::jsonb) END) END) AS previous_pending_human_count,
       cur.pending_human_count-coalesce(prev.pending_human_count,prev.element_count,CASE WHEN prev.visual_content IS NOT NULL THEN jsonb_array_length(CASE WHEN jsonb_typeof(convert_from(prev.visual_content,'UTF8')::jsonb->'elements')='array' THEN convert_from(prev.visual_content,'UTF8')::jsonb->'elements' ELSE coalesce(convert_from(prev.visual_content,'UTF8')::jsonb#>'{final_reader,elements}','[]'::jsonb) END) END,0) AS pending_human_delta,
       CASE
         WHEN prev.challenge_id IS NULL THEN 'BASELINE'
         WHEN cur.semantic_fingerprint=coalesce(prev.semantic_fingerprint,CASE WHEN prev.visual_content IS NOT NULL THEN private.fn_lf_p0_semantic_fingerprint_from_visual_v1(prev.visual_content) END)
              AND cur.pending_human_count > coalesce(prev.pending_human_count,prev.element_count,CASE WHEN prev.visual_content IS NOT NULL THEN jsonb_array_length(CASE WHEN jsonb_typeof(convert_from(prev.visual_content,'UTF8')::jsonb->'elements')='array' THEN convert_from(prev.visual_content,'UTF8')::jsonb->'elements' ELSE coalesce(convert_from(prev.visual_content,'UTF8')::jsonb#>'{final_reader,elements}','[]'::jsonb) END) END,0)
           THEN 'FAIL'
         WHEN cur.semantic_fingerprint=coalesce(prev.semantic_fingerprint,CASE WHEN prev.visual_content IS NOT NULL THEN private.fn_lf_p0_semantic_fingerprint_from_visual_v1(prev.visual_content) END) THEN 'PASS'
         ELSE 'MATERIAL_DELTA'
       END AS human_debt_convergence
FROM cur LEFT JOIN prev ON prev.review_lane=cur.review_lane AND prev.review_scope_key=cur.review_scope_key;