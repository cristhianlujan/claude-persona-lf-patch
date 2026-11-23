-- SALY: precise repair of misclassified USER literal in PR #4648.
-- User approved 23 Nov: separate original visual request from operational
-- instruction and require semantic QA before execution; no invented source.
-- One migration by PR/PASE/Merge Train only, B1/B2/B3/B6/B11/B12/B25/B30.
BEGIN;
DO $pre$
DECLARE v_code text;
BEGIN
 IF to_regclass('saly.creative_orders') IS NULL
 OR to_regclass('saly.creative_order_items') IS NULL
 OR to_regclass('saly.creative_runs') IS NULL
 OR to_regprocedure('saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)') IS NULL
 OR to_regprocedure('saly.creative_intake_semantic_gate_v1()') IS NOT NULL
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_REPAIR_SCHEMA_PRECONDITION'; END IF;
 IF (SELECT count(*) FROM saly.creative_orders o
   JOIN saly.creative_order_items i ON i.order_id=o.id
   WHERE o.code IN ('SALY_HOME_V015_SINGLE_20261123',
                    'SALY_ADELANTO_V015_SINGLE_20261123')
    AND o.request_kind='APP_SCREEN_SINGLE'
    AND o.status='PLANIFICADO' AND i.status='PENDIENTE'
    AND o.scope_json->>'render_authorized'='false'
    AND o.scope_json->>'review_only'='true'
    AND o.scope_json->>'rendering_authority'='false'
    AND encode(extensions.digest(convert_to(o.scope_json->>'literal_request','UTF8'),'sha256'),'hex')
       ='835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a'
    AND encode(extensions.digest(convert_to(o.scope_json->>'compiled_prompt','UTF8'),'sha256'),'hex')
       =o.scope_json->>'prompt_sha256'
   )<>2
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_REPAIR_EXACT_PRESTATE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_runs)
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_REPAIR_RUNNING_ORDER'; END IF;
END $pre$;

-- The gate is fail-closed for single-screen orders whenever PLANIFICADO or
-- execution authority is requested; BORRADOR remains a non-executable draft.
-- A quarantined historical order may remain PLANIFICADO only while its
-- REVIEW_ONLY/render_authorized=false lock is unchanged.
CREATE FUNCTION saly.creative_intake_semantic_gate_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog,saly,extensions,pg_temp
AS $gate$
DECLARE
 v_literal text;
 v_sem jsonb;
 v_source_sha text;
 v_prompt_sha text;
 v_quarantine boolean;
BEGIN
 IF NEW.request_kind IS DISTINCT FROM 'APP_SCREEN_SINGLE' THEN RETURN NEW; END IF;

 v_literal:=nullif(btrim(NEW.scope_json->>'literal_request'),'');
 v_sem:=NEW.scope_json->'intake_semantic_qa';
 v_quarantine:=NEW.status='PLANIFICADO'
   AND NEW.scope_json->>'intake_source_status'='MISSING_VERIFIED_USER_VISUAL_REQUEST'
   AND NEW.scope_json->>'review_only'='true'
   AND NEW.scope_json->>'render_authorized'='false'
   AND NEW.scope_json->>'rendering_authority'='false';

 -- This exact SHA is confirmed from the source seed in PR #4648 and live
 -- readback; it is an operational instruction, not a creative visual request.
 IF v_literal IS NOT NULL
 AND encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
    ='835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a'
 AND NEW.status<>'BORRADOR'
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_OPERATIONAL_LITERAL_REJECTED'; END IF;

 IF NEW.status='BORRADOR'
   AND NEW.scope_json->>'render_authorized' IS DISTINCT FROM 'true'
   AND NEW.scope_json->>'rendering_authority' IS DISTINCT FROM 'true'
 THEN RETURN NEW; END IF;

 IF v_quarantine THEN RETURN NEW; END IF;

 IF v_literal IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING'; END IF;
 IF NEW.scope_json->>'operational_instruction'=v_literal
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_OPERATIONAL_EQUALS_VISUAL_REQUEST'; END IF;
 IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object'
 OR v_sem->>'verdict' IS DISTINCT FROM 'PASS'
 OR v_sem->>'intent_class' IS DISTINCT FROM 'CREATIVE_IMAGE_REQUEST'
 OR nullif(btrim(v_sem->>'source_message_ref'),'') IS NULL
 OR nullif(btrim(v_sem->>'reviewer_ref'),'') IS NULL
 OR v_sem->>'reviewer_ref'=NEW.requested_by
 OR v_sem->>'source_origin' IS DISTINCT FROM 'USER_MESSAGE'
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_SEMANTIC_QA_NOT_ATTESTED'; END IF;
 v_source_sha:=encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex');
 v_prompt_sha:=encode(extensions.digest(convert_to(NEW.scope_json->>'compiled_prompt','UTF8'),'sha256'),'hex');
 IF v_sem->>'source_sha256' IS DISTINCT FROM v_source_sha
 OR v_sem->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
 OR NEW.scope_json->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_SEMANTIC_SOURCE_HASH_DRIFT'; END IF;
 RETURN NEW;
