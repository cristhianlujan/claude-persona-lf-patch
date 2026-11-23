-- Current exact production semantic trigger, isolated PG17 fixture only.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE OR REPLACE FUNCTION saly.creative_intake_semantic_gate_v1()
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
CREATE TRIGGER trg_creative_00_intake_semantic_gate_v1
BEFORE INSERT OR UPDATE OF status,scope_json ON saly.creative_orders
FOR EACH ROW EXECUTE FUNCTION saly.creative_intake_semantic_gate_v1();
CREATE TABLE saly.test_intake_guard_baseline AS
SELECT md5(pg_get_functiondef('saly.creative_intake_semantic_gate_v1()'::regprocedure)) AS hash;
