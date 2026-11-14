-- LF: additive run-independent inheritance by REFERENCE. Source hash is checked at READ.
-- No writer of lf_ops.*, no update to input_family_assessments or its 64 readers.
-- PG17/18: entire migration and test data executed under BEGIN / ROLLBACK.
BEGIN;
DO $pre$
BEGIN
 IF to_regclass('programacion.input_family_inheritable_sources_v1') IS NOT NULL
 OR to_regclass('programacion.input_family_inheritable_members_v1') IS NOT NULL
 OR to_regclass('public.v_lf_input_family_coverage_by_screen_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_FAMILY_REFERENCE_V1_ALREADY_EXISTS'; END IF;
 IF to_regclass('programacion.input_family_reuse_map_v1') IS NULL
 OR to_regprocedure('public.lf_input_family_reuse_before_propose_v1(integer,text,bigint)') IS NULL
 THEN RAISE EXCEPTION 'LF_FAMILY_REFERENCE_3940_SOURCE_MISSING'; END IF;
 IF (SELECT count(*) FROM programacion.input_family_reuse_map_v1
     WHERE source_run_id=956 AND resolution_path='HEREDAR')<>11
 OR (SELECT count(*) FROM programacion.input_family_reuse_map_v1
     WHERE source_run_id=956 AND resolution_path='ATAR_POLITICA')<>4
 THEN RAISE EXCEPTION 'LF_FAMILY_REFERENCE_956_MAP_11_4_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.input_family_reuse_map_v1 m
      JOIN lf_ops.reglas r ON r.id=m.transversal_regla_id
      WHERE m.source_run_id=956 AND m.resolution_path='HEREDAR'
      AND (r.estado<>'VIGENTE' OR r.es_transversal IS NOT TRUE))
 THEN RAISE EXCEPTION 'LF_FAMILY_REFERENCE_RULE_SOURCE_NOT_VIGENTE'; END IF;
 IF (SELECT status FROM lf_ops.politicas_sesion WHERE session_policy_id=1)<>'VIGENTE'
 OR (SELECT status FROM lf_ops.politicas_seguridad WHERE security_policy_id=9)<>'CANDIDATO'
 OR (SELECT status FROM lf_ops.politicas_rate_limit WHERE rate_limit_policy_id=2)<>'CANDIDATO'
 OR (SELECT status FROM lf_ops.politicas_timeout WHERE timeout_policy_id=2)<>'CANDIDATO'
 THEN RAISE EXCEPTION 'LF_FAMILY_REFERENCE_POLICY_SOURCE_STATUS_DRIFT'; END IF;
END $pre$;

CREATE TABLE programacion.input_family_inheritable_sources_v1 (
 source_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 family_code text NOT NULL CHECK(family_code ~ '^[A-Z][A-Z0-9_]{2,100}$'),
 source_kind text NOT NULL CHECK(source_kind IN('RULE','POLICY')),
 rule_id integer REFERENCES lf_ops.reglas(id) ON DELETE RESTRICT,
 rate_limit_policy_id bigint REFERENCES lf_ops.politicas_rate_limit(rate_limit_policy_id) ON DELETE RESTRICT,
 timeout_policy_id bigint REFERENCES lf_ops.politicas_timeout(timeout_policy_id) ON DELETE RESTRICT,
 session_policy_id bigint REFERENCES lf_ops.politicas_sesion(session_policy_id) ON DELETE RESTRICT,
 security_policy_id bigint REFERENCES lf_ops.politicas_seguridad(security_policy_id) ON DELETE RESTRICT,
 scope_kind text NOT NULL CHECK(scope_kind IN('GLOBAL','CANAL','CONJUNTO_PANTALLAS')),
 scope_channel_code text,
 source_hash text NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'),
 estado text NOT NULL DEFAULT 'ACTIVE' CHECK(estado IN('ACTIVE','REVIEW','DISABLED')),
 semantic_equivalence text NOT NULL CHECK(semantic_equivalence IN('EQUIVALENT_COMPONENT','PARTIAL_BASE')),
 semantic_transferability text NOT NULL CHECK(semantic_transferability IN('TRANSFERABLE','CONDITIONAL')),
 semantic_evidence_ref text NOT NULL CHECK(length(semantic_evidence_ref)>8),
 semantic_reason_code text NOT NULL CHECK(length(semantic_reason_code)>3),
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK ((source_kind='RULE' AND rule_id IS NOT NULL
         AND num_nonnulls(rate_limit_policy_id,timeout_policy_id,session_policy_id,security_policy_id)=0)
      OR (source_kind='POLICY' AND rule_id IS NULL
         AND num_nonnulls(rate_limit_policy_id,timeout_policy_id,session_policy_id,security_policy_id)=1)),
 CHECK ((scope_kind='CANAL' AND nullif(scope_channel_code,'') IS NOT NULL)
   OR (scope_kind IN('GLOBAL','CONJUNTO_PANTALLAS') AND scope_channel_code IS NULL))
);
CREATE UNIQUE INDEX input_family_ref_rule_once_v1 ON
 programacion.input_family_inheritable_sources_v1(family_code,rule_id)
 WHERE source_kind='RULE';
