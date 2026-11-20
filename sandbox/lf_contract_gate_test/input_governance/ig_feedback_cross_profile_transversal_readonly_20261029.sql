-- LF Input Governance / profile-neutral feedback integration: READ-ONLY
-- Checks actual catalog bindings and Router continuation independent of the
-- product_director_lf profile. Does not implement a feedback adapter.
-- Synthetic profile output tests ONLY the existing typed-routing classifier.
WITH registry AS MATERIALIZED (
 SELECT a.codigo_activo profile_code,
   a.metadata->>'input_governance_binding_mode' binding_mode,
   a.metadata->>'input_governance_consumer' consumer,
   EXISTS(
    SELECT 1 FROM public.lf_activo_relaciones r
    WHERE r.codigo_activo=a.codigo_activo
      AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND r.relacion_tipo='GOBERNADO_POR'
   ) AS direct_relation
 FROM public.lf_activos a
 WHERE a.tipo_activo='PERFIL' AND a.archived_at IS NULL
   AND a.codigo_activo NOT LIKE '%CANDIDATE%'
), cases AS MATERIALIZED (
 -- These are structural probes, not validated native model outputs.
 SELECT 'PRODUCT'::text AS test,
  'PERFIL-PRODUCT-DIRECTOR-LF'::text profile_code,
  jsonb_build_object('status','PASS_WITH_RESTRICTIONS',
    'routing',jsonb_build_object('pipeline_action','CONTINUE',
      'via','ORCHESTRATOR','resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION')) payload
 UNION ALL
 SELECT 'UI', 'PERFIL-UI-ARCHITECT',
  jsonb_build_object('status','PASS_WITH_RESTRICTIONS',
    'routing',jsonb_build_object('pipeline_action','CONTINUE_WITH_RESTRICTIONS',
      'via','ORCHESTRATOR','resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'))
 UNION ALL
 SELECT 'EVIDENCE', 'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
  jsonb_build_object('status','PASS_WITH_RESTRICTIONS',
    'routing',jsonb_build_object('pipeline_action','CONTINUE',
      'via','ORCHESTRATOR','resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'))
 UNION ALL
 SELECT 'REPAIR', 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
  jsonb_build_object('status','PASS_WITH_RESTRICTIONS',
    'routing',jsonb_build_object('pipeline_action','CONTINUE',
      'via','ORCHESTRATOR','resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'))
), routed AS MATERIALIZED (
 SELECT c.test,c.profile_code,
 public.lf_profile_result_router_return_classify_v1(
 c.payload, 'Revisar hallazgo LF por especialidad',
 'TEST-IG-PROFILE-NEUTRAL-'||c.test,c.profile_code
 ) AS result
 FROM cases c
), tests AS MATERIALIZED (
 SELECT 'ALL_TEN_CURRENT_PROFILES_REGISTERED' test,
   (SELECT count(*)=10 FROM registry) pass
 UNION ALL SELECT 'FOUR_DIRECT_IG_BINDINGS',
  (SELECT count(*)=4 FROM registry WHERE direct_relation
    AND binding_mode='DIRECT_PROFILE' AND consumer='CONTEXT_PACK')
 UNION ALL SELECT 'SIX_WITHOUT_DIRECT_IG_BINDING',
  (SELECT count(*)=6 FROM registry WHERE NOT direct_relation
   AND binding_mode IS NULL)
 UNION ALL SELECT 'NO_PROFILE_AS_TECHNICAL_CONSUMER',
  (SELECT count(*)=0 FROM registry WHERE consumer=profile_code)
 UNION ALL SELECT 'ROUTING_PRODUCT',
  (SELECT result->>'status'='RETURN_TO_ROUTER'
    AND result->>'next_action'='REENTER_ROUTER_STAGE1'
    FROM routed WHERE test='PRODUCT')
 UNION ALL SELECT 'ROUTING_UI',
  (SELECT result->>'status'='RETURN_TO_ROUTER'
    AND result->>'next_action'='REENTER_ROUTER_STAGE1'
    FROM routed WHERE test='UI')
 UNION ALL SELECT 'ROUTING_EVIDENCE',
  (SELECT result->>'status'='RETURN_TO_ROUTER'
    AND result->>'next_action'='REENTER_ROUTER_STAGE1'
    FROM routed WHERE test='EVIDENCE')
 UNION ALL SELECT 'ROUTING_REPAIR',
  (SELECT result->>'status'='RETURN_TO_ROUTER'
    AND result->>'next_action'='REENTER_ROUTER_STAGE1'
    FROM routed WHERE test='REPAIR')
 UNION ALL SELECT 'ALL_ROUTER_OUTPUTS_RETAIN_SOURCE_PROFILE',
  (SELECT count(*)=4 FROM routed r
   WHERE r.result->>'source_profile_code'=r.profile_code)
 UNION ALL SELECT 'REENTRY_RECLASSIFIES_ALL_PROFILES',
  (SELECT count(*)=4 FROM routed r WHERE
    r.result#>>'{router_return_request,route_policy}'='REPEAT_FULL_ROUTER_FLOW'
    AND r.result#>>'{router_return_request,reuse_prior_profile_selection}'='false'
    AND r.result#>>'{router_return_request,next_entrypoint}'='ACT-0001_STAGE1')
 UNION ALL SELECT 'EXPLICIT_DIRECT_TARGET_FORBIDDEN',
   (SELECT public.lf_profile_result_router_return_classify_v1(
     jsonb_build_object('status','PASS','target_profile','PERFIL-UI-ARCHITECT'),
     'Tarea de prueba', 'TEST-IG-DIRECT-FORBIDDEN',
     'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
   )->>'code'='PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN')
)
SELECT test,CASE WHEN pass IS TRUE THEN 'PASS' ELSE 'FAIL' END verdict
FROM tests ORDER BY test;
