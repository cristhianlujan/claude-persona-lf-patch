-- LF IG N-4 / G4. Candidate ONLY. Not a migration; not deployed.
-- Reuses the existing Input Governance run_id. No new execution, queue,
-- permissions, schema tables or approvals. P10 remains the write guard.
-- Read-only preflight returns HOLD if scope authority is not materialized.
CREATE OR REPLACE FUNCTION programacion.fn_ig_g4_run_scope_prepublication_readonly_v1(
 p_run_id bigint, p_rule_id integer, p_consumer text,
 p_proposed_applicability jsonb
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','programacion','lf_ops','private'
AS $g4$
DECLARE
 v_run programacion.input_readiness_runs%rowtype;
 v_rule lf_ops.reglas%rowtype;
 v_current jsonb;
 v_contract jsonb;
 v_routes integer;
 v_issuers integer;
 v_rule_sha text;
 v_selector_sha text;
BEGIN
 IF p_run_id IS NULL OR p_run_id<=0 OR p_rule_id IS NULL
    OR p_rule_id<=0 OR NULLIF(BTRIM(p_consumer),'') IS NULL
    OR jsonb_typeof(p_proposed_applicability) IS DISTINCT FROM 'object'
 THEN RETURN jsonb_build_object('status','HOLD','code','G4_SCOPE_PREFLIGHT_INPUT_INVALID'); END IF;
 SELECT * INTO v_run FROM programacion.input_readiness_runs
   WHERE id=p_run_id;
 IF NOT FOUND OR v_run.status<>'COMPLETED' OR v_run.invalidated_at IS NOT NULL
 THEN RETURN jsonb_build_object('status','HOLD','code','G4_IG_RUN_NOT_COMPLETED_OR_INVALIDATED','run_id',p_run_id); END IF;
 v_current:=programacion.fn_input_governance_continuation_currentness_v1(p_run_id);
 IF COALESCE((v_current->>'continuation_current')::boolean,false) IS NOT TRUE
 THEN RETURN jsonb_build_object('status','HOLD','code','G4_IG_RUN_NOT_CURRENT','run_id',p_run_id); END IF;
 SELECT especificacion->'allowed_consumers' INTO v_contract
 FROM programacion.contratos WHERE version_id=v_run.version_id
   AND contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
   AND estado='defined' ORDER BY id DESC LIMIT 1;
 IF jsonb_typeof(v_contract) IS DISTINCT FROM 'array' OR NOT (v_contract ? p_consumer)
 THEN RETURN jsonb_build_object('status','HOLD','code','G4_CONSUMER_NOT_ALLOWED','run_id',p_run_id); END IF;
 SELECT * INTO v_rule FROM lf_ops.reglas WHERE id=p_rule_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','HOLD','code','G4_RULE_NOT_FOUND','run_id',p_run_id); END IF;
 v_rule_sha:=programacion.fn_v09_sha256_jsonb(
    jsonb_build_object('id',v_rule.id,'codigo',v_rule.codigo,
      'estado',v_rule.estado,'valor_config',v_rule.valor_config));
 v_selector_sha:=programacion.fn_v09_sha256_jsonb(p_proposed_applicability);
 IF v_rule.valor_config->'applicability_v1' IS NOT DISTINCT FROM p_proposed_applicability
 THEN RETURN jsonb_build_object('status','NOT_APPLICABLE',
   'reason','UNCHANGED_SELECTOR','run_id',p_run_id,'rule_id',p_rule_id); END IF;
 SELECT count(*) INTO v_routes FROM private.lf_human_decision_route_policies_v1
   WHERE producer_code='INPUT_GOVERNANCE'
     AND subject_type='RULE_APPLICABILITY_CHANGE' AND status='ACTIVE';
 IF v_routes=0 THEN RETURN jsonb_build_object('status','HOLD',
    'code','G4_NO_SCOPE_AUTHORITY_ROUTE','run_id',p_run_id,
    'rule_ref',v_rule.codigo,'rule_sha256',v_rule_sha,
    'selector_sha256',v_selector_sha); END IF;
 SELECT count(*) INTO v_issuers FROM private.lf_human_decision_authority_policies_v1
   WHERE status='ACTIVE';
 IF v_issuers=0 THEN RETURN jsonb_build_object('status','HOLD',
    'code','G4_NO_ACTIVE_AUTHORITY_ISSUER','run_id',p_run_id); END IF;
 -- No automatic publication from a general human-decision route.
 -- A rule-specific competent source and an exact, verified receipt must
 -- be joined by the governed publisher. Their absence NEVER means PASS.
 RETURN jsonb_build_object('status','HOLD',
   'code','G4_EXACT_RULE_SCOPE_RECEIPT_REQUIRED','run_id',p_run_id,
   'rule_ref',v_rule.codigo,'rule_sha256',v_rule_sha,
   'selector_sha256',v_selector_sha);
END
$g4$;