END $gate$;
REVOKE ALL ON FUNCTION saly.creative_intake_semantic_gate_v1() FROM PUBLIC;
CREATE TRIGGER trg_creative_00_intake_semantic_gate_v1
BEFORE INSERT OR UPDATE OF status,scope_json ON saly.creative_orders
FOR EACH ROW EXECUTE FUNCTION saly.creative_intake_semantic_gate_v1();

-- Correct the two *misclassified fields only*, atomically. The operational
-- text is retained verbatim, no user visual message is reconstructed or
-- misattributed. Original compiled prompts and their SHA stay unchanged.
UPDATE saly.creative_orders o
SET scope_json=(o.scope_json-'literal_request')
 || jsonb_build_object(
    'operational_instruction',o.scope_json->>'literal_request',
    'intake_source_status','MISSING_VERIFIED_USER_VISUAL_REQUEST',
    'intake_semantic_qa',jsonb_build_object(
      'verdict','BLOCKED','intent_class','OPERATIONAL_PROCESS_INSTRUCTION',
      'source_origin','PR4648_SOURCE_SEED',
      'source_sha256','835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a',
      'blocking_reason','CREATIVE_USER_LITERAL_NOT_RECOVERED',
      'compiled_prompt_origin','ASSISTANT_DERIVED_REVIEW_NOT_USER_LITERAL',
      'repair_contract','SALY_CREATIVE_INTAKE_SEMANTIC_REPAIR_V1'))
WHERE o.code IN ('SALY_HOME_V015_SINGLE_20261123',
                 'SALY_ADELANTO_V015_SINGLE_20261123')
  AND o.request_kind='APP_SCREEN_SINGLE'
  AND o.status='PLANIFICADO';

DO $tests$
DECLARE v_home bigint; v_first text; v_bad text;
BEGIN
 SELECT id INTO STRICT v_home FROM saly.creative_orders
 WHERE code='SALY_HOME_V015_SINGLE_20261123';
 IF (SELECT count(*) FROM saly.creative_orders o
     WHERE o.code IN('SALY_HOME_V015_SINGLE_20261123',
                     'SALY_ADELANTO_V015_SINGLE_20261123')
       AND NOT (o.scope_json ? 'literal_request')
       AND o.scope_json->>'intake_source_status'='MISSING_VERIFIED_USER_VISUAL_REQUEST'
       AND o.scope_json->>'operational_instruction' IS NOT NULL
       AND encode(extensions.digest(convert_to(o.scope_json->>'operational_instruction','UTF8'),'sha256'),'hex')
           ='835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a'
       AND o.status='PLANIFICADO'
       AND o.scope_json->>'review_only'='true'
       AND o.scope_json->>'render_authorized'='false'
       AND encode(extensions.digest(convert_to(o.scope_json->>'compiled_prompt','UTF8'),'sha256'),'hex')
           =o.scope_json->>'prompt_sha256')<>2
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_REPAIR_POSTSTATE_INVALID'; END IF;

 -- Each negative test checks the exact intended error B11/B25.
 BEGIN
   UPDATE saly.creative_orders
   SET scope_json=scope_json||'{"render_authorized":true}'::jsonb
   WHERE id=v_home;
   RAISE EXCEPTION 'TEST_MISSING_ORIGINAL_ESCAPED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING'
   THEN RAISE; END IF;
 END;
 BEGIN
   UPDATE saly.creative_orders
   SET scope_json=scope_json || jsonb_build_object(
     'literal_request',scope_json->>'operational_instruction',
     'render_authorized',true)
   WHERE id=v_home;
   RAISE EXCEPTION 'TEST_OPERATIONAL_LITERAL_ESCAPED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_INTAKE_OPERATIONAL_LITERAL_REJECTED'
   THEN RAISE; END IF;
 END;
 BEGIN
   UPDATE saly.creative_orders
   SET scope_json=scope_json || jsonb_build_object(
     'literal_request','Diseña una pantalla SALY de revisión.',
     'render_authorized',true)
   WHERE id=v_home;
   RAISE EXCEPTION 'TEST_MISSING_SEMANTIC_QA_ESCAPED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_INTAKE_SEMANTIC_QA_NOT_ATTESTED'
   THEN RAISE; END IF;
 END;
 BEGIN
   UPDATE saly.creative_orders
   SET scope_json=scope_json || jsonb_build_object(
     'literal_request','Diseña una pantalla SALY de revisión.',
     'render_authorized',true,
     'intake_semantic_qa',jsonb_build_object(
       'verdict','PASS','intent_class','CREATIVE_IMAGE_REQUEST',
       'source_origin','USER_MESSAGE',
       'source_message_ref','TEST-ONLY','reviewer_ref','TEST-INDEPENDENT',
       'source_sha256',repeat('0',64),'prompt_sha256',scope_json->>'prompt_sha256'))
   WHERE id=v_home;
   RAISE EXCEPTION 'TEST_FAKE_HASH_SEMANTIC_QA_ESCAPED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_INTAKE_SEMANTIC_SOURCE_HASH_DRIFT'
   THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM saly.creative_runs)
 THEN RAISE EXCEPTION 'CREATIVE_INTAKE_REPAIR_UNEXPECTED_RUN'; END IF;
END $tests$;
COMMIT;