CREATE UNIQUE INDEX input_family_ref_rl_once_v1 ON
 programacion.input_family_inheritable_sources_v1(family_code,rate_limit_policy_id)
 WHERE rate_limit_policy_id IS NOT NULL;
CREATE UNIQUE INDEX input_family_ref_timeout_once_v1 ON
 programacion.input_family_inheritable_sources_v1(family_code,timeout_policy_id)
 WHERE timeout_policy_id IS NOT NULL;
CREATE UNIQUE INDEX input_family_ref_session_once_v1 ON
 programacion.input_family_inheritable_sources_v1(family_code,session_policy_id)
 WHERE session_policy_id IS NOT NULL;
CREATE UNIQUE INDEX input_family_ref_security_once_v1 ON
 programacion.input_family_inheritable_sources_v1(family_code,security_policy_id)
 WHERE security_policy_id IS NOT NULL;
CREATE TABLE programacion.input_family_inheritable_members_v1 (
 source_id bigint NOT NULL REFERENCES programacion.input_family_inheritable_sources_v1(source_id) ON DELETE RESTRICT,
 member_screen_id integer NOT NULL REFERENCES lf_ops.pantallas(id) ON DELETE RESTRICT,
 PRIMARY KEY(source_id,member_screen_id)
);
CREATE FUNCTION programacion.fn_lf_family_ref_member_guard_v1()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM programacion.input_family_inheritable_sources_v1 x
 WHERE x.source_id=NEW.source_id AND x.scope_kind='CONJUNTO_PANTALLAS')
 THEN RAISE EXCEPTION 'LF_FAMILY_REFERENCE_MEMBER_ONLY_SET_SCOPE'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER tr_lf_family_ref_members_v1 BEFORE INSERT OR UPDATE
 ON programacion.input_family_inheritable_members_v1 FOR EACH ROW
 EXECUTE FUNCTION programacion.fn_lf_family_ref_member_guard_v1();
COMMENT ON TABLE programacion.input_family_inheritable_sources_v1 IS
 'Run-independent family reference registry: only FK + hash; no rule text, copied parameters, run_id, pantalla_id, or content authority transfer.';
COMMENT ON TABLE programacion.input_family_inheritable_members_v1 IS
 'Screen members only for scope_kind CONJUNTO_PANTALLAS; no implicit link to lf_ops.reglas_pantallas or pantallas_politicas.';

