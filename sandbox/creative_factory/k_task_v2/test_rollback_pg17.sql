\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
\pset fieldsep ' | '

BEGIN;
SELECT 'A_INPUT|task=NEW_SCREEN; spatial=false; item=101; source=visual.knowledge_select_review_v1';
SELECT saly.creative_task_select_once_v2(101,'NEW_SCREEN',false);
SELECT 'A_OUTPUT|'||jsonb_build_object(
 'selected',(SELECT jsonb_agg(x->>'module_code' ORDER BY x->>'module_code')
   FROM jsonb_array_elements(selection_json->'decisions') x WHERE x->>'decision'='EJECUTAR'),
 'omitted',(SELECT count(*) FROM saly.creative_task_selection_v2 z,
  jsonb_array_elements(z.selection_json->'decisions') x
  WHERE z.item_id=101 AND x->>'decision'='OMITIDO'),
 'module_content_count',(SELECT jsonb_array_length(selection_json->'modules')
    FROM saly.creative_task_selection_v2 WHERE item_id=101),
 'source',(SELECT selection_json->>'source' FROM saly.creative_task_selection_v2 WHERE item_id=101)
)::text FROM saly.creative_task_selection_v2 WHERE item_id=101;
DO $test$ BEGIN
 IF (SELECT jsonb_array_length(selection_json->'modules') FROM saly.creative_task_selection_v2 WHERE item_id=101)<>6
 OR (SELECT count(*) FROM saly.creative_task_selection_v2 s,
    jsonb_array_elements(s.selection_json->'decisions') x WHERE s.item_id=101 AND x->>'decision'='EJECUTAR')<>6
 THEN RAISE EXCEPTION 'FAIL_NEW_SCREEN_SIX_K'; END IF;
END $test$;

SELECT 'B_INPUT|task=NUMERIC_ADJUST; spatial=false; item=102';
SELECT saly.creative_task_select_once_v2(102,'NUMERIC_ADJUST',false);
SELECT 'B_OUTPUT|'||jsonb_build_object(
 'selected',(SELECT jsonb_agg(x->>'module_code' ORDER BY x->>'module_code')
   FROM jsonb_array_elements(selection_json->'decisions') x WHERE x->>'decision'='EJECUTAR'),
 'omitted',(SELECT jsonb_agg(jsonb_build_object('module_code',x->>'module_code','reason',x->>'reason') ORDER BY x->>'module_code')
   FROM jsonb_array_elements(selection_json->'decisions') x WHERE x->>'decision'='OMITIDO')
)::text FROM saly.creative_task_selection_v2 WHERE item_id=102;
DO $test$ BEGIN
 IF (SELECT count(*) FROM saly.creative_task_selection_v2 s,
 jsonb_array_elements(s.selection_json->'decisions') x
 WHERE s.item_id=102 AND x->>'decision'='EJECUTAR' AND x->>'module_code' IN('K05','K06'))<>2
 OR (SELECT count(*) FROM saly.creative_task_selection_v2 s,
 jsonb_array_elements(s.selection_json->'decisions') x
 WHERE s.item_id=102 AND x->>'decision'='OMITIDO'
 AND x->>'module_code' IN('K01','K02','K03','K04')
 AND nullif(x->>'reason','') IS NOT NULL)<>4
 THEN RAISE EXCEPTION 'FAIL_NUMERIC_K_SELECTION'; END IF;
END $test$;

SELECT 'C_INPUT|task=LOCAL_CORRECTION; spatial=true; item=103';
SELECT saly.creative_task_select_once_v2(103,'LOCAL_CORRECTION',true);
SELECT 'C_OUTPUT|'||jsonb_build_object(
 'selected',(SELECT jsonb_agg(x->>'module_code' ORDER BY x->>'module_code')
   FROM jsonb_array_elements(selection_json->'decisions') x WHERE x->>'decision'='EJECUTAR'),
 'omitted',(SELECT jsonb_agg(x->>'module_code' ORDER BY x->>'module_code')
   FROM jsonb_array_elements(selection_json->'decisions') x WHERE x->>'decision'='OMITIDO')
)::text FROM saly.creative_task_selection_v2 WHERE item_id=103;
DO $test$ BEGIN
 IF (SELECT count(*) FROM saly.creative_task_selection_v2 s,
 jsonb_array_elements(s.selection_json->'decisions') x
 WHERE s.item_id=103 AND x->>'decision'='EJECUTAR'
 AND x->>'module_code' IN('K04','K05','K06'))<>3
 OR (SELECT count(*) FROM saly.creative_task_selection_v2 s,
 jsonb_array_elements(s.selection_json->'decisions') x
 WHERE s.item_id=103 AND x->>'decision'='OMITIDO')<>3
 THEN RAISE EXCEPTION 'FAIL_SPATIAL_LOCAL_SELECTION'; END IF;
END $test$;

SELECT 'D_INPUT|step4; reference=NULL; image not sent by owner';
SELECT 'D_OUTPUT|'||saly.creative_reference_step_v2(NULL)::text;
DO $test$ BEGIN
 IF saly.creative_reference_step_v2(NULL)->>'status'<>'SIN_REFERENCIA'
 OR saly.creative_reference_step_v2(NULL)->>'blocking'<>'false'
 THEN RAISE EXCEPTION 'FAIL_OPTIONAL_REFERENCE'; END IF;
END $test$;

