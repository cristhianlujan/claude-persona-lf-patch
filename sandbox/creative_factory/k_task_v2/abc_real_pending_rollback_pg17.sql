\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
SELECT 'ABC_START_INPUT|Source: orders 8/9 and items 11/13 copied from live Supabase, items 5-10 TERMINADO, 55 token versions';
SELECT 'ABC_START_OUTPUT|' || jsonb_build_object(
 'order8',(SELECT status FROM saly.creative_orders WHERE id=8),
 'item11',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order9',(SELECT status FROM saly.creative_orders WHERE id=9),
 'item13',(SELECT status FROM saly.creative_order_items WHERE id=13),
 'tokens',(SELECT count(*) FROM saly.identity_versions),
 'history_5_10',(SELECT count(*) FROM saly.creative_order_items WHERE id BETWEEN 5 AND 10 AND status='TERMINADO')
)::text;

BEGIN;
-- Migrations have their BEGIN/COMMIT removed for this disposable DB test, so
-- all schema, function and metadata writes are undone by the FINAL ROLLBACK.
\i /tmp/saly_abc_candidate_no_boundary.sql

SELECT 'C0_INPUT|new 55-token SEALED context in disposable transaction; order8 and order9 moved only in fixture';
INSERT INTO saly.creative_context_sets(id,code,state,project_id)
VALUES(100,'SALY_55_TOKENS_TEST_ONLY','SEALED',2);
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
SELECT 100,v.id,CASE WHEN v.approval_status='APPROVED' THEN 'OFFICIAL'
                    ELSE 'EXISTING' END,
 encode(extensions.digest(v.value_json::text,'sha256'),'hex')