-- Eleven rule sources are VIGENTE/transversal; each verdict is for an
-- INHERITABLE COMPONENT, not family COMPLETE or a replacement for UX/QA.
WITH source_rule(family_code,rule_id,scope_kind,scope_channel_code,
 eq,transfer,reason_code) AS (
 VALUES
 ('API_DATA_CONTRACT',179,'GLOBAL',NULL,'PARTIAL_BASE','TRANSFERABLE','API_ENVELOPE_ONLY_NO_ENDPOINT_SCHEMA'),
 ('ASSETS_ICONS',362,'GLOBAL',NULL,'PARTIAL_BASE','CONDITIONAL','ASSET_PROVENANCE_ONLY_NOT_ICON_MAPPING'),
 ('AUDIT',416,'CANAL','B2B_APP_SHELL','EQUIVALENT_COMPONENT','TRANSFERABLE','AUDIT_APPEND_ONLY_NOT_ACTIONS'),
 ('DESIGN_SYSTEM',387,'CANAL','B2B_APP_SHELL','EQUIVALENT_COMPONENT','TRANSFERABLE','DESIGN_TOKEN_REF_NOT_BINDING'),
 ('LOADING_EMPTY_ERROR_STATES',199,'GLOBAL',NULL,'EQUIVALENT_COMPONENT','TRANSFERABLE','UI_FIVE_STATES_NOT_PER_STEP'),
 ('OBSERVABILITY',412,'CANAL','B2B_APP_SHELL','EQUIVALENT_COMPONENT','TRANSFERABLE','CORRELATION_ONLY_RUNTIME_PENDING'),
 ('PRIVACY_PII',411,'CANAL','B2B_APP_SHELL','EQUIVALENT_COMPONENT','TRANSFERABLE','NO_PII_IN_TELEMETRY_SUBSET'),
 ('SECURITY',396,'CANAL','B2B_APP_SHELL','EQUIVALENT_COMPONENT','TRANSFERABLE','POST_AUTH_DENY_DEFAULT_NOT_PREAUTH'),
 ('TESTING_OBLIGATIONS',424,'CANAL','B2B_APP_SHELL','PARTIAL_BASE','CONDITIONAL','PRODUCTION_QA_GATE_NOT_TEST_EVIDENCE'),
 ('VALIDATIONS',25,'GLOBAL',NULL,'EQUIVALENT_COMPONENT','TRANSFERABLE','SERVER_FORMAT_CHECK_NOT_ALL_FIELD_CASES'),
 ('VISUAL_EVIDENCE',370,'GLOBAL',NULL,'EQUIVALENT_COMPONENT','TRANSFERABLE','RENDER_REVIEW_REQUIREMENT_NOT_CURRENT_ASSET')
)
INSERT INTO programacion.input_family_inheritable_sources_v1(
 family_code,source_kind,rule_id,scope_kind,scope_channel_code,source_hash,
 semantic_equivalence,semantic_transferability,semantic_evidence_ref,semantic_reason_code)
SELECT s.family_code,'RULE',r.id,s.scope_kind,s.scope_channel_code,
 encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
 s.eq,s.transfer,'supabase://lf_ops.reglas/'||r.id::text||'#source_hash',s.reason_code
FROM source_rule s JOIN lf_ops.reglas r ON r.id=s.rule_id
WHERE r.estado='VIGENTE' AND r.es_transversal=true;

-- Four existing source mappings, but ONLY ONE policy currently VIGENTE.
INSERT INTO programacion.input_family_inheritable_sources_v1(
 family_code,source_kind,session_policy_id,scope_kind,scope_channel_code,
 source_hash,semantic_equivalence,semantic_transferability,
 semantic_evidence_ref,semantic_reason_code)
SELECT 'SESSION','POLICY',p.session_policy_id,'CANAL','B2B_APP_SHELL',
 encode(sha256(convert_to(to_jsonb(p)::text,'UTF8')),'hex'),
 'EQUIVALENT_COMPONENT','TRANSFERABLE',
 'supabase://lf_ops.politicas_sesion/'||p.session_policy_id::text||'#source_hash',
 'B2B_SHELL_ONLY_RUNTIME_QA_PENDING'
FROM lf_ops.politicas_sesion p
WHERE p.session_policy_id=1 AND p.policy_code='SESSION-B2B-DEFAULT'
  AND p.status='VIGENTE';

DO $seed$
BEGIN
 IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>12
 OR (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE source_kind='RULE')<>11
 OR (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE source_kind='POLICY')<>1
 OR EXISTS (SELECT 1 FROM programacion.input_family_inheritable_sources_v1 c
   JOIN lf_ops.reglas r ON r.id=c.rule_id
   WHERE r.estado<>'VIGENTE')
 THEN RAISE EXCEPTION 'LF_FAMILY_REFERENCE_V1_SEED_INVALID'; END IF;
END $seed$;

