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
COMMIT;
