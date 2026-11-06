-- LF Input Governance L7: candidate model packet for the EXISTING Validator.
-- Non-promotable, read-only. New RUN + source pins required; never use historical RUN 949.
-- EKB preflight: GOV-010, GOV-032, GOV-LF-RECEIPT-001,
-- IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001, IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001.
-- Scope: RATE_LIMIT and SESSION pilot; other families explicitly fail closed.
-- NO new judge, Router, Curator path, table, canonical policy writes or outcome promotion.
BEGIN;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_packet_core_v1(
    p_run_id bigint, p_validator_identity text, p_receipt_id bigint
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'programacion', 'lf_ops', 'public'
AS $packet$
DECLARE
    v_run programacion.input_readiness_runs%ROWTYPE;
    v_handoff jsonb;
    v_families text[];
    v_family text;
    v_a programacion.input_family_assessments%ROWTYPE;
    v_src record;
    v_source jsonb;
    v_sources jsonb := '[]'::jsonb;
    v_missing_pins jsonb := '[]'::jsonb;
    v_expected_sha text;
    v_attested boolean;
    v_count int;
    v_packet jsonb;
BEGIN
    IF p_run_id IS NULL OR p_run_id<1 OR p_receipt_id IS NULL OR p_receipt_id<1
       OR nullif(btrim(coalesce(p_validator_identity,'')),'') IS NULL THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_INPUT_REQUIRED';
    END IF;
    SELECT * INTO v_run FROM programacion.input_readiness_runs WHERE id=p_run_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'IG_SEMANTIC_PACKET_RUN_NOT_FOUND:%',p_run_id; END IF;
    IF v_run.status NOT IN ('CURATING','VALIDATING')
       OR v_run.invalidated_at IS NOT NULL THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_RUN_NOT_OPEN:%:%',p_run_id,v_run.status;
    END IF;
    IF v_run.scope->>'validator_semantic_mode' IS DISTINCT FROM 'SELECTED_SEMANTIC_COMPARISON'
       OR v_run.scope->>'semantic_promotion_authorized' IS DISTINCT FROM 'false'
       OR nullif(v_run.source_snapshot_sha256,'') IS NULL THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_MODE_OR_SNAPSHOT_NOT_AUTHORIZED:%',p_run_id;
    END IF;
    IF v_run.validator_identity IS NOT NULL
       AND v_run.validator_identity IS DISTINCT FROM p_validator_identity THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_VALIDATOR_IDENTITY_MISMATCH:%',p_run_id;
    END IF;
    IF v_run.curator_identity IS NOT DISTINCT FROM p_validator_identity
       OR p_validator_identity NOT LIKE 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:%' THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_INDEPENDENCE_INVALID:%',p_run_id;
    END IF;

    -- Reuse the existing independent, source-bound handoff assertion.
    -- This validates graph+47 curated assessments, NOT a semantic model PASS.
    v_handoff:=programacion.fn_input_governance_validator_handoff_assert_v1(p_run_id,p_receipt_id);
    IF v_handoff->>'status'<>'VERIFIED'
       OR (v_handoff->>'receipt_id')::bigint IS DISTINCT FROM p_receipt_id
       OR (v_handoff->>'run_id')::bigint IS DISTINCT FROM p_run_id THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_HANDOFF_NOT_VERIFIED:%',p_run_id;
    END IF;
    v_families:=programacion.fn_input_validator_semantic_scope_v1(p_run_id);
    IF coalesce(cardinality(v_families),0)=0 THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_FAMILIES_REQUIRED:%',p_run_id;
    END IF;
    IF EXISTS(SELECT 1 FROM unnest(v_families) f WHERE f NOT IN ('RATE_LIMIT','SESSION')) THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_UNSUPPORTED_FAMILY_PILOT:%',p_run_id;
    END IF;

    -- Source code and family are grounded in current effective rules + explicit
    -- lf_ops.pantallas_politicas bindings, NOT inferred global/transversal scope.
    FOR v_src IN
      WITH eff AS (
        SELECT r.* FROM programacion.fn_input_effective_rule_links_v1(
             v_run.pantalla_id,'INPUT_GOVERNANCE') links
        JOIN lf_ops.reglas r ON r.id=links.regla_id
        WHERE r.estado IN ('VIGENTE','CANDIDATO') AND NOT coalesce(r.pendiente_decision,false)
      ),
      observed AS (
        SELECT 'RATE_LIMIT'::text AS family_code,
          jsonb_build_object(
           'ref','lf_ops.politicas_rate_limit:'||p.rate_limit_policy_id::text,
           'code',p.policy_code,'family','RATE_LIMIT',
           'record_status',p.status,'parameter_provenance',p.parameter_provenance,
           'required_provenance_fields',jsonb_build_array('max_requests','window_seconds','burst_limit'),
           'applicability_authority',NULL,
           'source_observed_sha256',programacion.fn_v09_sha256_jsonb(jsonb_build_object(
               'policy',to_jsonb(p),'binding',to_jsonb(b),'rule',to_jsonb(r))),
           'source_details',jsonb_build_object(
             'max_requests',p.max_requests,'window_seconds',p.window_seconds,
             'burst_limit',p.burst_limit,'scope_key',p.scope_key,
             'source_decision_id',p.source_decision_id,
             'rule_code',r.codigo,'rule_status',r.estado,'rule_title',r.titulo,
             'rule_description',r.descripcion,'rule_config',r.valor_config,
             'binding_status',b.status,'reference_role',b.reference_role)
          ) AS source
        FROM lf_ops.pantallas_politicas b
        JOIN lf_ops.politicas_rate_limit p ON p.rate_limit_policy_id=b.rate_limit_policy_id
        JOIN eff r ON r.valor_config->>'rate_limit_policy_id'=p.rate_limit_policy_id::text
        WHERE b.pantalla_id=v_run.pantalla_id
          AND b.policy_kind='RATE_LIMIT' AND b.reference_role='rate_limit_policy_id'
          AND 'RATE_LIMIT'=ANY(v_families)
        UNION ALL
        SELECT 'SESSION'::text,
          jsonb_build_object(
            'ref','lf_ops.reglas:'||r.id::text,
            'code',r.codigo,'family','SESSION','record_status',r.estado,
            'parameter_provenance',jsonb_build_object(),
            'required_provenance_fields',jsonb_build_array(),
            'applicability_authority',NULL,
            'source_observed_sha256',programacion.fn_v09_sha256_jsonb(jsonb_build_object(
                'policy',to_jsonb(p),'binding',to_jsonb(b),'rule',to_jsonb(r))),
            'source_details',jsonb_build_object(
              'rule_title',r.titulo,'rule_description',r.descripcion,'rule_config',r.valor_config,
              'policy_code',p.policy_code,'policy_status',p.status,
              'policy_provenance',p.parameter_provenance,
              'cookie_policy',p.cookie_policy,
              'refresh_rotation_enabled',p.refresh_rotation_enabled,
              'binding_status',b.status,'reference_role',b.reference_role)
          )
        FROM lf_ops.pantallas_politicas b
        JOIN lf_ops.politicas_sesion p ON p.session_policy_id=b.session_policy_id
        JOIN eff r ON r.valor_config->>'session_policy_id'=p.session_policy_id::text
        WHERE b.pantalla_id=v_run.pantalla_id
          AND b.policy_kind='SESSION' AND b.reference_role='session_policy_id'
          AND 'SESSION'=ANY(v_families)
      )
      SELECT family_code, source FROM observed ORDER BY family_code,source->>'code'
    LOOP
      SELECT * INTO v_a FROM programacion.input_family_assessments a
       WHERE a.run_id=p_run_id AND a.family_code=v_src.family_code;
      IF NOT FOUND OR v_a.curator_sha256 !~ '^[a-f0-9]{64}$' THEN
          RAISE EXCEPTION 'IG_SEMANTIC_PACKET_CURATOR_ASSESSMENT_MISSING:%',v_src.family_code;
      END IF;
      -- Only source pins issued by the Curator *before* its signed handoff qualify.
      -- Existing RUNs have none; do not synthesize pins from current SQL reads.
      v_expected_sha:=NULL;
      IF jsonb_typeof(v_a.curator_evidence->'ig_semantic_source_snapshot_v1')='array' THEN
        SELECT x.value->>'observed_sha256' INTO v_expected_sha
        FROM jsonb_array_elements(v_a.curator_evidence->'ig_semantic_source_snapshot_v1') x(value)
        WHERE x.value->>'ref'=v_src.source->>'ref'
        ORDER BY x.value->>'ref' LIMIT 1;
      END IF;
      v_attested:=v_expected_sha IS NOT NULL
          AND v_expected_sha=v_src.source->>'source_observed_sha256';
      v_source:=v_src.source||jsonb_build_object(
         'curator_assessment_id',v_a.id,
         'curator_sha256',v_a.curator_sha256,
         'source_frozen_by_curator',v_attested);
      v_sources:=v_sources||jsonb_build_array(v_source);
      IF NOT v_attested THEN
          v_missing_pins:=v_missing_pins||jsonb_build_array(
            jsonb_build_object('ref',v_source->>'ref','family',v_src.family_code,
                               'reason','CURATOR_SOURCE_SNAPSHOT_MISSING_OR_STALE'));
      END IF;
    END LOOP;

    IF jsonb_array_length(v_sources)>47 THEN
        RAISE EXCEPTION 'IG_SEMANTIC_PACKET_TOO_MANY_SOURCES:%',p_run_id;
    END IF;
    FOR v_family IN SELECT unnest(v_families) LOOP
        SELECT count(*) INTO v_count FROM jsonb_array_elements(v_sources) x(value)
        WHERE x.value->>'family'=v_family;
        IF v_count=0 THEN
          RAISE EXCEPTION 'IG_SEMANTIC_PACKET_FAMILY_SOURCE_UNRESOLVED:%:%',p_run_id,v_family;
        END IF;
    END LOOP;
    IF (SELECT count(DISTINCT x.value->>'ref') FROM jsonb_array_elements(v_sources) x(value))
       <> jsonb_array_length(v_sources)
       OR (SELECT count(DISTINCT x.value->>'code') FROM jsonb_array_elements(v_sources) x(value))
       <> jsonb_array_length(v_sources) THEN
       RAISE EXCEPTION 'IG_SEMANTIC_PACKET_DUPLICATE_SOURCE:%',p_run_id;
    END IF;

    v_packet:=jsonb_build_object(
        'schema_version','IG_SEMANTIC_MODEL_PACKET_V1',
        'status',CASE WHEN jsonb_array_length(v_missing_pins)=0
                      THEN 'READY_FOR_MODEL_CANDIDATE'
                      ELSE 'SOURCE_SNAPSHOT_PIN_REQUIRED' END,
        'run_id',p_run_id,'handoff_receipt_id',p_receipt_id,
        'screen_code',(SELECT codigo FROM lf_ops.pantallas WHERE id=v_run.pantalla_id),
        'validator_semantic_mode','SELECTED_SEMANTIC_COMPARISON',
        'source_integrity_verified',jsonb_array_length(v_missing_pins)=0,
        'source_snapshot_sha256',v_run.source_snapshot_sha256,
        'curator_identity',v_run.curator_identity,
        'validator_identity',p_validator_identity,
        'selected_families',to_jsonb(v_families),
        'handoff_receipt_sha256',v_handoff->>'receipt_sha256',
        'sources',v_sources,'missing_source_pins',v_missing_pins,
        'semantic_judge_executed',false,
        'semantic_independence_credited',false,
        'semantic_pass_authorized',false,
        'official_write_authorized',false,'production_authorized',false);
    RETURN v_packet||jsonb_build_object('db_packet_sha256',
          programacion.fn_v09_sha256_jsonb(v_packet));
END;
$packet$;

-- Only public RPC exposed to service_role. Existing ticket verifier is reused.
CREATE OR REPLACE FUNCTION public.fn_input_governance_semantic_packet_v1(
    p_run_id bigint,p_validator_identity text,p_receipt_id bigint,p_ticket uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion'
AS $wrapper$
BEGIN
    PERFORM public.lf_profile_ig_ticket_verify_v1(p_ticket,NULL,p_run_id);
    RETURN programacion.fn_input_governance_semantic_packet_core_v1(
        p_run_id,p_validator_identity,p_receipt_id);
END;
$wrapper$;

REVOKE ALL ON FUNCTION programacion.fn_input_governance_semantic_packet_core_v1(bigint,text,bigint)
    FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_input_governance_semantic_packet_v1(bigint,text,bigint,uuid)
    FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_input_governance_semantic_packet_v1(bigint,text,bigint,uuid)
    TO service_role;

-- Negative controls, no fixture/no writes. Current RUN 949 cannot become semantic evidence.
DO $preflight$
DECLARE v_error text;
BEGIN
   IF NOT has_function_privilege('service_role',
      'public.fn_input_governance_semantic_packet_v1(bigint,text,bigint,uuid)'::regprocedure,'EXECUTE')
   OR has_function_privilege('anon',
      'public.fn_input_governance_semantic_packet_v1(bigint,text,bigint,uuid)'::regprocedure,'EXECUTE')
   OR has_function_privilege('authenticated',
      'public.fn_input_governance_semantic_packet_v1(bigint,text,bigint,uuid)'::regprocedure,'EXECUTE')
   OR has_function_privilege('service_role',
      'programacion.fn_input_governance_semantic_packet_core_v1(bigint,text,bigint)'::regprocedure,'EXECUTE')
   THEN RAISE EXCEPTION 'IG_SEMANTIC_PACKET_PRIVILEGE_GUARD_FAILED'; END IF;
   BEGIN
     PERFORM programacion.fn_input_governance_semantic_packet_core_v1(
       949,'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:negative',1);
     RAISE EXCEPTION 'IG_SEMANTIC_OLD_RUN_WRONGLY_ADMITTED';
   EXCEPTION WHEN OTHERS THEN
     GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
     IF v_error NOT LIKE 'IG_SEMANTIC_PACKET_RUN_NOT_OPEN:%' THEN
       RAISE EXCEPTION 'IG_SEMANTIC_NEGATIVE_WRONG_ERROR:%',v_error;
     END IF;
   END;
END;
$preflight$;
COMMIT;