-- All five READ-ONLY legacy scope/effective locators remain intact. The view
-- NEVER uses the old run-bound map to decide scope, nor changes rule binding.
CREATE VIEW public.v_lf_input_family_coverage_by_screen_v1
WITH (security_barrier=true)
AS
SELECT
 s.id AS pantalla_id,s.codigo AS pantalla_codigo,
 c.source_id,c.family_code,c.source_kind,c.rule_id,
 c.rate_limit_policy_id,c.timeout_policy_id,
 c.session_policy_id,c.security_policy_id,
 c.scope_kind,c.scope_channel_code,
 c.source_hash,cur.current_source_hash,
 CASE WHEN cur.current_source_hash IS NULL OR cur.current_source_hash<>c.source_hash
           OR cur.current_source_status IS DISTINCT FROM 'VIGENTE'
           OR (c.source_kind='RULE' AND r.es_transversal IS NOT TRUE)
           THEN 'STALE' ELSE 'CURRENT' END AS freshness,
 c.estado AS catalog_status,
 c.semantic_equivalence,c.semantic_transferability,c.semantic_evidence_ref,c.semantic_reason_code,
 (c.scope_kind='GLOBAL'
   OR (c.scope_kind='CANAL' AND m.app_shell_code=c.scope_channel_code)
   OR (c.scope_kind='CONJUNTO_PANTALLAS' AND EXISTS(
     SELECT 1 FROM programacion.input_family_inheritable_members_v1 mem
     WHERE mem.source_id=c.source_id AND mem.member_screen_id=s.id))) AS scope_applies,
 CASE WHEN c.source_kind='RULE' THEN
   CASE WHEN EXISTS(SELECT 1 FROM lf_ops.reglas_pantallas rp WHERE rp.pantalla_id=s.id AND rp.regla_id=c.rule_id)
   THEN 'EXPLICIT_RULE_LINK'
   WHEN EXISTS(SELECT 1 FROM programacion.fn_input_effective_rule_links_v1(s.id,'INPUT_GOVERNANCE') z WHERE z.regla_id=c.rule_id)
   THEN 'IG_EFFECTIVE_LINK'
   WHEN EXISTS(SELECT 1 FROM programacion.fn_t_remed_global_rules_v1(0.25) z WHERE z.regla_id=c.rule_id)
   THEN 'GLOBAL_V1'
   WHEN EXISTS(SELECT 1 FROM programacion.fn_t_remed_inherited_rules_v1(s.id,0.30,true) z WHERE z.regla_id=c.rule_id)
   THEN 'NEIGHBOR_V1'
   WHEN EXISTS(SELECT 1 FROM programacion.fn_t_remed_effective_rules_v1(s.id,0.25) z WHERE z.regla_id=c.rule_id)
   THEN 'EFFECTIVE_V1'
   WHEN EXISTS(SELECT 1 FROM programacion.fn_t_remed_scope_judge_v1(0.25) z WHERE z.regla_id=c.rule_id AND z.verdict='PASS_GLOBAL')
   THEN 'SCOPE_JUDGE_V1'
   ELSE 'REFERENCE_SCOPE_ONLY' END
 ELSE 'POLICY_REFERENCE_ONLY' END AS legacy_evidence_route,
 false AS family_closure_verified,
 false AS implementation_authorized
FROM lf_ops.pantallas s
LEFT JOIN lf_ops.modulos m ON m.module_id=s.module_id
CROSS JOIN programacion.input_family_inheritable_sources_v1 c
LEFT JOIN lf_ops.reglas r ON r.id=c.rule_id
LEFT JOIN lf_ops.politicas_rate_limit pr ON pr.rate_limit_policy_id=c.rate_limit_policy_id
LEFT JOIN lf_ops.politicas_timeout pt ON pt.timeout_policy_id=c.timeout_policy_id
LEFT JOIN lf_ops.politicas_sesion ps ON ps.session_policy_id=c.session_policy_id
LEFT JOIN lf_ops.politicas_seguridad pg ON pg.security_policy_id=c.security_policy_id
CROSS JOIN LATERAL (
 SELECT coalesce(
    CASE WHEN c.rule_id IS NOT NULL THEN encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') END,
    CASE WHEN c.rate_limit_policy_id IS NOT NULL THEN encode(sha256(convert_to(to_jsonb(pr)::text,'UTF8')),'hex') END,
    CASE WHEN c.timeout_policy_id IS NOT NULL THEN encode(sha256(convert_to(to_jsonb(pt)::text,'UTF8')),'hex') END,
    CASE WHEN c.session_policy_id IS NOT NULL THEN encode(sha256(convert_to(to_jsonb(ps)::text,'UTF8')),'hex') END,
    CASE WHEN c.security_policy_id IS NOT NULL THEN encode(sha256(convert_to(to_jsonb(pg)::text,'UTF8')),'hex') END
 ) AS current_source_hash,
 coalesce(r.estado,pr.status,pt.status,ps.status,pg.status) AS current_source_status
) cur;

