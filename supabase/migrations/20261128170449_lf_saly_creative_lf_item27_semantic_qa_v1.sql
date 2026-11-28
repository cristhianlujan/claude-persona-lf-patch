-- LF Tu oferta item 27: semantic QA contract only. No claim/status/grant changes.
BEGIN;

DO $pre$
DECLARE
  v_acceptance jsonb;
  v_scope jsonb;
  v_order_code text;
  v_order_status text;
  v_item_status text;
  v_messages jsonb;
  v_sha text;
BEGIN
  SELECT i.acceptance_json,o.scope_json,o.code,o.status,i.status
  INTO STRICT v_acceptance,v_scope,v_order_code,v_order_status,v_item_status
  FROM saly.creative_order_items i
  JOIN saly.creative_orders o ON o.id=i.order_id
  WHERE i.id=27 AND i.order_id=23 AND i.code='TU_OFERTA';

  IF v_order_code IS DISTINCT FROM 'LF_TU_OFERTA_V1_20261126'
     OR v_order_status IS DISTINCT FROM 'EN_PROCESO'
     OR v_item_status IS DISTINCT FROM 'PRODUCIENDO'
  THEN RAISE EXCEPTION 'LF_SEM_ITEM27_STATE_DRIFT'; END IF;

  v_sha:=encode(extensions.digest(convert_to(v_acceptance::text,'UTF8'),'sha256'),'hex');
  IF v_sha IS DISTINCT FROM '428435754a4ba4128d10eeadad6eb29632e054e2618d7b1cd911271cd906532c'
     OR v_acceptance ? 'semantic_qa'
  THEN RAISE EXCEPTION 'LF_SEM_ITEM27_ACCEPTANCE_DRIFT'; END IF;

  IF encode(extensions.digest(convert_to(v_scope->>'literal_request','UTF8'),'sha256'),'hex')
       IS DISTINCT FROM 'd6c44a55b386ff5fff4863b24466a74ec833ee9743367e80191bec862c7245f7'
  THEN RAISE EXCEPTION 'LF_SEM_CURRENT_LITERAL_DRIFT'; END IF;

  v_messages:=jsonb_build_array(
    jsonb_build_object('text',v_scope->>'original_literal_request','speaker','USER'),
    jsonb_build_object('text',v_scope#>>'{owner_amendment,text}','speaker','USER')
  );
  v_sha:=encode(extensions.digest(convert_to(v_messages::text,'UTF8'),'sha256'),'hex');
  IF v_sha IS DISTINCT FROM '78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40'
  THEN RAISE EXCEPTION 'LF_SEM_ORIGINAL_MESSAGES_HASH_DRIFT'; END IF;
END
$pre$;

WITH source AS (
  SELECT o.scope_json
  FROM saly.creative_orders o
  WHERE o.id=23 AND o.code='LF_TU_OFERTA_V1_20261126'
), semantic AS (
  SELECT jsonb_build_object(
    'scope','LF_TU_OFERTA_V1_20261126',
    'source_type','OWNER_LITERAL_AND_OWNER_AMENDMENT',
    'schema_version','LF_SEMANTIC_QA_L3C_V1',
    'original_messages',jsonb_build_array(
      jsonb_build_object('text',scope_json->>'original_literal_request','speaker','USER'),
      jsonb_build_object('text',scope_json#>>'{owner_amendment,text}','speaker','USER')
    ),
    'original_request_sha256','78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40',
    'interpretation',jsonb_build_object(
      'objective','Representar fielmente la oferta autorizada para cerrar la deuda y recibir la carta, sin cambiar el significado económico ni la acción.',
      'preserve',jsonb_build_array(
        'S/ 189.00 como cuota mensual, por 12 meses y total S/ 2,268.00',
        'Tu deuda de BBVA pasa a Finanty',
        'Te la entregamos al cerrar tu deuda antes del CTA',
        'CTA exacto: Cerrar mi deuda y recibir mi carta ahora'
      ),
      'excluded',jsonb_build_array(
        'Añadir otras cifras',
        'Cambiar el significado de cuota, plazo o total',
        'Prometer la carta antes de cerrar la deuda',
        'Añadir acciones o alcance no solicitados'
      ),
      'creative_freedom','LIMITED_TO_AUTHORIZED_SCOPE',
      'interpretation_origin','ASSISTANT_INTERPRETATION_SEPARATE_FROM_OWNER_LITERAL'
    ),
    'checks',jsonb_build_array(
      jsonb_build_object('code','LF_SEM_OFFER_INTENT','severity','BLOCK',
        'expected','La pantalla comunica la oferta Tu oferta y conduce a cerrar la deuda mediante la acción autorizada.'),
      jsonb_build_object('code','LF_SEM_AMOUNT_MEANING','severity','BLOCK',
        'expected','S/ 189.00 es la cuota mensual, por 12 meses; S/ 2,268.00 es el total. No se añaden otras cifras ni se intercambia su significado.'),
      jsonb_build_object('code','LF_SEM_TRANSFER_MEANING','severity','BLOCK',
        'expected','Debe conservarse el significado literal: Tu deuda de BBVA pasa a Finanty.'),
      jsonb_build_object('code','LF_SEM_LETTER_CONDITION','severity','BLOCK',
        'expected','La carta de no adeudo es visible antes del CTA y se entrega al cerrar la deuda; no se promete antes de esa condición.'),
      jsonb_build_object('code','LF_SEM_SCOPE_AND_ACTION','severity','BLOCK',
        'expected','El alcance sigue siendo la pantalla Tu oferta y el CTA exacto es Cerrar mi deuda y recibir mi carta ahora, sin acciones adicionales.')
    ),
    'require_artifact_evidence',true,
    'require_independent_interpretation',true
  ) AS contract
  FROM source
)
UPDATE saly.creative_order_items i
SET acceptance_json=i.acceptance_json||jsonb_build_object('semantic_qa',semantic.contract)
FROM semantic
WHERE i.id=27 AND i.order_id=23 AND i.code='TU_OFERTA';

DO $post$
DECLARE
  v_acceptance jsonb;
  v_sem jsonb;
  v_codes text[];
  v_sha text;
BEGIN
  SELECT acceptance_json INTO STRICT v_acceptance
  FROM saly.creative_order_items
  WHERE id=27 AND order_id=23 AND code='TU_OFERTA' AND status='PRODUCIENDO';

  v_sem:=v_acceptance->'semantic_qa';
  IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object'
     OR jsonb_typeof(v_sem->'original_messages') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_sem->'original_messages')<>2
     OR jsonb_typeof(v_sem->'interpretation') IS DISTINCT FROM 'object'
     OR jsonb_typeof(v_sem->'checks') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_sem->'checks')<>5
  THEN RAISE EXCEPTION 'LF_SEM_CONTRACT_SHAPE_INVALID'; END IF;

  v_sha:=encode(extensions.digest(convert_to((v_sem->'original_messages')::text,'UTF8'),'sha256'),'hex');
  IF v_sha IS DISTINCT FROM '78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40'
     OR v_sem->>'original_request_sha256' IS DISTINCT FROM v_sha
  THEN RAISE EXCEPTION 'LF_SEM_CONTRACT_HASH_INVALID'; END IF;

  SELECT array_agg(x->>'code' ORDER BY x->>'code') INTO v_codes
  FROM jsonb_array_elements(v_sem->'checks') x;
  IF v_codes IS DISTINCT FROM ARRAY[
    'LF_SEM_AMOUNT_MEANING',
    'LF_SEM_LETTER_CONDITION',
    'LF_SEM_OFFER_INTENT',
    'LF_SEM_SCOPE_AND_ACTION',
    'LF_SEM_TRANSFER_MEANING'
  ]::text[]
  THEN RAISE EXCEPTION 'LF_SEM_CHECK_CODES_INVALID'; END IF;

  IF encode(extensions.digest(convert_to((v_acceptance-'semantic_qa')::text,'UTF8'),'sha256'),'hex')
       IS DISTINCT FROM '428435754a4ba4128d10eeadad6eb29632e054e2618d7b1cd911271cd906532c'
  THEN RAISE EXCEPTION 'LF_SEM_PREVIOUS_ACCEPTANCE_CHANGED'; END IF;
END
$post$;

COMMIT;
