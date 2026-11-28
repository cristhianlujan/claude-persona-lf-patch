-- PR2 F1 LF enablement: UNA migracion consolidada (una definicion por funcion). Generada desde candidato local sub2 y verificada contra base (sub).
BEGIN;
INSERT INTO saly.config_global(scope,config_key,config_value,value_type,value_status,description,valid_from)
SELECT 'CREATIVE_FACTORY_LF','EXECUTION_WINDOW_SECONDS','86400','INTEGER','REAL','LF native render window (claim lease and RUN deadline) from owner-authorized LF test lease',now()
WHERE NOT EXISTS (SELECT 1 FROM saly.config_global WHERE scope='CREATIVE_FACTORY_LF' AND config_key='EXECUTION_WINDOW_SECONDS');
INSERT INTO saly.config_global(scope,config_key,config_value,value_type,value_status,description,valid_from)
SELECT 'CREATIVE_FACTORY_LF','PROMPT_SEAL_AGENT_REFS','["GPT_NATIVE","CLAUDE_NATIVE"]','JSON','REAL','Governed agent references allowed as author/reviewer of an LF prompt seal (must differ)',now()
WHERE NOT EXISTS (SELECT 1 FROM saly.config_global WHERE scope='CREATIVE_FACTORY_LF' AND config_key='PROMPT_SEAL_AGENT_REFS');

\restrict SNgn8g2yJekF9aVNHQB4d0Yj6eNuG2Jx35VxFJp5IHd5u2dIlEJK6k8Wh28u1a2