-- Read-only bindings are concise: only source refs/IDs and fresh digest,
-- never copied rule text or policy configurations.
CREATE FUNCTION public.lf_input_family_catalog_context_v1(p_pantalla_id integer)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
WITH a AS (
 SELECT v.family_code,v.source_id,v.source_kind,v.rule_id,
  v.rate_limit_policy_id,v.timeout_policy_id,v.session_policy_id,v.security_policy_id,
  v.source_hash,v.freshness,v.legacy_evidence_route,
  v.semantic_equivalence,v.semantic_transferability,v.semantic_evidence_ref
 FROM public.v_lf_input_family_coverage_by_screen_v1 v
 WHERE v.pantalla_id=p_pantalla_id AND v.scope_applies
 AND v.catalog_status='ACTIVE'
)
SELECT jsonb_build_object(
 'schema_version','LF_FAMILY_SOURCE_CATALOG_REFERENCE_V1',
 'pantalla_id',p_pantalla_id,'source_count',count(*),
 'current_count',count(*) FILTER(WHERE freshness='CURRENT'),
 'stale_count',count(*) FILTER(WHERE freshness='STALE'),
 'catalog_ref','supabase://programacion.input_family_inheritable_sources_v1',
 'snapshot_sha256',encode(sha256(convert_to(
    coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.family_code,a.source_id),'[]'::jsonb)::text,'UTF8')),'hex'),
 'sources',coalesce(jsonb_agg(jsonb_build_object(
   'family_code',a.family_code,'source_id',a.source_id,
   'source_kind',a.source_kind,'rule_id',a.rule_id,
   'rate_limit_policy_id',a.rate_limit_policy_id,
   'timeout_policy_id',a.timeout_policy_id,'session_policy_id',a.session_policy_id,
   'security_policy_id',a.security_policy_id,
   'source_hash',a.source_hash,'freshness',a.freshness,
   'semantic_equivalence',a.semantic_equivalence,
   'semantic_transferability',a.semantic_transferability,
   'source_ref',a.semantic_evidence_ref
 ) ORDER BY a.family_code,a.source_id),'[]'::jsonb),
 'family_closure_verified',false,'production_authorized',false)
