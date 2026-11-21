-- SALY L3C: literal input + separate interpretation + dual QA gate.
-- Scope: HOME and ADELANTO of SALY_HOME_BATCH_001; do not modify REWARDS.
-- No image generation, fake run, approval, new table, new QA engine or ZIP.
BEGIN;
DO $policy$
DECLARE
 v_original jsonb;
 v_semantic jsonb;
 v_count integer;
BEGIN
 v_original:=jsonb_build_array(
 jsonb_build_object('speaker','USER','text',$u$Yeah, bueno, ¿me harías algunas cosas que debemos hacer? Por ejemplo, el manejo del CTA. No, el manejo del CTA creo que con el botón verde con las letras en blanco. Luego las imágenes que saquen no tiene que tener estos palitos, ¿no? Y tienen que ajustar la, los tamaños. Luego que utilice los colores, porque veo creo que hay muchos colores diferentes. Y no se ha seguido el patrón que teníamos en el home. Tampoco se ha seguido el patrón de la del andresuelo. Entonces tenemos muchas cosas de repente que no están en la definición, pero por eso veamos la definición uno por uno, por favor$u$),
 jsonb_build_object('speaker','USER','text',$u$Ok, tenemos que mejorar varias cosas 



1) El QA
2) La orden de envío para generar
3) la forma de correr ir mostrando en pantalla un resumen del pedido para ver qué está generando 
4) si dices que rae de supabase la información entonces corrige esa las 2 anteriores y veamos si es cierto, 
$u$),
 jsonb_build_object('speaker','USER','text',$u$Ah, ya, pero todavía falta un bloque semántico que sería de interpretación sobre el pedido en el QA.$u$)
 );
 v_semantic:=jsonb_build_object(
   'schema_version','SALY_SEMANTIC_QA_L3C_V1',
   'scope','SALY_HOME_BATCH_001',
   'source_type','USER_MESSAGES_IN_CURRENT_CONVERSATION',
   'original_messages',v_original,
   'original_request_sha256',encode(extensions.digest(convert_to(v_original::text,'UTF8'),'sha256'),'hex'),
   'interpretation',jsonb_build_object(
     'objective','Corregir las dos pantallas anteriores, no rediseñar la aplicación.',
     'screens',jsonb_build_array('HOME','ADELANTO'),
     'preserve',jsonb_build_array('Identidad SALY','Estructura y patrón de la referencia original','Funcionalidad, datos y contenidos sustentados'),
     'change',jsonb_build_array('CTA verde oficial con texto blanco','Eliminar rayitas decorativas','Ajustar tamaños y proporciones a la referencia','Usar la paleta versionada sin introducir colores ajenos'),
     'creative_freedom','LIMITED_TO_REQUESTED_CORRECTIONS',
     'excluded',jsonb_build_array('Nuevas funciones no solicitadas','Nuevos módulos no solicitados','Afirmaciones financieras no sustentadas','Rediseño integral'),
     'interpretation_origin','ASSISTANT_INTERPRETATION_SEPARATE_FROM_USER_LITERAL',
     'evaluation_basis','COMPARE_ORIGINAL_USER_MESSAGES_AND_LINKED_SOURCE_BYTES'),
   'checks',jsonb_build_array(
     jsonb_build_object('code','INTENT_MATCH','expected','Cumple el objetivo de corrección, no rediseño','severity','BLOCK'),
     jsonb_build_object('code','SCOPE_MATCH','expected','Solo cambia lo solicitado para la pantalla','severity','BLOCK'),
     jsonb_build_object('code','REFERENCE_PATTERN_PRESERVED','expected','Mantiene patrón y estructura de referencia SALY','severity','BLOCK'),
     jsonb_build_object('code','NO_UNREQUESTED_CHANGES','expected','No añade componentes, datos ni funciones fuera del pedido','severity','BLOCK'),
     jsonb_build_object('code','FUNCTIONAL_PURPOSE_PRESERVED','expected','Conserva propósito y contenido funcional de la pantalla','severity','BLOCK')),
   'require_independent_interpretation',true,
   'require_artifact_evidence',true);
 UPDATE saly.creative_order_items i
 SET acceptance_json=jsonb_set(i.acceptance_json,'{semantic_qa}',v_semantic,true)
 FROM saly.creative_orders o
 WHERE o.id=i.order_id AND o.code='SALY_HOME_BATCH_001'
   AND o.status='PLANIFICADO' AND i.code IN ('HOME','ADELANTO')
   AND i.status='PENDIENTE' AND NOT i.acceptance_json ? 'semantic_qa'
   AND NOT EXISTS(SELECT 1 FROM saly.creative_runs r WHERE r.item_id=i.id);
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>2 THEN RAISE EXCEPTION 'SALY_L3C_SCOPE_OR_PILOT_STATE_DRIFT'; END IF;
END $policy$;

