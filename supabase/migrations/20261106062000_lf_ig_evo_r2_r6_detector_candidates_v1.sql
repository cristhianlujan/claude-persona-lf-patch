-- IG-EVO R2-R6: policy-aware deterministic candidate discovery within native Input Governance.
-- No independent judge and no assertions of security implementation or global rule applicability.
-- Scope: R2 same-screen candidate conflicts; R3 active->candidate references;
-- R4 same-title/different-config co-screen; R5 declarative transversal selector gaps;
-- R6 generic threat evidence and OTP-definition-vs-MISSING.
-- Requires owner governed Curator hook in a subsequent migration.
BEGIN;
CREATE OR REPLACE FUNCTION programacion.fn_ig_evo_r2_r6_diagnostics_v1(p_pantalla_id integer,p_run_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
 SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $evo$
WITH effective AS (
 SELECT r.id,r.codigo,r.estado,r.titulo,r.categoria,r.valor_config,r.es_transversal,r.pendiente_decision
 FROM programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') e
 JOIN lf_ops.reglas r ON r.id=e.regla_id
 WHERE e.pantalla_id=p_pantalla_id AND r.estado IN ('VIGENTE','CANDIDATO')
), r2 AS (
 SELECT jsonb_build_object('rule_code',r.codigo,'policy_code',p.policy_code,
       'rule_state',r.estado,'binding_state',b.status,'policy_state',p.status,
       'action',r.valor_config->>'accion','policy_ip_hard_limit',p.policy_config->>'ip_hard_limit',
       'semantic_verdict','NOT_TESTED','scope','SAME_SCREEN_OBSERVED')
   result
 FROM effective r
 JOIN lf_ops.pantallas_politicas b ON b.pantalla_id=p_pantalla_id
 JOIN lf_ops.politicas_seguridad p ON p.security_policy_id=b.security_policy_id
 WHERE r.valor_config->>'accion' ~* '(bloquear_ip|bloqueo_ip)'
   AND p.policy_config->>'ip_hard_limit'='DENY'
), rule_refs AS (
 SELECT e.codigo source_code,e.estado source_state,kv.key reference_key,
   kv.value referenced_value
 FROM effective e
 CROSS JOIN LATERAL jsonb_each(
   CASE WHEN jsonb_typeof(e.valor_config)='object' THEN e.valor_config ELSE '{}'::jsonb END
 ) kv
 WHERE e.estado='VIGENTE'
), r3 AS (
 SELECT jsonb_build_object('source_code',s.source_code,'source_state',s.source_state,
   'reference_key',s.reference_key,'target_code',t.codigo,'target_status',t.estado,
   'link_kind','RULE_BY_ID','promotion_authorized',false) result
 FROM rule_refs s
 JOIN lf_ops.reglas t ON t.id=CASE WHEN jsonb_typeof(s.referenced_value)='number'
     AND (s.referenced_value #>> '{}') ~ '^[0-9]+$'
     THEN (s.referenced_value #>> '{}')::integer ELSE NULL END
 WHERE s.reference_key ~ '_rule_id$' AND t.estado='CANDIDATO'
 UNION ALL
 SELECT jsonb_build_object('source_code',s.source_code,'source_state',s.source_state,
   'reference_key',s.reference_key,'target_code',t.codigo,'target_status',t.estado,
   'link_kind','RULE_BY_CODE','promotion_authorized',false)
 FROM rule_refs s JOIN lf_ops.reglas t ON t.codigo=s.referenced_value #>> '{}'
 WHERE s.reference_key ~ '_rule_code$'
   AND jsonb_typeof(s.referenced_value)='string' AND t.estado='CANDIDATO'
), r4 AS (
 SELECT jsonb_build_object('first_rule',a.codigo,'second_rule',b.codigo,
   'first_state',a.estado,'second_state',b.estado,
   'same_title',true,'same_config',false,'true_duplicate','NOT_PROVEN',
   'semantic_verdict','NOT_TESTED') result
 FROM effective a JOIN effective b ON a.id<b.id
 WHERE a.titulo IS NOT NULL AND b.titulo IS NOT NULL
   AND lower(btrim(a.titulo))=lower(btrim(b.titulo))
   AND a.valor_config IS DISTINCT FROM b.valor_config
), r5 AS (
 SELECT jsonb_build_object('rule_code',r.codigo,'rule_state',r.estado,
   'selector_state',COALESCE(r.valor_config->'applicability_v1'->>'status','MISSING'),
   'global_applicability','NOT_PROVEN','effective_screen_context',p_pantalla_id)
 result
 FROM effective r
 WHERE r.es_transversal IS TRUE
   AND COALESCE(r.valor_config->'applicability_v1'->>'status','MISSING')<>'ACTIVE'
), sec_assessment AS (
 SELECT a.threat_coverage
 FROM programacion.input_family_assessments a
 WHERE a.run_id=p_run_id AND a.family_code='SECURITY'
), r6 AS (
 SELECT jsonb_build_object('threat_code',t->>'threat_code',
   'observed_status',t->>'status','evidence_refs',t->'evidence_refs',
   'finding_kind','GENERIC_EVIDENCE_NOT_SEMANTIC_PROOF',
   'semantic_verdict','NOT_TESTED') result
 FROM sec_assessment a CROSS JOIN LATERAL jsonb_array_elements(a.threat_coverage) t
 WHERE t->>'status'='COMPLETE' AND t->'evidence_refs'='["SCREEN_RULE_SET"]'::jsonb
 UNION ALL
 SELECT jsonb_build_object('threat_code',t->>'threat_code',
   'observed_status',t->>'status','evidence_rule',r.codigo,
   'rule_status',r.estado,'finding_kind','DECLARED_CONTROL_MISCLASSIFIED_AS_MISSING',
   'implementation_status','NOT_PROVEN','semantic_verdict','NOT_TESTED')
 FROM sec_assessment a
 CROSS JOIN LATERAL jsonb_array_elements(a.threat_coverage) t
 JOIN effective r ON r.valor_config->>'one_time_use'='REQUIRED'
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
    'cases',cases,'case_count',jsonb_array_length(cases),'auto_apply',false,
    'semantic_quality_evaluated',false,'semantic_pass_authorized',false,
    'decision','EVIDENCE_OR_SEMANTIC_REVIEW_REQUIRED') item
 FROM raw_findings WHERE jsonb_array_length(cases)>0
)
SELECT jsonb_build_object(
 'schema_version','IG_EVO_R2_R6_DIAGNOSTICS_V1',
 'pantalla_id',p_pantalla_id,'run_id',p_run_id,
 'mode','DETERMINISTIC_CANDIDATE_DISCOVERY',
 'canonical_write_authorized',false,'semantic_quality_evaluated',false,
 'finding_count',COUNT(*),
 'findings',COALESCE(jsonb_agg(item ORDER BY item->>'detector'),'[]'::jsonb)
) FROM findings;
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
COMMIT;