SELECT 'F_INPUT|record K05 twice on same PLAN object; item 102';
SELECT 'F_FIRST_OUTPUT|'||saly.creative_k_record_once_v2(
 102,'PLAN',repeat('a',64),'K05','EJECUTADO','7',
 '{"input":"literal_copy_and_components"}'::jsonb,
 '{"requirements":["CTA copy unchanged"]}'::jsonb)::text;
DO $negative$
DECLARE t text;
BEGIN
 BEGIN
 PERFORM saly.creative_k_record_once_v2(
 102,'PLAN',repeat('a',64),'K05','EJECUTADO','7',
 '{"input":"literal_copy_and_components"}'::jsonb,
 '{"requirements":["CTA copy unchanged"]}'::jsonb);
 RAISE EXCEPTION 'FAIL_DUPLICATE_WAS_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS t=MESSAGE_TEXT;
 IF t <> 'SALY_K_DUPLICATE_OBJECT_EXECUTION' THEN RAISE; END IF;
 RAISE NOTICE 'F_SECOND_OUTPUT: %',t;
 END;
END $negative$;
SELECT 'F_READBACK|'||jsonb_build_object(
 'k05_row_count',(SELECT count(*) FROM saly.creative_k_results_v2 WHERE item_id=102 AND module_code='K05' AND object_kind='PLAN'),
 'step9_consumer',(SELECT saly.creative_k_consume_v2(102,'PLAN',repeat('a',64),'K05')->'output')
)::text;

SELECT 'G_INPUT|K06 reviews PLAN and IMAGE as different objects, once each';
SELECT saly.creative_k_record_once_v2(
 102,'PLAN',repeat('a',64),'K06','EJECUTADO','8',
 '{"review":"plan"}'::jsonb,'{"finding":"plan reviewed"}'::jsonb);
SELECT saly.creative_k_record_once_v2(
 102,'IMAGE',repeat('b',64),'K06','EJECUTADO','11',
 '{"review":"image"}'::jsonb,'{"finding":"image reviewed"}'::jsonb);
SELECT 'G_OUTPUT|'||jsonb_build_object('k06_objects',
 (SELECT count(*) FROM saly.creative_k_results_v2 WHERE item_id=102 AND module_code='K06'),
 'different_objects',(SELECT count(DISTINCT object_kind) FROM saly.creative_k_results_v2
 WHERE item_id=102 AND module_code='K06'))::text;
DO $test$ BEGIN IF (SELECT count(*) FROM saly.creative_k_results_v2
 WHERE item_id=102 AND module_code='K06')<>2 THEN RAISE EXCEPTION 'FAIL_K06_TWO_OBJECTS'; END IF; END $test$;

SELECT 'H_INPUT|preQA author submits plan, same author attempts PASS, different reviewer PASS';
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT 'H_SUBMIT|'||saly.creative_plan_submit_v2(101,'{"intent":"HOME","copy":"literal"}'::jsonb)::text;
DO $negative$
DECLARE t text;
BEGIN
 BEGIN
 PERFORM saly.creative_plan_review_v2(101,
 (SELECT plan_sha256 FROM saly.creative_plan_pre_qa_v2 WHERE item_id=101),
 'PASS','{"checks":[{"code":"brief","verdict":"PASS","evidence":"source"}]}'::jsonb);
 RAISE EXCEPTION 'FAIL_SELF_REVIEW_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS t=MESSAGE_TEXT;
 IF t <> 'SALY_PREQA_INDEPENDENT_REVIEWER_REQUIRED' THEN RAISE; END IF;
 RAISE NOTICE 'H_SELF_REVIEW_OUTPUT: %',t;
 END;
END $negative$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
SELECT 'H_REVIEW|'||saly.creative_plan_review_v2(101,
 (SELECT plan_sha256 FROM saly.creative_plan_pre_qa_v2 WHERE item_id=101),
 'PASS','{"checks":[{"code":"brief","verdict":"PASS","evidence":"verified source exact"}]}'::jsonb)::text;
SELECT 'H_OUTPUT|'||jsonb_build_object(
 'verdict',(SELECT verdict FROM saly.creative_plan_pre_qa_v2 WHERE item_id=101),
 'different_reviewer',(SELECT reviewer_uid<>author_uid FROM saly.creative_plan_pre_qa_v2 WHERE item_id=101)
)::text;

SELECT 'E_SQL_INPUT|expired RUN deadline passed; use ORIGINAL creative_run_expire_v1';
INSERT INTO saly.creative_runs(id,state,deadline_at,attempt_number)
VALUES(501,'EJECUTANDO',clock_timestamp()-interval '1 second',1);
SELECT 'E_SQL_OUTPUT|'||saly.creative_run_expire_v1(501)::text;
DO $test$ BEGIN
 IF (SELECT state FROM saly.creative_runs WHERE id=501)<>'FALLIDO' OR
 (SELECT error_code FROM saly.creative_runs WHERE id=501)<>'LEASE_EXPIRED'
 THEN RAISE EXCEPTION 'FAIL_REAL_EXPIRER'; END IF;
END $test$;

SELECT 'Z_INPUT|ROLLBACK all candidate changes and execution/QA records';
ROLLBACK;
SELECT 'Z_OUTPUT|'||jsonb_build_object(
 'selection_rows',(SELECT count(*) FROM saly.creative_task_selection_v2),
 'result_rows',(SELECT count(*) FROM saly.creative_k_results_v2),
 'preqa_rows',(SELECT count(*) FROM saly.creative_plan_pre_qa_v2),
 'creative_run_rows',(SELECT count(*) FROM saly.creative_runs)
)::text;
SELECT 'PG17_SQL_TESTS_PASS';
