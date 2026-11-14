-- LF 2026-11-14. Read-only V2 dual gate; V1 and the historic 262+8 untouched.
-- Owner directive: never require a screen for backend rules; 5+ belongs only to POLICY.
-- No promotion, state change, screen linkage or owner identity update.
BEGIN;
DO $pre$
BEGIN
 IF to_regprocedure('programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)') IS NULL
    OR md5(pg_get_functiondef('programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)'::regprocedure))
     <> '92e8025b70d17e3de7da7206795ed73d'
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_HISTORIC_V1_SOURCE_DRIFT'; END IF;
 IF to_regprocedure('public.lf_rule_promotion_request_v1(text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_EXISTING_PROMOTION_ROUTE_MISSING'; END IF;
 IF to_regprocedure('programacion.fn_t_remed_rule_promotion_verdicts_v2(bigint)') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_ALREADY_INSTALLED'; END IF;
END $pre$;

-- Verifiable server catalog evidence; NEVER trust an unverified process or edge slug.
CREATE FUNCTION programacion.fn_lf_rule_scope_object_verified_v2(
 p_type text,p_ref text
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE a text[];
BEGIN
 IF p_ref IS NULL OR length(p_ref)>200 OR p_type IS NULL THEN RETURN false; END IF;
 CASE upper(p_type)
 WHEN 'TABLE' THEN
  IF p_ref !~ '^[a-z_][a-z0-9_]*[.][a-z_][a-z0-9_]*$'
  THEN RETURN false; END IF;
  RETURN to_regclass(p_ref) IS NOT NULL;
 WHEN 'FUNCTION' THEN
  IF p_ref !~ '^[a-z_][a-z0-9_]*[.][a-z_][a-z0-9_]*$'
  THEN RETURN false; END IF;
  a:=string_to_array(p_ref,'.');
  RETURN (SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname=a[1] AND p.proname=a[2]);
 WHEN 'PROCESS' THEN
  RETURN EXISTS(SELECT 1 FROM public.lf_operation_contracts
                WHERE operation_code=p_ref AND coalesce(contract_sha,'')<>'');
 WHEN 'POLICY' THEN
  RETURN EXISTS(SELECT 1 FROM lf_ops.politicas_seguridad WHERE policy_code=p_ref);
 WHEN 'EDGE_FUNCTION' THEN
  -- No authoritative, readable edge-deploy registry verified here. A freeform
  -- slug is not proof: require curated evidence and return REVIEW_SCOPE.
  RETURN false;
 ELSE RETURN false;
 END CASE;
END $fn$;

CREATE FUNCTION programacion.fn_t_remed_rule_promotion_verdicts_v2(
 p_regla_id bigint DEFAULT NULL
)
RETURNS TABLE (
 regla_id bigint,regla_codigo text,rule_state text,screens integer,
 scope_route text,scope_evidence jsonb,criteria jsonb,
 vigente_verdict text,failed text[],
 scope_review_required boolean,policy_breadth_pass boolean,
 policy_verdict text,fast_track boolean,step70_independent_required boolean,
 continuation_allowed boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops','public'
AS $fn$
WITH RECURSIVE
r AS (SELECT * FROM lf_ops.reglas WHERE estado IN ('CANDIDATO','VIGENTE')
      AND (p_regla_id IS NULL OR id=p_regla_id)),
j(rid,path,val) AS (
 SELECT id,''::text,valor_config FROM r
 WHERE jsonb_typeof(valor_config) IN ('object','array')
 UNION ALL
 SELECT j.rid,j.path||'/'||e.k,e.v FROM j CROSS JOIN LATERAL (
   SELECT k,v FROM jsonb_each(
      CASE WHEN jsonb_typeof(j.val)='object' THEN j.val ELSE '{}'::jsonb END) o(k,v)
   UNION ALL
   SELECT (a.i-1)::text,a.v FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(j.val)='array' THEN j.val ELSE '[]'::jsonb END)
      WITH ORDINALITY a(v,i)
 )e WHERE jsonb_typeof(j.val) IN ('object','array')
),
pending AS (
 SELECT rid,count(*)::int cnt FROM j
 WHERE jsonb_typeof(val)='string'
 AND (val#>>'{}') ~* '(pending|pendiente)'
 AND path <> '/implementation_status'
 AND CASE WHEN (val#>>'{}') ~ '^PENDING_CANONICAL_' THEN 'CANONICAL_SOURCE'
          WHEN (val#>>'{}') ~* '^PENDING_.*(LEGAL|BUSINESS)' THEN 'LEGAL_BUSINESS'
          WHEN (val#>>'{}') ~* '^PENDING_.*COPY' THEN 'COPY'
          WHEN (val#>>'{}') ~* '^(PENDING|PENDIENTE)([_ ].*)?$' THEN 'OTHER_PENDING'
          ELSE 'STATE_WORD' END <> 'STATE_WORD'
 GROUP BY rid
),
n AS (SELECT regla_id,count(DISTINCT pantalla_id)::int c
      FROM lf_ops.reglas_pantallas GROUP BY 1),
raw AS (
 SELECT r.id,r.codigo,r.estado,r.categoria,r.valor_config,r.es_transversal,
 COALESCE(n.c,0) screens,
 NOT COALESCE(r.pendiente_decision,false) no_pending_decision,
 COALESCE(pending.cnt,0)=0 no_pending_marker,
 nullif(btrim(coalesce(r.razon,'')),'') IS NOT NULL has_reason,
 NOT (r.valor_config IS NOT NULL AND r.valor_config<>'{}'::jsonb AND EXISTS(
   SELECT 1 FROM lf_ops.reglas o WHERE o.id<>r.id
    AND o.estado IN ('VIGENTE','CANDIDATO')
    AND o.categoria IS NOT DISTINCT FROM r.categoria
    AND o.valor_config=r.valor_config)) no_duplicate,
 nullif(btrim(coalesce(r.valor_config->>'scope',
      r.valor_config->>'alcance',r.valor_config->>'aplica_a',
      r.valor_config->>'applies_to','')),'') declared_scope,
 nullif(btrim(coalesce(r.valor_config->>'tabla_afectada',
      r.valor_config->>'current_route_registry',
      r.valor_config->>'runtime_source',
      r.valor_config->>'canonical_table','')),'') legacy_table_ref,
 r.valor_config->'scope_evidence_v2' structured
 FROM r LEFT JOIN n ON n.regla_id=r.id
 LEFT JOIN pending ON pending.rid=r.id
),
checked AS (
 SELECT raw.*,
 (coalesce(es_transversal,false) AND
  coalesce(nullif(btrim(coalesce(structured->>'declared_scope',declared_scope,'')),''),'')
    !~* '^(PENDING|UNRESOLVED|TBD|UNKNOWN)$' AND
  nullif(btrim(coalesce(structured->>'declared_scope',declared_scope,'')),'') IS NOT NULL
 ) transverse_scope_verified,
 CASE WHEN structured->>'object_type' IS NOT NULL
           AND nullif(btrim(coalesce(structured->>'evidence_ref','')),'') IS NOT NULL
      THEN programacion.fn_lf_rule_scope_object_verified_v2(
            structured->>'object_type',structured->>'object_ref')
      WHEN legacy_table_ref IS NOT NULL
      THEN programacion.fn_lf_rule_scope_object_verified_v2('TABLE',legacy_table_ref)
      ELSE false END backend_verified
 FROM raw
),
scope AS (
 SELECT *,
 CASE WHEN screens>=5 THEN 'FAST_5_PLUS'
      WHEN screens>=1 THEN 'SCREEN_LINK'
      WHEN transverse_scope_verified THEN 'TRANSVERSAL_DECLARED'
      WHEN backend_verified THEN 'BACKEND_OBJECT_VERIFIED'
      ELSE 'SCOPE_REVIEW' END route,
 (no_pending_decision AND no_pending_marker AND has_reason AND no_duplicate)
   AS quality_ok,
 (screens>=5 OR coalesce(es_transversal,false)) AS policy_breadth_ok
 FROM checked
),
criteria_row AS (
 SELECT *,jsonb_build_object(
   'NO_PENDING_DECISION',no_pending_decision,
   'NO_PENDING_MARKER',no_pending_marker,
   'HAS_STATED_REASON',has_reason,
   'SCOPE_EVIDENCE',route<>'SCOPE_REVIEW',
   'NO_DUPLICATE_ACTIVE_RULE',no_duplicate) crit
 FROM scope
)
SELECT id::bigint,codigo::text,estado::text,screens,route::text,
 jsonb_build_object('screen_count',screens,
   'transversal',coalesce(es_transversal,false),
   'declared_scope',coalesce(structured->>'declared_scope',declared_scope),
   'verified_backend_object',backend_verified,
   'object_type',coalesce(structured->>'object_type',
        CASE WHEN legacy_table_ref IS NOT NULL THEN 'TABLE' ELSE NULL END),
   'object_ref',coalesce(structured->>'object_ref',legacy_table_ref),
   'source_kind',CASE WHEN structured->>'object_type' IS NOT NULL
        THEN 'GOVERNED_STRUCTURED_EVIDENCE'
        WHEN legacy_table_ref IS NOT NULL THEN 'LEGACY_EXPLICIT_RULE_REFERENCE'
        WHEN route='SCOPE_REVIEW' THEN 'NOT_YET_VERIFIED'
        ELSE 'CANONICAL_RULE_SCREEN_OR_DECLARED_SCOPE' END
 )::jsonb,crit,
 CASE WHEN NOT quality_ok THEN 'HOLD_CONTENT_FINDINGS'
      WHEN route='SCOPE_REVIEW' THEN 'REVIEW_SCOPE'
      ELSE 'PASS' END::text,
 ARRAY(SELECT e.key::text FROM jsonb_each(crit) e
       WHERE e.value='false'::jsonb ORDER BY e.key),
 (route='SCOPE_REVIEW'),policy_breadth_ok,
 CASE WHEN NOT quality_ok THEN 'HOLD_CONTENT_FINDINGS'
      WHEN policy_breadth_ok THEN 'PASS_BREADTH'
      ELSE 'REVIEW_POLICY_BREADTH' END::text,
 (quality_ok AND screens>=5),
 true,true
FROM criteria_row ORDER BY id;
$fn$;

-- Only the existing authorized service role can inspect the V2 classification.
CREATE FUNCTION public.lf_rule_promotion_verdicts_readonly_v2(
 p_regla_id bigint DEFAULT NULL
) RETURNS TABLE (
 regla_id bigint,regla_codigo text,rule_state text,screens integer,
 scope_route text,scope_evidence jsonb,criteria jsonb,
 vigente_verdict text,failed text[],
 scope_review_required boolean,policy_breadth_pass boolean,
 policy_verdict text,fast_track boolean,step70_independent_required boolean,
 continuation_allowed boolean
) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion'
AS $fn$
 SELECT * FROM programacion.fn_t_remed_rule_promotion_verdicts_v2(p_regla_id);
$fn$;
REVOKE ALL ON FUNCTION programacion.fn_lf_rule_scope_object_verified_v2(text,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION programacion.fn_t_remed_rule_promotion_verdicts_v2(bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_verdicts_readonly_v2(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_verdicts_readonly_v2(bigint)
  TO service_role;
DO $readback$
BEGIN
 IF md5(pg_get_functiondef('programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)'::regprocedure))
    <> '92e8025b70d17e3de7da7206795ed73d'
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_LEGACY_V1_MUTATED'; END IF;
 IF to_regprocedure('public.lf_rule_promotion_verdicts_readonly_v2(bigint)') IS NULL
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_READBACK_MISSING'; END IF;
END $readback$;

-- Atomic EKB append in the SAME migration: LF Train accepts 1 new migration/PR.
DO $ekb$
BEGIN
 IF to_regprocedure('programacion.fn_t_remed_rule_promotion_verdicts_v2(bigint)') IS NULL
 THEN RAISE EXCEPTION 'LF_SCOPE_EKB_V2_NOT_INSTALLED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
   WHERE codigo='LF-PROMO-SCREEN-CRITERION-MISPLACED-20261114-001')
 THEN RAISE EXCEPTION 'LF_SCOPE_EKB_ALREADY_RECORDED'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
 created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
 detectability,source_context,source_ref)
 VALUES (
 gen_random_uuid(),
 'LF-PROMO-SCREEN-CRITERION-MISPLACED-20261114-001',
 'RULE_GOVERNANCE',
 'Umbral de cinco pantallas mal ubicado en puerta de vigencia',
 'SELECT 2026-11-14: 124/412 VIGENTE tienen menos de cinco pantallas; 34/412 cero. 148/166 CANDIDATO bajo cinco. V1 usa USED_BY_ENOUGH_SCREENS y mezcla calidad con amplitud de politica. Regla backend sin pantalla no debe quedar descartada por falta de pantalla.',
 'El mapeo regla-pantalla lo realiza Curator y es circular exigir cinco vinculaciones previas. La amplitud transversal y backend exige evidencia de alcance, no cantidad de pantallas.',
 'SCREEN_COUNT_CIRCULAR_DEPENDENCY_AND_POLICY_SCOPE_CONFLATION',
 'Separar VIGENTE: calidad+SCOPE_EVIDENCE (1 pantalla, alcance transversal declarado, objeto backend catalogado, o REVIEW_SCOPE sin veto de flujo). Separar POLITICA: 5+ o es_transversal. Conservar paso70 juez independiente e identidad humana. No relabel legacy 262+8 ni cambiar V1.',
 'SELECT lf_ops.reglas/reglas_pantallas; pg_get_functiondef V1 MD5=92e8025b70d17e3de7da7206795ed73d; V2 source-first; PG17/18 ROLLBACK; #3854 es promocion de politicas 19/22, no habilita bypass de la ruta regla->politica.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'LF_PROMOTION_SCOPE_EVIDENCE_DUAL_GATE_20261114','PR_GOVERNED','ACTIVO',
 'SELECT 166 + 412; no promotion requested/applied',
 clock_timestamp(),clock_timestamp(),'RULE_GOVERNANCE',
 ARRAY['PRODUCT_DIRECTOR','INPUT_GOVERNANCE_CURATOR','ENGINEERING','UI_ARCHITECT'],
 'R5_EROSION_PROCESO','LOUD_EARLY',
 'Owner instruction 2026-11-14. Preserve all historic rule states and policy bindings',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3854'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge
 WHERE codigo='LF-PROMO-SCREEN-CRITERION-MISPLACED-20261114-001'
  AND estado='ACTIVO')<>1
 THEN RAISE EXCEPTION 'LF_SCOPE_EKB_READBACK_MISSING'; END IF;
END $ekb$;
COMMIT;
