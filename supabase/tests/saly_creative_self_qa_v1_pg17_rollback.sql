\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA saly;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT NULL::uuid $$;
CREATE TABLE saly.creative_orders(id bigint PRIMARY KEY,status text,completed_at timestamptz,requested_by text);
CREATE TABLE saly.creative_order_items(id bigint PRIMARY KEY,order_id bigint,code text,status text,required boolean,acceptance_json jsonb,context_json jsonb,qa_receipt jsonb,approved_at timestamptz,approved_by text,updated_at timestamptz);
CREATE TABLE saly.creative_runs(id bigint PRIMARY KEY,item_id bigint,order_id bigint,state text,worker_ref text,input_snapshot jsonb,output_evidence jsonb,attempt_number integer);
CREATE TABLE saly.creative_run_detection_v1(run_id bigint,item_id bigint,order_id bigint,artifact_sha256 text,artifact_ref text,check_count integer);
CREATE TABLE saly.creative_item_dependencies(order_id bigint,item_id bigint,depends_on_item_id bigint);
\i /tmp/saly_self_qa_body.sql
CREATE TRIGGER trg_creative_item_guard_l1 BEFORE INSERT OR UPDATE ON saly.creative_order_items FOR EACH ROW EXECUTE FUNCTION saly.creative_item_guard_l1();
INSERT INTO saly.creative_orders VALUES(1,'EN_PROCESO',NULL,'TEST');
INSERT INTO saly.creative_order_items(id,order_id,code,status,required,acceptance_json,context_json,qa_receipt) VALUES(1,1,'test1','LISTO',true,'{"qa_checklist":{"logo":9,"copy":true}}','{}','{}');
INSERT INTO saly.creative_runs VALUES(1,1,1,'EXITOSO','GPT','{}',jsonb_build_object('artifact_ref','fixture','sha256',repeat('a',64)),1);
INSERT INTO saly.creative_run_detection_v1 VALUES(1,1,1,repeat('a',64),'fixture',1);
DO $$ DECLARE receipt jsonb:=jsonb_build_object('run_id','1','verdict','PASS','reviewer_ref','GPT','artifact_sha256',repeat('a',64),'review_mode','GPT_SELF_QA','semantic_independence_proven',false,'preflight',jsonb_build_object('verdict','PASS','evidence','fixture only'),'checklist_results','{"logo":{"verdict":"PASS","evidence":"fixture"},"copy":{"verdict":"PASS","evidence":"fixture"}}'::jsonb); BEGIN
 BEGIN UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=receipt-'checklist_results' WHERE id=1; RAISE EXCEPTION 'EXPECTED_MISSING_CHECK_FAILURE'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_SELF_QA_CHECKLIST_INCOMPLETE' THEN RAISE; END IF; END;
 BEGIN UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=receipt-'review_mode' WHERE id=1; RAISE EXCEPTION 'EXPECTED_INDEPENDENCE_FAILURE'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING' THEN RAISE; END IF; END;
 BEGIN UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=receipt||'{"semantic_independence_proven":true}' WHERE id=1; RAISE EXCEPTION 'EXPECTED_FALSE_INDEPENDENCE_FAILURE'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CREATIVE_SELF_QA_CHECKLIST_INCOMPLETE' THEN RAISE; END IF; END;
 UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=receipt WHERE id=1;
 IF (SELECT status FROM saly.creative_order_items WHERE id=1)<>'TERMINADO' THEN RAISE EXCEPTION 'SELF_QA_FAILED'; END IF;
 RAISE NOTICE 'PASS_GPT_SELF_QA_AND_NEGATIVE_CONTROLS';
END $$;
ROLLBACK;