FROM a
$fn$;
CREATE FUNCTION public.lf_input_family_catalog_context_for_run_v1(p_execution_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
SELECT coalesce((
 SELECT public.lf_input_family_catalog_context_v1(s.id)
 FROM public.lf_operation_execution_steps e
 JOIN lf_ops.pantallas s ON s.codigo=e.evidence_payload#>>'{resolved_scope,resolved_screen_code}'
 WHERE e.execution_id=p_execution_id AND e.step_id='input_validate'
  AND e.status='STEP_PASS_WITH_EVIDENCE'
 LIMIT 1
),jsonb_build_object('schema_version','LF_FAMILY_SOURCE_CATALOG_REFERENCE_V1',
   'status','SCREEN_NOT_RESOLVED','source_count',0,'sources','[]'::jsonb,
   'family_closure_verified',false))
$fn$;
-- V1 public consumer keeps signature; run 956 is HISTORICAL EVIDENCE only.
CREATE OR REPLACE FUNCTION public.lf_input_family_reuse_before_propose_v1(
 p_pantalla_id integer,p_family_code text,p_run_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE v_active jsonb;v_stale jsonb;v_count integer;
BEGIN
 SELECT coalesce(jsonb_agg(jsonb_build_object('source_id',v.source_id,
    'source_kind',v.source_kind,'source_hash',v.source_hash,
    'rule_id',v.rule_id,'session_policy_id',v.session_policy_id,
    'rate_limit_policy_id',v.rate_limit_policy_id,
    'timeout_policy_id',v.timeout_policy_id,'security_policy_id',v.security_policy_id,
    'equivalence',v.semantic_equivalence,'transferability',v.semantic_transferability,
    'source_ref',v.semantic_evidence_ref,'legacy_evidence_route',v.legacy_evidence_route)
    ORDER BY v.source_id),'[]'::jsonb),count(*)::integer
 INTO v_active,v_count
 FROM public.v_lf_input_family_coverage_by_screen_v1 v
 WHERE v.pantalla_id=p_pantalla_id AND v.family_code=p_family_code
 AND v.scope_applies AND v.catalog_status='ACTIVE' AND v.freshness='CURRENT';
 SELECT coalesce(jsonb_agg(v.source_id ORDER BY v.source_id),'[]'::jsonb)
 INTO v_stale FROM public.v_lf_input_family_coverage_by_screen_v1 v
 WHERE v.pantalla_id=p_pantalla_id AND v.family_code=p_family_code
   AND v.scope_applies AND v.freshness='STALE';
 RETURN jsonb_build_object(
 'schema_version','LF_FAMILY_REUSE_REFERENCE_BEFORE_PROPOSE_V1',
 'status',CASE WHEN v_count>0 THEN 'REFERENCE_REUSE_AVAILABLE_WITH_FINDINGS'
 WHEN jsonb_array_length(v_stale)>0 THEN 'STALE_SOURCE_REVIEW'
 ELSE 'RETURN_TO_WORKER' END,
 'family_code',p_family_code,'pantalla_id',p_pantalla_id,
 'source_count',v_count,'source_references',v_active,
 'stale_source_ids',v_stale,
 'historical_assessment_ref',CASE WHEN p_run_id=956
   THEN 'supabase://programacion.input_family_reuse_map_v1/run/956'
   ELSE NULL END,
 'run_independent',true,'automatic_rule_creation',false,
 'closure_verified',false,'continuation_allowed',true,
 'return_to_worker',v_count=0,
 'next_action',CASE WHEN v_count>0 THEN 'REUSE_EXISTING_SOURCE_AND_VERIFY_RESIDUAL'
 ELSE 'CURATOR_FIND_SOURCE_OR_PROVIDE_SOLUTION_CASES_OR_CLOSED_OWNER_QUESTION' END);
END $fn$;
CREATE FUNCTION public.lf_input_family_reuse_claims_gate_v1(
 p_pantalla_id integer,p_claims jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE item jsonb;x record;v_found jsonb;v_findings jsonb:='[]'::jsonb;
 v_count integer:=0;v_action text;v_family text;v_source_id bigint;
BEGIN
 IF p_claims IS NULL THEN RETURN jsonb_build_object('schema_version',
  'LF_FAMILY_REUSE_CLAIMS_V1','status','NOT_APPLICABLE','continuation_allowed',true,
  'automatic_rule_creation',false); END IF;
 IF jsonb_typeof(p_claims)<>'array' THEN RETURN jsonb_build_object(
  'status','RETURN_TO_WORKER','code','FAMILY_CLAIMS_ARRAY_REQUIRED',
  'continuation_allowed',true,'automatic_rule_creation',false); END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_claims) LOOP
  v_count:=v_count+1;v_family:=item->>'family_code';v_action:=item->>'action';
  IF jsonb_typeof(item)<>'object' OR coalesce(v_family,'')='' OR
     v_action NOT IN('REUSE_REFERENCE','GAP','PROPOSE_RULE') THEN
   v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
    'code','V1_CLAIM_SOURCE_AND_ACTION_REQUIRED','family_code',v_family));
   CONTINUE;
  END IF;
  -- V2: no copied literal rule text/config or local policy parameters.
  IF item ?| ARRAY['rule_text','description_copy','policy_params',
      'local_parameters','policy_config','valor_config','source_payload','local_policy_code'] THEN
   v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
    'code','V2_REFERENCE_ONLY_NO_COPIED_CONTENT','family_code',v_family));
   CONTINUE;
  END IF;
  IF v_action='REUSE_REFERENCE' THEN
   IF coalesce(item->>'source_catalog_id','') !~ '^[0-9]+$' OR
      coalesce(item->>'source_hash','') !~ '^[0-9a-f]{64}$' THEN
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
     'code','V1_SOURCE_ID_HASH_REQUIRED','family_code',v_family)); CONTINUE;
   END IF;
   v_source_id:=(item->>'source_catalog_id')::bigint;
   SELECT v.* INTO x FROM public.v_lf_input_family_coverage_by_screen_v1 v
   WHERE v.pantalla_id=p_pantalla_id AND v.source_id=v_source_id
       AND v.family_code=v_family AND v.scope_applies AND v.freshness='CURRENT'
       AND v.catalog_status='ACTIVE';
   IF NOT FOUND OR x.source_hash IS DISTINCT FROM item->>'source_hash' THEN
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
      'code','V1_SOURCE_NOT_VIGENTE_OR_SCOPE_OR_HASH','family_code',v_family,
      'source_id',v_source_id)); CONTINUE;
   END IF;
   -- V3: One canonical parameter reference. Never duplicate local configs.
   IF x.source_kind='POLICY' AND (item ? 'parameter_values' OR item ? 'local_params') THEN
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
     'code','V3_DUPLICATE_POLICY_PARAMETERS','family_code',v_family)); CONTINUE;
   END IF;
  ELSE
   -- V4: do not create a candidate for the *same* source already heritable.
   IF v_action='PROPOSE_RULE' AND EXISTS(
      SELECT 1 FROM public.v_lf_input_family_coverage_by_screen_v1 v
      WHERE v.pantalla_id=p_pantalla_id AND v.family_code=v_family
       AND v.catalog_status='ACTIVE' AND v.freshness='CURRENT'
       AND v.scope_applies AND v.semantic_equivalence='EQUIVALENT_COMPONENT'
       AND v.semantic_transferability='TRANSFERABLE')
   THEN
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
      'code','V4_EXISTING_HERITABLE_SOURCE_USE_REFERENCE',
      'family_code',v_family)); CONTINUE;
   END IF;
   -- V5: every unresolved gap needs solution OR cases OR closed owner question.
   IF nullif(btrim(coalesce(item->>'solution','')),'') IS NULL AND
      (jsonb_typeof(item->'cases')<>'array' OR
       jsonb_array_length(coalesce(item->'cases','[]'::jsonb))=0) AND
      (jsonb_typeof(item->'owner_question')<>'object' OR
       nullif(item#>>'{owner_question,recommended_option}','') IS NULL) THEN
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
       'code','V5_GAP_SOLUTION_CASES_OR_OWNER_QUESTION_REQUIRED',
       'family_code',v_family));
   END IF;
  END IF;
 END LOOP;
 RETURN jsonb_build_object(
  'schema_version','LF_FAMILY_REUSE_CLAIMS_V1',
  'status',CASE WHEN jsonb_array_length(v_findings)>0 THEN 'RETURN_TO_WORKER'
    ELSE 'REFERENCE_CLAIMS_READY_FOR_INDEPENDENT_REVIEW' END,
  'code',CASE WHEN jsonb_array_length(v_findings)>0 THEN 'FAMILY_REFERENCE_CONTENT_FINDINGS'
    ELSE NULL END,
  'screen_id',p_pantalla_id,'claims_checked',v_count,
  'findings',v_findings,'continuation_allowed',true,
  'automatic_rule_creation',false,'no_implementation_claim',true,
  'next_action',CASE WHEN jsonb_array_length(v_findings)>0
   THEN 'RETURN_TO_WORKER_FIX_SOURCE_OR_GAP' ELSE 'INDEPENDENT_SEMANTIC_TRANSFERABILITY_JUDGE' END);
