\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA saly;
CREATE TABLE saly.creative_orders(id bigint PRIMARY KEY,project_id bigint,context_set_id bigint,code text,status text,request_kind text,scope_json jsonb,completed_at timestamptz);
CREATE TABLE saly.creative_order_items(id bigint PRIMARY KEY,order_id bigint,code text,ordinal int,status text,acceptance_json jsonb,qa_receipt jsonb,required boolean);
CREATE TABLE saly.creative_queue_claims_v1(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,order_id bigint,item_id bigint,worker_ref text,state text,claim_token uuid DEFAULT gen_random_uuid(),claimed_at timestamptz,lease_until timestamptz,finished_at timestamptz,note text);
CREATE UNIQUE INDEX one_active ON saly.creative_queue_claims_v1((1)) WHERE state='ACTIVE';
CREATE TABLE saly.creative_runs(id bigint,item_id bigint,order_id bigint,state text,queue_claim_id bigint,output_evidence jsonb,attempt_number int);
CREATE TABLE saly.creative_run_detection_v1(claim_id bigint,run_id bigint,order_id bigint,item_id bigint,artifact_ref text,artifact_sha256 text,check_count int,first_ready_elapsed_seconds int);
CREATE TABLE saly.creative_item_dependencies(item_id bigint,order_id bigint,depends_on_item_id bigint);
CREATE FUNCTION saly.creative_execution_policy_v1(timestamptz) RETURNS jsonb LANGUAGE sql AS $$SELECT '{"LEASE_SECONDS":600}'::jsonb$$;
CREATE FUNCTION saly.creative_order_sequence_dependency_met_v1(bigint) RETURNS boolean LANGUAGE sql AS $$SELECT true$$;
INSERT INTO saly.creative_orders VALUES(8,2,5,'OLD_ORDER','PLANIFICADO','APP_SCREEN_SINGLE','{}',NULL),(11,2,5,'SALY_SOLICITAR_ADELANTO_01_SOLICITAR_20261124','PLANIFICADO','APP_SCREEN_SINGLE','{"module":"Solicitar adelanto"}',NULL),(12,2,5,'SALY_SOLICITAR_ADELANTO_02_VERIFICAR_20261124','PLANIFICADO','APP_SCREEN_SINGLE','{"module":"Solicitar adelanto"}',NULL);
INSERT INTO saly.creative_order_items VALUES(10,8,'OLD',1,'PENDIENTE','{}','{}',true),(15,11,'SOLICITAR',1,'PENDIENTE','{}','{}',true),(16,12,'VERIFICAR',1,'PENDIENTE','{}','{}',true);
\i /tmp/saly_serial_loop_body.sql
DO $$ DECLARE a jsonb; b jsonb; token uuid; cid bigint; BEGIN
 a:=saly.creative_queue_claim_next_v1('GPT',NULL);
 IF a->>'status'<>'CLAIMED' OR a->>'order_id'<>'11' OR (SELECT status FROM saly.creative_orders WHERE id=11)<>'EN_PROCESO' OR (SELECT status FROM saly.creative_order_items WHERE id=15)<>'PRODUCIENDO' THEN RAISE EXCEPTION 'SERIAL_FIRST_CLAIM_FAILED: %',a; END IF;
 b:=saly.creative_queue_claim_next_v1('OTHER',NULL);
 IF b->>'status'<>'BUSY' THEN RAISE EXCEPTION 'SERIAL_SECOND_CLAIM_ADMITTED'; END IF;
 token:=(a->>'claim_token')::uuid; cid:=(a->>'claim_id')::bigint;
 BEGIN PERFORM saly.creative_queue_release_v1(token,'DONE',NULL); RAISE EXCEPTION 'EXPECTED_EARLY_RELEASE_FAILURE'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF; END;
 -- Synthetic delivery evidence exercises queue release only, not actual generation.
 INSERT INTO saly.creative_runs VALUES(1,15,11,'EXITOSO',cid,jsonb_build_object('artifact_ref','fixture','worker_receipt','fixture','sha256',repeat('a',64)),1);
 INSERT INTO saly.creative_run_detection_v1 VALUES(cid,1,11,15,'fixture',repeat('a',64),1,0);
 UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt='{"review_mode":"GPT_SELF_QA"}' WHERE id=15;
 b:=saly.creative_queue_release_v1(token,'DONE',NULL);
 IF b->>'order_closed'<>'true' OR (SELECT status FROM saly.creative_orders WHERE id=11)<>'TERMINADO' THEN RAISE EXCEPTION 'SERIAL_CLOSE_FAILED'; END IF;
 b:=saly.creative_queue_claim_next_v1('GPT',NULL);
 IF b->>'order_id'<>'12' OR (SELECT status FROM saly.creative_orders WHERE id=8)<>'PLANIFICADO' THEN RAISE EXCEPTION 'SERIAL_NEXT_FAILED'; END IF;
 RAISE NOTICE 'PASS_SERIAL_CLAIM_BUSY_CLOSE_NEXT';
END $$;
ROLLBACK;
