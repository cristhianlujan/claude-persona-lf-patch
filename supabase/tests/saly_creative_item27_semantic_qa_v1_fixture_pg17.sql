\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS saly CASCADE;
DROP SCHEMA IF EXISTS extensions CASCADE;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA saly;

CREATE TABLE saly.creative_orders(
  id bigint PRIMARY KEY,
  project_id bigint NOT NULL,
  code text NOT NULL,
  status text NOT NULL,
  scope_json jsonb NOT NULL
);
CREATE TABLE saly.creative_order_items(
  id bigint PRIMARY KEY,
  order_id bigint NOT NULL,
  code text NOT NULL,
  status text NOT NULL,
  acceptance_json jsonb NOT NULL
);

INSERT INTO saly.creative_orders(id,project_id,code,status,scope_json)
VALUES (
  23,3,'LF_TU_OFERTA_V1_20261126','EN_PROCESO',
  jsonb_build_object(
    'original_literal_request',$q$Pantalla de app móvil (390 x 844) de Libertad Financiera, plataforma peruana de negociación de deuda castigada. Pantalla Tu oferta: título Tu oferta; la cuota mensual como elemento visualmente dominante (marcadores literales S/ [CUOTA], por [N] meses, total S/ [TOTAL]; no inventar cifras) y el total con menos peso; explicación visual del traslado de la deuda de BBVA a Finanty con la frase Tu deuda de BBVA pasa a Finanty; la carta de no adeudo como algo tangible y visible antes del botón, con el texto Te la entregamos al cerrar tu deuda; botón principal con el texto exacto Cerrar mi deuda y recibir mi carta ahora.$q$,
    'literal_request',$q$Pantalla de app móvil (390 x 844) de Libertad Financiera, plataforma peruana de negociación de deuda castigada. Pantalla Tu oferta: título Tu oferta; la cuota mensual como elemento visualmente dominante (cifras de muestra autorizadas: S/ 189.00, por 12 meses, total S/ 2,268.00; no añadir otras cifras; no son datos de cliente) y el total con menos peso; explicación visual del traslado de la deuda de BBVA a Finanty con la frase Tu deuda de BBVA pasa a Finanty; la carta de no adeudo como algo tangible y visible antes del botón, con el texto Te la entregamos al cerrar tu deuda; botón principal con el texto exacto Cerrar mi deuda y recibir mi carta ahora.$q$,
    'owner_amendment',jsonb_build_object('at','2026-11-26T23:45:00-05:00','text','Los montos deben ser reales no texto','illustrative',true)
  )
);
INSERT INTO saly.creative_order_items(id,order_id,code,status,acceptance_json)
VALUES (27,23,'TU_OFERTA','PRODUCIENDO',
  '{"qa_required":true,"qa_checklist":{"cta_exact":true,"lf_identity":true,"debt_transfer":true,"literal_fidelity":true,"monthly_payment_dominant":true,"letter_visible_before_cta":true,"authorized_sample_amounts_exact":true}}'::jsonb
);

DO $fixture$
BEGIN
 IF encode(extensions.digest(convert_to((SELECT acceptance_json FROM saly.creative_order_items WHERE id=27)::text,'UTF8'),'sha256'),'hex')
      IS DISTINCT FROM '428435754a4ba4128d10eeadad6eb29632e054e2618d7b1cd911271cd906532c'
 THEN RAISE EXCEPTION 'PR3_FIXTURE_ACCEPTANCE_HASH_DRIFT'; END IF;
 IF encode(extensions.digest(convert_to(jsonb_build_array(
      jsonb_build_object('text',(SELECT scope_json->>'original_literal_request' FROM saly.creative_orders WHERE id=23),'speaker','USER'),
      jsonb_build_object('text',(SELECT scope_json#>>'{owner_amendment,text}' FROM saly.creative_orders WHERE id=23),'speaker','USER')
    )::text,'UTF8'),'sha256'),'hex')
      IS DISTINCT FROM '78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40'
 THEN RAISE EXCEPTION 'PR3_FIXTURE_MESSAGES_HASH_DRIFT'; END IF;
END
$fixture$;