END $fn$;

-- Step70-specific independent semantic review contract. No invented model
-- receipt. This function only VALIDATES a submitted judge's evidence and never
-- represents itself as the independent judge.
CREATE FUNCTION public.lf_input_family_semantic_transfer_eval_v1(
 p_pantalla_id integer,p_claims jsonb,p_judge jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE v_gate jsonb;v_claim jsonb;v_review jsonb;v_count integer:=0;v_fail jsonb:='[]'::jsonb;
BEGIN
 v_gate:=public.lf_input_family_reuse_claims_gate_v1(p_pantalla_id,p_claims);
 IF v_gate->>'status'='NOT_APPLICABLE' THEN RETURN jsonb_build_object(
  'schema_version','LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1','status','NOT_APPLICABLE'); END IF;
 IF v_gate->>'status'='RETURN_TO_WORKER' THEN RETURN v_gate||jsonb_build_object(
   'schema_version','LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1'); END IF;
 IF p_judge->>'schema_version'<>'LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1'
 OR jsonb_typeof(p_judge->'reviews')<>'array' THEN
  RETURN jsonb_build_object('schema_version','LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1',
    'status','RETURN_TO_WORKER','code','INDEPENDENT_FAMILY_JUDGE_SCHEMA_REQUIRED',
    'continuation_allowed',true); END IF;
 FOR v_claim IN SELECT value FROM jsonb_array_elements(p_claims) LOOP
   v_count:=v_count+1;
   SELECT x.value INTO v_review FROM jsonb_array_elements(p_judge->'reviews') x(value)
   WHERE x.value->>'family_code'=v_claim->>'family_code'
    AND x.value->>'action'=v_claim->>'action'
    AND (v_claim->>'action'<>'REUSE_REFERENCE'
       OR (x.value->>'source_catalog_id'=v_claim->>'source_catalog_id'
         AND x.value->>'source_hash'=v_claim->>'source_hash'))
   LIMIT 1;
   IF v_review IS NULL OR v_review->>'equivalence' NOT IN
     ('EQUIVALENT_COMPONENT','PARTIAL_BASE','GAP_NO_SOURCE')
    OR v_review->>'transferability' NOT IN('TRANSFERABLE','CONDITIONAL','NOT_TRANSFERABLE')
    OR nullif(btrim(coalesce(v_review->>'reason','')),'') IS NULL
    OR jsonb_typeof(v_review->'source_refs')<>'array'
    OR jsonb_array_length(coalesce(v_review->'source_refs','[]'::jsonb))=0 THEN
     v_fail:=v_fail||jsonb_build_array(jsonb_build_object(
       'family_code',v_claim->>'family_code','code','INDEPENDENT_FAMILY_EVALUATION_MISSING'));
   END IF;
   v_review:=NULL;
 END LOOP;
 RETURN jsonb_build_object('schema_version','LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1',
 'status',CASE WHEN jsonb_array_length(v_fail)=0 THEN 'JUDGE_EVIDENCE_VALIDATED'
   ELSE 'RETURN_TO_WORKER' END,'reviews_checked',v_count,
 'findings',v_fail,'continuation_allowed',true,
 'independence_not_proven_by_this_function',true,
 'actual_independent_receipt_required',true);
END $fn$;

-- Service-only reader, public view still subject to ACL.
REVOKE ALL ON programacion.input_family_inheritable_sources_v1 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON programacion.input_family_inheritable_members_v1 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION programacion.fn_lf_family_ref_member_guard_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_input_family_reuse_before_propose_v1(integer,text,bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_input_family_catalog_context_v1(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_input_family_catalog_context_for_run_v1(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_input_family_reuse_claims_gate_v1(integer,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_input_family_semantic_transfer_eval_v1(integer,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.v_lf_input_family_coverage_by_screen_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON programacion.input_family_inheritable_sources_v1 TO service_role;
GRANT SELECT ON programacion.input_family_inheritable_members_v1 TO service_role;
GRANT SELECT ON public.v_lf_input_family_coverage_by_screen_v1 TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_input_family_reuse_before_propose_v1(integer,text,bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_input_family_catalog_context_v1(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_input_family_catalog_context_for_run_v1(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_input_family_reuse_claims_gate_v1(integer,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_input_family_semantic_transfer_eval_v1(integer,jsonb,jsonb) TO service_role;
COMMIT;
