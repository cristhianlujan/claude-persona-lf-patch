-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M2.2 / PAULO-018
-- Preserve the canonical resolver surface. Empty canonical collections are resolvable evidence;
-- missing/malformed refs and non-empty cardinality mismatches remain fail-closed.
-- No parallel source resolver, no runtime activation.

DO $m2_2_preflight$
DECLARE
  v_contract_revision text;
  v_empty_semantics text;
BEGIN
  IF md5(pg_get_functiondef('programacion.fn_input_resolve_source_ref(jsonb,integer,bigint)'::regprocedure))
       <> '7c79c5f5bc42fbc2d9ff2b0134f5a7ee' THEN
    RAISE EXCEPTION 'M2_2_RESOLVER_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_resolve_source_ref_v510(jsonb,integer,bigint)'::regprocedure))
       <> '50073e4d4d4dd0dfeaf091b3df763fb3' THEN
    RAISE EXCEPTION 'M2_2_RESOLVER_V510_DRIFT';
  END IF;

  SELECT especificacion->>'contract_revision', especificacion->>'empty_collection_semantics'
    INTO v_contract_revision, v_empty_semantics
  FROM programacion.contratos
  WHERE contrato_codigo='INPUT_READINESS_CONTRACT'
  ORDER BY version_id DESC
  LIMIT 1;

  IF v_contract_revision IS DISTINCT FROM '5.13'
     OR v_empty_semantics IS DISTINCT FROM 'CANONICAL_EMPTY_ARRAY_IS_RESOLVABLE_EVIDENCE' THEN
    RAISE EXCEPTION 'M2_2_CONTRACT_SEMANTICS_DRIFT:revision=% semantics=%',
      v_contract_revision, v_empty_semantics;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code LIKE 'M2_2_KIND_%'
  ) THEN
    RAISE EXCEPTION 'M2_2_CASES_ALREADY_EXIST';
  END IF;
END
$m2_2_preflight$;

