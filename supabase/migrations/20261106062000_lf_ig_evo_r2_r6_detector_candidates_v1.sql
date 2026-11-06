-- IG-EVO R2-R6: policy-aware deterministic candidate discovery within native Input Governance.
-- No independent judge and no assertions of security implementation or global rule applicability.
-- Scope: R2 same-screen candidate conflicts; R3 active->candidate references;
-- R4 same-title/different-config co-screen; R5 declarative transversal selector gaps;
-- R6 generic threat evidence and OTP-definition-vs-MISSING.
-- Requires owner governed Curator hook in a subsequent migration.
BEGIN;
CREATE OR REPLACE FUNCTION programacion.fn_ig_evo_r2_r6_diagnostics_v1(p_pantalla_id integer,p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY INVOKER
 SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $evo$
DECLARE
  v_run record;
  v_prev record;
  v_result jsonb;
BEGIN
  SELECT id,pantalla_id,status,invalidated_at,source_snapshot_sha256
  INTO v_run
  FROM programacion.input_readiness_runs
  WHERE id=p_run_id;
  IF NOT FOUND OR v_run.pantalla_id IS DISTINCT FROM p_pantalla_id
     OR v_run.invalidated_at IS NOT NULL THEN
    RAISE EXCEPTION 'IG_EVO_R2_R6_RUN_SCOPE_INVALID:%:%',p_pantalla_id,p_run_id;
  END IF;
  IF (SELECT count(*) FROM programacion.input_family_assessments
      WHERE run_id=p_run_id AND family_code='SECURITY')<>1 THEN
    RAISE EXCEPTION 'IG_EVO_R6_SECURITY_FAMILY_MISSING:%',p_run_id;
  END IF;
  SELECT id,source_snapshot_sha256,invalidated_at INTO v_prev
  FROM programacion.input_readiness_runs
  WHERE pantalla_id=p_pantalla_id AND id<p_run_id AND status='COMPLETED'
  ORDER BY id DESC LIMIT 1;
WITH effective AS (
 SELECT r.id,r.codigo,r.estado,r.titulo,r.categoria,r.valor_config,r.es_transversal,r.pendiente_decision,e.binding_source
 FROM programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') e
 JOIN lf_ops.reglas r ON r.id=e.regla_id
 WHERE e.pantalla_id=p_pantalla_id AND r.estado IN ('VIGENTE','CANDIDATO')
), r2 AS (
 -- Narrow falsifier: temporary IP mitigation and hard single-signal lockout
 -- are not contradictory. Compare only an identical explicit control key with
 -- truly opposite ALLOW/DENY values. Semantics still require native Validator.
 SELECT jsonb_build_object('rule_code',r.codigo,'policy_code',p.policy_code,
       'rule_state',r.estado,'binding_state',b.status,'policy_state',p.status,
       'control_key',kv.key,'rule_value',kv.value,
       'policy_value',p.policy_config->>kv.key,
       'semantic_verdict','NOT_TESTED','scope','SAME_SCREEN_SHARED_EXACT_CONTROL_KEY')
   result
 FROM effective r
 CROSS JOIN LATERAL jsonb_each_text(
   CASE WHEN jsonb_typeof(r.valor_config)='object' THEN r.valor_config ELSE '{}'::jsonb END) kv
 JOIN lf_ops.pantallas_politicas b ON b.pantalla_id=p_pantalla_id
 JOIN lf_ops.politicas_seguridad p ON p.security_policy_id=b.security_policy_id
 WHERE r.binding_source<>'DERIVED_GLOBAL'
   AND p.policy_config ? kv.key
   AND (
      (upper(kv.value)='ALLOW' AND upper(p.policy_config->>kv.key)='DENY')
      OR
      (upper(kv.value)='DENY' AND upper(p.policy_config->>kv.key)='ALLOW')
   )
), rule_refs AS (
 SELECT e.id source_id,e.codigo source_code,e.estado source_state,e.titulo source_title,e.binding_source source_binding_source,e.valor_config source_config,kv.key reference_key,
   kv.value referenced_value
 FROM effective e
 CROSS JOIN LATERAL jsonb_each(
   CASE WHEN jsonb_typeof(e.valor_config)='object' THEN e.valor_config ELSE '{}'::jsonb END
 ) kv
 WHERE e.estado='VIGENTE' AND e.binding_source<>'DERIVED_GLOBAL'
), r3 AS (
 SELECT jsonb_build_object('source_code',s.source_code,'source_state',s.source_state,
   'reference_key',s.reference_key,'target_code',t.codigo,'target_status',t.estado,
   'source_rule_id',s.source_id,'target_rule_id',t.id,
   'source_title',s.source_title,'target_title',t.titulo,
   'source_binding_source',s.source_binding_source,
   'source_production_authorized',s.source_config->>'production_authorized',
   'target_production_authorized',t.valor_config->>'production_authorized',
   'target_implementation_status',t.valor_config->>'implementation_status',
   'repair_focus','VERIFY_TARGET_AUTHORITY_AND_APPLICABILITY_BEFORE_PROMOTION',
   'link_kind','RULE_BY_ID','promotion_authorized',false) result
 FROM rule_refs s
 JOIN lf_ops.reglas t ON t.id=CASE WHEN jsonb_typeof(s.referenced_value)='number'
     AND (s.referenced_value #>> '{}') ~ '^[0-9]+$'
     THEN (s.referenced_value #>> '{}')::integer ELSE NULL END
 WHERE s.reference_key ~ '_rule_id$' AND t.estado='CANDIDATO'
 UNION ALL
 SELECT jsonb_build_object('source_code',s.source_code,'source_state',s.source_state,
   'reference_key',s.reference_key,'target_code',t.codigo,'target_status',t.estado,
   'source_rule_id',s.source_id,'target_rule_id',t.id,
   'source_title',s.source_title,'target_title',t.titulo,
   'source_binding_source',s.source_binding_source,
   'source_production_authorized',s.source_config->>'production_authorized',
   'target_production_authorized',t.valor_config->>'production_authorized',
   'target_implementation_status',t.valor_config->>'implementation_status',
   'repair_focus','VERIFY_TARGET_AUTHORITY_AND_APPLICABILITY_BEFORE_PROMOTION',
   'link_kind','RULE_BY_CODE','promotion_authorized',false)
 FROM rule_refs s JOIN lf_ops.reglas t ON t.codigo=s.referenced_value #>> '{}'
 WHERE s.reference_key ~ '_rule_code$'
   AND jsonb_typeof(s.referenced_value)='string' AND t.estado='CANDIDATO'
), r4 AS (
 SELECT jsonb_build_object('first_rule',a.codigo,'second_rule',b.codigo,
   'first_state',a.estado,'second_state',b.estado,
   'same_title',true,'same_config',false,'true_duplicate','NOT_PROVEN',
   'first_rule_id',a.id,'second_rule_id',b.id,
   'first_config',a.valor_config,'second_config',b.valor_config,
   'first_binding_source',a.binding_source,'second_binding_source',b.binding_source,
   'repair_focus','COMPARE_BEHAVIOR_NOT_TITLE_BEFORE_MERGE',
   'semantic_verdict','NOT_TESTED') result
 FROM effective a JOIN effective b ON a.id<b.id
 WHERE a.binding_source<>'DERIVED_GLOBAL'
   AND b.binding_source<>'DERIVED_GLOBAL'
   AND a.titulo IS NOT NULL AND b.titulo IS NOT NULL
   AND lower(btrim(a.titulo))=lower(btrim(b.titulo))
   AND a.valor_config IS DISTINCT FROM b.valor_config
), r5 AS (
 -- Group by root cause and binding provenance, never 101 repetitive cards.
 SELECT jsonb_build_object(
   'binding_source',r.binding_source,
   'selector_status',COALESCE(r.valor_config->'applicability_v1'->>'status','MISSING'),
   'rule_count',COUNT(*),
   'rule_ids',COALESCE(jsonb_agg(r.id ORDER BY r.id),'[]'::jsonb),
   'rule_codes',COALESCE(jsonb_agg(r.codigo ORDER BY r.codigo),'[]'::jsonb),
   'repair_target','lf_ops.reglas.valor_config.applicability_v1',
   'root_cause','DECLARATIVE_APPLICABILITY_AUTHORITY_NOT_EVIDENCED',
   'global_applicability','NOT_PROVEN',
   'semantic_verdict','NOT_TESTED',
   'effective_screen_context',p_pantalla_id
 ) result
 FROM effective r
 WHERE r.es_transversal IS TRUE
   AND COALESCE(r.valor_config->'applicability_v1'->>'status','MISSING')<>'ACTIVE'
 GROUP BY r.binding_source,COALESCE(r.valor_config->'applicability_v1'->>'status','MISSING')
), sec_assessment AS (
 SELECT a.threat_coverage
 FROM programacion.input_family_assessments a
 WHERE a.run_id=p_run_id AND a.family_code='SECURITY'
), auth_abuse_context AS (
 -- Link graph: explicit rule -> referenced policies -> screen-policy bindings.
 -- CANDIDATO is a declared source, not operational/production evidence.
 SELECT r.id rule_id,r.codigo rule_code,r.estado rule_status,r.binding_source,
   rp.rate_limit_policy_id rate_id,rp.policy_code rate_code,rp.status rate_status,
   rp.resource_code,rp.scope_key,rp.max_requests,rp.window_seconds,rp.burst_limit,
   rp.parameter_provenance,rp.source_decision_id rate_decision,
   sp.security_policy_id sec_id,sp.policy_code sec_code,sp.status sec_status,
   sp.policy_config security_controls,
   br.pantalla_politica_id rate_binding_id,br.status rate_binding_status,
   bs.pantalla_politica_id sec_binding_id,bs.status sec_binding_status,
   programacion.fn_v09_sha256_jsonb(to_jsonb(r.valor_config)) rule_sha,
   programacion.fn_v09_sha256_jsonb(to_jsonb(rp)) rate_sha,
   programacion.fn_v09_sha256_jsonb(to_jsonb(sp)) sec_sha
 FROM effective r
 LEFT JOIN lf_ops.politicas_rate_limit rp
  ON rp.rate_limit_policy_id=CASE
    WHEN r.valor_config->>'rate_limit_policy_id' ~ '^[0-9]+$'
    THEN (r.valor_config->>'rate_limit_policy_id')::bigint END
 LEFT JOIN lf_ops.politicas_seguridad sp
  ON sp.security_policy_id=CASE
    WHEN r.valor_config->>'abuse_security_policy_id' ~ '^[0-9]+$'
    THEN (r.valor_config->>'abuse_security_policy_id')::bigint END
 LEFT JOIN lf_ops.pantallas_politicas br ON br.pantalla_id=p_pantalla_id
    AND br.rate_limit_policy_id=rp.rate_limit_policy_id
 LEFT JOIN lf_ops.pantallas_politicas bs ON bs.pantalla_id=p_pantalla_id
    AND bs.security_policy_id=sp.security_policy_id
 WHERE r.binding_source<>'DERIVED_GLOBAL'
   AND (r.valor_config ? 'rate_limit_policy_id')
   AND (r.valor_config ? 'abuse_security_policy_id')
), auth_abuse_cases AS (
 SELECT jsonb_build_object(
   'finding_root_key',concat('IG_EVO_AUTH_ABUSE_',ctx.rule_id,'_',coalesce(ctx.sec_id::text,'UNRESOLVED')),
   'finding_kind','CROSS_POLICY_CONTROL_AND_ADVERSARIAL_SCENARIOS',
   'risk_confirmed',false,'semantic_verdict','NOT_TESTED',
   'implementation_evidence','NOT_PROVEN',
   'source_rule',jsonb_build_object('table','lf_ops.reglas','id',ctx.rule_id,
     'code',ctx.rule_code,'status',ctx.rule_status,
     'binding_source',ctx.binding_source,'sha256',ctx.rule_sha),
   'rate_policy',jsonb_build_object('table','lf_ops.politicas_rate_limit',
     'id',ctx.rate_id,'code',ctx.rate_code,'status',ctx.rate_status,
     'resource_code',ctx.resource_code,'scope_key',ctx.scope_key,
     'max_requests',ctx.max_requests,'window_seconds',ctx.window_seconds,
     'burst_limit',ctx.burst_limit,'parameter_provenance',ctx.parameter_provenance,
     'source_decision_id',ctx.rate_decision,'binding_id',ctx.rate_binding_id,
     'binding_status',ctx.rate_binding_status,'sha256',ctx.rate_sha),
   'security_policy',jsonb_build_object('table','lf_ops.politicas_seguridad',
     'id',ctx.sec_id,'code',ctx.sec_code,'status',ctx.sec_status,
     'binding_id',ctx.sec_binding_id,'binding_status',ctx.sec_binding_status,
     'sha256',ctx.sec_sha),
   'existing_controls',jsonb_build_object(
     'distributed_attack_detection',ctx.security_controls->>'distributed_attack_detection',
     'shared_ip_false_positive_mitigation',ctx.security_controls->>'shared_ip_false_positive_mitigation',
     'ip_hard_limit',ctx.security_controls->>'ip_hard_limit',
     'single_signal_hard_lockout',ctx.security_controls->>'single_signal_hard_lockout',
     'signal_families',ctx.security_controls->'signal_families'),
   'unverified',jsonb_build_array(
     'COUNTER_COMPOSITION','SUBJECT_AND_ORIGIN_INDEPENDENT_ENFORCEMENT',
     'COUNTED_EVENT_CLASSES','DISTRIBUTED_RISK_ENFORCEMENT',
     'SHARED_NETWORK_QA','WINDOW_AND_BURST_QA','FAIL_CLOSED_RUNTIME'),
   'risk_scenarios',(
     SELECT COALESCE(jsonb_agg(jsonb_build_object(
       'scenario_code',x.code,'operation_scope',x.operation_scope,'hypothesis',x.hypothesis,
       'test_objective',x.test_objective,'expected_control',x.expected_control,
       'status','NOT_TESTED','positive_and_negative_tests_required',true)
       ORDER BY x.code),'[]'::jsonb)
     FROM (VALUES
       ('MULTI_ORIGIN_SINGLE_SUBJECT',
        'A single pair counter may reset when the origin changes',
        'Same subject across distinct origin networks',
        'Subject-level protection remains effective across origins','ALL'),
       ('SINGLE_ORIGIN_MULTI_SUBJECT',
        'A pair counter may allow cumulative attempts across subjects',
        'Different subjects using one origin',
        'Distributed abuse protection and origin policy are evaluated','ALL'),
       ('LEGITIMATE_SHARED_NETWORK',
        'One IP may represent several legitimate subjects',
        'Multiple legitimate subjects behind shared NAT',
        'No hard single-IP lockout; false-positive mitigation demonstrated','ALL'),
       ('SUCCESS_FAILURE_AND_RETRY',
        'The source does not define which authentication outcomes count',
        'Success, failure, rejected anti-bot, transport retries',
        'Event inclusion, exclusion and reset semantics are verified','LOGIN'),
       ('CONCURRENT_REQUESTS',
        'Counter atomicity and concurrent requests are unverified',
        'Parallel attempts for one subject and origin',
        'Server-side atomic enforcement demonstrated','ALL'),
       ('WINDOW_BOUNDARY',
        'Window boundaries and burst handling are unverified',
        'Requests around window and burst limits',
        'Central max/window/burst values enforced as intended','ALL'),
       ('CONTROL_DEGRADATION',
        'External anti-bot or identity services may be unavailable',
        'Unavailable anti-bot or identity-provider dependency',
        'Fail closed without granting a session','ALL'),
       ('MULTISIGNAL_DISTRIBUTED_ABUSE',
        'Declared multi-signal control may not be active server-side',
        'Distributed suspicious requests with independent risk signals',
        'Adaptive protection and relevant logging are demonstrated','ALL'),
       ('OTP_SEND_REPLAY_AND_ABUSE',
        'A send counter may not protect all repeated issuance paths',
        'Repeated OTP delivery events to the same subject',
        'Per-operation issuance and anti-abuse throttling are proven','OTP'),
       ('OTP_CROSS_OPERATION_SEPARATION',
        'Password recovery and new-device OTP might share counters',
        'Distinct OTP operations on the same subject and origin',
        'Counters and outcomes remain independent by functional operation','OTP'),
       ('OTP_DELIVERY_AND_ENFORCEMENT',
        'Delivery acceptance does not prove a secure issued challenge',
        'Delivery failure, delayed response and duplicate provider event',
        'State transitions follow policy and do not expose identity','OTP'),
       ('OTP_SEND_ENUMERATION',
        'Response differences may reveal whether the subject exists',
        'Existing and nonexistent subject delivery attempts',
        'Responses do not disclose identity or account state','OTP')
     ) x(code,hypothesis,test_objective,expected_control,operation_scope)
     WHERE ctx.resource_code LIKE 'AUTH_%'
       AND (x.operation_scope='ALL'
            OR (x.operation_scope='LOGIN' AND ctx.resource_code='AUTH_LOGIN')
            OR (x.operation_scope='OTP' AND ctx.resource_code LIKE '%OTP%'))
   ),
   'standard_context',jsonb_build_array(
     jsonb_build_object('authority','OWASP','kind','NONBINDING_GUIDANCE',
       'reference','Bot Management and Anti-Automation Cheat Sheet',
       'url','https://cheatsheetseries.owasp.org/cheatsheets/Bot_Management_and_Anti-Automation_Cheat_Sheet.html'),
     jsonb_build_object('authority','NIST','kind','CONDITIONAL_REQUIREMENTS',
       'reference','SP 800-63B-4, rate limiting for applicable authenticators',
       'url','https://pages.nist.gov/800-63-4/sp800-63b.html')),
   'remediation_gate','VERIFY_EXISTING_POLICY_BINDINGS_AND_RUNTIME_BEFORE_ADJUSTING_ANY_LIMIT',
   'acceptance','Positive/negative multi-scenario evidence, governed source authority and post-change readback'
 ) result
 FROM auth_abuse_context ctx
 WHERE ctx.resource_code LIKE 'AUTH_%'
), r6 AS (
 SELECT result FROM auth_abuse_cases
 UNION ALL
 SELECT jsonb_build_object('threat_code',t->>'threat_code',
   'observed_status',t->>'status','evidence_refs',t->'evidence_refs',
   'finding_kind','GENERIC_EVIDENCE_NOT_SEMANTIC_PROOF',
   'semantic_verdict','NOT_TESTED') result
 FROM sec_assessment a CROSS JOIN LATERAL jsonb_array_elements(a.threat_coverage) t
 WHERE t->>'status'='COMPLETE' AND t->'evidence_refs'='["SCREEN_RULE_SET"]'::jsonb
 UNION ALL
 -- An applicable PARTIAL or MISSING claim remains actionable even after
 -- the generic evidence issue is fixed in a newer RUN.
 SELECT jsonb_build_object('threat_code',t->>'threat_code',
   'observed_status',t->>'status','applicability',t->>'applicability',
   'applicability_authority',t->>'applicability_authority',
   'current_evidence_refs',t->'evidence_refs',
   'declared_rationale',t->>'rationale',
   'finding_kind','APPLICABLE_SECURITY_COVERAGE_INCOMPLETE',
   'repair_focus','LOCATE_CANONICAL_MITIGATION_AND_VERIFY_IMPLEMENTATION',
   'semantic_verdict','NOT_TESTED') result
 FROM sec_assessment a CROSS JOIN LATERAL jsonb_array_elements(a.threat_coverage) t
 WHERE t->>'applicability'='APPLICABLE' AND t->>'status' IN ('PARTIAL','MISSING')
 AND NOT (t->>'threat_code'='OTP_REPLAY_SINGLE_USE' AND EXISTS(
   SELECT 1 FROM effective e WHERE e.binding_source<>'DERIVED_GLOBAL'
     AND e.valor_config->>'one_time_use'='REQUIRED'
     AND e.valor_config->>'replay_after_success'='DENY'))
 UNION ALL
 -- A candidate rule can support definition coverage, but not proof of
 -- implementation or security enforcement. Keep the dimension separate.
 SELECT jsonb_build_object('threat_code',t->>'threat_code',
   'observed_status',t->>'status','evidence_rule',r.codigo,
   'evidence_rule_id',r.id,'rule_status',r.estado,
   'implementation_status',r.valor_config->>'implementation_status',
   'production_authorized',r.valor_config->>'production_authorized',
   'binding_source',r.binding_source,
   'finding_kind','DECLARED_CONTROL_WITHOUT_IMPLEMENTATION_PROOF',
   'repair_focus','VERIFY_SERVER_ENFORCEMENT_AND_QA_BEFORE_PRODUCTION_CLAIM',
   'semantic_verdict','NOT_TESTED') result
 FROM sec_assessment a CROSS JOIN LATERAL jsonb_array_elements(a.threat_coverage) t
 CROSS JOIN LATERAL jsonb_array_elements_text(
   CASE WHEN jsonb_typeof(t->'evidence_refs')='array'
   THEN t->'evidence_refs' ELSE '[]'::jsonb END) ref(code)
 JOIN effective r ON r.codigo=ref.code AND r.binding_source<>'DERIVED_GLOBAL'
 WHERE t->>'status'='COMPLETE' AND (
     r.estado='CANDIDATO'
     OR r.valor_config->>'implementation_status' IN (
       'PENDING_IMPLEMENTATION_QA','NOT_IMPLEMENTED','UNVERIFIED'))
 UNION ALL
 SELECT jsonb_build_object('threat_code',t->>'threat_code',
   'observed_status',t->>'status','evidence_rule',r.codigo,
   'rule_status',r.estado,'finding_kind','DECLARED_CONTROL_MISCLASSIFIED_AS_MISSING',
   'implementation_status','NOT_PROVEN','semantic_verdict','NOT_TESTED')
 FROM sec_assessment a
 CROSS JOIN LATERAL jsonb_array_elements(a.threat_coverage) t
 JOIN effective r ON r.binding_source<>'DERIVED_GLOBAL'
   AND r.valor_config->>'one_time_use'='REQUIRED'
   AND r.valor_config->>'replay_after_success'='DENY'
 WHERE t->>'threat_code'='OTP_REPLAY_SINGLE_USE' AND t->>'status'='MISSING'
), raw_findings AS (
 SELECT 'R2' detector,'CONFLICT_PRECEDENCE' family_code,'RESEARCH_REQUIRED' proposal_kind,
   'CO_SCOPED_CONFLICT_REVIEW' gap_code,
   (SELECT COALESCE(jsonb_agg(result),'[]'::jsonb) FROM r2) cases
 UNION ALL SELECT 'R3','SOURCE_AUTHORITY_PROVENANCE','SOURCE_INCOMPLETE',
   'ACTIVE_TO_CANDIDATE_REFERENCE',
   (SELECT COALESCE(jsonb_agg(result),'[]'::jsonb) FROM r3)
 UNION ALL SELECT 'R4','CONFLICT_PRECEDENCE','RESEARCH_REQUIRED',
   'SAME_TITLE_DISTINCT_CONFIG_REVIEW',
   (SELECT COALESCE(jsonb_agg(result),'[]'::jsonb) FROM r4)
 UNION ALL SELECT 'R5','APPLICABILITY_READINESS','SOURCE_INCOMPLETE',
   'TRANSVERSAL_SELECTOR_UNRESOLVED',
   (SELECT COALESCE(jsonb_agg(result),'[]'::jsonb) FROM r5)
 UNION ALL SELECT 'R6','SECURITY','RESEARCH_REQUIRED',
   'SECURITY_THREAT_EVIDENCE_SEMANTIC_REVIEW',
   (SELECT COALESCE(jsonb_agg(result),'[]'::jsonb) FROM r6)
), findings AS (
 SELECT jsonb_build_object('detector',detector,'family_code',family_code,
    'proposal_kind',proposal_kind,'gap_code',concat('IG_EVO_',detector,'_',gap_code),
    'cases',cases,'case_count',jsonb_array_length(cases),
    'affected_entity_count',case when detector='R5' then
      COALESCE((select sum((x->>'rule_count')::integer) from jsonb_array_elements(cases) x),0)
      else jsonb_array_length(cases) end,
    'detector_root_key',concat('IG_EVO_',detector,'_',gap_code),
    'auto_apply',false,
    'semantic_quality_evaluated',false,'semantic_pass_authorized',false,
    'decision','EVIDENCE_OR_SEMANTIC_REVIEW_REQUIRED') item
 FROM raw_findings WHERE jsonb_array_length(cases)>0
)
SELECT jsonb_build_object(
 'schema_version','IG_EVO_R2_R6_DIAGNOSTICS_V1',
 'pantalla_id',p_pantalla_id,'run_id',p_run_id,
 'run_source_snapshot_sha256',v_run.source_snapshot_sha256,
 'previous_run_id',v_prev.id,
 'previous_run_is_historical',v_prev.invalidated_at IS NOT NULL,
 'previous_source_snapshot_sha256',v_prev.source_snapshot_sha256,
 'source_snapshot_comparison',case when v_prev.id is null then 'NO_BASELINE'
     when v_prev.source_snapshot_sha256 IS DISTINCT FROM v_run.source_snapshot_sha256
       then 'CHANGED_SNAPSHOT' else 'SAME_SNAPSHOT' end,
 'detector_version','IG_EVO_R2_R6_DIAGNOSTICS_V1',
 'mode','DETERMINISTIC_CANDIDATE_DISCOVERY',
 'canonical_write_authorized',false,'semantic_quality_evaluated',false,
 'finding_count',COUNT(*),
 'findings',COALESCE(jsonb_agg(item ORDER BY item->>'detector'),'[]'::jsonb)
) INTO v_result FROM findings;
  RETURN v_result;
END;
$evo$;
REVOKE ALL ON FUNCTION programacion.fn_ig_evo_r2_r6_diagnostics_v1(integer,bigint) FROM PUBLIC;

DO $preflight$
BEGIN
 IF has_function_privilege('public',
     'programacion.fn_ig_evo_r2_r6_diagnostics_v1(integer,bigint)'::regprocedure,'EXECUTE')
 THEN RAISE EXCEPTION 'IG_EVO_R2_R6_PUBLIC_EXPOSURE'; END IF;
 IF position('semantic_pass_authorized' in
      pg_get_functiondef('programacion.fn_ig_evo_r2_r6_diagnostics_v1(integer,bigint)'::regprocedure))=0
 THEN RAISE EXCEPTION 'IG_EVO_R2_R6_SEMANTIC_GUARD_MISSING'; END IF;
END $preflight$;
-- Negative guard: wrong RUN and mismatched screen must fail closed.
DO $scope_tests$
DECLARE v_error text;
BEGIN
  BEGIN
    PERFORM programacion.fn_ig_evo_r2_r6_diagnostics_v1(51,0);
    RAISE EXCEPTION 'IG_EVO_R2_R6_INVALID_RUN_WAS_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'IG_EVO_R2_R6_RUN_SCOPE_INVALID:%'
      THEN RAISE EXCEPTION 'IG_EVO_R2_R6_INVALID_RUN_WRONG_ERROR:%',v_error;
    END IF;
  END;
  BEGIN
    PERFORM programacion.fn_ig_evo_r2_r6_diagnostics_v1(1,949);
    RAISE EXCEPTION 'IG_EVO_R2_R6_WRONG_SCREEN_WAS_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'IG_EVO_R2_R6_RUN_SCOPE_INVALID:%'
      THEN RAISE EXCEPTION 'IG_EVO_R2_R6_WRONG_SCREEN_WRONG_ERROR:%',v_error;
    END IF;
  END;
END $scope_tests$;
-- Controlled positive and negative evidence checks. No historical RUN mutated.
DO $cross_policy_tests$
DECLARE
 v_doc jsonb; v_chain jsonb; v_recovery jsonb; v_negative jsonb;
BEGIN
 v_doc:=programacion.fn_ig_evo_r2_r6_diagnostics_v1(51,949);
 SELECT c INTO v_chain
 FROM jsonb_array_elements(v_doc->'findings') f
 CROSS JOIN LATERAL jsonb_array_elements(f->'cases') c
 WHERE c->>'finding_kind'='CROSS_POLICY_CONTROL_AND_ADVERSARIAL_SCENARIOS'
   AND c->'source_rule'->>'code'='B2B-RULE-AUTH-021'
 LIMIT 1;
 IF v_chain IS NULL
 OR v_chain->'security_policy'->>'code'<>'SEC-B2B-AUTH-ABUSE-PROTECTION'
 OR v_chain->'security_policy'->>'status'<>'CANDIDATO'
 OR v_chain->'security_policy'->>'binding_status'<>'CANDIDATO'
 OR v_chain->'rate_policy'->>'code'<>'RATE-B2B-LOGIN'
 OR v_chain->'rate_policy'->>'scope_key'<>'IP_USER'
 OR v_chain->'existing_controls'->>'distributed_attack_detection'<>'REQUIRED'
 OR v_chain->'existing_controls'->>'shared_ip_false_positive_mitigation'<>'REQUIRED'
 OR v_chain->>'risk_confirmed'<>'false'
 OR v_chain->>'semantic_verdict'<>'NOT_TESTED'
 OR jsonb_array_length(v_chain->'risk_scenarios')<>8 THEN
   RAISE EXCEPTION 'IG_EVO_R6_CROSS_POLICY_POSITIVE_NOT_PROVEN:%',v_chain;
 END IF;
 v_recovery:=programacion.fn_ig_evo_r2_r6_diagnostics_v1(56,836);
 SELECT c INTO v_chain
 FROM jsonb_array_elements(v_recovery->'findings') f
 CROSS JOIN LATERAL jsonb_array_elements(f->'cases') c
 WHERE c->>'finding_kind'='CROSS_POLICY_CONTROL_AND_ADVERSARIAL_SCENARIOS'
   AND c->'rate_policy'->>'resource_code' LIKE '%OTP%'
 LIMIT 1;
 IF v_chain IS NULL OR jsonb_array_length(v_chain->'risk_scenarios')<>11 OR
   EXISTS(SELECT 1 FROM jsonb_array_elements(v_chain->'risk_scenarios') x
      WHERE x->>'operation_scope'='LOGIN') THEN
   RAISE EXCEPTION 'IG_EVO_R6_OTP_SCENARIO_SCOPE_INVALID:%',v_chain;
 END IF;
 v_negative:=programacion.fn_ig_evo_r2_r6_diagnostics_v1(1,931);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_negative->'findings') f
   CROSS JOIN LATERAL jsonb_array_elements(f->'cases') c
   WHERE c->>'finding_kind'='CROSS_POLICY_CONTROL_AND_ADVERSARIAL_SCENARIOS') THEN
   RAISE EXCEPTION 'IG_EVO_R6_UNRELATED_SCREEN_FALSE_POSITIVE';
 END IF;
END $cross_policy_tests$;

COMMIT;