CREATE TABLE IF NOT EXISTS saly.creative_lf_prompt_seal_v1 (
    id bigint NOT NULL,
    order_id bigint NOT NULL,
    item_id bigint NOT NULL,
    prompt_utf8 text NOT NULL,
    prompt_sha256 text NOT NULL,
    literal_sha256 text NOT NULL,
    context_sha256 text NOT NULL,
    author_ref text NOT NULL,
    reviewer_ref text NOT NULL,
    review_json jsonb NOT NULL,
    sealed_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT creative_lf_prompt_seal_v1_author_ref_check CHECK ((NULLIF(btrim(author_ref), ''::text) IS NOT NULL)),
    CONSTRAINT creative_lf_prompt_seal_v1_check CHECK ((lower(btrim(author_ref)) <> lower(btrim(reviewer_ref)))),
    CONSTRAINT creative_lf_prompt_seal_v1_context_sha256_check CHECK ((context_sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT creative_lf_prompt_seal_v1_literal_sha256_check CHECK ((literal_sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT creative_lf_prompt_seal_v1_prompt_sha256_check CHECK ((prompt_sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT creative_lf_prompt_seal_v1_prompt_utf8_check CHECK ((NULLIF(btrim(prompt_utf8), ''::text) IS NOT NULL)),
    CONSTRAINT creative_lf_prompt_seal_v1_review_json_check CHECK ((jsonb_typeof(review_json) = 'object'::text)),
    CONSTRAINT creative_lf_prompt_seal_v1_reviewer_ref_check CHECK ((NULLIF(btrim(reviewer_ref), ''::text) IS NOT NULL))
);

ALTER TABLE ONLY saly.creative_lf_prompt_seal_v1 FORCE ROW LEVEL SECURITY;



ALTER TABLE saly.creative_lf_prompt_seal_v1 ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME saly.creative_lf_prompt_seal_v1_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY saly.creative_lf_prompt_seal_v1
    ADD CONSTRAINT creative_lf_prompt_seal_v1_item_id_prompt_sha256_literal_sh_key UNIQUE (item_id, prompt_sha256, literal_sha256, context_sha256);



ALTER TABLE ONLY saly.creative_lf_prompt_seal_v1
    ADD CONSTRAINT creative_lf_prompt_seal_v1_pkey PRIMARY KEY (id);









ALTER TABLE ONLY saly.creative_lf_prompt_seal_v1
    ADD CONSTRAINT creative_lf_prompt_seal_v1_item_id_fkey FOREIGN KEY (item_id) REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT;



ALTER TABLE ONLY saly.creative_lf_prompt_seal_v1
    ADD CONSTRAINT creative_lf_prompt_seal_v1_order_id_fkey FOREIGN KEY (order_id) REFERENCES saly.creative_orders(id) ON DELETE RESTRICT;



ALTER TABLE saly.creative_lf_prompt_seal_v1 ENABLE ROW LEVEL SECURITY;


\unrestrict SNgn8g2yJekF9aVNHQB4d0Yj6eNuG2Jx35VxFJp5IHd5u2dIlEJK6k8Wh28u1a2

CREATE OR REPLACE FUNCTION saly.creative_lf_assert_semantic_qa_v1(p_acceptance jsonb, p_scope jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'extensions', 'pg_temp'
AS $function$
DECLARE s jsonb; i jsonb; k text; m jsonb; c jsonb; v_codes text[]; v_sha text; v_gov jsonb;
 v_keys text[]:=ARRAY['checks','interpretation','original_messages','original_request_sha256','require_artifact_evidence','require_independent_interpretation','schema_version','scope','source_type'];
 v_ikeys text[]:=ARRAY['change','creative_freedom','evaluation_basis','excluded','interpretation_origin','objective','preserve','screens'];
BEGIN
 s:=p_acceptance->'semantic_qa';
 IF jsonb_typeof(s) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_NOT_DEVELOPED'; END IF;
 IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(s) x) IS DISTINCT FROM v_keys THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_KEYS_INVALID'; END IF;
 IF s->>'schema_version' IS DISTINCT FROM 'SALY_SEMANTIC_QA_L3C_V1' THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_SCHEMA_VERSION'; END IF;
 FOREACH k IN ARRAY ARRAY['scope','source_type'] LOOP
   IF jsonb_typeof(s->k) IS DISTINCT FROM 'string' OR nullif(btrim(s->>k),'') IS NULL THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_FIELD_INVALID'; END IF;
 END LOOP;
 IF s->'require_artifact_evidence' IS DISTINCT FROM 'true'::jsonb OR s->'require_independent_interpretation' IS DISTINCT FROM 'true'::jsonb
 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_EVIDENCE_FLAGS'; END IF;
 m:=s->'original_messages';
 IF jsonb_typeof(m) IS DISTINCT FROM 'array' OR jsonb_array_length(m)=0 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_MESSAGES_INVALID'; END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(m) e WHERE jsonb_typeof(e) IS DISTINCT FROM 'object'
      OR jsonb_typeof(e->'text') IS DISTINCT FROM 'string' OR nullif(btrim(e->>'text'),'') IS NULL OR e->>'speaker' IS DISTINCT FROM 'USER')
 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_MESSAGES_INVALID'; END IF;
 -- Authority of the literal: the sealed messages must be exactly the order's governed literal (+ owner amendment text, if any).
 IF jsonb_typeof(p_scope->'original_literal_request') IS DISTINCT FROM 'string' OR nullif(btrim(p_scope->>'original_literal_request'),'') IS NULL
 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_LITERAL_UNGOVERNED'; END IF;
 v_gov:=jsonb_build_array(jsonb_build_object('text',p_scope->>'original_literal_request','speaker','USER'));
 IF p_scope ? 'owner_amendment' THEN
   IF jsonb_typeof(p_scope->'owner_amendment'->'text') IS DISTINCT FROM 'string' OR nullif(btrim(p_scope->'owner_amendment'->>'text'),'') IS NULL
   THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_LITERAL_UNGOVERNED'; END IF;
   v_gov:=v_gov||jsonb_build_array(jsonb_build_object('text',p_scope->'owner_amendment'->>'text','speaker','USER'));
 END IF;
 IF m IS DISTINCT FROM v_gov THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_LITERAL_NOT_GOVERNED'; END IF;
 v_sha:=encode(extensions.digest(convert_to(m::text,'UTF8'),'sha256'),'hex');
 IF s->>'original_request_sha256' IS DISTINCT FROM v_sha THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_ORIGINAL_HASH_MISMATCH'; END IF;
 i:=s->'interpretation';
 IF jsonb_typeof(i) IS DISTINCT FROM 'object' OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(i) x) IS DISTINCT FROM v_ikeys
 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_INTERPRETATION_KEYS'; END IF;
 FOREACH k IN ARRAY ARRAY['change','excluded','preserve','screens'] LOOP
   IF jsonb_typeof(i->k) IS DISTINCT FROM 'array' OR jsonb_array_length(i->k)=0
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(i->k) e WHERE jsonb_typeof(e) IS DISTINCT FROM 'string' OR nullif(btrim(e#>>'{}'),'') IS NULL)
   THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_INTERPRETATION_TYPES'; END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['creative_freedom','evaluation_basis','interpretation_origin','objective'] LOOP
   IF jsonb_typeof(i->k) IS DISTINCT FROM 'string' OR nullif(btrim(i->>k),'') IS NULL THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_INTERPRETATION_TYPES'; END IF;
 END LOOP;
 IF i->>'interpretation_origin' IS DISTINCT FROM 'ASSISTANT_INTERPRETATION_SEPARATE_FROM_USER_LITERAL' THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_INTERPRETATION_ORIGIN'; END IF;
 c:=s->'checks';
 IF jsonb_typeof(c) IS DISTINCT FROM 'array' OR jsonb_array_length(c)<>5 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_CHECKS_INVALID'; END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(c) e WHERE jsonb_typeof(e) IS DISTINCT FROM 'object'
      OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(e) x) IS DISTINCT FROM ARRAY['code','expected','severity']
      OR jsonb_typeof(e->'code') IS DISTINCT FROM 'string' OR (e->>'code') !~ '^LF_SEM_[A-Z0-9_]+$'
      OR jsonb_typeof(e->'expected') IS DISTINCT FROM 'string' OR nullif(btrim(e->>'expected'),'') IS NULL
      OR e->>'severity' IS DISTINCT FROM 'BLOCK')
 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_CHECKS_INVALID'; END IF;
 IF (SELECT count(DISTINCT e->>'code') FROM jsonb_array_elements(c) e)<>5 THEN RAISE EXCEPTION 'LF_SEMANTIC_QA_CHECK_CODES_DUPLICATED'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_current_prompt_seal_v1(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE v_lit text; v_ctx text; v_row record;
BEGIN
 SELECT i.acceptance_json#>>'{semantic_qa,original_request_sha256}' INTO v_lit FROM saly.creative_order_items i WHERE i.id=p_item_id;
 v_ctx:=encode(extensions.digest(convert_to(saly.creative_lf_item_context_v1(p_item_id)::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_row FROM saly.creative_lf_prompt_seal_v1 s
 WHERE s.item_id=p_item_id AND s.literal_sha256=v_lit AND s.context_sha256=v_ctx ORDER BY s.id DESC LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('seal_id',v_row.id,'order_id',v_row.order_id,'item_id',v_row.item_id,'prompt_utf8',v_row.prompt_utf8,
   'prompt_sha256',v_row.prompt_sha256,'literal_sha256',v_row.literal_sha256,'context_sha256',v_row.context_sha256);
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_item_context_v1(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'lf_design', 'extensions', 'pg_temp'
AS $function$
DECLARE v_item record; v_expected jsonb; v_tokens jsonb; v_refs jsonb; v_needed int; v_found int; v_drift int; v_req_assets int; v_asset_found int;
BEGIN
 SELECT i.id,i.code,i.context_json,o.id AS order_id,o.context_set_id,o.design_mode,o.status AS order_status,
        o.identity_snapshot AS order_snapshot,ctx.state AS context_state,ctx.provenance AS provenance,p.codigo AS project_code
 INTO v_item FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 LEFT JOIN saly.creative_context_sets ctx ON ctx.id=o.context_set_id
 WHERE i.id=p_item_id;
 IF NOT FOUND OR v_item.project_code<>'LF' OR v_item.context_set_id IS NULL
 THEN RAISE EXCEPTION 'LF_ITEM_CONTEXT_UNAVAILABLE'; END IF;
 IF v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA') OR v_item.context_state IS DISTINCT FROM 'SEALED'
 THEN RAISE EXCEPTION 'LF_ITEM_CONTEXT_NOT_ADMITTED'; END IF;
 SELECT jsonb_agg(jsonb_build_object('version_id',identity_version_id,'sha256',value_sha256,'role',role) ORDER BY identity_version_id)
 INTO v_expected FROM saly.creative_context_tokens WHERE context_set_id=v_item.context_set_id;
 IF v_expected IS NULL OR v_item.order_snapshot IS DISTINCT FROM jsonb_build_object('context_set_id',v_item.context_set_id,'selected_versions',v_expected)
 THEN RAISE EXCEPTION 'LF_ITEM_CONTEXT_SNAPSHOT_MISMATCH'; END IF;
 -- every sealed LF token must be the current approved lf.source.* version, unchanged
 SELECT count(*)::int INTO v_drift FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
   AND (t.value_sha256<>encode(extensions.digest(convert_to(v.value_json::text,'UTF8'),'sha256'),'hex')
        OR v.approval_status<>'APPROVED' OR e.code NOT LIKE 'lf.source.%' OR t.role<>'OFFICIAL');
 IF v_drift<>0 THEN RAISE EXCEPTION 'LF_ITEM_TOKEN_VERSION_DRIFT'; END IF;
 IF v_item.context_json ? 'token_codes' AND jsonb_typeof(v_item.context_json->'token_codes')<>'array'
 THEN RAISE EXCEPTION 'LF_ITEM_TOKEN_SELECTION_INVALID'; END IF;
 SELECT count(DISTINCT c)::int INTO v_needed FROM jsonb_array_elements_text(COALESCE(v_item.context_json->'token_codes','[]'::jsonb)) c;
 SELECT count(DISTINCT e.code)::int INTO v_found FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id AND e.code IN (SELECT jsonb_array_elements_text(COALESCE(v_item.context_json->'token_codes','[]'::jsonb)));
 IF v_needed<>v_found THEN RAISE EXCEPTION 'LF_ITEM_TOKEN_NOT_IN_LOCKED_CONTEXT'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('code',e.code,'role',t.role,'version_id',v.id,'value_json',v.value_json,'value_sha256',t.value_sha256) ORDER BY e.code),'[]'::jsonb)
 INTO v_tokens FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id;
 IF jsonb_array_length(v_tokens)<1 THEN RAISE EXCEPTION 'LF_ITEM_CONTEXT_EMPTY'; END IF;
 -- assets: only those the item requests by asset_code, taken from the SEALED provenance and
 -- re-verified against current lf_design.brand_assets (VIGENTE, is_current, same checksum)
 IF v_item.context_json ? 'asset_codes' AND jsonb_typeof(v_item.context_json->'asset_codes')<>'array'
 THEN RAISE EXCEPTION 'LF_ITEM_ASSET_SELECTION_INVALID'; END IF;
 SELECT count(DISTINCT c)::int INTO v_req_assets FROM jsonb_array_elements_text(COALESCE(v_item.context_json->'asset_codes','[]'::jsonb)) c;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_code',a->>'asset_code','filename',a->>'filename','mime_type',a->>'mime_type',
        'checksum_sha256',a->>'checksum_sha256','storage_provider',a->>'storage_provider','storage_object_path',a->>'storage_object_path',
        'brand_asset_id',a->'brand_asset_id') ORDER BY a->>'asset_code'),'[]'::jsonb), count(*)::int
 INTO v_refs, v_asset_found
 FROM jsonb_array_elements(v_item.provenance::jsonb->'assets') a
 JOIN lf_design.brand_assets b ON b.asset_code=a->>'asset_code' AND b.is_current AND b.status='VIGENTE'
      AND b.checksum_sha256=a->>'checksum_sha256' AND b.brand_asset_id=(a->>'brand_asset_id')::bigint
 WHERE a->>'asset_code' IN (SELECT jsonb_array_elements_text(COALESCE(v_item.context_json->'asset_codes','[]'::jsonb)))
   AND (a->>'checksum_sha256') ~ '^[0-9a-f]{64}$';
 IF v_req_assets<>v_asset_found THEN RAISE EXCEPTION 'LF_ITEM_ASSET_NOT_VERIFIED'; END IF;
 RETURN jsonb_build_object('schema_version','LF_CREATIVE_CONTEXT_L2A','business_code','LF','project_code',v_item.project_code,
  'order_id',v_item.order_id,'item_id',v_item.id,'item_code',v_item.code,'design_mode',v_item.design_mode,
  'context_set_id',v_item.context_set_id,'tokens',v_tokens,'source_refs',v_refs,
  'image_generation_allowed',false,'visual_standard_status','NOT_ACTIVATED_BY_THIS_CONTEXT');
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_item_visual_contract_v1(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'lf_design', 'extensions', 'pg_temp'
AS $function$
DECLARE v_item record; v_context jsonb; v_pkt jsonb; v_checks jsonb; v_contract jsonb; v_seal jsonb; v_manifest jsonb;
BEGIN
 SELECT i.id,i.order_id,i.code AS item_code,i.status AS item_status,i.context_json,i.acceptance_json,o.code AS order_code,o.status AS order_status,
        o.context_set_id,p.codigo AS project_code
 INTO v_item FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id JOIN saly.proyecto p ON p.id=o.project_id WHERE i.id=p_item_id;
 IF NOT FOUND OR v_item.project_code<>'LF' THEN RAISE EXCEPTION 'LF_L3B_ITEM_NOT_ADMITTED'; END IF;
 v_context:=saly.creative_lf_item_context_v1(p_item_id);
 v_pkt:=saly.creative_lf_item_work_packet_v1(p_item_id);
 v_checks:=jsonb_build_array(
  jsonb_build_object('code','LF_IDENTITY_AND_FORMAT','severity','BLOCK','expected','LF_TOKENS_AND_SCREEN_SPEC_DIMENSIONS','method','IMAGE_STYLE_AND_DIMENSION_VERIFICATION','qa_result','NOT_EVALUATED'),
  jsonb_build_object('code','LF_COPY_AND_AMOUNTS','severity','BLOCK','expected','EXACT_AUTHORIZED_COPY_AND_REAL_AMOUNTS_ONLY','method','IMAGE_COPY_AND_SOURCE_COMPARISON','qa_result','NOT_EVALUATED'),
  jsonb_build_object('code','LF_MONTHLY_HIERARCHY','severity','BLOCK','expected','MONTHLY_PAYMENT_VISUALLY_DOMINANT_TOTAL_SECONDARY','method','INDEPENDENT_IMAGE_VISUAL_INSPECTION','qa_result','NOT_EVALUATED'),
  jsonb_build_object('code','LF_DEBT_TRANSFER_VISUAL','severity','BLOCK','expected','DEBT_TRANSFER_EXPLAINED_VISUALLY_WITH_AUTHORIZED_PHRASE','method','INDEPENDENT_IMAGE_VISUAL_INSPECTION','qa_result','NOT_EVALUATED'),
  jsonb_build_object('code','LF_LETTER_AND_CTA','severity','BLOCK','expected','LETTER_TANGIBLE_BEFORE_EXACT_CTA','method','INDEPENDENT_IMAGE_VISUAL_INSPECTION','qa_result','NOT_EVALUATED'));
 IF v_pkt->>'readiness_code'='READY_FOR_NATIVE_HANDOFF' THEN
   v_seal:=saly.creative_lf_current_prompt_seal_v1(p_item_id);
   IF v_seal IS NULL OR (v_pkt->'input_snapshot'->'prompt_seal'->>'seal_id') IS DISTINCT FROM (v_seal->>'seal_id')
   THEN RAISE EXCEPTION 'LF_L3B_PROMPT_SEAL_DRIFT'; END IF;
   v_manifest:=jsonb_build_object('schema_version','CREATIVE_UNIT_HANDOFF_V1','order_id',v_item.order_id::text,'item_id',v_item.id::text,
     'mode','PLAN_ONLY','transmitted',false,'qa','NOT_TESTED','dispatch_readiness','READY_FOR_NATIVE_HANDOFF',
     'prompt_utf8',v_seal->>'prompt_utf8','prompt_sha256',v_seal->>'prompt_sha256','prompt_seal_id',v_seal->'seal_id');
 END IF;
 v_contract:=jsonb_build_object('schema_version','LF_VISUAL_CONTRACT_L3B_V1','business_code','LF','project_code','LF',
   'order_id',v_item.order_id,'order_code',v_item.order_code,'item_id',v_item.id,'item_code',v_item.item_code,'item_status',v_item.item_status,
   'order_status',v_item.order_status,'context_set_id',v_item.context_set_id,
   'source_context_sha256',encode(extensions.digest(convert_to(v_context::text,'UTF8'),'sha256'),'hex'),
   'tokens',v_context->'tokens','source_refs',v_context->'source_refs','screen_spec',v_item.context_json->'screen_spec',
   'acceptance_criteria',v_item.acceptance_json,'qa_checks',v_checks,'qa_verdict','NOT_EVALUATED','visual_generation_state','NOT_EXECUTED',
   'production_manifest',v_manifest,
   'ready_for_handoff',v_pkt->>'readiness_code','native_execution_authorized',false,'image_generation_allowed',false,
   'next_action','INVOKE_REAL_GOVERNED_RENDERER_WITH_THIS_EXACT_CONTRACT');
 RETURN jsonb_build_object('contract',v_contract,'contract_sha256',encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex'),
   'generator_must_echo_contract_sha256',true,'qa_must_compare_same_contract_sha256',true);
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_item_work_packet_v1(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'lf_design', 'extensions', 'pg_temp'
AS $function$
DECLARE v_item record; v_blockers jsonb; v_latest_state text; v_attempt integer:=0; v_readiness text; v_context jsonb; v_snapshot jsonb; v_claim_ok boolean:=false; v_seal jsonb;
BEGIN
 SELECT i.id AS item_id,i.order_id,i.code AS item_code,i.status AS item_status,i.context_json,i.acceptance_json,
   o.code AS order_code,o.status AS order_status,o.context_set_id,o.design_mode,o.scope_json,p.codigo AS project_code
 INTO v_item FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_L2C_ITEM_NOT_FOUND'; END IF;
 IF v_item.project_code<>'LF' THEN RAISE EXCEPTION 'LF_L2C_PROJECT_NOT_ALLOWED'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('item_id',prereq.id,'code',prereq.code,'status',prereq.status) ORDER BY prereq.ordinal),'[]'::jsonb)
 INTO v_blockers FROM saly.creative_item_dependencies d JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
 WHERE d.order_id=v_item.order_id AND d.item_id=v_item.item_id AND prereq.status<>'APROBADO';
 SELECT COALESCE(max(attempt_number),0) INTO v_attempt FROM saly.creative_runs WHERE order_id=v_item.order_id AND item_id=v_item.item_id;
 SELECT state INTO v_latest_state FROM saly.creative_runs WHERE order_id=v_item.order_id AND item_id=v_item.item_id ORDER BY attempt_number DESC LIMIT 1;
 -- An item claimed from PENDIENTE is PRODUCIENDO: eligible only under a live ACTIVE claim and with no run yet.
 IF v_item.item_status='PRODUCIENDO' THEN
   SELECT EXISTS (SELECT 1 FROM saly.creative_queue_claims_v1 c WHERE c.order_id=v_item.order_id AND c.item_id=v_item.item_id
                  AND c.state='ACTIVE' AND c.lease_until>clock_timestamp()) INTO v_claim_ok;
 END IF;
 v_readiness:=CASE
   WHEN v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA') THEN 'ORDER_NOT_ELIGIBLE'
   WHEN v_item.item_status NOT IN ('PENDIENTE','LISTO') AND NOT (v_item.item_status='PRODUCIENDO' AND v_claim_ok) THEN 'ITEM_NOT_ELIGIBLE'
   WHEN jsonb_array_length(v_blockers)>0 THEN 'DEPENDENCIES_NOT_APPROVED'
   WHEN v_latest_state IN ('EN_COLA','EJECUTANDO') THEN 'RUN_ALREADY_ACTIVE'
   WHEN v_latest_state='EXITOSO' THEN 'AWAITING_INDEPENDENT_QA'
   ELSE 'READY_FOR_NATIVE_HANDOFF' END;
 IF v_readiness='READY_FOR_NATIVE_HANDOFF' THEN
   v_seal:=saly.creative_lf_current_prompt_seal_v1(v_item.item_id);
   IF v_seal IS NULL THEN v_readiness:='PROMPT_SEAL_MISSING'; END IF;
 END IF;
 IF v_readiness<>'READY_FOR_NATIVE_HANDOFF' THEN
   RETURN jsonb_build_object('schema_version','LF_WORK_PACKET_L2C_V1','business_code','LF','order_id',v_item.order_id,'order_code',v_item.order_code,
     'item_id',v_item.item_id,'item_code',v_item.item_code,'readiness_code',v_readiness,'blocking_dependencies',v_blockers,
     'latest_run_state',v_latest_state,'input_snapshot',NULL,'native_execution_authorized',false,'image_generation_allowed',false);
 END IF;
 v_context:=saly.creative_lf_item_context_v1(v_item.item_id);
 IF v_context->>'business_code'<>'LF' OR v_context->>'image_generation_allowed'<>'false'
    OR v_context->>'context_set_id' IS DISTINCT FROM v_item.context_set_id::text
    OR jsonb_typeof(v_context->'tokens')<>'array' OR jsonb_array_length(v_context->'tokens')<1
 THEN RAISE EXCEPTION 'LF_L2C_COMPILED_CONTEXT_INVALID'; END IF;
 IF jsonb_typeof(v_item.context_json->'screen_spec')<>'object' OR jsonb_typeof(v_item.acceptance_json)<>'object'
    OR v_item.acceptance_json->>'qa_required'<>'true'
 THEN RAISE EXCEPTION 'LF_L2C_SCREEN_SPEC_OR_QA_MISSING'; END IF;
 v_snapshot:=jsonb_build_object('schema_version','LF_NATIVE_INPUT_SNAPSHOT_L2C_V1','business_code','LF','order_id',v_item.order_id,
   'item_id',v_item.item_id,'item_code',v_item.item_code,'design_mode',v_item.design_mode,'context_set_id',v_item.context_set_id,
   'identity_versions',v_context->'tokens','source_refs',v_context->'source_refs','screen_spec',v_item.context_json->'screen_spec',
   'acceptance_criteria',v_item.acceptance_json,
   'context_sha256',encode(extensions.digest(convert_to(v_context::text,'UTF8'),'sha256'),'hex'),
   'prompt_seal',jsonb_build_object('seal_id',v_seal->'seal_id','prompt_sha256',v_seal->'prompt_sha256','literal_sha256',v_seal->'literal_sha256','context_sha256',v_seal->'context_sha256'),
   'native_execution_authorized',false);
 RETURN jsonb_build_object('schema_version','LF_WORK_PACKET_L2C_V1','business_code','LF','order_id',v_item.order_id,'order_code',v_item.order_code,
   'item_id',v_item.item_id,'item_code',v_item.item_code,'readiness_code','READY_FOR_NATIVE_HANDOFF','blocking_dependencies','[]'::jsonb,
   'next_attempt_hint',v_attempt+1,'idempotency_key_hint','LF-'||v_item.order_id||'-'||v_item.item_id||'-'||(v_attempt+1),
   'latest_run_state',v_latest_state,'input_snapshot',v_snapshot,'native_execution_authorized',false,'image_generation_allowed',false,
   'next_action','GOVERNED_NATIVE_EXECUTOR_AND_WORKER_RECEIPT_REQUIRED');
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_prompt_seal_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE v_item record; v_refs jsonb; v_ctx jsonb; v_lit text; v_chk jsonb; v_code text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_IMMUTABLE'; END IF;
 -- Item row lock: serializes sealing against RUN admission (run_guard_l1 locks the same row FOR UPDATE).
 SELECT i.id,i.order_id,i.status,i.acceptance_json,o.scope_json,p.codigo AS project_code INTO v_item
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i;
 IF NOT FOUND OR v_item.project_code<>'LF' THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_TARGET_INVALID'; END IF;
 IF v_item.status NOT IN ('PENDIENTE','LISTO','PRODUCIENDO') THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_ITEM_NOT_ELIGIBLE'; END IF;
 IF EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.item_id=NEW.item_id AND r.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_RUN_ACTIVE'; END IF;
 -- A01: persisted bytes == reviewed hash
 IF NEW.prompt_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(NEW.prompt_utf8,'UTF8'),'sha256'),'hex')
    OR NEW.review_json->>'prompt_sha256' IS DISTINCT FROM NEW.prompt_sha256
    OR NEW.prompt_utf8 ~ 'claim_token|queue_claim_token'
 THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_HASH_MISMATCH'; END IF;
 -- A02: bound to the governed literal (validated semantic_qa) and to the current LF context
 PERFORM saly.creative_lf_assert_semantic_qa_v1(v_item.acceptance_json,v_item.scope_json);
 v_lit:=v_item.acceptance_json#>>'{semantic_qa,original_request_sha256}';
 v_ctx:=saly.creative_lf_item_context_v1(NEW.item_id);
 IF NEW.literal_sha256 IS DISTINCT FROM v_lit
    OR NEW.context_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(v_ctx::text,'UTF8'),'sha256'),'hex')
 THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_BINDING_MISMATCH'; END IF;
 -- S01: author/reviewer from governed allowlist and different
 SELECT config_value::jsonb INTO v_refs FROM saly.config_global
 WHERE scope='CREATIVE_FACTORY_LF' AND config_key='PROMPT_SEAL_AGENT_REFS' AND value_type='JSON' AND value_status='REAL' AND valid_from<=clock_timestamp()
 ORDER BY valid_from DESC LIMIT 1;
 IF jsonb_typeof(v_refs) IS DISTINCT FROM 'array'
    OR NOT (v_refs @> to_jsonb(NEW.author_ref)) OR NOT (v_refs @> to_jsonb(NEW.reviewer_ref))
 THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_AGENT_NOT_GOVERNED'; END IF;
 -- review: every required check PASS with evidence
 v_chk:=NEW.review_json->'checks';
 IF NEW.review_json->>'verdict' IS DISTINCT FROM 'PASS' OR jsonb_typeof(v_chk) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_REVIEW_INVALID'; END IF;
 FOREACH v_code IN ARRAY ARRAY['PROMPT_LITERAL_MATCH','PROMPT_IDENTITY_MATCH','PROMPT_CONTEXT_MATCH','PROMPT_HASH_MATCH'] LOOP
   IF (SELECT count(*) FROM jsonb_array_elements(v_chk) c WHERE c->>'code'=v_code AND c->>'verdict'='PASS'
         AND jsonb_typeof(c->'evidence')='string' AND nullif(btrim(c->>'evidence'),'') IS NOT NULL)<>1
   THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_REVIEW_INVALID'; END IF;
 END LOOP;
 RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_prompt_seal_truncate_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$ BEGIN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_IMMUTABLE'; END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_prompt_seal_v1(p_item_id bigint, p_prompt_utf8 text, p_author_ref text, p_reviewer_ref text, p_review jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE v_order bigint; v_lit text; v_ctx jsonb; v_id bigint;
