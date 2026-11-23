-- Disposable PostgreSQL 17 fixture; synthetic positive is NOT a user message.
\set ON_ERROR_STOP on
DO $test$
DECLARE
 v_id bigint;
 v_visual text:='Diseña una pantalla HOME SALY de revisión en iPhone 16 Pro.';
 v_original_sha text;
 v_prompt_sha text;
 v_scope jsonb;
BEGIN
 SELECT id, scope_json->>'prompt_sha256' INTO STRICT v_id,v_prompt_sha
 FROM saly.creative_orders WHERE code='SALY_HOME_V015_SINGLE_20261123';
 v_original_sha:=encode(extensions.digest(convert_to(v_visual,'UTF8'),'sha256'),'hex');
 -- The exact original wrong text is archived, never used as user visual input.
 IF EXISTS (SELECT 1 FROM saly.creative_orders
  WHERE code IN ('SALY_HOME_V015_SINGLE_20261123','SALY_ADELANTO_V015_SINGLE_20261123')
  AND (scope_json ? 'literal_request' OR scope_json->>'intake_source_status'
        IS DISTINCT FROM 'MISSING_VERIFIED_USER_VISUAL_REQUEST'))
 THEN RAISE EXCEPTION 'TEST_V1_QUARANTINE_NOT_APPLIED'; END IF;

 -- Test that a genuine-shaped creative request + QA contract can progress
 -- syntactically. The evidence here is fake by design, and ROLLBACK below
 -- prevents it being registered. No real QA is claimed.
 BEGIN
   UPDATE saly.creative_orders
   SET scope_json=scope_json || jsonb_build_object(
       'literal_request',v_visual,'render_authorized',true,
       'rendering_authority',true,'review_only',false,
       'intake_source_status','VERIFIED_USER_VISUAL_REQUEST',
       'intake_semantic_qa',jsonb_build_object(
          'verdict','PASS','intent_class','CREATIVE_IMAGE_REQUEST',
          'source_origin','USER_MESSAGE',
          'source_message_ref','FIXTURE_FAKE_MESSAGE',
          'reviewer_ref','PG17_INDEPENDENT_FIXTURE',
          'source_sha256',v_original_sha,'prompt_sha256',v_prompt_sha))
   WHERE id=v_id;
   IF (SELECT scope_json->>'literal_request' FROM saly.creative_orders
     WHERE id=v_id)<>v_visual
   THEN RAISE EXCEPTION 'TEST_V1_VALID_SHAPE_NOT_ACCEPTED'; END IF;
   RAISE EXCEPTION 'TEST_V1_POSITIVE_REVERT';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'TEST_V1_POSITIVE_REVERT' THEN RAISE; END IF;
 END;

 -- Changed prompt after verdict must invalidate source/prompt pair.
 BEGIN
   UPDATE saly.creative_orders
   SET scope_json=scope_json || jsonb_build_object(
       'literal_request',v_visual,'render_authorized',true,
       'rendering_authority',true,'review_only',false,
       'intake_source_status','VERIFIED_USER_VISUAL_REQUEST',
       'compiled_prompt','MUTATED PROMPT',
       'intake_semantic_qa',jsonb_build_object(
          'verdict','PASS','intent_class','CREATIVE_IMAGE_REQUEST',
          'source_origin','USER_MESSAGE',
          'source_message_ref','FIXTURE_FAKE_MESSAGE',
          'reviewer_ref','PG17_INDEPENDENT_FIXTURE',
          'source_sha256',v_original_sha,'prompt_sha256',v_prompt_sha))
   WHERE id=v_id;
   RAISE EXCEPTION 'TEST_V1_MUTATED_PROMPT_ESCAPED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_INTAKE_SEMANTIC_SOURCE_HASH_DRIFT'
   THEN RAISE; END IF;
 END;
 IF (SELECT COUNT(*) FROM saly.creative_orders
      WHERE code IN ('SALY_HOME_V015_SINGLE_20261123',
                     'SALY_ADELANTO_V015_SINGLE_20261123')
      AND status='PLANIFICADO' AND scope_json->>'render_authorized'='false')<>2
 OR EXISTS (SELECT 1 FROM saly.creative_runs)
 THEN RAISE EXCEPTION 'TEST_V1_RUNTIME_OR_ORDERS_CHANGED'; END IF;
 RAISE NOTICE 'PASS_SALY_CREATIVE_INTAKE_REPAIR_PG17_STRUCTURAL_QA_NEGATIVES';
END $test$;
