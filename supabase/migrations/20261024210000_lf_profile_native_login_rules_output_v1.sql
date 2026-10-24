-- Record the current GPT_NATIVE Product Director RAW for the Login B2B canonical-rule canary.
-- Deliberately stops at 9/11; independent semantic judgment is not produced here.
BEGIN;
DO $record$
DECLARE
  v_result jsonb;
  v_n integer;
BEGIN
  v_result:=public.lf_profile_native_bridge_record_output_v1(
    'EXEC-PROFILE-GATE2-1BDAD35D77DC30810DE68282',
    $raw${"worker":"product_director_lf","output_type":"PRODUCT_DIRECTION_SPEC","deliverable_created":{"product_decision":{"decision_id":"B2B-AUTH-001-CANONICAL-RULE-READ-001","selected_decision":"Para esta consulta de lectura, devolver las 71 reglas directamente vinculadas a B2B-AUTH-001 preservando código, título y estado; informar por separado que el contrato efectivo agrega 283 reglas en total, sin expandir las heredadas salvo que el usuario lo solicite.","rationale":"Es una extracción canónica, no una modificación. La autoridad ya resolvió el conjunto directo y el agregado efectivo.","source_refs":[{"source_ref":"supabase://lf_ops.reglas_pantallas/B2B-AUTH-001","authority":"AUTHORITATIVE","supports":"71 reglas directas con código, título y estado.","current":true},{"source_ref":"supabase://lf_ops.fn_screen_contract_v1/B2B_APP_SHELL/B2B_AUTENTICACION/B2B-AUTH-001#rules","authority":"AUTHORITATIVE","supports":"283 reglas efectivas incluyendo herencia/transversalidad.","current":true}],"rejected_alternatives":["Devolver solo AUTH-* omitiría otras reglas directas.","Expandir 283 reglas mezclaría el conjunto directo con la herencia efectiva."],"tradeoffs":["Precisión canónica antes que expansión innecesaria."],"preserved_constraints":["Lectura sin mutación.","Preservar estados VIGENTE/CANDIDATO.","Distinguir 71 directas de 283 efectivas."],"semantic_qualifiers":["71 corresponde a reglas directamente vinculadas a B2B-AUTH-001.","283 corresponde al agregado efectivo incluyendo reglas heredadas o transversales.","La pantalla B2B-AUTH-001 está en estado CANDIDATO versión v0.5."]},"included_scope":["Reglas directas de B2B-AUTH-001.","Código, título y estado.","Comentario breve de alcance."],"excluded_scope":["Modificar reglas.","Crear reglas.","Expandir las 283 efectivas sin solicitud expresa."],"priority":{"level":"READ_ONLY_CANONICAL","reason":"Responder la verdad canónica actual."},"acceptance_criteria":[{"criterion_id":"AC-DIRECT-COUNT","condition":"Responder el conjunto directo.","observable_check":"El listado contiene exactamente 71 reglas directas con código, título y estado."},{"criterion_id":"AC-EFFECTIVE-DISTINCTION","condition":"Separar agregado efectivo.","observable_check":"Se informa 283 como agregado efectivo, no como reglas directas."},{"criterion_id":"AC-NO-MUTATION","condition":"Mantener lectura.","observable_check":"No se modifica ninguna regla, estado o pantalla."}],"dependencies":[],"risks":["Confundir reglas directas con efectivas.","Filtrar solo AUTH-* ocultaría otras categorías directas."],"profiles_to_activate":[],"blockers":[],"next_step":{"target":"Orchestrator","action":"Renderizar las 71 reglas directas y preservar la distinción 71/283."},"final_verdict":"READ_ONLY_CANONICAL_EXTRACTION","evidence_used":[{"source_ref":"supabase://lf_ops.reglas_pantallas/B2B-AUTH-001","fact":"direct_rule_count=71"},{"source_ref":"supabase://lf_ops.fn_screen_contract_v1/B2B_APP_SHELL/B2B_AUTENTICACION/B2B-AUTH-001#rules","fact":"effective_rule_count=283"}],"open_assumptions":[],"success_metric_or_proxy":{"metric":"canonical_rule_fidelity","target":"71/71 directas; 0 inventadas; agregado 283 distinguido."},"handoff_to_next":{"target":"Orchestrator","input_contract":"Renderizar lista canónica directa sin reclasificar ni modificar.","qualifiers_to_preserve":["71 corresponde a reglas directamente vinculadas a B2B-AUTH-001.","283 corresponde al agregado efectivo incluyendo reglas heredadas o transversales.","La pantalla B2B-AUTH-001 está en estado CANDIDATO versión v0.5."]},"authority_status":"SUPPORTED","material_claims":[{"claim":"B2B-AUTH-001 tiene 71 reglas directamente vinculadas.","authority_ref":"supabase://lf_ops.reglas_pantallas/B2B-AUTH-001","status":"SUPPORTED"},{"claim":"B2B-AUTH-001 tiene 283 reglas efectivas incluyendo herencia/transversalidad.","authority_ref":"supabase://lf_ops.fn_screen_contract_v1/B2B_APP_SHELL/B2B_AUTENTICACION/B2B-AUTH-001#rules","status":"SUPPORTED"}],"decision_lineage":{"objective":"Responder las reglas actuales del Login B2B sin modificar producto.","selected_decision":"Para esta consulta de lectura, devolver las 71 reglas directamente vinculadas a B2B-AUTH-001 preservando código, título y estado; informar por separado que el contrato efectivo agrega 283 reglas en total, sin expandir las heredadas salvo que el usuario lo solicite.","evidence_refs":["supabase://lf_ops.reglas_pantallas/B2B-AUTH-001","supabase://lf_ops.fn_screen_contract_v1/B2B_APP_SHELL/B2B_AUTENTICACION/B2B-AUTH-001#rules"],"preserved_constraints":["No modificar reglas o estados.","No confundir directas con efectivas.","No inventar reglas."],"acceptance_refs":["AC-DIRECT-COUNT","AC-EFFECTIVE-DISTINCTION","AC-NO-MUTATION"],"handoff_effect":"El Orchestrator presenta el listado canónico directo sin reinterpretar el alcance."}},"score":{"product_decision_clarity":5,"scope_control_mvp_separation":5,"acceptance_criteria_quality":5,"cross_profile_handoff_quality":4,"evidence_risk_governance_traceability":5,"total":24,"evidence_by_criterion":{"product_decision_clarity":["selected_decision distingue lectura directa y agregado efectivo."],"scope_control_mvp_separation":["included_scope/excluded_scope limita a extracción sin mutación."],"acceptance_criteria_quality":["AC-DIRECT-COUNT y AC-EFFECTIVE-DISTINCTION detectan errores."],"cross_profile_handoff_quality":["handoff_to_next conserva los calificadores 71 directas / 283 efectivas."],"evidence_risk_governance_traceability":["source_refs vincula conteos a referencias canónicas."]}},"handoff_to_next":{"target":"Orchestrator","mode":"READ_ONLY_CANONICAL_RESPONSE"},"self_verdict":"PASS","traceability":{"execution_id":"EXEC-PROFILE-GATE2-1BDAD35D77DC30810DE68282","profile_source_ref":"github://cristhianlujan/claude-persona-lf-patch@fc88aca0874f3bee7d4dbe29379e975989b26cb2/profiles/product_director_lf/SKILL.md","context_receipt_ref":"supabase://public.lf_eventos/21538#context_receipt","context_receipt_digest":"sha256:bd17ab42af76ef3bc75a3e9e5038eda3dd8819e9ced90828357fc30e7daa2fb4"}}$raw$::jsonb,
    jsonb_build_object(
      'valid',true,
      'errors','[]'::jsonb,
      'blocking_codes','[]'::jsonb,
      'validator','profiles/product_director_lf/validators/validate_product_director_output.py',
      'validator_profile_revision','fc88aca0874f3bee7d4dbe29379e975989b26cb2'
    ),
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/login_b2b_rules_product_director_20261024/raw_output.json',
    'github://cristhianlujan/claude-persona-lf-patch@fc88aca0874f3bee7d4dbe29379e975989b26cb2/profiles/product_director_lf/validators/validate_product_director_output.py',
    NULL
  );
  IF v_result->>'status'<>'NATIVE_PRODUCER_VALIDATED'
     OR coalesce((v_result->>'clean_step_count')::integer,0)<>9
     OR coalesce((v_result->>'independent_semantic_judge_required')::boolean,false) IS NOT TRUE
     OR coalesce((v_result->>'producer_may_self_authorize')::boolean,true) IS TRUE
     OR coalesce((v_result->>'terminal_authority_ready')::boolean,true) IS TRUE THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_LOGIN_RULES_RAW_RECORD_FAILED:%',v_result;
  END IF;
  SELECT count(*) INTO v_n
  FROM public.lf_operation_execution_steps
  WHERE execution_id='EXEC-PROFILE-GATE2-1BDAD35D77DC30810DE68282'
    AND status='STEP_PASS_WITH_EVIDENCE';
  IF v_n<>9 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_LOGIN_RULES_RAW_STEP_COUNT:%',v_n;
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id='EXEC-PROFILE-GATE2-1BDAD35D77DC30810DE68282'
      AND step_id IN ('semantic_judge','report_output')
  ) THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_LOGIN_RULES_PREMATURE_TERMINAL_STEPS';
  END IF;
END
$record$;
COMMIT;