FROM saly.identity_versions v;
UPDATE saly.creative_orders SET context_set_id=100 WHERE id IN (8,9);
SELECT 'C0_OUTPUT|'||jsonb_build_object(
 'context_id',100,'state',(SELECT state FROM saly.creative_context_sets WHERE id=100),
 'tokens',(SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=100),
 'versions_with_applies_to',(SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to'='["PROTOTIPO_APP"]'::jsonb),
 'orders',(SELECT jsonb_agg(jsonb_build_object('id',id,'status',status,'context',context_set_id) ORDER BY id)
 FROM saly.creative_orders WHERE id IN(8,9)))::text;

SELECT 'C11_APP_INPUT|item 11 copied, screen_spec.device=IPHONE16PRO; medium implicit PROTOTIPO_APP';
SELECT 'C11_APP_OUTPUT|'||saly.creative_item_context_medium_v3(11,NULL)::text;
SELECT 'C13_APP_INPUT|item 13 copied, screen_spec.device=IPHONE16PRO; medium implicit PROTOTIPO_APP, order BORRADOR';
SELECT 'C13_APP_OUTPUT|'||saly.creative_item_context_medium_v3(13,NULL)::text;
SELECT 'C13_PRINT_INPUT|same item13, output_medium override IMPRESION';
SELECT 'C13_PRINT_OUTPUT|'||saly.creative_item_context_medium_v3(13,'IMPRESION')::text;
DO $assert$ BEGIN
 IF (saly.creative_item_context_medium_v3(11,NULL)->>'selected_count')::int<>55
 OR (saly.creative_item_context_medium_v3(13,NULL)->>'selected_count')::int<>55
 OR (saly.creative_item_context_medium_v3(13,'IMPRESION')->>'selected_count')::int<>0
 OR (saly.creative_item_context_medium_v3(13,'IMPRESION')->>'omitted_count')::int<>55
 OR EXISTS (SELECT 1 FROM jsonb_array_elements(saly.creative_item_context_medium_v3(13,'IMPRESION')->'omitted') e
 WHERE e->>'reason'<>'MEDIO_NO_APLICA')
 THEN RAISE EXCEPTION 'FAIL_MEDIUM_SELECTION_COUNTS'; END IF;
END $assert$;

SELECT 'C_UNCLASSIFIED_INPUT|remove applies_to from candidate version 63 in ROLLBACK only';
UPDATE saly.identity_versions SET metadata=metadata-'applies_to' WHERE id=63;
SELECT 'C_UNCLASSIFIED_OUTPUT|'||jsonb_build_object(
 'selected_count',(saly.creative_item_context_medium_v3(13,NULL)->>'selected_count')::int,
 'unclassified',(SELECT jsonb_agg(e ORDER BY e->>'code')
   FROM jsonb_array_elements(saly.creative_item_context_medium_v3(13,NULL)->'omitted') e)
)::text;
DO $assert$ BEGIN
 IF (saly.creative_item_context_medium_v3(13,NULL)->>'selected_count')::int<>54
 OR (saly.creative_item_context_medium_v3(13,NULL)->'omitted'->0->>'reason')<>'SIN_CLASIFICAR'
 THEN RAISE EXCEPTION 'FAIL_UNCLASSIFIED_TOKEN_NOT_EXCLUDED'; END IF;
END $assert$;

-- Technical lifecycle test: simulate an authorized test-only sender after
-- copying the exact initial pending records. Production intake gates are not
-- bypassed in SALY; this isolated fixture has no production dispatch adapter.
SELECT 'B0_INPUT|item 11 from PENDIENTE into PRODUCIENDO in PG17 fixture; prepare independent QA receipt and 1 active claim';
UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=8;
UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=11;
INSERT INTO saly.creative_queue_claims_v1
(id,order_id,item_id,worker_ref,claim_token,state,lease_until)
VALUES (700,8,11,'worker_a','70000000-0000-4000-8000-000000000700','ACTIVE',
 clock_timestamp()+interval '10 minutes');

CREATE TEMP TABLE qa_test_data (receipt jsonb, original_acceptance jsonb);
DO $qa$
DECLARE
 sem jsonb; orig jsonb; acceptance jsonb; visual jsonb; sha_orig text;
 sha_sem text;sha_contract text; sem_checks jsonb;tech_checks jsonb; receipt jsonb;
BEGIN
 orig:='[{"role":"user","text":"Solicitar adelanto SALY"}]'::jsonb;
 sha_orig:=encode(extensions.digest(convert_to(orig::text,'UTF8'),'sha256'),'hex');
 sem_checks:=(SELECT jsonb_agg(jsonb_build_object('code','SEM_'||n::text) ORDER BY n)
             FROM generate_series(1,5) AS n);
 sem:=jsonb_build_object('original_messages',orig,
 'original_request_sha256',sha_orig,
 'interpretation',jsonb_build_object('objective','SOLICITAR_ADELANTO'),
 'checks',sem_checks);
 SELECT jsonb_set(acceptance_json,'{semantic_qa}',sem,true) INTO acceptance
 FROM saly.creative_order_items WHERE id=11;
 UPDATE saly.creative_order_items SET acceptance_json=acceptance WHERE id=11;
 tech_checks:=(SELECT jsonb_agg(jsonb_build_object('code',c->>'code',
    'verdict','PASS','evidence','test fixture independent review') ORDER BY n)
 FROM jsonb_array_elements(saly.creative_item_visual_contract_l3b(11)#>'{contract,qa_checks}')
 WITH ORDINALITY t(c,n));
 visual:=jsonb_build_object('acceptance_criteria',acceptance,
  'qa_checks',saly.creative_item_visual_contract_l3b(11)#>'{contract,qa_checks}');
 sha_contract:=encode(extensions.digest(convert_to(visual::text,'UTF8'),'sha256'),'hex');
 sha_sem:=encode(extensions.digest(convert_to(sem::text,'UTF8'),'sha256'),'hex');
 receipt:=jsonb_build_object(
  'verdict','PASS','comment','Independently inspected simulated artifact',
  'reviewer_ref','reviewer_b','artifact_ref','fixture-image-11.png',
  'artifact_sha256',repeat('a',64),'contract_sha256',sha_contract,
  'semantic_qa',jsonb_build_object(
   'verdict','PASS','original_request_sha256',sha_orig,
   'semantic_contract_sha256',sha_sem,
   'independent_interpretation','Synthetic fixture semantic check',
   'checks',(SELECT jsonb_agg(jsonb_build_object('code',c->>'code',
       'verdict','PASS','evidence','source bytes reviewed') ORDER BY n)
       FROM jsonb_array_elements(sem_checks) WITH ORDINALITY t(c,n))),
  'technical_qa',jsonb_build_object('verdict','PASS','checks',tech_checks));
 INSERT INTO qa_test_data VALUES(receipt,acceptance);
 INSERT INTO saly.creative_runs(id,order_id,item_id,state,attempt_number,
 queue_claim_id,worker_ref,deadline_at,started_at,input_snapshot,output_evidence,
 idempotency_key)
 VALUES(800,8,11,'EJECUTANDO',1,700,'worker_a',
 clock_timestamp()+interval '10 minutes',clock_timestamp(),
 jsonb_build_object('identity_versions','[{"version_id":7}]'::jsonb,
  'source_refs','[]'::jsonb,'screen_spec', '{"device":"IPHONE16PRO"}'::jsonb,
  'visual_contract',visual,'visual_contract_sha256',sha_contract),
 '{}'::jsonb,'TEST_ITEM11_ATTEMPT1');
END $qa$;
-- Original item and order guards, with candidate function bodies, run in the test.
CREATE TRIGGER trg_creative_item_guard_l1
BEFORE INSERT OR UPDATE ON saly.creative_order_items
FOR EACH ROW EXECUTE FUNCTION saly.creative_item_guard_l1();
CREATE TRIGGER trg_saly_creative_chat_terminal_item_guard_v1
BEFORE UPDATE OR DELETE ON saly.creative_order_items
FOR EACH ROW EXECUTE FUNCTION saly.creative_chat_terminal_item_guard_v1();
CREATE TRIGGER trg_creative_00_single_screen_item_guard_v1
BEFORE INSERT OR UPDATE ON saly.creative_order_items
FOR EACH ROW EXECUTE FUNCTION saly.creative_single_screen_item_guard_v1();
CREATE TRIGGER trg_saly_creative_chat_terminal_order_guard_v1
BEFORE UPDATE ON saly.creative_orders
FOR EACH ROW EXECUTE FUNCTION saly.creative_chat_terminal_order_guard_v1();
CREATE TRIGGER trg_creative_order_close_guard_l1
BEFORE UPDATE ON saly.creative_orders
FOR EACH ROW EXECUTE FUNCTION saly.creative_order_close_guard_l1();
CREATE TRIGGER trg_creative_queue_native_delivery_guard_v1
BEFORE INSERT OR UPDATE ON saly.creative_queue_native_delivery_evidence_v1
FOR EACH ROW EXECUTE FUNCTION saly.creative_queue_native_delivery_guard_v1();

SELECT 'B0_OUTPUT|'||jsonb_build_object('order_status',(SELECT status FROM saly.creative_orders WHERE id=8),
'item_status',(SELECT status FROM saly.creative_order_items WHERE id=11),
'claim_state',(SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700),
'run_state',(SELECT state FROM saly.creative_runs WHERE id=800),
'qa_original','COPY_WITH_SYNTHETIC_TEST_ONLY')::text;

SAVEPOINT before_fail;
SELECT 'B_FAIL_INPUT|QA FAIL with artifact sha and independent reviewer; item 11 in PRODUCIENDO';
SELECT 'B_FAIL_OUTPUT|'||saly.creative_chat_save_qa_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,'fixture-image-11.png',
 repeat('a',64),'worker_receipt_test',
 jsonb_build_object('verdict','FAIL','comment','QA technical rejected',
  'reviewer_ref','reviewer_b','artifact_sha256',repeat('a',64)))::text;
SELECT 'B_FAIL_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order',(SELECT status FROM saly.creative_orders WHERE id=8),
 'run',(SELECT state FROM saly.creative_runs WHERE id=800),
 'claim',(SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700),
 'approved_at',(SELECT approved_at FROM saly.creative_order_items WHERE id=11))::text;
DO $assert$ BEGIN
 IF (SELECT status FROM saly.creative_order_items WHERE id=11)<>'BLOQUEADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=8)<>'EN_PROCESO'
 OR (SELECT approved_at FROM saly.creative_order_items WHERE id=11) IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL_QA_FAIL_DID_NOT_BLOCK'; END IF;END $assert$;
ROLLBACK TO SAVEPOINT before_fail;

SELECT 'B_PASS_INPUT|QA PASS with independent semantic/technical check evidence; original copied item11';
SELECT 'B_PASS_OUTPUT|'||saly.creative_chat_save_qa_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,
 'fixture-image-11.png',repeat('a',64),'worker_receipt_test',
 (SELECT receipt FROM qa_test_data))::text;