-- Receipt gate, not an image reviewer: validates both QA reports against the
-- real worker run and the frozen original/interpretation in that run.
CREATE FUNCTION saly.creative_assert_dual_qa_l3c(
 p_acceptance jsonb,p_receipt jsonb,p_snapshot jsonb,p_output jsonb)
RETURNS void LANGUAGE plpgsql STABLE
SET search_path=pg_catalog,saly,extensions,pg_temp AS $fn$
DECLARE
 v_sem jsonb:=p_acceptance->'semantic_qa';
 v_visual jsonb:=p_snapshot->'visual_contract';
 v_contract_sha text;
 v_original_sha text;
 v_semantic_sha text;
 v_artifact_sha text;
 v_group text;
 v_expected jsonb;
 v_actual jsonb;
 v_n integer;
BEGIN
 IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_sem->'original_messages') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_sem->'original_messages')=0
    OR jsonb_typeof(v_sem->'interpretation') IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_sem->'checks') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_sem->'checks')<>5
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_INPUT_INVALID'; END IF;
 v_original_sha:=encode(extensions.digest(convert_to((v_sem->'original_messages')::text,'UTF8'),'sha256'),'hex');
 v_semantic_sha:=encode(extensions.digest(convert_to(v_sem::text,'UTF8'),'sha256'),'hex');
 IF v_sem->>'original_request_sha256' IS DISTINCT FROM v_original_sha
    OR jsonb_typeof(v_visual) IS DISTINCT FROM 'object'
    OR v_visual->'acceptance_criteria' IS DISTINCT FROM p_acceptance
    OR jsonb_typeof(v_visual->'qa_checks') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_visual->'qa_checks')<>5
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CONTRACT_MISMATCH'; END IF;
 v_contract_sha:=encode(extensions.digest(convert_to(v_visual::text,'UTF8'),'sha256'),'hex');
 v_artifact_sha:=p_output->>'sha256';

 IF p_snapshot->>'visual_contract_sha256' IS DISTINCT FROM v_contract_sha
    OR p_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
    OR v_artifact_sha IS NULL OR v_artifact_sha !~ '^[0-9a-f]{64}$'
    OR p_receipt->>'artifact_sha256' IS DISTINCT FROM v_artifact_sha
    OR p_receipt->>'artifact_ref' IS DISTINCT FROM p_output->>'artifact_ref'
    OR nullif(btrim(p_output->>'artifact_ref'),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_ARTIFACT_OR_HASH_MISMATCH'; END IF;

 IF p_receipt#>>'{semantic_qa,original_request_sha256}' IS DISTINCT FROM v_original_sha
    OR p_receipt#>>'{semantic_qa,semantic_contract_sha256}' IS DISTINCT FROM v_semantic_sha
    OR nullif(btrim(p_receipt#>>'{semantic_qa,independent_interpretation}'),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_REVIEW_MISSING'; END IF;

 FOREACH v_group IN ARRAY ARRAY['semantic_qa','technical_qa'] LOOP
   IF p_receipt#>>ARRAY[v_group,'verdict'] IS DISTINCT FROM 'PASS'
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_NOT_PASS'; END IF;
   v_expected:=CASE v_group WHEN 'semantic_qa' THEN v_sem->'checks' ELSE v_visual->'qa_checks' END;
   v_actual:=p_receipt#>ARRAY[v_group,'checks'];
   IF jsonb_typeof(v_actual) IS DISTINCT FROM 'array'
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECKS_MISSING'; END IF;
   IF (SELECT count(DISTINCT check_item->>'code') FROM jsonb_array_elements(v_expected) AS t(check_item))<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_INVALID_EXPECTED_CODES'; END IF;
   IF jsonb_array_length(v_actual)<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECK_COUNT'; END IF;
   SELECT count(*) INTO v_n
    FROM jsonb_array_elements(v_expected) AS exp(check_item)
    WHERE (SELECT count(*) FROM jsonb_array_elements(v_actual) AS act(check_item)
      WHERE act.check_item->>'code'=exp.check_item->>'code'
       AND act.check_item->>'verdict'='PASS'
       AND nullif(btrim(act.check_item->>'evidence'),'') IS NOT NULL)=1;
   IF v_n<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECK_FAILED_OR_MISSING'; END IF;
 END LOOP;
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_assert_dual_qa_l3c(jsonb,jsonb,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION saly.creative_item_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_order_status text; v_run record; v_run_id text;
BEGIN
 SELECT status INTO v_order_status FROM saly.creative_orders WHERE id=NEW.order_id FOR UPDATE;
 IF v_order_status IN ('COMPLETADO','CANCELADO')
 THEN RAISE EXCEPTION 'CREATIVE_CLOSED_ORDER_IMMUTABLE_ITEMS'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='APROBADO'
 THEN RAISE EXCEPTION 'CREATIVE_APPROVED_ITEM_IMMUTABLE'; END IF;
 -- Original input and interpretation cannot be silently replaced after capture.
 IF TG_OP='UPDATE' AND OLD.acceptance_json ? 'semantic_qa'
    AND NEW.acceptance_json->'semantic_qa' IS DISTINCT FROM OLD.acceptance_json->'semantic_qa'
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_CONTRACT_IMMUTABLE'; END IF;
 IF NEW.status='APROBADO' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF TG_OP='INSERT' OR OLD.status<>'EN_QA'
   THEN RAISE EXCEPTION 'CREATIVE_ITEM_NOT_IN_QA'; END IF;
   IF EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id AND prereq.status<>'APROBADO'
   ) THEN RAISE EXCEPTION 'CREATIVE_DEPENDENCY_NOT_APPROVED'; END IF;
   v_run_id:=NEW.qa_receipt->>'run_id';
   IF v_run_id IS NULL OR v_run_id !~ '^[0-9]+$'
      OR (NEW.qa_receipt->>'verdict') IS DISTINCT FROM 'PASS'
      OR nullif(btrim(NEW.qa_receipt->>'reviewer_ref'),'') IS NULL
   THEN RAISE EXCEPTION 'CREATIVE_QA_RECEIPT_MISSING'; END IF;
   SELECT r.id,r.worker_ref,r.input_snapshot,r.output_evidence INTO v_run
   FROM saly.creative_runs r
   WHERE r.id=v_run_id::bigint AND r.item_id=NEW.id AND r.order_id=NEW.order_id
     AND r.state='EXITOSO' AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
       WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number);
   IF NOT FOUND OR NEW.qa_receipt->>'reviewer_ref'=v_run.worker_ref
      OR NEW.approved_by IS DISTINCT FROM NEW.qa_receipt->>'reviewer_ref'
   THEN RAISE EXCEPTION 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING'; END IF;
   IF NEW.acceptance_json ? 'semantic_qa' THEN
     IF v_run.input_snapshot#>'{visual_contract,qa_checks}' IS DISTINCT FROM
        saly.creative_item_visual_contract_l3b(NEW.id)#>'{contract,qa_checks}'
     THEN RAISE EXCEPTION 'CREATIVE_TECHNICAL_CHECK_EXPECTATIONS_MISMATCH'; END IF;
     PERFORM saly.creative_assert_dual_qa_l3c(
        NEW.acceptance_json,NEW.qa_receipt,v_run.input_snapshot,v_run.output_evidence);
   END IF;
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION saly.creative_order_live_summary_l3b(p_order_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE v_order record; v_items jsonb; v_all integer; v_ready integer; v_blocked integer;
BEGIN
 SELECT o.id,o.code,o.status,p.codigo AS project_code INTO v_order
 FROM saly.creative_orders o JOIN saly.proyecto p ON p.id=o.project_id
 WHERE o.id=p_order_id;
 IF NOT FOUND OR v_order.project_code<>'SALY-001'
 THEN RAISE EXCEPTION 'SALY_L3B_ORDER_NOT_ADMITTED'; END IF;

 WITH entries AS (
 SELECT i.ordinal,i.id,i.code,i.status,
    i.acceptance_json->'semantic_qa' AS semantic_contract, i.qa_receipt,
    pkt.result->>'readiness_code' AS readiness,
    COALESCE(jsonb_array_length(pkt.result->'blocking_dependencies'),0) AS deps,
    vc.info->>'contract_sha256' AS contract_sha256,
    (SELECT count(*) FROM saly.creative_runs r WHERE r.item_id=i.id) AS runs,
    (SELECT count(*) FROM saly.creative_item_sources s WHERE s.item_id=i.id) AS sources
 FROM saly.creative_order_items i
 CROSS JOIN LATERAL (SELECT saly.creative_item_work_packet_l2c(i.id) AS result) pkt
 CROSS JOIN LATERAL (SELECT saly.creative_item_visual_contract_l3b(i.id) AS info) vc
 WHERE i.order_id=v_order.id)
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'ordinal',ordinal,'item_id',id,'screen',code,'status',status,
    'readiness',readiness,'blocked_dependencies',deps,
    'sources',sources,'runs',runs,
    'visual_contract_sha256',contract_sha256,
    'qa_status',COALESCE(qa_receipt->>'verdict','NOT_EVALUATED'),
    'semantic_qa',CASE WHEN semantic_contract IS NULL THEN NULL ELSE
      jsonb_build_object('request_original',semantic_contract->'original_messages',
        'original_request_sha256',semantic_contract->>'original_request_sha256',
        'interpretation',semantic_contract->'interpretation',
        'checks',semantic_contract->'checks',
        'verdict',COALESCE(qa_receipt#>>'{semantic_qa,verdict}','NOT_EVALUATED'),
        'technical_verdict',COALESCE(qa_receipt#>>'{technical_qa,verdict}','NOT_EVALUATED'))
      END)
    ORDER BY ordinal),'[]'::jsonb),
 count(*)::integer,
 count(*) FILTER(WHERE readiness='READY_FOR_NATIVE_HANDOFF')::integer,
 count(*) FILTER(WHERE readiness<>'READY_FOR_NATIVE_HANDOFF')::integer
 INTO v_items,v_all,v_ready,v_blocked FROM entries;
 RETURN jsonb_build_object(
 'schema_version','SALY_ORDER_LIVE_SUMMARY_L3B_V1',
 'order_id',v_order.id,'order_code',v_order.code,'order_status',v_order.status,
 'total_screens',v_all,'ready_for_handoff',v_ready,'blocked',v_blocked,
 'items',v_items,
 'actual_generation_count',(SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order.id),
 'qa_pass_count',(SELECT count(*) FROM saly.creative_order_items WHERE order_id=v_order.id AND status='APROBADO'),
 'visual_generation_enabled',false,
 'batch_status','PREPARED_NOT_RENDERED');
END $function$;

-- Test the contract and its rejection paths against the existing real pilot.
-- JSON receipts below are LOCAL TEST FIXTURES, never persisted as runs or QA.
DO $test$
DECLARE
 v_order bigint; v_item bigint; v_accept jsonb; v_packet jsonb;
 v_sem jsonb; v_snapshot jsonb; v_receipt jsonb; v_output jsonb;
 v_summary jsonb; v_bad jsonb; v_cases jsonb; v_case jsonb;
 v_expected_error text; v_rejected boolean;
 v_original_sha text; v_sem_sha text;
BEGIN
 SELECT id INTO STRICT v_order FROM saly.creative_orders WHERE code='SALY_HOME_BATCH_001';
 SELECT id,acceptance_json INTO STRICT v_item,v_accept FROM saly.creative_order_items
 WHERE order_id=v_order AND code='HOME';
 v_sem:=v_accept->'semantic_qa';
 v_packet:=saly.creative_item_visual_contract_l3b(v_item);
 v_original_sha:=v_sem->>'original_request_sha256';
 v_sem_sha:=encode(extensions.digest(convert_to(v_sem::text,'UTF8'),'sha256'),'hex');
 IF v_packet#>'{contract,acceptance_criteria,semantic_qa}' IS DISTINCT FROM v_sem
 OR jsonb_array_length(v_sem->'original_messages')<>3
 OR jsonb_array_length(v_sem->'checks')<>5
 THEN RAISE EXCEPTION 'SALY_L3C_GENERATION_SEMANTIC_PARITY_FAILED'; END IF;
 v_summary:=saly.creative_order_live_summary_l3b(v_order);
 IF (SELECT count(*) FROM jsonb_array_elements(v_summary->'items') AS i(x)
     WHERE jsonb_typeof(i.x->'semantic_qa')='object'
      AND i.x#>>'{semantic_qa,verdict}'='NOT_EVALUATED'
      AND i.x#>>'{semantic_qa,technical_verdict}'='NOT_EVALUATED')<>2
 OR EXISTS(SELECT 1 FROM saly.creative_order_items
      WHERE order_id=v_order AND code='REWARDS' AND acceptance_json ? 'semantic_qa')
 THEN RAISE EXCEPTION 'SALY_L3C_PREVIEW_SCOPE_INVALID'; END IF;

 v_snapshot:=jsonb_build_object('visual_contract',v_packet->'contract',
   'visual_contract_sha256',v_packet->>'contract_sha256');
 v_output:=jsonb_build_object('artifact_ref','TEST_FIXTURE_ONLY',
    'sha256',repeat('a',64));
 v_receipt:=jsonb_build_object(
    'contract_sha256',v_packet->>'contract_sha256',
    'artifact_ref','TEST_FIXTURE_ONLY','artifact_sha256',repeat('a',64),
    'semantic_qa',jsonb_build_object('verdict','PASS',
      'original_request_sha256',v_original_sha,'semantic_contract_sha256',v_sem_sha,
      'independent_interpretation','TEST_FIXTURE_ONLY',
      'checks',(SELECT jsonb_agg(jsonb_build_object('code',x->>'code','verdict','PASS','evidence','TEST_FIXTURE_ONLY'))
       FROM jsonb_array_elements(v_sem->'checks') AS j(x))),
    'technical_qa',jsonb_build_object('verdict','PASS',
      'checks',(SELECT jsonb_agg(jsonb_build_object('code',x->>'code','verdict','PASS','evidence','TEST_FIXTURE_ONLY'))
       FROM jsonb_array_elements(v_packet#>'{contract,qa_checks}') AS j(x))));
 PERFORM saly.creative_assert_dual_qa_l3c(v_accept,v_receipt,v_snapshot,v_output);

 v_cases:=jsonb_build_array(
  jsonb_build_object('receipt',v_receipt-'semantic_qa','error','CREATIVE_SEMANTIC_REVIEW_MISSING'),
  jsonb_build_object('receipt',v_receipt-'technical_qa','error','CREATIVE_DUAL_QA_NOT_PASS'),
  jsonb_build_object('receipt',jsonb_set(v_receipt,'{semantic_qa,original_request_sha256}',to_jsonb(repeat('b',64))),'error','CREATIVE_SEMANTIC_REVIEW_MISSING'),
  jsonb_build_object('receipt',jsonb_set(v_receipt,'{artifact_sha256}',to_jsonb(repeat('b',64))),'error','CREATIVE_DUAL_QA_ARTIFACT_OR_HASH_MISMATCH'),
  jsonb_build_object('receipt',jsonb_set(v_receipt,'{semantic_qa,verdict}','"FAIL"'::jsonb),'error','CREATIVE_DUAL_QA_NOT_PASS'),
  jsonb_build_object('receipt',jsonb_set(v_receipt,'{semantic_qa,checks,0,verdict}','"FAIL"'::jsonb),'error','CREATIVE_DUAL_QA_CHECK_FAILED_OR_MISSING'),
  jsonb_build_object('receipt',jsonb_set(v_receipt,'{technical_qa,checks,0,evidence}','""'::jsonb),'error','CREATIVE_DUAL_QA_CHECK_FAILED_OR_MISSING')
 );
 FOR v_case IN SELECT value FROM jsonb_array_elements(v_cases) LOOP
   v_rejected:=false;
   v_bad:=v_case->'receipt';
   v_expected_error:=v_case->>'error';
   BEGIN
     PERFORM saly.creative_assert_dual_qa_l3c(v_accept,v_bad,v_snapshot,v_output);
   EXCEPTION WHEN raise_exception THEN
     IF SQLERRM=v_expected_error THEN v_rejected:=true; ELSE RAISE; END IF;
   END;
   IF NOT v_rejected THEN RAISE EXCEPTION 'SALY_L3C_NEGATIVE_TEST_FALSE_PASS'; END IF;
 END LOOP;

 v_rejected:=false;
 BEGIN
   UPDATE saly.creative_order_items SET acceptance_json=acceptance_json-'semantic_qa'
   WHERE id=v_item;
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='CREATIVE_SEMANTIC_CONTRACT_IMMUTABLE'
   THEN v_rejected:=true; ELSE RAISE; END IF;
 END;
 IF NOT v_rejected THEN RAISE EXCEPTION 'SALY_L3C_ORIGINAL_CAN_BE_REMOVED'; END IF;

 IF (SELECT count(*) FROM saly.creative_runs WHERE order_id=v_order)<>0
 OR EXISTS(SELECT 1 FROM saly.creative_order_items WHERE order_id=v_order AND status<>'PENDIENTE')
 OR EXISTS(SELECT 1 FROM saly.creative_order_items WHERE order_id=v_order AND qa_receipt<>'{}'::jsonb)
 THEN RAISE EXCEPTION 'SALY_L3C_UNAUTHORIZED_RUN_OR_APPROVAL'; END IF;
 RAISE NOTICE 'SALY L3C: 1 positive fixture, 7 rejection fixtures, immutability and preview scope verified; no generated image or QA receipt';
END $test$;

COMMIT;
