-- Owner decision 2026-11-24 01:25 America/Lima via Claude: no author/reviewer for plan pre-QA.
-- Existing permissions and final image QA/owner approval are unchanged.
BEGIN;
ALTER TABLE saly.creative_plan_pre_qa_v2 ALTER COLUMN author_uid DROP NOT NULL;
ALTER TABLE saly.creative_plan_pre_qa_v2 DROP CONSTRAINT creative_plan_pre_qa_v2_check;
ALTER TABLE saly.creative_plan_pre_qa_v2 ADD CONSTRAINT creative_plan_pre_qa_v2_check CHECK (
 (verdict='PENDING' AND reviewer_uid IS NULL AND review_json IS NULL AND reviewed_at IS NULL)
 OR (verdict<>'PENDING' AND review_json IS NOT NULL AND reviewed_at IS NOT NULL
     AND (reviewer_uid IS NOT NULL OR (review_json->>'review_mode') IS NOT DISTINCT FROM 'SIN_REVISOR_POR_DECISION_DEL_DUEÑO'))
);
CREATE OR REPLACE FUNCTION saly.creative_plan_submit_v2(p_item_id bigint,p_plan_json jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'pg_catalog','saly','auth','extensions','pg_temp'
AS $function$
DECLARE v_sha text;
BEGIN
 IF jsonb_typeof(p_plan_json) IS DISTINCT FROM 'object' OR p_plan_json='{}'::jsonb
 OR NOT EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=p_item_id)
 THEN RAISE EXCEPTION 'SALY_PREQA_PLAN_MISSING'; END IF;
 v_sha:=encode(extensions.digest(p_plan_json::text,'sha256'),'hex');
 INSERT INTO saly.creative_plan_pre_qa_v2(item_id,plan_sha256,plan_json,author_uid,verdict,reviewer_uid,review_json,reviewed_at)
 VALUES(p_item_id,v_sha,p_plan_json,NULL,'PASS',NULL,
  jsonb_build_object('review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO',
    'decision_source','OWNER_CHAT_CLAUDE_2026-11-24T01:25-05:00',
    'automatic_pass',true,'independent_pass',false,'visual_qa','NO_EVALUADO',
    'plan_sha256',v_sha),now());
 RETURN jsonb_build_object('status','PASS','plan_sha256',v_sha,'author_uid',NULL,
   'reviewer_uid',NULL,'independent_pass',false,'usable',true,
   'review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO');
END; $function$;
CREATE OR REPLACE FUNCTION saly.creative_plan_review_v2(p_item_id bigint,p_plan_sha256 text,p_verdict text,p_evidence jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'pg_catalog','saly','auth','extensions','pg_temp'
AS $function$
DECLARE v_row saly.creative_plan_pre_qa_v2%ROWTYPE;
BEGIN
 SELECT * INTO STRICT v_row FROM saly.creative_plan_pre_qa_v2
 WHERE item_id=p_item_id AND plan_sha256=p_plan_sha256 FOR UPDATE;
 IF v_row.verdict<>'PENDING' OR
 encode(extensions.digest(v_row.plan_json::text,'sha256'),'hex')<>v_row.plan_sha256
 THEN RAISE EXCEPTION 'SALY_PREQA_PLAN_IMMUTABLE_OR_ALREADY_REVIEWED'; END IF;
 IF p_verdict NOT IN ('PASS','FAIL','NO_EVALUADO') OR p_verdict IS NULL
 OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object' OR p_evidence='{}'::jsonb
 OR (p_verdict='PASS' AND (
  jsonb_typeof(p_evidence->'checks') IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_evidence->'checks')=0
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_evidence->'checks') c
    WHERE c->>'verdict' IS DISTINCT FROM 'PASS' OR nullif(btrim(c->>'evidence'),'') IS NULL)))
 THEN RAISE EXCEPTION 'SALY_PREQA_REVIEW_EVIDENCE_INVALID'; END IF;
 UPDATE saly.creative_plan_pre_qa_v2
 SET verdict=p_verdict,reviewer_uid=NULL,review_json=p_evidence||jsonb_build_object(
   'review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO','independent_pass',false,
   'decision_source','OWNER_CHAT_CLAUDE_2026-11-24T01:25-05:00'),reviewed_at=now()
 WHERE item_id=p_item_id AND plan_sha256=p_plan_sha256;
 RETURN jsonb_build_object('status',p_verdict,'plan_sha256',p_plan_sha256,
   'reviewer_uid',NULL,'independent_pass',false,'usable',p_verdict='PASS',
   'review_mode','SIN_REVISOR_POR_DECISION_DEL_DUEÑO');
END; $function$;
DO $$
DECLARE v_plan jsonb; v_sha text; v_result jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=11 AND order_id=8 AND status='LISTO')
 OR EXISTS(SELECT 1 FROM saly.creative_plan_pre_qa_v2 WHERE item_id=11)
 THEN RAISE EXCEPTION 'SALY_ITEM11_EXPECTED_STATE_MISSING'; END IF;
 SELECT evidence->'plan_snapshot',object_sha256 INTO STRICT v_plan,v_sha
 FROM saly.creative_k_results_v2
 WHERE item_id=11 AND object_kind='PLAN' AND module_code='K01';
 IF encode(extensions.digest(v_plan::text,'sha256'),'hex') IS DISTINCT FROM v_sha
 OR (SELECT count(*) FROM saly.creative_k_results_v2
   WHERE item_id=11 AND object_kind='PLAN' AND object_sha256=v_sha AND decision='EJECUTADO')<>6
 THEN RAISE EXCEPTION 'SALY_ITEM11_K_PLAN_MISMATCH'; END IF;
 v_result:=saly.creative_plan_submit_v2(11,v_plan);
 IF v_result->>'plan_sha256' IS DISTINCT FROM v_sha OR v_result->>'status' IS DISTINCT FROM 'PASS'
 OR NOT EXISTS(SELECT 1 FROM saly.creative_plan_pre_qa_v2
   WHERE item_id=11 AND plan_sha256=v_sha AND plan_json=v_plan AND verdict='PASS'
   AND author_uid IS NULL AND reviewer_uid IS NULL
   AND review_json->>'review_mode'='SIN_REVISOR_POR_DECISION_DEL_DUEÑO')
 THEN RAISE EXCEPTION 'SALY_ITEM11_PREQA_READBACK_MISMATCH'; END IF;
END $$;
COMMIT;
