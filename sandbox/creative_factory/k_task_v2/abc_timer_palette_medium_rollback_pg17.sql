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

SAVEPOINT before_unclassified;
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
ROLLBACK TO SAVEPOINT before_unclassified;


SELECT 'C_ROLES_INPUT|all 55 app versions classified and proposed media remain unconfirmed';
SELECT 'C_ROLES_OUTPUT|'||jsonb_build_object(
 'classified',(SELECT count(*) FROM saly.identity_versions WHERE metadata ? 'token_role' AND metadata->'applies_to'='["PROTOTIPO_APP"]'::jsonb),
 'proposed_redes',(SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to_proposed' ? 'REDES_SOCIALES'),
 'proposed_impresion',(SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to_proposed' ? 'IMPRESION'),
 'proposed_papel',(SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to_proposed' ? 'PAPEL')
)::text;
SELECT 'C_GREEN_INPUT|item11 with CTA and logo; approved CTA7 vs approved brand8; duplicate10/alias21 candidates';
SELECT 'C_GREEN_OUTPUT|'||jsonb_build_object(
 'palette',saly.creative_item_context_medium_v3(11,NULL)->'effective_color_roles',
 'excluded_duplicate',saly.creative_item_context_medium_v3(11,NULL)->'effective_palette_exclusions',
 'alias21_target',(SELECT metadata->>'alias_target_code' FROM saly.identity_versions WHERE id=21),
 'alias21_kind',(SELECT metadata->>'kind' FROM saly.identity_versions WHERE id=21),
 'candidate10_role',(SELECT metadata->>'token_role' FROM saly.identity_versions WHERE id=10),
 'status7',(SELECT approval_status FROM saly.identity_versions WHERE id=7),
 'status8',(SELECT approval_status FROM saly.identity_versions WHERE id=8),
 'status10',(SELECT approval_status FROM saly.identity_versions WHERE id=10)
)::text;
SELECT 'C_REDES_UNCONFIRMED_INPUT|same item13 output_medium REDES_SOCIALES; proposals not confirmed';
SELECT 'C_REDES_UNCONFIRMED_OUTPUT|'||jsonb_build_object(
 'selected',(saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->>'selected_count')::int,
 'omitted',(saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->>'omitted_count')::int)::text;
DO $assert$ BEGIN
 IF (SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to'='["PROTOTIPO_APP"]'::jsonb)<>55
 OR (SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to_proposed' ? 'REDES_SOCIALES')<>18
 OR (SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to_proposed' ? 'IMPRESION')<>9
 OR (SELECT count(*) FROM saly.identity_versions WHERE metadata->'applies_to_proposed' ? 'PAPEL')<>9
 OR saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->>'selected_count'<>'0'
 OR saly.creative_item_context_medium_v3(11,NULL)#>>'{effective_color_roles,CTA,hex}'<>'#008200'
 OR saly.creative_item_context_medium_v3(11,NULL)#>>'{effective_color_roles,MARCA,hex}'<>'#00C853'
 OR (saly.creative_item_context_medium_v3(11,NULL)->>'selected_count')::int<>55
 OR (SELECT metadata->>'alias_target_code' FROM saly.identity_versions WHERE id=21)<>'color.action.primary.bg'
 THEN RAISE EXCEPTION 'FAIL_CLASSIFICATION_COLORS_OR_COUNTS'; END IF;
END $assert$;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
INSERT INTO saly.creative_owner_accounts_v1(requested_by,owner_uid)
VALUES('CHAT_USER','11111111-1111-4111-8111-111111111111'::uuid);
SELECT 'C_CONFIRM_INPUT|owner simulation confirms exactly proposed REDES_SOCIALES token versions, records identity/time';
DO $confirm$ DECLARE v record;
BEGIN
 FOR v IN SELECT id FROM saly.identity_versions
  WHERE metadata->'applies_to_proposed' ? 'REDES_SOCIALES' ORDER BY id LOOP
   PERFORM saly.creative_token_confirm_medium_v1(v.id,'REDES_SOCIALES',
      'Owner simulation only, rollback');
 END LOOP;
END $confirm$;
SELECT 'C_CONFIRM_OUTPUT|'||jsonb_build_object(
 'selected',(saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->>'selected_count')::int,
 'audit',(SELECT count(*) FROM saly.creative_token_medium_confirmations_v1),
 'who',(SELECT min(confirmed_by::text) FROM saly.creative_token_medium_confirmations_v1),
 'when_present',(SELECT count(*) FROM saly.creative_token_medium_confirmations_v1 WHERE confirmed_at IS NOT NULL)
)::text;
SELECT 'C_FORBIDDEN_INPUT|malicious proposed REDES for CTA7 duplicate10 geometry42 navigation58; confirmation must reject';
DO $protection$ DECLARE v bigint;msg text;
BEGIN
 FOREACH v IN ARRAY ARRAY[7::bigint,10,42,58] LOOP
  UPDATE saly.identity_versions SET metadata=jsonb_set(metadata,'{applies_to_proposed}',
   '["REDES_SOCIALES"]'::jsonb,true) WHERE id=v;
  BEGIN
   PERFORM saly.creative_token_confirm_medium_v1(v,'REDES_SOCIALES','should be blocked');
   RAISE EXCEPTION 'FAIL_ROLE_PROTECTION';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
   IF msg<>'SALY_TOKEN_ROLE_APP_ONLY' THEN RAISE; END IF;
   RAISE NOTICE 'C_FORBIDDEN_OUTPUT: version_id=% cause=%',v,msg;
  END;
 END LOOP;
END $protection$;
SELECT 'C_FORBIDDEN_READBACK|'||jsonb_build_object(
 'selected',(saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->>'selected_count')::int,
 'protected_selected',(SELECT count(*) FROM jsonb_array_elements(
 saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->'selected') e
 WHERE e->>'token_role' IN('CTA','DUPLICADO_DE_CTA','GEOMETRIA_UI','NAVEGACION_ESTADO_UI')),
 'audit',(SELECT count(*) FROM saly.creative_token_medium_confirmations_v1)
)::text;
DO $assert$ BEGIN
 IF saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->>'selected_count'<>'18'
 OR (SELECT count(*) FROM saly.creative_token_medium_confirmations_v1)<>18
 OR (SELECT count(*) FROM jsonb_array_elements(saly.creative_item_context_medium_v3(13,'REDES_SOCIALES')->'selected') e
     WHERE e->>'token_role' IN('CTA','DUPLICADO_DE_CTA','GEOMETRIA_UI','NAVEGACION_ESTADO_UI'))<>0
 THEN RAISE EXCEPTION 'FAIL_CONFIRMATION_SCOPE'; END IF;
END $assert$;

SELECT 'B0_INPUT|item 11 from PENDIENTE into PRODUCIENDO in PG17 fixture; prepare independent QA receipt and 1 active claim';
UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=8;
UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=11;
INSERT INTO saly.creative_queue_claims_v1
(id,order_id,item_id,worker_ref,claim_token,state,lease_until)
VALUES (700,8,11,'GPT_GENERATOR','70000000-0000-4000-8000-000000000700','ACTIVE',
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
  'verdict','PASS','comment','Independent automated QA fixture',
  'reviewer_kind','AUTOMATED_MODEL',
  'generator_model_family','GPT','reviewer_model_family','CLAUDE',
  'reviewer_ref','CLAUDE_QA','artifact_ref','fixture-image-11.png',
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
 VALUES(800,8,11,'EJECUTANDO',1,700,'GPT_GENERATOR',
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


SELECT 'B0_OUTPUT|'||jsonb_build_object(
 'order8',(SELECT status FROM saly.creative_orders WHERE id=8),
 'item11',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'run800',(SELECT state FROM saly.creative_runs WHERE id=800),
 'claim700',(SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700)
)::text;
SELECT 'A_GENERATE_INPUT|generator GPT_GENERATOR completes RUN as EXITOSO BEFORE timer detection';
SELECT 'A_GENERATE_OUTPUT|'||saly.creative_queue_advance_run_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,'EXITOSO',
 jsonb_build_object('artifact_ref','fixture-image-11.png',
 'sha256',repeat('a',64),'worker_receipt','worker_receipt_test'),NULL)::text;
SELECT 'A_READY_OUTPUT|'||saly.creative_run_image_readback_v2(800,11)::text;

SELECT 'B_MISSING_DETECTION_INPUT|QA PASS must reject if timer not yet recorded READY, no TERMINADO';
DO $negative$ DECLARE msg text;
BEGIN
 BEGIN
 PERFORM saly.creative_chat_save_qa_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,
 'fixture-image-11.png',repeat('a',64),'worker_receipt_test',
 (SELECT receipt FROM qa_test_data));
 RAISE EXCEPTION 'FAIL_QA_WITHOUT_DETECTION_SUCCEEDED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg<>'SALY_CHAT_QA_DETECTION_NOT_RECORDED' THEN RAISE; END IF;
  RAISE NOTICE 'B_MISSING_DETECTION_OUTPUT: %',msg;
 END;
END $negative$;
SELECT 'B_MISSING_DETECTION_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'claim',(SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700),
 'detection_rows',(SELECT count(*) FROM saly.creative_run_detection_v1))::text;

SELECT 'A_DETECTION_INPUT|image ready at t20, observer first sees READY t30, 2 checks';
SELECT 'A_DETECTION_OUTPUT|'||saly.creative_run_detection_record_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,2)::text;
SELECT 'A_DETECTION_READBACK|'||jsonb_build_object(
 'run_state',(SELECT state FROM saly.creative_runs WHERE id=800),
 'checks',(SELECT check_count FROM saly.creative_run_detection_v1 WHERE run_id=800),
 'first_ready_s',(SELECT first_ready_elapsed_seconds FROM saly.creative_run_detection_v1 WHERE run_id=800),
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'native_delivery_rows',(SELECT count(*) FROM saly.creative_queue_native_delivery_evidence_v1))::text;

SELECT 'B_SAME_REVIEWER_INPUT|generator GPT_GENERATOR and same reviewer_ref GPT_GENERATOR, reject';
DO $negative$ DECLARE msg text;
BEGIN
 BEGIN
 PERFORM saly.creative_chat_save_qa_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,
 'fixture-image-11.png',repeat('a',64),'worker_receipt_test',
 (SELECT jsonb_set(receipt,'{reviewer_ref}','"GPT_GENERATOR"'::jsonb)
 FROM qa_test_data));
 RAISE EXCEPTION 'FAIL_AUTOMATED_SELF_REVIEW_SUCCEEDED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg<>'CREATIVE_CHAT_QA_REVIEWER_NOT_INDEPENDENT' THEN RAISE; END IF;
  RAISE NOTICE 'B_SAME_REVIEWER_OUTPUT: %',msg;
 END;
END $negative$;

SAVEPOINT before_qa_fail;
SELECT 'B_QA_FAIL_INPUT|detected READY + independent automated CLAUDE_QA rejects image';
SELECT 'B_QA_FAIL_OUTPUT|'||saly.creative_chat_save_qa_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,
 'fixture-image-11.png',repeat('a',64),'worker_receipt_test',
 jsonb_build_object(
 'verdict','FAIL','comment','Automated technical QA failure',
 'reviewer_ref','CLAUDE_QA','reviewer_kind','AUTOMATED_MODEL',
 'generator_model_family','GPT','reviewer_model_family','CLAUDE',
 'artifact_sha256',repeat('a',64)))::text;
SELECT 'B_QA_FAIL_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'claim',(SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700),
 'run',(SELECT state FROM saly.creative_runs WHERE id=800),
 'order',(SELECT status FROM saly.creative_orders WHERE id=8),
 'approved_at',(SELECT approved_at FROM saly.creative_order_items WHERE id=11)
)::text;
DO $assert$ BEGIN
 IF (SELECT status FROM saly.creative_order_items WHERE id=11)<>'BLOQUEADO'
 OR (SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700)<>'BLOCKED'
 OR (SELECT status FROM saly.creative_orders WHERE id=8)='TERMINADO'
 THEN RAISE EXCEPTION 'FAIL_QA_FAIL_NOT_BLOCKED'; END IF;
END $assert$;
ROLLBACK TO SAVEPOINT before_qa_fail;


SELECT 'B_ATOMIC_PASS_INPUT|READY detected at t30, CLAUDE_QA automated independent verdict PASS; single database call';
SELECT 'B_ATOMIC_PASS_OUTPUT|'||saly.creative_chat_save_qa_v1(
 '70000000-0000-4000-8000-000000000700'::uuid,800,
 'fixture-image-11.png',repeat('a',64),'worker_receipt_test',
 (SELECT receipt FROM qa_test_data))::text;
SELECT 'B_ATOMIC_PASS_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order',(SELECT status FROM saly.creative_orders WHERE id=8),
 'claim',(SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700),
 'run',(SELECT state FROM saly.creative_runs WHERE id=800),
 'approved_at',(SELECT approved_at FROM saly.creative_order_items WHERE id=11),
 'approved_by',(SELECT approved_by FROM saly.creative_order_items WHERE id=11),
 'detections',(SELECT count(*) FROM saly.creative_run_detection_v1 WHERE run_id=800),
 'external_verified_deliveries',(SELECT count(*) FROM saly.creative_queue_native_delivery_evidence_v1),
 'check_count',(SELECT check_count FROM saly.creative_run_detection_v1 WHERE run_id=800)
)::text;
DO $assert$ BEGIN
 IF (SELECT status FROM saly.creative_order_items WHERE id=11)<>'TERMINADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=8)<>'TERMINADO'
 OR (SELECT state FROM saly.creative_queue_claims_v1 WHERE id=700)<>'DONE'
 OR (SELECT approved_at FROM saly.creative_order_items WHERE id=11) IS NOT NULL
 OR (SELECT count(*) FROM saly.creative_queue_native_delivery_evidence_v1)<>0
 THEN RAISE EXCEPTION 'FAIL_ATOMIC_CLOSE_NO_EXTERNAL_VERIFIER'; END IF;