SELECT 'B_TERMINADO_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'approved_at',(SELECT approved_at FROM saly.creative_order_items WHERE id=11),
 'approved_by',(SELECT approved_by FROM saly.creative_order_items WHERE id=11),
 'run',(SELECT state FROM saly.creative_runs WHERE id=800),
 'order',(SELECT status FROM saly.creative_orders WHERE id=8))::text;

-- Real delivery evidence is still a separate requirement to finalize.
SELECT 'B_DELIVERY_INPUT|stage verified native delivery with independent verifier after PASS';
INSERT INTO saly.creative_queue_native_delivery_evidence_v1(
 id,claim_id,run_id,order_id,item_id,artifact_ref,artifact_sha256,
 host_surface,message_id,executor_mode,host_evidence_ref,host_evidence_sha256,state)
VALUES(900,700,800,8,11,'fixture-image-11.png',repeat('a',64),
 'chat','mock_message_id','TEST_ONLY',
 'local_fixture_artifact',repeat('f',64),'STAGED');
UPDATE saly.creative_queue_native_delivery_evidence_v1 SET
 state='VERIFIED',verifier_ref='verifier_c',verified_at=clock_timestamp()
WHERE id=900;
SELECT 'B_DELIVERY_OUTPUT|'||jsonb_build_object('state',
 (SELECT state FROM saly.creative_queue_native_delivery_evidence_v1 WHERE id=900),
 'verifier',(SELECT verifier_ref FROM saly.creative_queue_native_delivery_evidence_v1 WHERE id=900))::text;