CREATE OR REPLACE FUNCTION programacion.fn_input_resolve_source_ref_v510(
  p_ref jsonb,
  p_pantalla_id integer,
  p_version_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'programacion', 'lf_ops', 'transversal'
AS $function$
DECLARE
  v_kind text := p_ref->>'kind';
  v_observed jsonb;
  v_code text;
  v_codes text[];
  v_ids bigint[];
  v_expected integer;
  v_actual integer;
  v_capability text;
  v_relations jsonb := '[]'::jsonb;
  v_rules jsonb := '[]'::jsonb;
BEGIN
  IF jsonb_typeof(p_ref) <> 'object' OR coalesce(v_kind,'')='' THEN
    RAISE EXCEPTION 'INVALID_STRUCTURED_SOURCE_REF';
  END IF;

  CASE v_kind
    WHEN 'SCREEN' THEN
      SELECT to_jsonb(p) INTO v_observed
      FROM lf_ops.pantallas p
      WHERE p.id=p_pantalla_id;
      IF v_observed IS NULL THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:SCREEN:%',p_pantalla_id;
      END IF;

    WHEN 'SCREEN_RULE_SET' THEN
      SELECT jsonb_build_object(
        'screen',to_jsonb(p),
        'rules',coalesce((
          SELECT jsonb_agg(jsonb_build_object('link',to_jsonb(rp),'rule',to_jsonb(r)) ORDER BY r.id)
          FROM programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
          JOIN lf_ops.reglas r ON r.id=rp.regla_id
          WHERE rp.pantalla_id=p.id
        ),'[]'::jsonb)
      )
      INTO v_observed
      FROM lf_ops.pantallas p
      WHERE p.id=p_pantalla_id;
      IF v_observed IS NULL THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:SCREEN_RULE_SET:%',p_pantalla_id;
      END IF;

    WHEN 'RULE' THEN
      v_code:=p_ref->>'codigo';
      SELECT to_jsonb(r) INTO v_observed
      FROM lf_ops.reglas r
      WHERE r.codigo=v_code;
      IF v_observed IS NULL THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:RULE:%',coalesce(v_code,'NULL');
      END IF;

    WHEN 'ROUTE_SET' THEN
      IF NOT (p_ref ? 'ids') OR jsonb_typeof(p_ref->'ids') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_ROUTE_SET_REF';
      END IF;
      IF jsonb_array_length(p_ref->'ids')=0 THEN
        v_observed:='[]'::jsonb;
      ELSE
        SELECT array_agg(x::bigint ORDER BY x::bigint)
          INTO v_ids
        FROM jsonb_array_elements_text(p_ref->'ids') x;
        v_expected:=cardinality(v_ids);
        SELECT count(*),coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.route_id),'[]'::jsonb)
          INTO v_actual,v_observed
        FROM lf_ops.rutas r
        WHERE r.route_id=any(v_ids);
        IF v_actual<>v_expected THEN
          RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:ROUTE_SET expected=% actual=%',v_expected,v_actual;
        END IF;
      END IF;

    WHEN 'SECURITY_POLICY_SET' THEN
      IF NOT (p_ref ? 'ids') OR jsonb_typeof(p_ref->'ids') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_SECURITY_POLICY_SET_REF';
      END IF;
      IF jsonb_array_length(p_ref->'ids')=0 THEN
        v_observed:='[]'::jsonb;
      ELSE
        SELECT array_agg(x::bigint ORDER BY x::bigint)
          INTO v_ids
        FROM jsonb_array_elements_text(p_ref->'ids') x;
        v_expected:=cardinality(v_ids);
        SELECT count(*),coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.security_policy_id),'[]'::jsonb)
          INTO v_actual,v_observed
        FROM lf_ops.politicas_seguridad s
        WHERE s.security_policy_id=any(v_ids);
        IF v_actual<>v_expected THEN
          RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:SECURITY_POLICY_SET expected=% actual=%',v_expected,v_actual;
        END IF;
      END IF;

    WHEN 'TRANSITION_SET' THEN
      IF NOT (p_ref ? 'ids') OR jsonb_typeof(p_ref->'ids') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_TRANSITION_SET_REF';
      END IF;
      IF jsonb_array_length(p_ref->'ids')=0 THEN
        v_observed:='[]'::jsonb;
      ELSE
        SELECT array_agg(x::bigint ORDER BY x::bigint)
          INTO v_ids
        FROM jsonb_array_elements_text(p_ref->'ids') x;
        v_expected:=cardinality(v_ids);
        SELECT count(*),coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.transition_id),'[]'::jsonb)
          INTO v_actual,v_observed
        FROM lf_ops.estados_transiciones t
        WHERE t.transition_id=any(v_ids);
        IF v_actual<>v_expected THEN
          RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:TRANSITION_SET expected=% actual=%',v_expected,v_actual;
        END IF;
      END IF;

    WHEN 'SCREEN_STATE_SET' THEN
      IF NOT EXISTS(SELECT 1 FROM lf_ops.pantallas p WHERE p.id=p_pantalla_id) THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:SCREEN_STATE_SET_SCREEN:%',p_pantalla_id;
      END IF;
      SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.state_id),'[]'::jsonb)
        INTO v_observed
      FROM lf_ops.pantallas_estados s
      WHERE s.pantalla_id=p_pantalla_id;

    WHEN 'CURRENT_VISUAL_ARTIFACT' THEN
      IF NOT EXISTS(SELECT 1 FROM lf_ops.pantallas p WHERE p.id=p_pantalla_id) THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:CURRENT_VISUAL_ARTIFACT_SCREEN:%',p_pantalla_id;
      END IF;
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'artifact',to_jsonb(a),
        'storage_exists',CASE WHEN a.storage_bucket IS NOT NULL AND a.storage_object_path IS NOT NULL
          THEN EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id=a.storage_bucket AND o.name=a.storage_object_path)
          ELSE false END
      ) ORDER BY a.id),'[]'::jsonb)
        INTO v_observed
      FROM lf_ops.pantalla_artefactos a
      WHERE a.pantalla_id=p_pantalla_id AND a.is_current=true;

    WHEN 'EKB_ERROR_SET' THEN
      IF NOT (p_ref ? 'codes') OR jsonb_typeof(p_ref->'codes') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_EKB_ERROR_SET_REF';
      END IF;
      IF jsonb_array_length(p_ref->'codes')=0 THEN
        v_observed:='[]'::jsonb;
      ELSE
        SELECT array_agg(x ORDER BY x)
          INTO v_codes
        FROM jsonb_array_elements_text(p_ref->'codes') x;
        v_expected:=cardinality(v_codes);
        SELECT count(*),coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.codigo),'[]'::jsonb)
          INTO v_actual,v_observed
        FROM transversal.error_knowledge e
        WHERE e.codigo=any(v_codes);
        IF v_actual<>v_expected THEN
          RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:EKB_ERROR_SET expected=% actual=%',v_expected,v_actual;
        END IF;
      END IF;

    WHEN 'EKB_PREVENTION_SET' THEN
      IF NOT (p_ref ? 'codes') OR jsonb_typeof(p_ref->'codes') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_EKB_PREVENTION_SET_REF';
      END IF;
      IF jsonb_array_length(p_ref->'codes')=0 THEN
        v_observed:='[]'::jsonb;
      ELSE
        SELECT array_agg(x ORDER BY x)
          INTO v_codes
        FROM jsonb_array_elements_text(p_ref->'codes') x;
        v_expected:=cardinality(v_codes);
        SELECT count(*),coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.regla_codigo),'[]'::jsonb)
          INTO v_actual,v_observed
        FROM transversal.prevention_rules e
        WHERE e.regla_codigo=any(v_codes);
        IF v_actual<>v_expected THEN
          RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:EKB_PREVENTION_SET expected=% actual=%',v_expected,v_actual;
        END IF;
      END IF;

    WHEN 'EKB_DECISION_SET' THEN
      IF NOT (p_ref ? 'adrs') OR jsonb_typeof(p_ref->'adrs') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_EKB_DECISION_SET_REF';
      END IF;
      IF jsonb_array_length(p_ref->'adrs')=0 THEN
        v_observed:='[]'::jsonb;
      ELSE
        SELECT array_agg(x ORDER BY x)
          INTO v_codes
        FROM jsonb_array_elements_text(p_ref->'adrs') x;
        v_expected:=cardinality(v_codes);
        SELECT count(*),coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.adr),'[]'::jsonb)
          INTO v_actual,v_observed
        FROM transversal.decision_log d
        WHERE d.adr=any(v_codes);
        IF v_actual<>v_expected THEN
          RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:EKB_DECISION_SET expected=% actual=%',v_expected,v_actual;
        END IF;
      END IF;

    WHEN 'CONTRACT' THEN
      v_code:=p_ref->>'codigo';
      SELECT to_jsonb(c) INTO v_observed
      FROM programacion.contratos c
      WHERE c.version_id=p_version_id AND c.contrato_codigo=v_code;
      IF v_observed IS NULL THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:CONTRACT:%',coalesce(v_code,'NULL');
      END IF;

    WHEN 'CAPABILITY_ABSENCE' THEN
      v_capability:=upper(p_ref->>'capability');
      IF v_capability NOT IN ('FEATURE_FLAGS','I18N_FORMATS') THEN
        RAISE EXCEPTION 'UNSUPPORTED_CAPABILITY_ABSENCE:%',coalesce(v_capability,'NULL');
      END IF;
      IF v_capability='FEATURE_FLAGS' THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname) ORDER BY n.nspname,c.relname),'[]'::jsonb)
          INTO v_relations
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('lf_ops','lf_design') AND c.relkind IN ('r','v','m')
          AND lower(c.relname) ~ '(feature.*flag|flag.*feature)';
        SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'categoria',r.categoria) ORDER BY r.codigo),'[]'::jsonb)
          INTO v_rules
        FROM programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
        JOIN lf_ops.reglas r ON r.id=rp.regla_id
        WHERE rp.pantalla_id=p_pantalla_id AND r.codigo<>'B2B-RULE-STORY-READINESS-001'
          AND (upper(coalesce(r.categoria,'')) IN ('FEATURE_FLAG','FEATURE_FLAGS') OR upper(r.codigo) LIKE '%FEATURE%FLAG%');
      ELSE
        SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname) ORDER BY n.nspname,c.relname),'[]'::jsonb)
          INTO v_relations
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('lf_ops','lf_design') AND c.relkind IN ('r','v','m')
          AND lower(c.relname) ~ '(i18n|locale|localization|localisation)';
        SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'categoria',r.categoria) ORDER BY r.codigo),'[]'::jsonb)
          INTO v_rules
        FROM programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
        JOIN lf_ops.reglas r ON r.id=rp.regla_id
        WHERE rp.pantalla_id=p_pantalla_id AND r.codigo<>'B2B-RULE-STORY-READINESS-001'
          AND upper(coalesce(r.categoria,'')) IN ('I18N','LOCALIZATION','LOCALISATION','LOCALE');
      END IF;
      IF jsonb_array_length(v_relations)>0 OR jsonb_array_length(v_rules)>0 THEN
        RAISE EXCEPTION 'CAPABILITY_ABSENCE_ASSERTION_FALSE:%',v_capability;
      END IF;
      v_observed:=jsonb_build_object(
        'capability',v_capability,
        'matching_relations',v_relations,
        'matching_linked_rules',v_rules,
        'pantalla_id',p_pantalla_id
      );

    ELSE
      RAISE EXCEPTION 'UNSUPPORTED_SOURCE_REF_KIND:%',v_kind;
  END CASE;

  RETURN jsonb_build_object(
    'ref',p_ref,
    'observed',v_observed,
    'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_resolve_source_ref(
  p_ref jsonb,
  p_pantalla_id integer,
  p_version_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
DECLARE
  v_kind text:=p_ref->>'kind';
  v_ids bigint[];
  v_expected integer;
  v_actual integer;
  v_observed jsonb;
BEGIN
  IF v_kind='SCREEN_CANONICAL_GRAPH' THEN
    IF NOT (p_ref?'pantalla_id') OR (p_ref->>'pantalla_id')::integer<>p_pantalla_id THEN
      RAISE EXCEPTION 'SCREEN_CANONICAL_GRAPH_REQUIRES_EXPLICIT_PANTALLA_ID:%',p_pantalla_id;
    END IF;
    v_observed:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
    RETURN jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));

  ELSIF v_kind='ERROR_SET' THEN
    IF NOT (p_ref ? 'ids') OR jsonb_typeof(p_ref->'ids') <> 'array' THEN
      RAISE EXCEPTION 'INVALID_ERROR_SET_REF';
    END IF;
    IF jsonb_array_length(p_ref->'ids')=0 THEN
      v_observed:='[]'::jsonb;
    ELSE
      SELECT array_agg(x::bigint ORDER BY x::bigint)
        INTO v_ids
      FROM jsonb_array_elements_text(p_ref->'ids') x;
      v_expected:=cardinality(v_ids);
      SELECT count(*),coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.error_id),'[]'::jsonb)
        INTO v_actual,v_observed
      FROM lf_ops.errores_catalogo e
      WHERE e.error_id=any(v_ids);
      IF v_actual<>v_expected THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:ERROR_SET expected=% actual=%',v_expected,v_actual;
      END IF;
    END IF;
    RETURN jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));

  ELSIF v_kind='MESSAGE_SET' THEN
    IF NOT (p_ref ? 'ids') OR jsonb_typeof(p_ref->'ids') <> 'array' THEN
      RAISE EXCEPTION 'INVALID_MESSAGE_SET_REF';
    END IF;
    IF jsonb_array_length(p_ref->'ids')=0 THEN
      v_observed:='[]'::jsonb;
    ELSE
      SELECT array_agg(x::bigint ORDER BY x::bigint)
        INTO v_ids
      FROM jsonb_array_elements_text(p_ref->'ids') x;
      v_expected:=cardinality(v_ids);
      SELECT count(*),coalesce(jsonb_agg(jsonb_build_object(
        'message',to_jsonb(m),
        'screen_links',coalesce((
          SELECT jsonb_agg(to_jsonb(mp) ORDER BY mp.message_screen_id)
          FROM lf_ops.mensajes_pantallas mp
          WHERE mp.message_id=m.message_id
        ),'[]'::jsonb)
      ) ORDER BY m.message_id),'[]'::jsonb)
        INTO v_actual,v_observed
      FROM lf_ops.mensajes_ui m
      WHERE m.message_id=any(v_ids);
      IF v_actual<>v_expected THEN
        RAISE EXCEPTION 'SOURCE_REF_UNRESOLVED:MESSAGE_SET expected=% actual=%',v_expected,v_actual;
      END IF;
    END IF;
    RETURN jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));
  END IF;

  RETURN programacion.fn_input_resolve_source_ref_v510(p_ref,p_pantalla_id,p_version_id);