BEGIN
 SELECT i.order_id,i.acceptance_json#>>'{semantic_qa,original_request_sha256}' INTO v_order,v_lit FROM saly.creative_order_items i WHERE i.id=p_item_id;
 IF v_order IS NULL OR p_prompt_utf8 IS NULL OR jsonb_typeof(p_review) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_LF_PROMPT_SEAL_TARGET_INVALID'; END IF;
 v_ctx:=saly.creative_lf_item_context_v1(p_item_id);
 INSERT INTO saly.creative_lf_prompt_seal_v1(order_id,item_id,prompt_utf8,prompt_sha256,literal_sha256,context_sha256,author_ref,reviewer_ref,review_json)
 VALUES (v_order,p_item_id,p_prompt_utf8,encode(extensions.digest(convert_to(p_prompt_utf8,'UTF8'),'sha256'),'hex'),v_lit,
         encode(extensions.digest(convert_to(v_ctx::text,'UTF8'),'sha256'),'hex'),p_author_ref,p_reviewer_ref,p_review)
 RETURNING id INTO v_id;
 RETURN jsonb_build_object('status','LF_PROMPT_SEALED','seal_id',v_id,'item_id',p_item_id,'render_authorized',false,'native_transmitted',false);
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_lf_render_wire_core_v1(p_run_id bigint, p_claim_id bigint, p_mode text, p_provider text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'lf_design', 'extensions', 'pg_temp'
AS $function$
DECLARE r record; v_snap jsonb; v_con jsonb; v_man jsonb; v_seal record; v_prompt text; v_psha text; v_csha text; v_ssha text;
 v_att jsonb:='[]'::jsonb; v_src jsonb; v_b record; v_names text[]:=ARRAY[]::text[]; v_payload jsonb; v_bytes bytea; v_ctx text;
BEGIN
 SELECT run.id,run.order_id,run.item_id,run.input_snapshot INTO r FROM saly.creative_runs run WHERE run.id=p_run_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_RUN_CLAIM_NOT_BOUND'; END IF;
 v_snap:=r.input_snapshot; v_con:=v_snap->'visual_contract'; v_man:=v_con->'production_manifest';
 IF jsonb_typeof(v_snap)<>'object' OR v_snap->>'schema_version' IS DISTINCT FROM 'LF_NATIVE_INPUT_SNAPSHOT_L2C_V1'
    OR v_snap->>'business_code' IS DISTINCT FROM 'LF' OR v_snap->>'order_id' IS DISTINCT FROM r.order_id::text
    OR v_snap->>'item_id' IS DISTINCT FROM r.item_id::text OR jsonb_typeof(v_con)<>'object'
    OR v_con->>'schema_version' IS DISTINCT FROM 'LF_VISUAL_CONTRACT_L3B_V1'
    OR v_con->>'order_id' IS DISTINCT FROM r.order_id::text OR v_con->>'item_id' IS DISTINCT FROM r.item_id::text
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_SNAPSHOT_INVALID'; END IF;
 v_ssha:=encode(extensions.digest(convert_to(v_snap::text,'UTF8'),'sha256'),'hex');
 v_csha:=encode(extensions.digest(convert_to(v_con::text,'UTF8'),'sha256'),'hex');
 IF v_snap->>'visual_contract_sha256' IS DISTINCT FROM v_csha OR jsonb_typeof(v_man)<>'object'
    OR v_man->>'schema_version' IS DISTINCT FROM 'CREATIVE_UNIT_HANDOFF_V1'
    OR v_man->>'order_id' IS DISTINCT FROM r.order_id::text OR v_man->>'item_id' IS DISTINCT FROM r.item_id::text
    OR v_man->>'dispatch_readiness' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF' OR v_man->>'mode' IS DISTINCT FROM 'PLAN_ONLY'
    OR v_man->'transmitted' IS DISTINCT FROM 'false'::jsonb OR v_man->>'qa' IS DISTINCT FROM 'NOT_TESTED'
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_FROZEN_CONTRACT_INVALID'; END IF;
 -- prompt must be the sealed one (bytes, hash, snapshot binding), never recompiled
 v_prompt:=v_man->>'prompt_utf8';
 IF nullif(btrim(coalesce(v_prompt,'')),'') IS NULL THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PROMPT_NOT_SEALED'; END IF;
 v_psha:=encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_seal FROM saly.creative_lf_prompt_seal_v1 s WHERE s.id=(v_snap#>>'{prompt_seal,seal_id}')::bigint;
 IF NOT FOUND OR v_seal.item_id<>r.item_id OR v_seal.order_id<>r.order_id
    OR v_seal.prompt_utf8 IS DISTINCT FROM v_prompt OR v_seal.prompt_sha256 IS DISTINCT FROM v_psha
    OR v_man->>'prompt_sha256' IS DISTINCT FROM v_psha OR v_man->>'prompt_seal_id' IS DISTINCT FROM v_seal.id::text
    OR v_snap#>>'{prompt_seal,prompt_sha256}' IS DISTINCT FROM v_psha
    OR v_snap#>>'{prompt_seal,context_sha256}' IS DISTINCT FROM v_snap->>'context_sha256'
    OR v_seal.context_sha256 IS DISTINCT FROM v_snap->>'context_sha256'
    OR v_prompt ~ 'claim_token|queue_claim_token'
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PROMPT_DRIFT'; END IF;
 -- live re-verification: context (tokens + assets VIGENTE/current/checksum) must still equal the frozen one
 v_ctx:=encode(extensions.digest(convert_to(saly.creative_lf_item_context_v1(r.item_id)::text,'UTF8'),'sha256'),'hex');
 IF v_ctx IS DISTINCT FROM v_snap->>'context_sha256' THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_CONTEXT_DRIFT'; END IF;
 -- attachment descriptors from frozen source_refs, re-read from authoritative brand_assets
 IF jsonb_typeof(v_snap->'source_refs')<>'array' THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCES_REQUIRED'; END IF;
 FOR v_src IN SELECT value FROM jsonb_array_elements(v_snap->'source_refs') LOOP
   SELECT b.* INTO v_b FROM lf_design.brand_assets b
    WHERE b.brand_asset_id=(v_src->>'brand_asset_id')::bigint AND b.asset_code=v_src->>'asset_code'
      AND b.is_current AND b.status='VIGENTE' AND b.checksum_sha256=v_src->>'checksum_sha256'
      AND b.filename=v_src->>'filename' AND b.mime_type=v_src->>'mime_type'
      AND b.storage_provider=v_src->>'storage_provider' AND b.storage_object_path=v_src->>'storage_object_path';
   IF NOT FOUND OR v_b.checksum_sha256 !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCE_DRIFT'; END IF;
   IF v_b.filename !~ '^[A-Za-z0-9][A-Za-z0-9_. -]{0,127}$' OR v_b.filename=ANY(v_names)
      OR v_b.mime_type NOT IN ('image/png','image/jpeg','image/svg+xml')
   THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ATTACHMENT_INVALID'; END IF;
   v_names:=v_names||v_b.filename;
   v_att:=v_att||jsonb_build_array(jsonb_build_object('filename',v_b.filename,'sha256',v_b.checksum_sha256,'asset_code',v_b.asset_code,
     'provider',v_b.storage_provider,'file_ref',v_b.storage_object_path,'mime_type',v_b.mime_type));
 END LOOP;
 v_payload:=jsonb_build_object('prompt',v_prompt,'attachments',v_att);
 v_bytes:=convert_to(v_payload::text,'UTF8');
 RETURN jsonb_build_object('schema_version','SALY_NATIVE_RENDER_WIRE_V1','status','RENDER_WIRE_FROZEN_AUTHORIZED','business_code','LF',
   'order_id',r.order_id,'item_id',r.item_id,'run_id',r.id,'claim_id',p_claim_id,'executor_mode',p_mode,'executor_provider',p_provider,
   'executor_identity_attested',false,'input_snapshot_sha256',v_ssha,'contract_sha256',v_csha,'prompt_sha256',v_psha,
   'prompt_seal_id',v_seal.id,'wire_sha256',encode(extensions.digest(v_bytes,'sha256'),'hex'),
   'wire_base64',replace(encode(v_bytes,'base64'),chr(10),''),'render_authorized',true,'native_transmitted',false,'provider_receipt',NULL,
   'host_delivery_verified',false,'db_done_allowed',false,'next_action','ARCHIVE_EXACT_SOURCE_BYTES_THEN_OWNING_NATIVE_CHAT');
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_execution_policy_for_item_v1(p_asof timestamp with time zone, p_order_id bigint, p_item_id bigint, p_attempt integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_base jsonb; v_win text;
BEGIN
 v_base:=saly.creative_execution_policy_v1(p_asof);
 IF p_order_id=22 AND p_item_id=26 AND p_attempt IN (3,4)
 THEN RETURN v_base||jsonb_build_object('MAX_ATTEMPTS',p_attempt); END IF;
 IF EXISTS (SELECT 1 FROM saly.creative_orders o JOIN saly.proyecto p ON p.id=o.project_id
            WHERE o.id=p_order_id AND p.codigo='LF') THEN
   SELECT config_value INTO v_win FROM saly.config_global
   WHERE scope='CREATIVE_FACTORY_LF' AND config_key='EXECUTION_WINDOW_SECONDS'
     AND value_type='INTEGER' AND value_status='REAL' AND valid_from<=p_asof
   ORDER BY valid_from DESC LIMIT 1;
   IF v_win IS NULL OR v_win !~ '^[1-9][0-9]{0,8}$' THEN RAISE EXCEPTION 'CREATIVE_LF_WINDOW_CONFIG_MISSING'; END IF;
   RETURN v_base||jsonb_build_object('EXECUTION_WINDOW_SECONDS',v_win::integer);
 END IF;
 RETURN v_base;
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_item_context_l2a(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions'
AS $function$
DECLARE v_item record; v_tokens jsonb; v_refs jsonb; v_expected_snapshot jsonb; v_needed int; v_found int; v_drift int;
BEGIN
 IF EXISTS (SELECT 1 FROM saly.creative_order_items ii JOIN saly.creative_orders oo ON oo.id=ii.order_id JOIN saly.proyecto pp ON pp.id=oo.project_id WHERE ii.id=p_item_id AND pp.codigo='LF')
 THEN RETURN saly.creative_lf_item_context_v1(p_item_id); END IF;
 SELECT i.id,i.code,i.context_json,o.id AS order_id,o.context_set_id,o.design_mode,
   o.status AS order_status,o.identity_snapshot AS order_snapshot,
   ctx.state AS context_state,p.codigo AS project_code
 INTO v_item FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 LEFT JOIN saly.creative_context_sets ctx ON ctx.id=o.context_set_id
 WHERE i.id=p_item_id;
 IF NOT FOUND OR v_item.project_code<>'SALY-001' OR v_item.context_set_id IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_CONTEXT_UNAVAILABLE'; END IF;
 IF v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA')
   OR v_item.context_state IS DISTINCT FROM 'SEALED'
   OR v_item.design_mode<>'EXPLORE'
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_CONTEXT_NOT_ADMITTED'; END IF;
 SELECT jsonb_agg(jsonb_build_object('version_id',identity_version_id,
    'sha256',value_sha256,'role',role) ORDER BY identity_version_id)
 INTO v_expected_snapshot
 FROM saly.creative_context_tokens WHERE context_set_id=v_item.context_set_id;
 IF v_expected_snapshot IS NULL OR
    v_item.order_snapshot IS DISTINCT FROM jsonb_build_object(
      'context_set_id',v_item.context_set_id,'selected_versions',v_expected_snapshot)
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_CONTEXT_SNAPSHOT_MISMATCH'; END IF;
 IF v_item.context_json ? 'token_codes'
    AND jsonb_typeof(v_item.context_json->'token_codes')<>'array'
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_TOKEN_SELECTION_INVALID'; END IF;
 -- Candidate tokens are opt-in per screen; official tokens always included.
 WITH requested AS (
  SELECT DISTINCT jsonb_array_elements_text(
    COALESCE(v_item.context_json->'token_codes','[]'::jsonb)) AS code
 )
 SELECT count(*)::int INTO v_needed FROM requested;
 WITH requested AS (
  SELECT DISTINCT jsonb_array_elements_text(
    COALESCE(v_item.context_json->'token_codes','[]'::jsonb)) AS code
 ), available AS (
  SELECT e.code,t.role FROM saly.creative_context_tokens t
  JOIN saly.identity_versions v ON v.id=t.identity_version_id
  JOIN saly.identity_elements e ON e.id=v.element_id
  WHERE t.context_set_id=v_item.context_set_id
 )
 SELECT count(*)::int INTO v_found
 FROM requested r JOIN available a ON a.code=r.code;
 IF v_needed<>v_found THEN RAISE EXCEPTION 'CREATIVE_ITEM_TOKEN_NOT_IN_LOCKED_CONTEXT'; END IF;
 SELECT count(*)::int INTO v_drift FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 WHERE t.context_set_id=v_item.context_set_id
 AND t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex');
 IF v_drift<>0 THEN RAISE EXCEPTION 'CREATIVE_ITEM_TOKEN_VERSION_DRIFT'; END IF;
 WITH requested AS (
  SELECT DISTINCT jsonb_array_elements_text(
    COALESCE(v_item.context_json->'token_codes','[]'::jsonb)) AS code
 )
 SELECT COALESCE(jsonb_agg(jsonb_build_object('code',e.code,'role',t.role,
   'version_id',v.id,'value_json',v.value_json,'value_sha256',t.value_sha256)
   ORDER BY e.code),'[]'::jsonb)
 INTO v_tokens
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id AND
   (t.role='OFFICIAL' OR e.code IN (SELECT code FROM requested)
   OR e.code IN (
       SELECT DISTINCT alias_v.metadata->>'alias_target_code'
       FROM saly.creative_context_tokens alias_link
       JOIN saly.identity_versions alias_v ON alias_v.id=alias_link.identity_version_id
       JOIN saly.identity_elements alias_e ON alias_e.id=alias_v.element_id
       WHERE alias_link.context_set_id=v_item.context_set_id
        AND alias_e.code IN (SELECT code FROM requested)
        AND alias_v.metadata->>'kind'='ALIAS')
   );
 IF EXISTS (SELECT 1 FROM saly.creative_item_sources s
   JOIN visual.source_assets a ON a.id=s.source_asset_id
   WHERE s.item_id=v_item.id AND s.order_id=v_item.order_id
     AND (s.source_sha256 IS DISTINCT FROM a.source_sha256
       OR NOT a.independent_sha_verified OR a.brand_code<>'SALY'
       OR a.approval_status NOT IN ('CANDIDATE','APPROVED')))
 THEN RAISE EXCEPTION 'CREATIVE_ITEM_SOURCE_REFERENCE_DRIFT'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_id',a.id,
  'asset_code',a.asset_code,'source_kind',a.source_kind,
  'provider',a.provider,'file_ref',a.file_ref,
  'source_sha256',s.source_sha256,'approval_status',a.approval_status,
  'purpose',s.purpose) ORDER BY a.asset_code),'[]'::jsonb)
 INTO v_refs
 FROM saly.creative_item_sources s JOIN visual.source_assets a ON a.id=s.source_asset_id
 WHERE s.item_id=v_item.id AND s.order_id=v_item.order_id;
 RETURN jsonb_build_object('schema_version','SALY_CREATIVE_CONTEXT_L2A',
  'business_code','SALY','project_code',v_item.project_code,
  'order_id',v_item.order_id,'item_id',v_item.id,'item_code',v_item.code,
  'design_mode',v_item.design_mode,'context_set_id',v_item.context_set_id,
  'tokens',v_tokens,'source_refs',v_refs,
  'image_generation_allowed',false,'visual_standard_status','NOT_ACTIVATED_BY_THIS_CONTEXT');
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_item_visual_contract_l3b(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_bp jsonb; v_lock jsonb; v_binding record; v_token record; v_resolved jsonb := '{}'::jsonb;
 v_code text; v_seen text[]; v_prompt text;
 v_item record; v_context jsonb; v_dispatch jsonb;
 v_cta record; v_brand record; v_white record;
 v_contract jsonb; v_rules jsonb; v_hash text;
BEGIN
 IF EXISTS (SELECT 1 FROM saly.creative_order_items ii JOIN saly.creative_orders oo ON oo.id=ii.order_id JOIN saly.proyecto pp ON pp.id=oo.project_id WHERE ii.id=p_item_id AND pp.codigo='LF')
 THEN RETURN saly.creative_lf_item_visual_contract_v1(p_item_id); END IF;
 SELECT i.id,i.order_id,i.code AS item_code,i.ordinal,i.status AS item_status,
        i.context_json,i.acceptance_json,
        o.code AS order_code,o.status AS order_status,o.context_set_id,
        p.codigo AS project_code
 INTO v_item
 FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=p_item_id;
 IF NOT FOUND OR v_item.project_code<>'SALY-001'
 THEN RAISE EXCEPTION 'SALY_L3B_ITEM_NOT_ADMITTED'; END IF;
 IF v_item.acceptance_json#>>'{visual_rules,scope}'
    IS DISTINCT FROM v_item.order_code
 OR v_item.acceptance_json#>>'{visual_rules,no_decorative_rays}'
    IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'SALY_L3B_OWNER_VISUAL_POLICY_MISSING'; END IF;

 -- L2A validates SEALED set, version snapshots and SHA, candidate selections,
 -- source identity and hash. Neither prompt nor QA can choose another version.
 v_context:=saly.creative_item_context_l2a(p_item_id);
 v_dispatch:=saly.creative_item_work_packet_l2c(p_item_id);

 SELECT v.id AS version_id,v.value_json->>'value' AS color_value,
        v.value_json->>'usage' AS usage,t.value_sha256,v.approval_status
 INTO v_cta
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
       AND e.code='color.action.primary.bg' AND t.role='OFFICIAL';
 IF NOT FOUND OR v_cta.approval_status<>'APPROVED'
    OR v_cta.usage<>'CTA_BACKGROUND_FOR_WHITE_TEXT'
    OR v_cta.color_value !~ '^#[0-9A-Fa-f]{6}$'
 THEN RAISE EXCEPTION 'SALY_L3B_OFFICIAL_CTA_UNAVAILABLE'; END IF;

 SELECT v.id AS version_id,v.value_json->>'value' AS color_value,
        v.value_json->>'usage' AS usage,t.value_sha256,v.approval_status
 INTO v_brand
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
       AND e.code='color.brand.primary' AND t.role='OFFICIAL';
 IF NOT FOUND OR v_brand.approval_status<>'APPROVED'
    OR v_brand.usage<>'BRAND_ONLY_NOT_WHITE_TEXT_CTA'
 THEN RAISE EXCEPTION 'SALY_L3B_BRAND_COLOR_AUTHORITY_INVALID'; END IF;

 -- Candidate white representation is NOT promoted to an official token:
 -- white typography is separately authorized by the official CTA usage.
 SELECT v.id AS version_id,v.value_json->>'value' AS color_value,
        t.value_sha256,v.approval_status
 INTO v_white
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=v_item.context_set_id
       AND e.code='candidate.saly_ds_v1.color.surface.white';
 IF NOT FOUND OR v_white.approval_status NOT IN ('CANDIDATE','APPROVED')
    OR upper(v_white.color_value)<>'#FFFFFF'
 THEN RAISE EXCEPTION 'SALY_L3B_WHITE_REFERENCE_UNAVAILABLE'; END IF;

 IF jsonb_array_length(v_context->'source_refs')<1
 THEN RAISE EXCEPTION 'SALY_L3B_SOURCE_REFERENCE_REQUIRED'; END IF;

 v_rules:=jsonb_build_array(
   jsonb_build_object('code','SALY_CTA_BACKGROUND','severity','BLOCK',
     'expected',v_cta.color_value,'source','saly.identity_versions',
     'token_code','color.action.primary.bg','version_id',v_cta.version_id,
     'source_sha256',v_cta.value_sha256,'method','IMAGE_PIXEL_OR_STYLE_VERIFICATION',
     'qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_CTA_TEXT','severity','BLOCK',
     'expected',v_white.color_value,
     'source','OFFICIAL_CTA_USAGE_AND_CANDIDATE_WHITE_REFERENCE',
     'white_reference_status','CANDIDATE_NOT_PROMOTED',
     'version_id',v_white.version_id,'source_sha256',v_white.value_sha256,
     'method','IMAGE_PIXEL_OR_STYLE_VERIFICATION','qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_NO_DECORATIVE_RAYS','severity','BLOCK',
     'expected','ABSENT','source','creative_order_items.acceptance_json.visual_rules',
     'method','INDEPENDENT_IMAGE_VISUAL_INSPECTION','qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_GEOMETRY_SOURCE_MATCH','severity','BLOCK',
     'expected','MATCH_LINKED_SOURCE_GEOMETRY',
     'source','saly.creative_item_sources',
     'reference_sha256',v_context->'source_refs',
     'method','IMAGE_DIMENSIONS_AND_VISUAL_REFERENCE_COMPARE',
     'qa_result','NOT_EVALUATED'),
   jsonb_build_object('code','SALY_NO_UNGROUNDED_FINANCIAL_AMOUNTS','severity','BLOCK',
     'expected','ONLY_SOURCE_SUPPORTED_VALUES',
     'source','creative_order_items.acceptance_json.visual_rules',
     'method','IMAGE_COPY_AND_SOURCE_COMPARISON','qa_result','NOT_EVALUATED')
 );

 v_contract:=jsonb_build_object(
   'schema_version','SALY_VISUAL_CONTRACT_L3B_V1',
   'business_code','SALY','project_code',v_item.project_code,
   'order_id',v_item.order_id,'order_code',v_item.order_code,
   'item_id',v_item.id,'item_code',v_item.item_code,
   'item_status',v_item.item_status,
   'order_status',v_item.order_status,
   'context_set_id',v_item.context_set_id,
   'source_context_sha256',encode(extensions.digest(convert_to(v_context::text,'UTF8'),'sha256'),'hex'),
   'official_cta',jsonb_build_object(
      'background',v_cta.color_value,'foreground',v_white.color_value,
      'background_version_id',v_cta.version_id,
      'background_version_sha256',v_cta.value_sha256,
      'foreground_reference_version_id',v_white.version_id,
      'foreground_status','DERIVED_FROM_APPROVED_CTA_USAGE'),
   'brand_color',jsonb_build_object('value',v_brand.color_value,
      'version_id',v_brand.version_id,'source_sha256',v_brand.value_sha256,
      'not_valid_for_primary_cta',true),
   'tokens',v_context->'tokens',
   'source_refs',v_context->'source_refs',
   'screen_spec',v_item.context_json->'screen_spec',
   'acceptance_criteria',v_item.acceptance_json,
   'qa_checks',v_rules,
   'qa_verdict','NOT_EVALUATED',
   'visual_generation_state','NOT_EXECUTED',
   'ready_for_handoff',v_dispatch->>'readiness_code',
   'native_execution_authorized',false,
   'image_generation_allowed',false,
   'next_action','INVOKE_REAL_GOVERNED_RENDERER_WITH_THIS_EXACT_CONTRACT');
 -- Opt-in extension of the existing read-only contract. L2C retains dispatch ownership.
 v_bp := v_item.context_json#>'{screen_spec,visual_blueprint}';
 IF v_bp IS NOT NULL THEN
   IF v_bp->>'schema_version' IS DISTINCT FROM 'CREATIVE_VISUAL_BLUEPRINT_V1'
      OR v_bp->>'brand' IS DISTINCT FROM v_contract->>'business_code'
      OR jsonb_array_length(v_context->'source_refs') <> 1
      OR v_bp->>'reference_sha256' IS DISTINCT FROM v_context#>>'{source_refs,0,source_sha256}'
      OR v_bp#>>'{output,count}' IS DISTINCT FROM '1'
      OR v_bp->>'design_lock_sha256' IS DISTINCT FROM
         encode(extensions.digest(convert_to((v_bp->'design_lock')::text,'UTF8'),'sha256'),'hex')
      OR v_bp->>'mode' IS DISTINCT FROM 'PLAN_ONLY'
   THEN RAISE EXCEPTION 'CREATIVE_BLUEPRINT_MISMATCH'; END IF;
   -- Use the locked values in the prompt. Candidate aliases can only resolve
   -- inside the same frozen context and terminate at a selected token or CTA white.
   v_lock := v_bp#>'{design_lock,LOCK}';
   IF NOT (v_lock ?& ARRAY['copy_locked','visual_lock','layout_lock','hierarchy','cta',
      'reference_sha256','output','bindings','restrictions'])
      OR v_lock IS DISTINCT FROM (SELECT jsonb_object_agg(k,v_bp->k)
          FROM jsonb_object_keys(v_lock) AS property(k))
      OR v_bp#>'{design_lock,GUIDED}' IS DISTINCT FROM v_bp->'guided'
      OR v_bp#>'{design_lock,FREE}' IS DISTINCT FROM v_bp->'free'
   THEN RAISE EXCEPTION 'CREATIVE_LOCK_DRIFT'; END IF;
   FOR v_binding IN SELECT key,value FROM jsonb_each_text(v_lock->'bindings') ORDER BY key COLLATE "C" LOOP
     v_code := v_binding.value;
     v_seen := ARRAY[]::text[];
     LOOP
       IF v_code=ANY(v_seen) THEN RAISE EXCEPTION 'CREATIVE_TOKEN_ALIAS_CYCLE'; END IF;
       v_seen := array_append(v_seen,v_code);
       SELECT v.id AS version_id, v.value_json->'value' AS val, v.metadata->>'alias_target_code' AS target
         INTO STRICT v_token
         FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
         JOIN saly.identity_elements e ON e.id=v.element_id
         WHERE t.context_set_id=v_item.context_set_id AND e.code=v_code
           AND (v.id=v_white.version_id OR EXISTS
               (SELECT 1 FROM jsonb_array_elements(v_context->'tokens') tok WHERE tok->>'code'=e.code));
       EXIT WHEN v_token.target IS NULL;
       v_code := v_token.target;
     END LOOP;
     IF v_token.val IS NULL OR jsonb_typeof(v_token.val)='null' OR
        (jsonb_typeof(v_token.val)='string' AND left(v_token.val#>>'{}',1)='{')
     THEN RAISE EXCEPTION 'CREATIVE_UNRESOLVED_TOKEN'; END IF;
     v_resolved := v_resolved || jsonb_build_object(v_binding.key,v_token.val);
   END LOOP;
   IF v_resolved->>'CTA fondo' IS DISTINCT FROM v_cta.color_value
      OR v_resolved->>'CTA texto' IS DISTINCT FROM v_white.color_value
      OR v_resolved->>'Identidad' IS DISTINCT FROM v_brand.color_value
   THEN RAISE EXCEPTION 'CREATIVE_TOKEN_AUTHORITY_CONFLICT'; END IF;
   v_prompt := concat_ws(chr(10),
      format('%s · %s. Una pantalla en PNG de %s × %s.',v_bp->>'brand',v_item.item_code,
          v_lock#>>'{output,dimensions,0}',v_lock#>>'{output,dimensions,1}'),
      v_bp->>'intent', v_bp->>'art', 'Usar la referencia adjunta de esta pieza.',
      'De arriba abajo: '||array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_lock->'hierarchy')),' → '),
      v_lock->>'layout_lock',v_lock->>'visual_lock',v_lock#>>'{copy_locked,base}',
      (SELECT string_agg(format('%s: «%s».',entry->>'component',entry->>'value'),chr(10) ORDER BY ord)
         FROM jsonb_array_elements(v_lock#>'{copy_locked,overrides}') WITH ORDINALITY AS x(entry,ord)),
      format('Conservar CTA «%s».',v_lock->>'cta'),'Tokens aplicables: '||v_resolved::text,
      'Aplicar copy aprobado y CTA oficial. Para lo demás, conservar la referencia. Los candidatos orientan ajustes compatibles.',
      array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_lock->'restrictions')),chr(10)),
      array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_bp->'guided')),chr(10)),
      CASE WHEN jsonb_array_length(v_bp->'free')>0 THEN 'Libertad permitida: '||(v_bp->'free')::text END);
   v_contract := v_contract || jsonb_build_object('production_manifest',jsonb_build_object(
       'schema_version','CREATIVE_UNIT_HANDOFF_V1','order_id',v_item.order_id,'item_id',v_item.id,
       'context_set_id',v_item.context_set_id,'variant','original','mode','PLAN_ONLY',
       'source_refs',v_context->'source_refs','design_lock_sha256',v_bp->>'design_lock_sha256',
       'dispatch_readiness',v_dispatch->>'readiness_code','prompt_utf8',v_prompt,
       'prompt_sha256',encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex'),
       'transmitted',false,'renderer',NULL,'attempt',NULL,'artifact_sha256',NULL,'qa','NOT_TESTED'));
 END IF;
 v_hash:=encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex');
 RETURN jsonb_build_object(
   'contract',v_contract,
   'contract_sha256',v_hash,
   'generator_must_echo_contract_sha256',true,
   'qa_must_compare_same_contract_sha256',true);
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_item_work_packet_l2c(p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_item record;
 v_blockers jsonb:='[]'::jsonb;
 v_latest_state text;
 v_attempt integer:=0;
 v_readiness text;
 v_context jsonb;
 v_snapshot jsonb;
 v_review jsonb; v_assets jsonb; v_review_status text;
BEGIN
 IF EXISTS (SELECT 1 FROM saly.creative_order_items ii JOIN saly.creative_orders oo ON oo.id=ii.order_id JOIN saly.proyecto pp ON pp.id=oo.project_id WHERE ii.id=p_item_id AND pp.codigo='LF')
 THEN RETURN saly.creative_lf_item_work_packet_v1(p_item_id); END IF;
 SELECT i.id AS item_id,i.order_id,i.code AS item_code,i.ordinal,
   i.status AS item_status,i.kind,i.required,i.context_json,i.acceptance_json,
   o.code AS order_code,o.status AS order_status,o.context_set_id,o.design_mode,o.scope_json,
   p.codigo AS project_code
 INTO v_item
 FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id
 WHERE i.id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_L2C_ITEM_NOT_FOUND'; END IF;
 IF v_item.project_code<>'SALY-001' THEN
   RAISE EXCEPTION 'SALY_L2C_PROJECT_NOT_ALLOWED'; END IF;

 SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'item_id',prereq.id,'code',prereq.code,'status',prereq.status)
    ORDER BY prereq.ordinal),'[]'::jsonb)
 INTO v_blockers
 FROM saly.creative_item_dependencies d
 JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
 WHERE d.order_id=v_item.order_id AND d.item_id=v_item.item_id
   AND prereq.status<>'APROBADO';

 SELECT COALESCE(max(attempt_number),0) INTO v_attempt
 FROM saly.creative_runs WHERE order_id=v_item.order_id AND item_id=v_item.item_id;
 SELECT state INTO v_latest_state
 FROM saly.creative_runs
 WHERE order_id=v_item.order_id AND item_id=v_item.item_id
 ORDER BY attempt_number DESC LIMIT 1;

 v_readiness:=CASE
   WHEN v_item.order_status NOT IN ('PLANIFICADO','EN_PROCESO','EN_QA')
     THEN 'ORDER_NOT_ELIGIBLE'
   WHEN v_item.item_status NOT IN ('PENDIENTE','LISTO')
     THEN 'ITEM_NOT_ELIGIBLE'
   WHEN jsonb_array_length(v_blockers)>0
     THEN 'DEPENDENCIES_NOT_APPROVED'
   WHEN v_latest_state IN ('EN_COLA','EJECUTANDO')
     THEN 'RUN_ALREADY_ACTIVE'
   WHEN v_latest_state='EXITOSO'
     THEN 'AWAITING_INDEPENDENT_QA'
   ELSE 'READY_FOR_NATIVE_HANDOFF'
 END;

 IF v_readiness<>'READY_FOR_NATIVE_HANDOFF' THEN
   RETURN jsonb_build_object(
     'schema_version','SALY_WORK_PACKET_L2C_V1',
     'business_code','SALY',
     'order_id',v_item.order_id,'order_code',v_item.order_code,
     'item_id',v_item.item_id,'item_code',v_item.item_code,
     'readiness_code',v_readiness,'blocking_dependencies',v_blockers,
     'latest_run_state',v_latest_state,'input_snapshot',NULL,
     'native_execution_authorized',false,'image_generation_allowed',false);
 END IF;

 -- Explicit review-only lane; never advertise native dispatch readiness.
 IF v_item.scope_json->'review_only'='true'::jsonb OR v_item.context_json#>>'{screen_spec,mode}'='TEMPLATE_REVIEW' THEN
   IF v_item.scope_json->'review_only' IS DISTINCT FROM 'true'::jsonb
     OR v_item.scope_json->'render_authorized' IS DISTINCT FROM 'false'::jsonb
     OR v_item.context_json#>>'{screen_spec,mode}' IS DISTINCT FROM 'TEMPLATE_REVIEW'
   THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_AUTHORITY_MISMATCH'; END IF;
   v_review_status:='REVIEW_TEMPLATE_INCOMPLETE';
   IF v_item.context_json ? 'preflight_review' THEN
     v_review:=saly.creative_template_preflight_v1(p_item_id);
     IF v_review IS DISTINCT FROM v_item.context_json->'preflight_review'
       OR v_review#>'{contract,handoff}' IS DISTINCT FROM v_item.context_json->'handoff_review'
       OR v_review#>>'{contract,qa_verdict}' IS DISTINCT FROM 'NOT_EVALUATED'
       OR v_review#>'{contract,image_generation_allowed}' IS DISTINCT FROM 'false'::jsonb
       OR v_review#>'{contract,native_execution_authorized}' IS DISTINCT FROM 'false'::jsonb
     THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_CONTRACT_DRIFT'; END IF;
     SELECT jsonb_object_agg(r.key,jsonb_build_object('ref',r.value,'svg_utf8',a.metadata->>'svg')) INTO v_assets
     FROM jsonb_each(v_review#>'{contract,handoff,composition,asset_refs}') r
     JOIN visual.source_assets a ON a.id=(r.value->>'asset_id')::bigint
     AND a.source_sha256=r.value->>'sha256'
     AND a.source_sha256=encode(extensions.digest(convert_to(a.metadata->>'svg','UTF8'),'sha256'),'hex');
     IF v_assets IS NULL OR (SELECT count(*) FROM jsonb_object_keys(v_assets))<>5
     THEN RAISE EXCEPTION 'SALY_TEMPLATE_REVIEW_ASSET_BYTES_MISMATCH'; END IF;
     v_review_status:='READY_FOR_REVIEW_ONLY';
   END IF;
   RETURN jsonb_build_object('schema_version','SALY_WORK_PACKET_L2C_V1','business_code','SALY',
     'order_id',v_item.order_id,'order_code',v_item.order_code,'item_id',v_item.item_id,'item_code',v_item.item_code,
     'readiness_code',v_review_status,'blocking_dependencies','[]'::jsonb,'latest_run_state',v_latest_state,
     'input_snapshot',NULL,'review_contract',v_review,'composition_svg_assets',v_assets,
     'native_transport',CASE WHEN v_review_status='READY_FOR_REVIEW_ONLY' THEN
       jsonb_build_object('schema_version','SALY_NATIVE_TRANSPORT_V2','item_id',p_item_id,
         'contract_sha256',v_review->>'contract_sha256',
         'prompt_sha256',v_review#>>'{contract,handoff,prompt_sha256}',
         'payload',jsonb_build_object('prompt',v_review#>>'{contract,handoff,native_prompt}',
          'attachments',v_review#>'{contract,handoff,attachments}'))
       ELSE NULL END,
     'native_execution_authorized',false,'image_generation_allowed',false,
     'next_action',CASE WHEN v_review IS NULL THEN 'COMPLETE_TEMPLATE_REVIEW' ELSE 'REVIEW_EXACT_HANDOFF_NO_RENDER' END);
 END IF;

 -- The L2A compiler rechecks SEALED context, frozen identity/version hashes,
 -- candidate opt-in and source status/SHA on every call. No copy of tokens in code.
 v_context:=saly.creative_item_context_l2a(v_item.item_id);
 IF v_context->>'business_code'<>'SALY'
    OR v_context->>'image_generation_allowed'<>'false'
    OR v_context->>'context_set_id' IS DISTINCT FROM v_item.context_set_id::text
    OR jsonb_typeof(v_context->'tokens')<>'array'
    OR jsonb_array_length(v_context->'tokens')<2
    OR (SELECT count(*) FROM jsonb_array_elements(v_context->'tokens') AS tok(value)
       WHERE tok.value->>'role'='OFFICIAL')<>2
 THEN RAISE EXCEPTION 'SALY_L2C_COMPILED_CONTEXT_INVALID'; END IF;
 IF jsonb_typeof(v_context->'source_refs')<>'array'
    OR jsonb_array_length(v_context->'source_refs')<1
 THEN RAISE EXCEPTION 'SALY_L2C_VERIFIED_SOURCE_REQUIRED'; END IF;
 IF jsonb_typeof(v_item.context_json->'screen_spec')<>'object'
    OR jsonb_typeof(v_item.acceptance_json)<>'object'
    OR v_item.acceptance_json->>'qa_required'<>'true'
 THEN RAISE EXCEPTION 'SALY_L2C_SCREEN_SPEC_OR_QA_MISSING'; END IF;

 -- Matches existing creative_runs input_snapshot fields and success constraints.
 -- This is a proposal for the owning native executor, NOT a run reservation,
 -- rendering receipt, deployment authority or visual approval.
 v_snapshot:=jsonb_build_object(
    'schema_version','SALY_NATIVE_INPUT_SNAPSHOT_L2C_V1',
    'business_code','SALY',
    'order_id',v_item.order_id,
    'item_id',v_item.item_id,
    'item_code',v_item.item_code,
    'design_mode',v_item.design_mode,
    'context_set_id',v_item.context_set_id,
    'identity_versions',v_context->'tokens',
    'source_refs',v_context->'source_refs',
    'screen_spec',v_item.context_json->'screen_spec',
    'acceptance_criteria',v_item.acceptance_json,
    'context_sha256',encode(extensions.digest(
        convert_to(v_context::text,'UTF8'),'sha256'),'hex'),
    'native_execution_authorized',false);

 RETURN jsonb_build_object(
    'schema_version','SALY_WORK_PACKET_L2C_V1',
    'business_code','SALY',
    'order_id',v_item.order_id,'order_code',v_item.order_code,
    'item_id',v_item.item_id,'item_code',v_item.item_code,
    'readiness_code','READY_FOR_NATIVE_HANDOFF',
    'blocking_dependencies','[]'::jsonb,
    'next_attempt_hint',v_attempt+1,
    'idempotency_key_hint','SALY-'||v_item.order_id||'-'||v_item.item_id||
       '-'||(v_attempt+1),
    'latest_run_state',v_latest_state,
    'input_snapshot',v_snapshot,
    'native_execution_authorized',false,
    'image_generation_allowed',false,
    'next_action','GOVERNED_NATIVE_EXECUTOR_AND_WORKER_RECEIPT_REQUIRED');
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_native_render_wire_v1(p_claim_token uuid, p_run_id bigint, p_executor_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_now timestamptz;
  v_row record;
  v_policy jsonb;
  v_snapshot jsonb;
  v_contract jsonb;
  v_manifest jsonb;
  v_sources jsonb;
  v_source jsonb;
  v_attachments jsonb:='[]'::jsonb;
  v_asset record;
  v_name text;
  v_names text[]:=ARRAY[]::text[];
  v_prompt text;
  v_prompt_sha text;
  v_contract_sha text;
  v_snapshot_sha text;
  v_payload jsonb;
  v_wire_bytes bytea;
  v_mode text;
  v_provider text;
  v_ref_count integer:=0;
  v_proj text;
BEGIN
  -- A queue claim is a fencing token, NOT a provider-identity credential.
  IF p_claim_token IS NULL OR p_run_id IS NULL OR p_run_id<1
     OR p_executor_mode IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ARGUMENT_INVALID'; END IF;
  v_mode:=upper(btrim(p_executor_mode));
  IF v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE')
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_EXECUTOR_MODE_INVALID'; END IF;
  v_provider:=CASE v_mode WHEN 'GPT_NATIVE' THEN 'OPENAI_CHATGPT_NATIVE'
                      ELSE 'ANTHROPIC_CLAUDE_NATIVE' END;

  -- Use same serial lock as the queue. Read one current time AFTER locking.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT c.id AS claim_id,c.claim_token,c.state AS claim_state,
         c.lease_until,c.worker_ref AS claim_worker,
         r.id AS run_id,r.order_id,r.item_id,r.state AS run_state,
         r.worker_ref AS run_worker,r.deadline_at,r.attempt_number,
         r.execution_policy,r.input_snapshot,
         i.status AS item_status,
         o.status AS order_status,o.scope_json
  INTO v_row
  FROM saly.creative_queue_claims_v1 c
  JOIN saly.creative_runs r ON r.queue_claim_id=c.id
      AND r.order_id=c.order_id AND r.item_id=c.item_id
  JOIN saly.creative_orders o ON o.id=r.order_id
  JOIN saly.creative_order_items i ON i.id=r.item_id AND i.order_id=r.order_id
  WHERE c.claim_token=p_claim_token AND r.id=p_run_id
  FOR UPDATE OF c,r,o,i;
  IF NOT FOUND
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_RUN_CLAIM_NOT_BOUND'; END IF;
  v_now:=clock_timestamp();
  IF v_row.claim_state<>'ACTIVE' OR v_row.run_state<>'EJECUTANDO'
     OR v_row.lease_until<=v_now OR v_row.deadline_at<=v_now
     OR nullif(btrim(coalesce(v_row.run_worker,'')),'') IS NULL
     OR v_row.claim_worker IS DISTINCT FROM v_row.run_worker
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_CLAIM_NOT_ACTIVE'; END IF;

  -- An explicit authority at the order is required; REVIEW_ONLY is never promoted.
  IF v_row.order_status NOT IN ('PLANIFICADO','EN_PROCESO')
     OR v_row.item_status NOT IN ('LISTO','PRODUCIENDO')
     OR v_row.scope_json->>'queue_mode' IS DISTINCT FROM 'SERIAL_V1'
     OR v_row.scope_json->'rendering_authority' IS DISTINCT FROM 'true'::jsonb
     OR v_row.scope_json->'render_authorized' IS DISTINCT FROM 'true'::jsonb
     OR v_row.scope_json->'review_only' IS DISTINCT FROM 'false'::jsonb
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ORDER_AUTHORITY_MISSING'; END IF;

  -- W02: the business branch is decided by the order's real project, never by the snapshot alone.
  -- Real project codes: 'LF' and 'SALY-001' (SALY business). Never assume a code that production does not use.
  SELECT CASE p.codigo WHEN 'LF' THEN 'LF' WHEN 'SALY-001' THEN 'SALY' END INTO v_proj
  FROM saly.creative_orders o JOIN saly.proyecto p ON p.id=o.project_id WHERE o.id=v_row.order_id;
  IF v_proj IS NULL OR v_proj NOT IN ('LF','SALY')
     OR (v_row.input_snapshot->>'business_code') IS DISTINCT FROM v_proj
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PROJECT_SNAPSHOT_MISMATCH'; END IF;
  IF v_proj='LF' THEN
    -- W01: LF runs carry a FROZEN policy; never compare it against later configuration.
    IF jsonb_typeof(v_row.execution_policy) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_row.execution_policy->'MAX_ATTEMPTS') IS DISTINCT FROM 'number'
       OR jsonb_typeof(v_row.execution_policy->'EXECUTION_WINDOW_SECONDS') IS DISTINCT FROM 'number'
       OR (v_row.execution_policy->>'EXECUTION_WINDOW_SECONDS')::numeric<=0
       OR (v_row.execution_policy->>'EXECUTION_WINDOW_SECONDS')::numeric<>trunc((v_row.execution_policy->>'EXECUTION_WINDOW_SECONDS')::numeric)
       OR (v_row.execution_policy->>'MAX_ATTEMPTS')::numeric<=0
       OR (v_row.execution_policy->>'MAX_ATTEMPTS')::numeric<>trunc((v_row.execution_policy->>'MAX_ATTEMPTS')::numeric)
       OR v_row.attempt_number<1
       OR v_row.attempt_number>(v_row.execution_policy->>'MAX_ATTEMPTS')::integer
    THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_POLICY_DRIFT'; END IF;
    RETURN saly.creative_lf_render_wire_core_v1(v_row.run_id,v_row.claim_id,v_mode,v_provider);
  END IF;
  v_policy:=saly.creative_execution_policy_for_item_v1(v_now,v_row.order_id,v_row.item_id,v_row.attempt_number);
  IF v_row.execution_policy IS DISTINCT FROM v_policy
     OR v_row.attempt_number<1
     OR v_row.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_POLICY_DRIFT'; END IF;

  -- The work packet is only valid before RUN admission; after RUN starts it
  -- deliberately returns RUN_ALREADY_ACTIVE. NEVER recompile the prompt here.
  v_snapshot:=v_row.input_snapshot;
  v_contract:=v_snapshot->'visual_contract';
  v_manifest:=v_contract->'production_manifest';
  IF jsonb_typeof(v_snapshot) IS DISTINCT FROM 'object'
     OR v_snapshot->>'schema_version' IS DISTINCT FROM 'SALY_NATIVE_INPUT_SNAPSHOT_L2C_V1'
     OR v_snapshot->>'business_code' IS DISTINCT FROM 'SALY'
     OR v_snapshot->>'order_id' IS DISTINCT FROM v_row.order_id::text
     OR v_snapshot->>'item_id' IS DISTINCT FROM v_row.item_id::text
     OR jsonb_typeof(v_contract) IS DISTINCT FROM 'object'
     OR v_contract->>'schema_version' IS DISTINCT FROM 'SALY_VISUAL_CONTRACT_L3B_V1'
     OR v_contract->>'order_id' IS DISTINCT FROM v_row.order_id::text
     OR v_contract->>'item_id' IS DISTINCT FROM v_row.item_id::text
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_SNAPSHOT_INVALID'; END IF;

  v_snapshot_sha:=encode(extensions.digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex');
  v_contract_sha:=encode(extensions.digest(convert_to(v_contract::text,'UTF8'),'sha256'),'hex');
  IF v_snapshot->>'visual_contract_sha256' IS DISTINCT FROM v_contract_sha
     OR jsonb_typeof(v_manifest) IS DISTINCT FROM 'object'
     OR v_manifest->>'schema_version' IS DISTINCT FROM 'CREATIVE_UNIT_HANDOFF_V1'
     OR v_manifest->>'order_id' IS DISTINCT FROM v_row.order_id::text
     OR v_manifest->>'item_id' IS DISTINCT FROM v_row.item_id::text
     OR v_manifest->>'dispatch_readiness' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF'
     OR v_manifest->>'mode' IS DISTINCT FROM 'PLAN_ONLY'
     OR v_manifest->'transmitted' IS DISTINCT FROM 'false'::jsonb
     OR v_manifest->>'qa' IS DISTINCT FROM 'NOT_TESTED'
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_FROZEN_CONTRACT_INVALID'; END IF;
  -- The PLAN_ONLY manifest is input provenance, NOT production approval.
  -- Production admission originates only in the explicit order+claim+RUN gates.
  v_prompt:=v_manifest->>'prompt_utf8';
  IF nullif(btrim(coalesce(v_prompt,'')),'') IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PROMPT_NOT_SEALED'; END IF;
  v_prompt_sha:=encode(extensions.digest(convert_to(v_prompt,'UTF8'),'sha256'),'hex');
  IF v_manifest->>'prompt_sha256' IS DISTINCT FROM v_prompt_sha
     OR v_prompt ~ 'claim_token|queue_claim_token'
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_PROMPT_DRIFT'; END IF;

  -- Source descriptors are derived from the frozen RUN snapshot and checked
  -- against authoritative source asset rows, never constructed from model text.
  -- Raw file bytes are NOT in SQL: the Native host MUST download, hash, archive,
  -- and attach exact bytes; this function alone is not a provider receipt.
  v_sources:=v_snapshot->'source_refs';
  IF jsonb_typeof(v_sources) IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_sources)=0
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCES_REQUIRED'; END IF;
  FOR v_source IN SELECT value FROM jsonb_array_elements(v_sources)
  LOOP
    IF jsonb_typeof(v_source) IS DISTINCT FROM 'object'
       OR coalesce(v_source->>'asset_id','') !~ '^[1-9][0-9]*$'
       OR (v_source->>'asset_id')::numeric>9223372036854775807::numeric
    THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCE_INVALID'; END IF;
    SELECT a.*,s.purpose AS source_purpose,s.source_sha256 AS link_sha
    INTO v_asset
    FROM saly.creative_item_sources s
    JOIN visual.source_assets a ON a.id=s.source_asset_id
    WHERE s.order_id=v_row.order_id AND s.item_id=v_row.item_id
      AND a.id=(v_source->>'asset_id')::bigint;
    IF NOT FOUND OR v_asset.source_sha256 IS DISTINCT FROM v_asset.link_sha
       OR v_asset.source_sha256 IS DISTINCT FROM v_source->>'source_sha256'
       OR v_asset.asset_code IS DISTINCT FROM v_source->>'asset_code'
       OR v_asset.file_ref IS DISTINCT FROM v_source->>'file_ref'
       OR v_asset.provider IS DISTINCT FROM v_source->>'provider'
       OR v_asset.source_kind IS DISTINCT FROM v_source->>'source_kind'
       OR v_asset.approval_status IS DISTINCT FROM v_source->>'approval_status'
       OR v_asset.source_purpose IS DISTINCT FROM v_source->>'purpose'
       OR v_asset.brand_code<>'SALY'
       OR v_asset.independent_sha_verified IS DISTINCT FROM true
       OR v_asset.approval_status NOT IN ('CANDIDATE','APPROVED')
       OR v_asset.source_sha256 !~ '^[0-9a-f]{64}$'
       OR nullif(btrim(coalesce(v_asset.file_ref,'')),'') IS NULL
    THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCE_DRIFT'; END IF;
    v_name:=v_asset.metadata->>'source_filename';
    IF v_name IS NULL OR v_name !~ '^[A-Za-z0-9][A-Za-z0-9_. -]{0,127}$'
       OR v_name IN ('.','..') OR v_name=ANY(v_names)
       OR v_asset.metadata->>'mime_type' IS NULL
       OR v_asset.metadata->>'mime_type' NOT IN ('image/png','image/jpeg','image/svg+xml')
    THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_ATTACHMENT_INVALID'; END IF;
    v_names:=array_append(v_names,v_name);
    v_attachments:=v_attachments||jsonb_build_array(jsonb_build_object(
       'filename',v_name,'sha256',v_asset.source_sha256,
       'asset_code',v_asset.asset_code,'provider',v_asset.provider,
       'file_ref',v_asset.file_ref,'mime_type',v_asset.metadata->>'mime_type'));
    v_ref_count:=v_ref_count+1;
  END LOOP;
  IF v_ref_count <> jsonb_array_length(v_sources)
  THEN RAISE EXCEPTION 'CREATIVE_RENDER_WIRE_REFERENCE_COUNT_DRIFT'; END IF;

  v_payload:=jsonb_build_object('prompt',v_prompt,'attachments',v_attachments);
  v_wire_bytes:=convert_to(v_payload::text,'UTF8');
  RETURN jsonb_build_object(
     'schema_version','SALY_NATIVE_RENDER_WIRE_V1',
     'status','RENDER_WIRE_FROZEN_AUTHORIZED',
     'order_id',v_row.order_id,'item_id',v_row.item_id,
     'run_id',v_row.run_id,'claim_id',v_row.claim_id,
     'executor_mode',v_mode,'executor_provider',v_provider,
     'executor_identity_attested',false,
     'input_snapshot_sha256',v_snapshot_sha,
     'contract_sha256',v_contract_sha,
     'prompt_sha256',v_prompt_sha,
     'wire_sha256',encode(extensions.digest(v_wire_bytes,'sha256'),'hex'),
     'wire_base64',replace(encode(v_wire_bytes,'base64'),chr(10),''),
     'render_authorized',true,'native_transmitted',false,
     'provider_receipt',NULL,
     'host_delivery_verified',false,
     'db_done_allowed',false,
     'next_action','ARCHIVE_EXACT_SOURCE_BYTES_THEN_OWNING_NATIVE_CHAT');
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_queue_claim_by_id_v1(p_order_id bigint, p_worker_ref text, p_lease_seconds integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_item record;
  v_active record;
  v_claim record;
  v_now timestamptz;
  v_policy jsonb;
  v_lease_seconds integer;
BEGIN
  IF p_order_id IS NULL OR p_order_id<1 OR length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  -- Fail before claiming if an operational policy has not been published.
  -- The existing creative run admission reads the same source of truth.
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  -- Owner-authorized LF test lease; all other orders retain the published policy.
  v_lease_seconds:=coalesce((saly.creative_execution_policy_for_item_v1(v_now,p_order_id,0,1)->>'EXECUTION_WINDOW_SECONDS')::integer,v_lease_seconds);
  IF p_lease_seconds IS NOT NULL AND p_lease_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT id,lease_until,item_id INTO v_active
  FROM saly.creative_queue_claims_v1 WHERE order_id=p_order_id AND state='ACTIVE' FOR UPDATE;
  IF FOUND THEN
    IF v_active.lease_until > v_now THEN
      RETURN jsonb_build_object('status','BUSY','claim_id',v_active.id);
    END IF;
    -- Old fencing token is invalid after this update. Preserve audit trail.
    UPDATE saly.creative_queue_claims_v1
    SET state='EXPIRED',finished_at=v_now,note='LEASE_EXPIRED'
    WHERE id=v_active.id AND order_id=p_order_id AND state='ACTIVE';
  END IF;

  -- Admission is intentionally conservative: review-only and legacy orders excluded.
  -- Caller must still validate semantic/brand sources, generate and QA within lease.
  IF EXISTS (SELECT 1 FROM saly.creative_runs r
             WHERE r.order_id=p_order_id AND r.state IN ('EN_COLA','EJECUTANDO')) THEN
    RETURN jsonb_build_object('status','RUN_ACTIVE','claim_id',NULL);
  END IF;

  SELECT i.id AS item_id,o.id AS order_id,i.code AS item_code,o.code AS order_code
  INTO v_item
  FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.id=p_order_id AND o.status IN ('PLANIFICADO','EN_PROCESO')
    AND (i.status='LISTO' OR (i.status='PENDIENTE' AND (o.project_id=2 OR EXISTS (SELECT 1 FROM saly.proyecto lfp WHERE lfp.id=o.project_id AND lfp.codigo='LF')) AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1'))
    AND o.scope_json->>'queue_mode'='SERIAL_V1'
    AND (o.request_kind <> 'APP_SCREEN_SINGLE'
         OR saly.creative_order_sequence_dependency_met_v1(o.id))
    AND o.scope_json->>'rendering_authority'='true'
    AND coalesce(o.scope_json->>'review_only','false')='false'
    AND coalesce(o.scope_json->>'render_authorized','true')='true'
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.item_id=i.id AND d.order_id=o.id AND prereq.status<>'APROBADO'
    )
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=i.id AND r.state='EXITOSO'
    )
  ORDER BY o.id, i.ordinal, i.id
  LIMIT 1 FOR UPDATE OF i SKIP LOCKED;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_item.order_id AND status='PLANIFICADO';
  UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.item_id AND status='PENDIENTE';
  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>v_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $function$
;
CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb; v_next_attempt bigint; v_now timestamptz; v_policy jsonb; v_acceptance jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
   THEN RAISE EXCEPTION 'CREATIVE_TERMINAL_RUN_IMMUTABLE'; END IF;
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
      OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
   THEN RAISE EXCEPTION 'CREATIVE_RUN_BINDING_IMMUTABLE'; END IF;
   IF NEW.input_snapshot IS DISTINCT FROM OLD.input_snapshot
   THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_IMMUTABLE'; END IF;
   IF NEW.execution_policy IS DISTINCT FROM OLD.execution_policy
      OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_IMMUTABLE'; END IF;
   IF OLD.state='EJECUTANDO' AND (NEW.worker_ref IS DISTINCT FROM OLD.worker_ref
      OR NEW.started_at IS DISTINCT FROM OLD.started_at)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_IMMUTABLE'; END IF;
   IF NEW.state<>OLD.state
     AND NOT ((OLD.state='EN_COLA' AND NEW.state IN ('EJECUTANDO','BLOQUEADO','CANCELADO'))
       OR (OLD.state='EJECUTANDO' AND NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_INVALID_TRANSITION'; END IF;
 END IF;
 -- Only admissions contend on the queue capacity lock.
 IF TG_OP='INSERT' THEN
   -- A transaction-wide stale snapshot cannot enforce an aggregate queue cap.
   IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted')
   THEN RAISE EXCEPTION 'CREATIVE_ADMISSION_REQUIRES_READ_COMMITTED'; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('saly.creative_runs:queue_capacity',0));
 END IF;
 SELECT i.status,o.status,o.scope_json,i.acceptance_json INTO v_item_status,v_order_status,v_scope,v_acceptance
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i,o;
 -- Measure time only after waiting for the actual admission and parent locks.
 v_now:=clock_timestamp();
 IF v_item_status IS NULL OR
    ((v_item_status IN ('APROBADO','OMITIDO') OR v_order_status IN ('COMPLETADO','CANCELADO'))
     AND (TG_OP='INSERT' OR NEW.state NOT IN ('FALLIDO','BLOQUEADO','CANCELADO')))
 THEN RAISE EXCEPTION 'CREATIVE_RUN_ITEM_NOT_ELIGIBLE'; END IF;
 -- Review-only and explicitly disabled orders cannot enter or progress render.
 -- Permit cancellation/failure of an existing run so a revoked order can stop.
 IF (TG_OP='INSERT' OR NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 AND (v_scope->'review_only'='true'::jsonb
   OR (v_scope ? 'render_authorized' AND v_scope->'render_authorized' IS DISTINCT FROM 'true'::jsonb)
   OR (v_scope ? 'rendering_authority' AND v_scope->'rendering_authority' IS DISTINCT FROM 'true'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_NOT_AUTHORIZED'; END IF;
 -- The existing item row lock serializes attempt admission; existing unique
 -- indexes remain the authoritative idempotency and single-active constraints.
 IF TG_OP='INSERT' THEN
   IF NEW.state IS DISTINCT FROM 'EN_COLA' THEN RAISE EXCEPTION 'CREATIVE_RUN_INITIAL_STATE'; END IF;
   SELECT coalesce(max(attempt_number)::bigint,0)+1 INTO v_next_attempt
   FROM saly.creative_runs WHERE item_id=NEW.item_id;
   IF NEW.attempt_number IS DISTINCT FROM v_next_attempt
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_OUT_OF_SEQUENCE'; END IF;
   v_policy:=saly.creative_execution_policy_for_item_v1(v_now,NEW.order_id,NEW.item_id,NEW.attempt_number);
   IF NEW.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_LIMIT'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND idempotency_key=NEW.idempotency_key)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_IDEMPOTENCY_REPLAY'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ALREADY_ACTIVE'; END IF;
   IF (SELECT count(*) FROM saly.creative_runs WHERE state='EN_COLA') >= (v_policy->>'QUEUE_MAX')::integer
   THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FULL'; END IF;
   -- Legacy items without a semantic contract retain the existing behavior.
   -- A sealed semantic item cannot enter with a substitute contract or snapshot.
   IF EXISTS (SELECT 1 FROM saly.creative_orders oo JOIN saly.proyecto pp ON pp.id=oo.project_id WHERE oo.id=NEW.order_id AND pp.codigo='LF') THEN
     IF NOT (v_acceptance ? 'semantic_qa') THEN RAISE EXCEPTION 'LF_RUN_SEMANTIC_QA_REQUIRED'; END IF;
     PERFORM saly.creative_lf_assert_semantic_qa_v1(v_acceptance,v_scope);
   END IF;
   IF v_acceptance ? 'semantic_qa' THEN
     PERFORM saly.creative_assert_run_snapshot_v1(NEW.item_id,NEW.input_snapshot);
   END IF;
   NEW.execution_policy:=v_policy;
   NEW.deadline_at:=v_now+make_interval(secs=>(v_policy->>'QUEUE_TIMEOUT_SECONDS')::integer);
   NEW.started_at:=NULL;
   NEW.finished_at:=NULL;
 ELSE
   IF NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO') AND OLD.deadline_at<=v_now
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_EXPIRED'; END IF;
   IF OLD.state='EN_COLA' AND NEW.state='EJECUTANDO' THEN
     IF nullif(btrim(NEW.worker_ref),'') IS NULL THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_REQUIRED'; END IF;
     NEW.started_at:=v_now;
     NEW.deadline_at:=CASE WHEN OLD.order_id=22 AND OLD.item_id=26 AND OLD.attempt_number IN (3,4) THEN v_now+interval '24 hours' WHEN OLD.execution_policy ? 'EXECUTION_WINDOW_SECONDS' THEN v_now+make_interval(secs=>(OLD.execution_policy->>'EXECUTION_WINDOW_SECONDS')::integer) ELSE v_now+make_interval(secs=>(OLD.execution_policy->>'LEASE_SECONDS')::integer) END;
   ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
     RAISE EXCEPTION 'CREATIVE_RUN_STARTED_AT_IMMUTABLE';
   END IF;
   IF NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO') THEN NEW.finished_at:=v_now; END IF;
 END IF;
 RETURN NEW;
END $function$
;
CREATE TRIGGER trg_creative_lf_prompt_seal_guard_v1 BEFORE INSERT OR DELETE OR UPDATE ON saly.creative_lf_prompt_seal_v1 FOR EACH ROW EXECUTE FUNCTION saly.creative_lf_prompt_seal_guard_v1();
CREATE TRIGGER trg_creative_lf_prompt_seal_truncate_v1 BEFORE TRUNCATE ON saly.creative_lf_prompt_seal_v1 FOR EACH STATEMENT EXECUTE FUNCTION saly.creative_lf_prompt_seal_truncate_guard_v1();
REVOKE ALL ON FUNCTION saly.creative_lf_assert_semantic_qa_v1(jsonb,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_current_prompt_seal_v1(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_item_context_v1(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_item_visual_contract_v1(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_item_work_packet_v1(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_prompt_seal_guard_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_prompt_seal_truncate_guard_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_prompt_seal_v1(bigint,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_lf_render_wire_core_v1(bigint,bigint,text,text) FROM PUBLIC;
REVOKE ALL ON TABLE saly.creative_lf_prompt_seal_v1 FROM PUBLIC;
DO $g$ DECLARE r text; BEGIN FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON TABLE saly.creative_lf_prompt_seal_v1 FROM %I',r); END IF; END LOOP; END $g$;
COMMIT;