END $assert$;

SELECT 'B_OWNER_APPROVE_INPUT|explicit owner decision after independent automated QA and atomic technical close';
SELECT 'B_OWNER_APPROVE_OUTPUT|'||saly.creative_owner_approve_v1(
 11,'APROBADO','Owner separately approves the image')::text;
SELECT 'B_OWNER_APPROVE_READBACK|'||jsonb_build_object(
 'item',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order',(SELECT status FROM saly.creative_orders WHERE id=8),
 'approved_by',(SELECT approved_by FROM saly.creative_order_items WHERE id=11),
 'approved_at_present',(SELECT approved_at IS NOT NULL FROM saly.creative_order_items WHERE id=11)
)::text;

SELECT 'B_TIMEOUT_INPUT|item13 copied from BORRADOR and PENDIENTE; test-only run never READY, seven checks until t180; expire real run';
UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=9;
UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=13;
INSERT INTO saly.creative_runs(id,order_id,item_id,state,attempt_number,
 worker_ref,deadline_at,started_at,idempotency_key)
VALUES(801,9,13,'EJECUTANDO',1,'GPT_GENERATOR',
 clock_timestamp()-interval '1 second',clock_timestamp()-interval '5 minutes',
 'TEST_TIMEOUT_ITEM13');
SELECT 'B_TIMEOUT_PRE|'||saly.creative_run_image_readback_v2(801,13)::text;
SELECT 'B_TIMEOUT_EXPIRE|'||saly.creative_run_expire_v1(801)::text;
SELECT 'B_TIMEOUT_OUTPUT|'||jsonb_build_object(
 'run',(SELECT state FROM saly.creative_runs WHERE id=801),
 'item',(SELECT status FROM saly.creative_order_items WHERE id=13),
 'order',(SELECT status FROM saly.creative_orders WHERE id=9),
 'detection_rows',(SELECT count(*) FROM saly.creative_run_detection_v1 WHERE item_id=13)
)::text;
DO $assert$ BEGIN
 IF (SELECT status FROM saly.creative_order_items WHERE id=13)='TERMINADO'
 OR (SELECT state FROM saly.creative_runs WHERE id=801)<>'FALLIDO'
 THEN RAISE EXCEPTION 'FAIL_TIMEOUT_CLOSED_ITEM13'; END IF;