END;
$function$;

DO $m2_2_behavior$
DECLARE
  v_kind text;
  v_key text;
  v_empty_ref jsonb;
  v_missing_ref jsonb;
  v_cardinality_ref jsonb;
  v_positive_ref jsonb;
  v_receipt jsonb;
  v_pantalla_id integer;
  v_version_id bigint;
  v_rejected boolean;
  v_kinds constant text[] := ARRAY[
    'ERROR_SET','MESSAGE_SET','ROUTE_SET','SECURITY_POLICY_SET',
    'TRANSITION_SET','EKB_ERROR_SET','EKB_PREVENTION_SET','EKB_DECISION_SET'
  ];
BEGIN
  SELECT r.pantalla_id,r.version_id
    INTO v_pantalla_id,v_version_id
  FROM programacion.input_readiness_runs r
  ORDER BY r.id DESC
  LIMIT 1;

  IF v_pantalla_id IS NULL OR v_version_id IS NULL THEN
    RAISE EXCEPTION 'M2_2_NO_READINESS_SAMPLE';
  END IF;

  FOREACH v_kind IN ARRAY v_kinds LOOP
    v_key := CASE
      WHEN v_kind IN ('EKB_ERROR_SET','EKB_PREVENTION_SET') THEN 'codes'
      WHEN v_kind='EKB_DECISION_SET' THEN 'adrs'
      ELSE 'ids'
    END;

    v_empty_ref := jsonb_build_object('kind',v_kind,v_key,'[]'::jsonb);
    v_receipt := programacion.fn_input_resolve_source_ref(v_empty_ref,v_pantalla_id,v_version_id);
    IF v_receipt->'observed' IS DISTINCT FROM '[]'::jsonb
       OR coalesce(v_receipt->>'observed_sha256','')='' THEN
      RAISE EXCEPTION 'M2_2_EMPTY_COLLECTION_NOT_RESOLVED:%:%',v_kind,v_receipt;
    END IF;

    SELECT m->'ref'
      INTO v_positive_ref
    FROM programacion.input_readiness_runs r
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(r.source_manifest)='array' THEN r.source_manifest ELSE '[]'::jsonb END
    ) m
    WHERE m->'ref'->>'kind'=v_kind
      AND jsonb_typeof(m->'ref'->v_key)='array'
      AND jsonb_array_length(m->'ref'->v_key)>0
    ORDER BY programacion.fn_input_readiness_run_is_current(r.id) DESC,r.id DESC
    LIMIT 1;

    IF v_positive_ref IS NULL THEN
      RAISE EXCEPTION 'M2_2_POSITIVE_SAMPLE_MISSING:%',v_kind;
    END IF;
    PERFORM programacion.fn_input_resolve_source_ref(v_positive_ref,v_pantalla_id,v_version_id);

    v_missing_ref := jsonb_build_object('kind',v_kind);
    v_rejected := false;
    BEGIN
      PERFORM programacion.fn_input_resolve_source_ref(v_missing_ref,v_pantalla_id,v_version_id);
    EXCEPTION WHEN OTHERS THEN
      v_rejected := true;
    END;
    IF NOT v_rejected THEN
      RAISE EXCEPTION 'M2_2_MISSING_REF_NOT_REJECTED:%',v_kind;
    END IF;

    v_cardinality_ref := CASE
      WHEN v_key='ids' THEN jsonb_build_object('kind',v_kind,v_key,jsonb_build_array(9223372036854775807::bigint))
      WHEN v_key='codes' THEN jsonb_build_object('kind',v_kind,v_key,jsonb_build_array('__M2_2_MISSING__'))
      ELSE jsonb_build_object('kind',v_kind,v_key,jsonb_build_array('ADR-M2-2-DOES-NOT-EXIST'))
    END;
    v_rejected := false;
    BEGIN
      PERFORM programacion.fn_input_resolve_source_ref(v_cardinality_ref,v_pantalla_id,v_version_id);
    EXCEPTION WHEN OTHERS THEN
      v_rejected := true;
    END;
    IF NOT v_rejected THEN
      RAISE EXCEPTION 'M2_2_CARDINALITY_MISMATCH_NOT_REJECTED:%',v_kind;
    END IF;
  END LOOP;
