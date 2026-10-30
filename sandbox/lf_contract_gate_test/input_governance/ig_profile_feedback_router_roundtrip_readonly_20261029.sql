-- SELECT-only: synthetic profile output with *explicit existing typed routing*.
-- This tests the EXISTING Router classifier and Stage1/semantic preparation;
-- it DOES NOT test applying the proposed classifier patch nor valid Product output.
-- Subject labels and fixture 949 are historical test inputs, not runtime authority.
WITH fixture AS MATERIALIZED (
 SELECT r.id,r.pantalla_id,r.source_snapshot_sha256 AS sha,
        e.execution_id,e.target_code AS profile_code
 FROM programacion.input_readiness_runs r
 JOIN public.lf_operation_execution_steps s
  ON s.evidence_payload#>>'{input_governance,run_id}'=r.id::text
  AND s.step_id='input_validate'
  AND s.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution e ON e.execution_id=s.execution_id
 WHERE r.id=949 AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 LIMIT 1
), mock_profile_output AS MATERIALIZED (
 SELECT f.execution_id,f.profile_code,jsonb_build_object(
  'status','PASS_WITH_RESTRICTIONS',
  'output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
  'routing',jsonb_build_object(
    'via','ORCHESTRATOR',
    'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
    'resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'
  ),
  'deliverable_created',jsonb_build_object(
    'input_governance_feedback',jsonb_build_object(
      'schema_version','IG_PROFILE_FEEDBACK_V1',
      'kind','EVIDENCE_CHALLENGE','run_id',f.id,
      'pantalla_id',f.pantalla_id,'family_code','SESSION',
      'source_snapshot_sha256',f.sha,
      'reason','Fixture: revisar el sustento de la completitud de SESSION',
      'evidence_refs',jsonb_build_array('supabase://lf_ops/politicas_sesion/1')
    )
  )) AS output FROM fixture f
), classified AS MATERIALIZED (
 SELECT public.lf_profile_result_router_return_classify_v1(
   output,'Revisar reglas login B2B',execution_id,profile_code
 ) AS result FROM mock_profile_output
), began AS MATERIALIZED (
 SELECT result,public.lf_router_pipeline_context_begin_v2(
   result#>>'{router_return_request,stage1_literal}'
 ) AS started FROM classified
), submitted AS MATERIALIZED (
 SELECT result,started,
 public.lf_router_pipeline_context_stage1_submit_v2(
   started->>'context_token',
   jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original',result#>>'{router_return_request,stage1_literal}',
    'es_operacion',true,'ambiguo',false,'respuesta_directa',false,
    'sujeto','Revisar evidencia de reglas del login B2B',
    'accion','resolver discrepancia sobre contexto canónico',
    'formas_busqueda',jsonb_build_array(
      'login B2B','reglas de negocio','Input Governance'
    ),
    'alternativas','[]'::jsonb,'correcciones','[]'::jsonb,
    'canal_candidato','PRODUCTO','negocio_codigo','LF',
    'negocios_afectados','[]'::jsonb,
    'razon_seleccion','Fixture Stage1: revision contextual sin target_profile',
    'alcance',jsonb_build_object(
      'target_type','PANTALLA','target_hint','login B2B',
      'resolution_status','UNRESOLVED'
    ),
    'downstream_execution_allowed',false
   )
 ) AS sealed FROM began
), prepared AS MATERIALIZED (
 SELECT result,started,sealed,
 public.lf_router_pipeline_context_profile_semantic_prepare_v2(
   sealed->>'context_token'
 ) AS semantic FROM submitted
), checks AS MATERIALIZED (
 SELECT 'PROFILE_RETURN_ROUTER' test,
  (SELECT result->>'status'='RETURN_TO_ROUTER' FROM prepared) AS pass
 UNION ALL SELECT 'ROUTER_REENTRY',
  (SELECT result->>'next_action'='REENTER_ROUTER_STAGE1' FROM prepared)
 UNION ALL SELECT 'PRIOR_SELECTION_NOT_AUTHORITY',
  (SELECT result#>>'{router_return_request,route_policy}'='REPEAT_FULL_ROUTER_FLOW'
  AND result#>>'{router_return_request,reuse_prior_profile_selection}'='false'
  FROM prepared)
 UNION ALL SELECT 'UPSTREAM_FEEDBACK_PRESERVED',
  (SELECT result#>>'{router_return_request,unresolved_payload,upstream_profile_output,deliverable_created,input_governance_feedback,run_id}'='949'
  AND result#>>'{router_return_request,unresolved_payload,upstream_profile_output,deliverable_created,input_governance_feedback,kind}'='EVIDENCE_CHALLENGE'
  FROM prepared)
 UNION ALL SELECT 'UPSTREAM_HASH_PRESERVED',
  (SELECT result#>>'{router_return_request,unresolved_payload,upstream_profile_output_sha256}'
  ~ '^sha256:[a-f0-9]{64}$' FROM prepared)
 UNION ALL SELECT 'ROUTER_STAGE1_REQUIRED',
  (SELECT started->>'status'='STAGE1_REQUIRED' FROM prepared)
 UNION ALL SELECT 'STAGE1_VALID',
  (SELECT sealed->>'status'='NEXT_TRANSITION_READY'
    AND sealed#>>'{stage1_validation,valid}'='true' FROM prepared)
 UNION ALL SELECT 'SEMANTIC_SELECTION_REQUIRED',
  (SELECT semantic->>'status'='PROFILE_SEMANTIC_SELECTION_REQUIRED'
    AND semantic#>>'{profile_selection_request,catalog_profile_count}'='10'
    FROM prepared)
 UNION ALL SELECT 'NO_EXECUTION_AUTHORITY',
  (SELECT started->>'effect_authority'='false'
     AND semantic->>'downstream_execution_allowed'='false'
     FROM prepared)
)
SELECT test,CASE WHEN pass IS TRUE THEN 'PASS' ELSE 'FAIL' END verdict
FROM checks ORDER BY test;
