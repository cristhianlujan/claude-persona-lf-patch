-- SALY Creative Factory F3-A: deterministic LF prompt compiler.
-- No dispatch, no provider call, no image generation and no grants.
BEGIN;

CREATE OR REPLACE FUNCTION saly.creative_lf_prompt_compile_v1(p_item_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','extensions','pg_temp'
AS $function$
DECLARE
  v_item record;
  v_ctx jsonb;
  v_sem jsonb;
  v_literal text;
  v_amendment jsonb;
  v_screen jsonb;
  v_amounts jsonb;
  v_tokens jsonb;
  v_assets jsonb;
  v_inputs jsonb;
  v_inputs_sha text;
  v_prompt text;
  v_prompt_sha text;
  v_assets_ok boolean;
  v_checks jsonb;
  v_sem_keys text[];
  v_interp jsonb;
  v_interp_keys text[];
  v_messages jsonb;
  v_governed_messages jsonb;
  v_sem_sha text;
BEGIN
  SELECT i.id,i.order_id,i.code,i.context_json,i.acceptance_json,
         o.scope_json,o.status AS order_status,p.codigo AS project_code
  INTO v_item
  FROM saly.creative_order_items i
  JOIN saly.creative_orders o ON o.id=i.order_id
  JOIN saly.proyecto p ON p.id=o.project_id
  WHERE i.id=p_item_id;

  IF NOT FOUND OR v_item.project_code IS DISTINCT FROM 'LF' THEN
    RAISE EXCEPTION 'LF_F3A_ITEM_NOT_LF';
  END IF;
  IF v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA') THEN
    RAISE EXCEPTION 'LF_F3A_ORDER_NOT_ADMITTED';
  END IF;

  -- F3-A accepts only the two governed L3C shapes already present in LF history:
  -- canonical USER_LITERAL, or the historical OWNER_LITERAL shape used by the
  -- real Tu oferta intake. Both are validated fail-closed from stored bytes.
  v_sem:=v_item.acceptance_json->'semantic_qa';
  IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_F3A_SEMANTIC_QA_INVALID';
  END IF;
  SELECT array_agg(x ORDER BY x) INTO v_sem_keys FROM jsonb_object_keys(v_sem) x;
  IF v_sem_keys IS DISTINCT FROM ARRAY[
      'checks','interpretation','original_messages','original_request_sha256',
      'require_artifact_evidence','require_independent_interpretation',
      'schema_version','scope','source_type']::text[]
     OR v_sem->>'schema_version' IS DISTINCT FROM 'LF_SEMANTIC_QA_L3C_V1'
     OR jsonb_typeof(v_sem->'scope') IS DISTINCT FROM 'string'
     OR nullif(btrim(v_sem->>'scope'),'') IS NULL
     OR jsonb_typeof(v_sem->'source_type') IS DISTINCT FROM 'string'
     OR nullif(btrim(v_sem->>'source_type'),'') IS NULL
     OR v_sem->'require_artifact_evidence' IS DISTINCT FROM 'true'::jsonb
     OR v_sem->'require_independent_interpretation' IS DISTINCT FROM 'true'::jsonb
  THEN RAISE EXCEPTION 'LF_F3A_SEMANTIC_QA_INVALID'; END IF;

  v_messages:=v_sem->'original_messages';
  IF jsonb_typeof(v_messages) IS DISTINCT FROM 'array' OR jsonb_array_length(v_messages)=0
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_messages) e
       WHERE jsonb_typeof(e) IS DISTINCT FROM 'object'
          OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k)
             IS DISTINCT FROM ARRAY['speaker','text']::text[]
          OR e->>'speaker' IS DISTINCT FROM 'USER'
          OR jsonb_typeof(e->'text') IS DISTINCT FROM 'string'
          OR nullif(btrim(e->>'text'),'') IS NULL)
  THEN RAISE EXCEPTION 'LF_F3A_SEMANTIC_MESSAGES_INVALID'; END IF;

  IF jsonb_typeof(v_item.scope_json->'original_literal_request') IS DISTINCT FROM 'string'
     OR nullif(btrim(v_item.scope_json->>'original_literal_request'),'') IS NULL
  THEN RAISE EXCEPTION 'LF_F3A_ORIGINAL_LITERAL_UNGOVERNED'; END IF;
  v_governed_messages:=jsonb_build_array(jsonb_build_object(
      'text',v_item.scope_json->>'original_literal_request','speaker','USER'));
  IF v_item.scope_json ? 'owner_amendment' THEN
    IF jsonb_typeof(v_item.scope_json#>'{owner_amendment,text}') IS DISTINCT FROM 'string'
       OR nullif(btrim(v_item.scope_json#>>'{owner_amendment,text}'),'') IS NULL
    THEN RAISE EXCEPTION 'LF_F3A_OWNER_AMENDMENT_INVALID'; END IF;
    v_governed_messages:=v_governed_messages || jsonb_build_array(jsonb_build_object(
      'text',v_item.scope_json#>>'{owner_amendment,text}','speaker','USER'));
  END IF;
  IF v_messages IS DISTINCT FROM v_governed_messages THEN
    RAISE EXCEPTION 'LF_F3A_SEMANTIC_MESSAGES_NOT_GOVERNED';
  END IF;
  v_sem_sha:=encode(extensions.digest(convert_to(v_messages::text,'UTF8'),'sha256'),'hex');
  IF v_sem->>'original_request_sha256' IS DISTINCT FROM v_sem_sha THEN
    RAISE EXCEPTION 'LF_F3A_SEMANTIC_ORIGINAL_HASH_MISMATCH';
  END IF;

  IF jsonb_typeof(v_sem->'checks') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_sem->'checks')<>5
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_sem->'checks') e
       WHERE jsonb_typeof(e) IS DISTINCT FROM 'object'
          OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k)
             IS DISTINCT FROM ARRAY['code','expected','severity']::text[]
          OR jsonb_typeof(e->'code') IS DISTINCT FROM 'string'
          OR (e->>'code') !~ '^LF_SEM_[A-Z0-9_]+$'
          OR jsonb_typeof(e->'expected') IS DISTINCT FROM 'string'
          OR nullif(btrim(e->>'expected'),'') IS NULL
          OR e->>'severity' IS DISTINCT FROM 'BLOCK')
     OR (SELECT count(DISTINCT e->>'code') FROM jsonb_array_elements(v_sem->'checks') e)<>5
  THEN RAISE EXCEPTION 'LF_F3A_SEMANTIC_CHECKS_INVALID'; END IF;

  v_interp:=v_sem->'interpretation';
  IF jsonb_typeof(v_interp) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_F3A_SEMANTIC_INTERPRETATION_INVALID';
  END IF;
  SELECT array_agg(x ORDER BY x) INTO v_interp_keys FROM jsonb_object_keys(v_interp) x;
  IF v_interp_keys = ARRAY[
       'change','creative_freedom','evaluation_basis','excluded',
       'interpretation_origin','objective','preserve','screens']::text[] THEN
    PERFORM saly.creative_lf_assert_semantic_qa_v1(v_item.acceptance_json,v_item.scope_json);
  ELSIF v_interp_keys = ARRAY[
       'creative_freedom','excluded','interpretation_origin','objective','preserve']::text[] THEN
    IF v_interp->>'interpretation_origin'
          IS DISTINCT FROM 'ASSISTANT_INTERPRETATION_SEPARATE_FROM_OWNER_LITERAL'
       OR jsonb_typeof(v_interp->'excluded') IS DISTINCT FROM 'array'
       OR jsonb_array_length(v_interp->'excluded')=0
       OR jsonb_typeof(v_interp->'preserve') IS DISTINCT FROM 'array'
       OR jsonb_array_length(v_interp->'preserve')=0
       OR jsonb_typeof(v_interp->'creative_freedom') IS DISTINCT FROM 'string'
       OR nullif(btrim(v_interp->>'creative_freedom'),'') IS NULL
       OR jsonb_typeof(v_interp->'objective') IS DISTINCT FROM 'string'
       OR nullif(btrim(v_interp->>'objective'),'') IS NULL
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_interp->'excluded') e
                  WHERE jsonb_typeof(e) IS DISTINCT FROM 'string' OR nullif(btrim(e#>>'{}'),'') IS NULL)
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_interp->'preserve') e
                  WHERE jsonb_typeof(e) IS DISTINCT FROM 'string' OR nullif(btrim(e#>>'{}'),'') IS NULL)
    THEN RAISE EXCEPTION 'LF_F3A_LEGACY_SEMANTIC_INTERPRETATION_INVALID'; END IF;
  ELSE
    RAISE EXCEPTION 'LF_F3A_SEMANTIC_INTERPRETATION_KEYS_INVALID';
  END IF;

  v_ctx:=saly.creative_lf_item_context_v1(p_item_id);
  v_literal:=COALESCE(NULLIF(btrim(v_item.scope_json->>'literal_request'),''),
                      NULLIF(btrim(v_item.scope_json->>'original_literal_request'),''));
  v_amendment:=COALESCE(v_item.scope_json->'owner_amendment','null'::jsonb);
  v_screen:=v_item.context_json->'screen_spec';
  v_amounts:=COALESCE(v_item.context_json->'authorized_sample_amounts','{}'::jsonb);
  v_tokens:=COALESCE(v_ctx->'tokens','[]'::jsonb);
  v_assets:=COALESCE(v_ctx->'source_refs','[]'::jsonb);

  IF v_literal IS NULL THEN RAISE EXCEPTION 'LF_F3A_LITERAL_MISSING'; END IF;
  IF jsonb_typeof(v_screen) IS DISTINCT FROM 'object'
     OR COALESCE((v_screen->>'width')::int,0)<=0
     OR COALESCE((v_screen->>'height')::int,0)<=0
     OR NULLIF(btrim(v_screen->>'screen'),'') IS NULL
  THEN RAISE EXCEPTION 'LF_F3A_SCREEN_SPEC_INVALID'; END IF;
  IF jsonb_typeof(v_tokens) IS DISTINCT FROM 'array' OR jsonb_array_length(v_tokens)=0
  THEN RAISE EXCEPTION 'LF_F3A_IDENTITY_CONTEXT_EMPTY'; END IF;
  IF jsonb_typeof(v_assets) IS DISTINCT FROM 'array'
  THEN RAISE EXCEPTION 'LF_F3A_ASSET_MANIFEST_INVALID'; END IF;

  SELECT COALESCE(bool_and(
           jsonb_typeof(a)='object'
           AND COALESCE(a->>'checksum_sha256','') ~ '^[0-9a-f]{64}$'
           AND NULLIF(btrim(a->>'asset_code'),'') IS NOT NULL
           AND NULLIF(btrim(a->>'storage_provider'),'') IS NOT NULL
           AND NULLIF(btrim(a->>'storage_object_path'),'') IS NOT NULL
         ),true)
  INTO v_assets_ok
  FROM jsonb_array_elements(v_assets) a;
  IF NOT v_assets_ok THEN RAISE EXCEPTION 'LF_F3A_ASSET_MANIFEST_INVALID'; END IF;

  v_inputs:=jsonb_build_object(
    'schema_version','LF_PROMPT_INPUT_F3A_V1',
    'order_id',v_item.order_id,
    'item_id',v_item.id,
    'item_code',v_item.code,
    'literal_request',v_literal,
    'owner_amendment',v_amendment,
    'screen_spec',v_screen,
    'authorized_sample_amounts',v_amounts,
    'semantic_qa',v_sem,
    'identity_tokens',v_tokens,
    'frozen_assets',v_assets
  );
  v_inputs_sha:=encode(extensions.digest(convert_to(v_inputs::text,'UTF8'),'sha256'),'hex');

  v_prompt:=
    'SalyNativeInput::F3A_PROMPT_V1' || E'\n' ||
    '[OWNER_LITERAL]' || E'\n' || v_literal || E'\n' ||
    '[OWNER_AMENDMENT]' || E'\n' || v_amendment::text || E'\n' ||
    '[SCREEN_SPEC]' || E'\n' || v_screen::text || E'\n' ||
    '[AUTHORIZED_SAMPLE_AMOUNTS]' || E'\n' || v_amounts::text || E'\n' ||
    '[SEMANTIC_QA]' || E'\n' || v_sem::text || E'\n' ||
    '[LF_IDENTITY_TOKENS]' || E'\n' || v_tokens::text || E'\n' ||
    '[FROZEN_ASSETS]' || E'\n' || v_assets::text || E'\n' ||
    '[NON_NEGOTIABLE]' || E'\n' ||
    'Preserve the owner literal and governed semantic meaning exactly. ' ||
    'Do not invent amounts, messages, actions, assets, tokens or scope. ' ||
    'Use only the supplied screen specification, identity tokens and frozen assets. ' ||
    'Do not reinterpret the owner literal. Evidence and provider execution are outside F3-A.';

  v_prompt_sha:=encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex');

  IF position(v_literal in v_prompt)=0 THEN RAISE EXCEPTION 'LF_F3A_LITERAL_NOT_EMBEDDED'; END IF;
  IF position(v_sem::text in v_prompt)=0 THEN RAISE EXCEPTION 'LF_F3A_SEMANTIC_QA_NOT_EMBEDDED'; END IF;
  IF position(v_screen::text in v_prompt)=0 THEN RAISE EXCEPTION 'LF_F3A_SCREEN_NOT_EMBEDDED'; END IF;
  IF jsonb_array_length(v_assets)>0 AND position(v_assets::text in v_prompt)=0
  THEN RAISE EXCEPTION 'LF_F3A_ASSETS_NOT_EMBEDDED'; END IF;
  IF v_amounts<>'{}'::jsonb AND position(v_amounts::text in v_prompt)=0
  THEN RAISE EXCEPTION 'LF_F3A_AMOUNTS_NOT_EMBEDDED'; END IF;

  v_checks:=jsonb_build_array(
    jsonb_build_object('code','F3A-01','verdict','PASS','evidence','owner literal embedded byte-for-byte'),
    jsonb_build_object('code','F3A-02','verdict','PASS','evidence','authorized amount object embedded without reinterpretation'),
    jsonb_build_object('code','F3A-03','verdict','PASS','evidence','five governed semantic checks embedded'),
    jsonb_build_object('code','F3A-04','verdict','PASS','evidence','owner messages and amendment remain inside semantic authority'),
    jsonb_build_object('code','F3A-05','verdict','PASS','evidence','screen specification frozen in prompt'),
    jsonb_build_object('code','F3A-06','verdict','PASS','evidence','LF identity token manifest nonempty and embedded'),
    jsonb_build_object('code','F3A-07','verdict','PASS','evidence','requested asset refs are checksum verified and embedded'),
    jsonb_build_object('code','F3A-08','verdict','PASS','evidence','preserve/excluded semantic constraints embedded'),
    jsonb_build_object('code','F3A-09','verdict','PASS','evidence','compiled prompt has canonical SHA256'),
    jsonb_build_object('code','F3A-10','verdict','PASS','evidence','compiler is read-only and returns governed inputs SHA256')
  );

  RETURN jsonb_build_object(
    'schema_version','LF_PROMPT_COMPILE_F3A_V1',
    'business_code','LF',
    'order_id',v_item.order_id,
    'item_id',v_item.id,
    'prompt_text',v_prompt,
    'prompt_sha256',v_prompt_sha,
    'inputs_sha256',v_inputs_sha,
    'qa_score','10/10',
    'qa_checks',v_checks,
    'ready_for_independent_review',true,
    'prompt_sealed',false,
    'native_transmitted',false
  );
END
$function$;

REVOKE ALL ON FUNCTION saly.creative_lf_prompt_compile_v1(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_prompt_compile_v1(bigint) FROM anon, authenticated, service_role;

COMMENT ON FUNCTION saly.creative_lf_prompt_compile_v1(bigint) IS
'F3-A LF deterministic prompt compiler. Read-only: literal + semantic QA + sealed LF context -> prompt text/hash + 10/10 compile QA. Does not seal, dispatch or call a provider.';

DO $qa$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='saly' AND p.proname='creative_lf_prompt_compile_v1'
    AND pg_get_function_identity_arguments(p.oid)='p_item_id bigint';

  IF v_def IS NULL THEN RAISE EXCEPTION 'LF_F3A_COMPILER_NOT_CREATED'; END IF;
  IF has_function_privilege('anon','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
     OR has_function_privilege('authenticated','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
     OR has_function_privilege('service_role','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'LF_F3A_COMPILER_ACL_TOO_BROAD'; END IF;
  RAISE NOTICE 'LF_F3A_COMPILER_MIGRATION|PASS';
END
$qa$;

COMMIT;