END
$m2_2_behavior$;

WITH kinds(kind,ord) AS (
  VALUES
    ('ERROR_SET',1),('MESSAGE_SET',2),('ROUTE_SET',3),('SECURITY_POLICY_SET',4),
    ('TRANSITION_SET',5),('EKB_ERROR_SET',6),('EKB_PREVENTION_SET',7),('EKB_DECISION_SET',8)
), scenarios(scenario,sord,expected) AS (
  VALUES
    ('EMPTY_POSITIVE',1,'RESOLVES_EMPTY'),
    ('NONEMPTY_POSITIVE',2,'RESOLVES'),
    ('MISSING_REF_NEGATIVE',3,'REJECTS'),
    ('CARDINALITY_NEGATIVE',4,'REJECTS')
)
INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_at,updated_at,created_by_execution_id,updated_by_execution_id
)
SELECT
  'INPUT_GOVERNANCE_REGRESSION',
  'M2_2_KIND_'||kind||'_'||scenario,
  500 + ((ord-1)*4) + sord,
  NULL,
  ARRAY[]::text[],
  'M2.2 '||kind||' '||lower(replace(scenario,'_',' ')),
  'DETERMINISTIC','AUTOMATED','HIGH',
  jsonb_build_object(
    'resolver','programacion.fn_input_resolve_source_ref',
    'source_kind',kind,
    'empty_collection_semantics','CANONICAL_EMPTY_ARRAY_IS_RESOLVABLE_EVIDENCE'
  ),
  jsonb_build_object('source_kind',kind,'scenario',scenario),
  jsonb_build_object('resolver_outcome',expected),
  '{}'::jsonb,
  'CANDIDATO',
  jsonb_build_object(
    'plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M2.2',
    'work_code','PAULO-018',
    'source_kind',kind,
    'scenario',scenario,
    'resolver_surface','programacion.fn_input_resolve_source_ref',
    'generic_identity_owner','T-SOURCE',
    'empty_collection_semantics','CANONICAL_EMPTY_ARRAY_IS_RESOLVABLE_EVIDENCE'
  ),
  now(),now(),'CHATGPT-IG-CV-M2-2-20261003','CHATGPT-IG-CV-M2-2-20261003'