END $assert$;

SELECT 'ABC_ROLLBACK_INPUT|ROLLBACK all test-only state, token roles, owner medium confirmations, records of image detection and QA';
ROLLBACK;
SELECT 'ABC_ROLLBACK_OUTPUT|'||jsonb_build_object(
 'order8',(SELECT status FROM saly.creative_orders WHERE id=8),
 'item11',(SELECT status FROM saly.creative_order_items WHERE id=11),
 'order9',(SELECT status FROM saly.creative_orders WHERE id=9),
 'item13',(SELECT status FROM saly.creative_order_items WHERE id=13),
 'historical_terminal',(SELECT count(*) FROM saly.creative_order_items WHERE id BETWEEN 5 AND 10 AND status='TERMINADO'),
 'classification_count',(SELECT count(*) FROM saly.identity_versions WHERE metadata ? 'token_role'),
 'context100_exists',(SELECT count(*) FROM saly.creative_context_sets WHERE id=100),
 'detection_table_exists',to_regclass('saly.creative_run_detection_v1') IS NOT NULL,
 'owner_medium_confirmation_table_exists',to_regclass('saly.creative_token_medium_confirmations_v1') IS NOT NULL
)::text;
SELECT 'PASS_ABC_TIMER_PALETTE_MEDIUM_REAL_PENDING_ROLLBACK';