SELECT 'B_FINALIZE_INPUT|release DONE via actual finalize function with verified delivery';
SELECT 'B_FINALIZE_OUTPUT|'||saly.creative_chat_finalize_after_verified_delivery_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800)::text;
SELECT 'B_FINALIZE_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order',(SELECT status FROM saly.creative_orders WHERE id=8),
 'order_closed',(SELECT completed_at IS NOT NULL FROM saly.creative_orders WHERE id=8),
 'approved_at',(SELECT approved_at FROM saly.creative_order_items WHERE id=11),
 'approved_by',(SELECT approved_by FROM saly.creative_order_items WHERE id=11))::text;
DO $assert$ BEGIN
 IF (SELECT status FROM saly.creative_order_items WHERE id=11)<>'TERMINADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=8)<>'TERMINADO'
 OR (SELECT approved_at FROM saly.creative_order_items WHERE id=11) IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL_TERMINADO_AND_NO_HUMAN_APPROVAL';END IF;
END $assert$;

SELECT 'B_OWNER_BAD_INPUT|owner_approve(item13) while item13 PENDIENTE';
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
INSERT INTO saly.creative_owner_accounts_v1(requested_by,owner_uid)
VALUES('CHAT_USER','11111111-1111-4111-8111-111111111111'::uuid);
DO $negative$
DECLARE err text;
BEGIN
 BEGIN
   PERFORM saly.creative_owner_approve_v1(13,'APROBADO','approve pending');
   RAISE EXCEPTION 'FAIL_NON_TERMINADO_APPROVED';
 EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
 IF err<>'SALY_OWNER_REQUIRES_TERMINADO' THEN RAISE; END IF;
 RAISE NOTICE 'B_OWNER_BAD_OUTPUT: %',err;
 END;
END $negative$;

SAVEPOINT before_reject;
SELECT 'B_OWNER_REJECT_INPUT|owner_approve(item11,RECHAZADO) after TERMINADO';
SELECT 'B_OWNER_REJECT_OUTPUT|'||saly.creative_owner_approve_v1(
 11,'RECHAZADO','Owner requests a later correction')::text;
SELECT 'B_OWNER_REJECT_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'decision',(SELECT decision FROM saly.creative_owner_decisions_v1 WHERE item_id=11))::text;
ROLLBACK TO SAVEPOINT before_reject;

SELECT 'B_OWNER_APPROVE_INPUT|owner_approve(item11,APROBADO) after TERMINADO and closed order';
SELECT 'B_OWNER_APPROVE_OUTPUT|'||saly.creative_owner_approve_v1(
 11,'APROBADO','Owner approves image after technical completion')::text;
SELECT 'B_OWNER_APPROVE_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order',(SELECT status FROM saly.creative_orders WHERE id=8),
 'approved_at_present',(SELECT approved_at IS NOT NULL FROM saly.creative_order_items WHERE id=11),
 'approved_by',(SELECT approved_by FROM saly.creative_order_items WHERE id=11),
 'owner_decision',(SELECT decision FROM saly.creative_owner_decisions_v1 WHERE item_id=11))::text;
DO $assert$ BEGIN
 IF (SELECT status FROM saly.creative_order_items WHERE id=11)<>'APROBADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=8)<>'TERMINADO'
 OR (SELECT approved_at FROM saly.creative_order_items WHERE id=11) IS NULL
 THEN RAISE EXCEPTION 'FAIL_OWNER_APPROVAL_SEPARATION';END IF;
END $assert$;

SELECT 'ABC_ROLLBACK_INPUT|ROLLBACK all fixture order/item changes, 55 metadata classifications, owner tables, candidate functions and contexts';
ROLLBACK;
SELECT 'ABC_ROLLBACK_OUTPUT|'||jsonb_build_object(
 'order8',(SELECT status FROM saly.creative_orders WHERE id=8),
 'item11',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order9',(SELECT status FROM saly.creative_orders WHERE id=9),
 'item13',(SELECT status FROM saly.creative_order_items WHERE id=13),
 'history_5_10',(SELECT count(*) FROM saly.creative_order_items WHERE id BETWEEN 5 AND 10 AND status='TERMINADO'),
 'token_applies_to_present',(SELECT count(*) FROM saly.identity_versions WHERE metadata ? 'applies_to'),
 'context100_exists',(SELECT count(*) FROM saly.creative_context_sets WHERE id=100),
 'owner_table_exists',to_regclass('saly.creative_owner_decisions_v1') IS NOT NULL,
 'medium_function_exists',to_regprocedure('saly.creative_item_context_medium_v3(bigint,text)') IS NOT NULL)::text;
SELECT 'ABC_PG17_ROLLBACK_TESTS_PASS';