FROM kinds CROSS JOIN scenarios;

UPDATE public.lf_test_suites
SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'm2_2_empty_collection_semantics',jsonb_build_object(
        'kind_count',8,
        'case_count',32,
        'empty_positive_per_kind',true,
        'nonempty_positive_per_kind',true,
        'missing_ref_negative_per_kind',true,
        'cardinality_negative_per_kind',true,
        'resolver_surface','programacion.fn_input_resolve_source_ref',
        'generic_identity_owner','T-SOURCE',
        'contract_revision','5.13',
        'empty_collection_semantics','CANONICAL_EMPTY_ARRAY_IS_RESOLVABLE_EVIDENCE'
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M2-2-20261003'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION';

DO $m2_2_readback$
DECLARE
  v_cases integer;
  v_kinds integer;
  v_scenario_sets integer;
BEGIN
  SELECT count(*),count(distinct metadata->>'source_kind')
    INTO v_cases,v_kinds
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND test_code LIKE 'M2_2_KIND_%';

  SELECT count(*) INTO v_scenario_sets
  FROM (
    SELECT metadata->>'source_kind' kind
    FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code LIKE 'M2_2_KIND_%'
    GROUP BY metadata->>'source_kind'
    HAVING count(*)=4
       AND bool_or(metadata->>'scenario'='EMPTY_POSITIVE')
       AND bool_or(metadata->>'scenario'='NONEMPTY_POSITIVE')
       AND bool_or(metadata->>'scenario'='MISSING_REF_NEGATIVE')
       AND bool_or(metadata->>'scenario'='CARDINALITY_NEGATIVE')
  ) q;

  IF v_cases<>32 OR v_kinds<>8 OR v_scenario_sets<>8 THEN
    RAISE EXCEPTION 'M2_2_CASE_READBACK_FAILED:cases=% kinds=% scenario_sets=%',
      v_cases,v_kinds,v_scenario_sets;
  END IF;
END
$m2_2_readback$;
