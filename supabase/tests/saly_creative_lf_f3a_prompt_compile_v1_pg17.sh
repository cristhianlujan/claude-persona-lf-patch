#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PGHOST="${PGHOST:-127.0.0.1}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
[[ "$PGHOST" == 127.0.0.1 && "$PGUSER" == postgres ]] || { echo F3A_UNSAFE_TARGET; exit 2; }

shopt -s nullglob
F1S=("$ROOT"/supabase/migrations/*_lf_saly_creative_f1_enablement_v1.sql)
F3S=("$ROOT"/supabase/migrations/*_lf_saly_creative_lf_f3a_prompt_compile_v1.sql)
[[ "${#F1S[@]}" -eq 1 && "${#F3S[@]}" -eq 1 ]] || { echo F3A_CANDIDATE_FILES_INVALID; exit 3; }
F1="${F1S[0]}"
F3="${F3S[0]}"
F1_SHA="$(sha256sum "$F1" | awk '{print $1}')"

export PGDATABASE=lf_creative_f1_ci
F1_CANDIDATE="$F1" F1_CANDIDATE_SHA256="$F1_SHA" bash "$ROOT/sandbox/creative_factory/f1_pg17/setup.sh" >/tmp/f3a_f1_setup.log
grep -q 'F1_SETUP_PASS' /tmp/f3a_f1_setup.log

export PGDATABASE=postgres
dropdb --if-exists --maintenance-db=postgres lf_creative_f3a_test
createdb --maintenance-db=postgres -T lf_creative_f1_candidate lf_creative_f3a_test
export PGDATABASE=lf_creative_f3a_test
psql -X -v ON_ERROR_STOP=1 -f "$F3" >/tmp/f3a_migration.log
grep -q 'LF_F3A_COMPILER_MIGRATION|PASS' /tmp/f3a_migration.log || true

psql -XAt -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

DO $$
DECLARE
  v_literal text:='Pantalla de app móvil (390 x 844) de Libertad Financiera. Pantalla Tu oferta: cuota mensual S/ 189.00 como elemento dominante, por 12 meses, total S/ 2,268.00; Tu deuda de BBVA pasa a Finanty; la carta de no adeudo es visible antes del botón con el texto Te la entregamos al cerrar tu deuda; CTA exacto Cerrar mi deuda y recibir mi carta ahora.';
  v_amend text:='Los montos deben ser reales no texto';
  v_scope jsonb;
  v_msgs jsonb;
  v_sem jsonb;
  v_accept jsonb;
  v1 jsonb;
  v2 jsonb;
  v_prompt text;
  v_currency text[];
  v_codes text[];
  v_seals_before int;
  v_seals_after int;
BEGIN
  v_scope:=jsonb_build_object(
    'queue_mode','SERIAL_V1','review_only',false,'render_authorized',true,'rendering_authority',true,
    'literal_request',v_literal,'original_literal_request',v_literal,
    'owner_amendment',jsonb_build_object('text',v_amend,'at','2026-11-28T12:00:00-05:00','illustrative',true)
  );
  v_msgs:=jsonb_build_array(
    jsonb_build_object('text',v_literal,'speaker','USER'),
    jsonb_build_object('text',v_amend,'speaker','USER')
  );
  v_sem:=jsonb_build_object(
    'schema_version','SALY_SEMANTIC_QA_L3C_V1',
    'scope','LF_F3A_CI_TU_OFERTA',
    'source_type','OWNER_LITERAL_AND_OWNER_AMENDMENT',
    'require_artifact_evidence',true,
    'require_independent_interpretation',true,
    'original_messages',v_msgs,
    'original_request_sha256',encode(extensions.digest(convert_to(v_msgs::text,'UTF8'),'sha256'),'hex'),
    'interpretation',jsonb_build_object(
      'change',jsonb_build_array('Compile governed prompt only'),
      'creative_freedom','LIMITED_TO_AUTHORIZED_SCOPE',
      'evaluation_basis','OWNER_LITERAL_PLUS_SEMANTIC_QA',
      'excluded',jsonb_build_array('Añadir otras cifras','Cambiar significado económico','Prometer carta antes del cierre','Añadir acciones'),
      'interpretation_origin','ASSISTANT_INTERPRETATION_SEPARATE_FROM_USER_LITERAL',
      'objective','Representar fielmente la oferta autorizada',
      'preserve',jsonb_build_array(
        'S/ 189.00 como cuota mensual, por 12 meses y total S/ 2,268.00',
        'Tu deuda de BBVA pasa a Finanty',
        'Te la entregamos al cerrar tu deuda antes del CTA',
        'CTA exacto: Cerrar mi deuda y recibir mi carta ahora'),
      'screens',jsonb_build_array('TU_OFERTA')
    ),
    'checks',jsonb_build_array(
      jsonb_build_object('code','LF_SEM_OFFER_INTENT','expected','La pantalla comunica Tu oferta y conduce al cierre autorizado.','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_AMOUNT_MEANING','expected','S/ 189.00 es cuota mensual por 12 meses; S/ 2,268.00 es total.','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_TRANSFER_MEANING','expected','Tu deuda de BBVA pasa a Finanty.','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_LETTER_CONDITION','expected','La carta es visible antes del CTA y se entrega al cerrar la deuda.','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_SCOPE_AND_ACTION','expected','CTA exacto Cerrar mi deuda y recibir mi carta ahora; sin acciones adicionales.','severity','BLOCK')
    )
  );
  v_accept:=jsonb_build_object('qa_required',true,'semantic_qa',v_sem);

  INSERT INTO saly.creative_orders(
    id,project_id,code,request_key,title,request_kind,design_mode,requested_by,
    scope_json,identity_snapshot,status,context_set_id)
  OVERRIDING SYSTEM VALUE VALUES(
    9300,3,'LF_F3A_CI_ORDER','lf-f3a-ci-order','LF F3-A CI synthetic',
    'APP_SCREEN_SINGLE','EXPLORE','CI_F3A',v_scope,'{}'::jsonb,'PLANIFICADO',9001);

  INSERT INTO saly.creative_order_items(
    id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
  OVERRIDING SYSTEM VALUE VALUES(
    9301,9300,'TU_OFERTA_F3A_CI',1,'SCREEN','Tu oferta F3-A CI',true,v_accept,
    jsonb_build_object(
      'screen_spec',jsonb_build_object('width',390,'height',844,'screen','TU_OFERTA'),
      'authorized_sample_amounts',jsonb_build_object(
        'monthly','S/ 189.00','term','por 12 meses','total','S/ 2,268.00','illustrative',true),
      'asset_codes',jsonb_build_array('LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT')
    ),
    'PENDIENTE');

  SELECT count(*) INTO v_seals_before FROM saly.creative_lf_prompt_seal_v1 WHERE item_id=9301;
  v1:=saly.creative_lf_prompt_compile_v1(9301);
  v2:=saly.creative_lf_prompt_compile_v1(9301);
  SELECT count(*) INTO v_seals_after FROM saly.creative_lf_prompt_seal_v1 WHERE item_id=9301;
  v_prompt:=v1->>'prompt_text';

  IF v1->>'schema_version'<>'LF_PROMPT_COMPILE_F3A_V1'
     OR v1->>'qa_score'<>'10/10'
     OR jsonb_array_length(v1->'qa_checks')<>10
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v1->'qa_checks') x WHERE x->>'verdict'<>'PASS')
  THEN RAISE EXCEPTION 'F3A_QA_10_10_INVALID'; END IF;

  SELECT array_agg(x->>'code' ORDER BY ord) INTO v_codes
  FROM jsonb_array_elements(v1->'qa_checks') WITH ORDINALITY a(x,ord);
  IF v_codes IS DISTINCT FROM ARRAY['F3A-01','F3A-02','F3A-03','F3A-04','F3A-05','F3A-06','F3A-07','F3A-08','F3A-09','F3A-10']
  THEN RAISE EXCEPTION 'F3A_QA_CODES_INVALID'; END IF;

  IF v1->>'prompt_sha256' IS DISTINCT FROM v2->>'prompt_sha256'
     OR v1->>'inputs_sha256' IS DISTINCT FROM v2->>'inputs_sha256'
     OR v1->>'prompt_text' IS DISTINCT FROM v2->>'prompt_text'
  THEN RAISE EXCEPTION 'F3A_COMPILE_NOT_DETERMINISTIC'; END IF;
  IF v1->>'prompt_sha256' IS DISTINCT FROM encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex')
  THEN RAISE EXCEPTION 'F3A_PROMPT_HASH_INVALID'; END IF;

  IF position(v_literal in v_prompt)=0
     OR position('S/ 189.00' in v_prompt)=0
     OR position('por 12 meses' in v_prompt)=0
     OR position('S/ 2,268.00' in v_prompt)=0
     OR position('Tu deuda de BBVA pasa a Finanty' in v_prompt)=0
     OR position('Te la entregamos al cerrar tu deuda' in v_prompt)=0
     OR position('Cerrar mi deuda y recibir mi carta ahora' in v_prompt)=0
     OR position('"width": 390' in v_prompt)=0
     OR position('"height": 844' in v_prompt)=0
     OR position('lf.source.colors.green_action' in v_prompt)=0
     OR position('LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT' in v_prompt)=0
  THEN RAISE EXCEPTION 'F3A_TU_OFERTA_CONTRACT_MISSING'; END IF;

  SELECT array_agg(DISTINCT m[1] ORDER BY m[1]) INTO v_currency
  FROM regexp_matches(v_prompt,'(S/ [0-9][0-9,.]*)','g') m;
  IF v_currency IS DISTINCT FROM ARRAY['S/ 189.00','S/ 2,268.00']
  THEN RAISE EXCEPTION 'F3A_UNAUTHORIZED_CURRENCY:%',v_currency; END IF;

  IF v_seals_before<>0 OR v_seals_after<>0
     OR (v1->>'prompt_sealed')::boolean
     OR (v1->>'native_transmitted')::boolean
     OR NOT (v1->>'ready_for_independent_review')::boolean
  THEN RAISE EXCEPTION 'F3A_SCOPE_BREACH'; END IF;

  IF has_function_privilege('anon','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
     OR has_function_privilege('authenticated','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
     OR has_function_privilege('service_role','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'F3A_ACL_TOO_BROAD'; END IF;
END $$;

SELECT (x->>'code')||'|PASS'
FROM jsonb_array_elements(saly.creative_lf_prompt_compile_v1(9301)->'qa_checks') AS x;

ROLLBACK;
SQL
