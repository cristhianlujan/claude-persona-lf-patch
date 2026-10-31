-- Materialize EJECUCION_PERFIL_LF step 70 through the deployed governed semantic bridge.
DO $step70$
DECLARE
  v_execution_id text := 'EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975';
  v_judge jsonb := $judge$
{
  "schema_version": "LF_PRODUCT_DIRECTOR_SEMANTIC_JUDGE_V3_RECEIPT_V1",
  "execution_id": "EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975",
  "profile_code": "PERFIL-PRODUCT-DIRECTOR-LF",
  "judge_invocation_kind": "NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE",
  "prior_verdict_authority": "NOT_USED",
  "status": "PASS",
  "verdict": "PASS_INDEPENDENT_SEMANTIC",
  "validator_status": "PASS",
  "producer_independence_proven": true,
  "model_call_count": 1,
  "candidate_sha256": "09e647fe47e111620bbfe7da95a2ac885f1e59f3f3f29f5782150371a17b2d8f",
  "scope_packet_sha256": "d5f6ba9a2b51b90d0dc0e96def4b31ac8592a609cee80b032d2d8565f8bc6ee8",
  "decision_checks": {
    "context_resolution_valid": {
      "result": true,
      "source_refs": [
        "supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975#manifest"
      ],
      "reason": "Consumió el contexto y restricciones ya resueltos."
    },
    "evidence_supported": {
      "result": true,
      "source_refs": [
        "supabase://programacion.input_readiness_runs/949",
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-015",
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-022"
      ],
      "reason": "Las fuentes actuales sostienen la decisión."
    },
    "decision_resolves_objective": {
      "result": true,
      "source_refs": [
        "supabase://lf_ops.pantallas/B2B-AUTH-001"
      ],
      "reason": "Distingue regla faltante de implementación no lista."
    },
    "authority_resolution_valid": {
      "result": true,
      "source_refs": [
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-015"
      ],
      "reason": "Preserva autoridad actual."
    },
    "constraints_preserved": {
      "result": true,
      "source_refs": [
        "supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975#manifest"
      ],
      "reason": "Preserva NO_WRITE/no promoción y límites del handoff."
    },
    "claims_authorized": {
      "result": true,
      "source_refs": [
        "supabase://programacion.input_readiness_runs/949"
      ],
      "reason": "No fortalece readiness."
    },
    "materiality_handled_correctly": {
      "result": true,
      "source_refs": [
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-015"
      ],
      "reason": "No inventa identidad ni contrato ejecutable."
    },
    "tradeoff_defensible": {
      "result": true,
      "source_refs": [
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-015"
      ],
      "reason": "Las alternativas se rechazan por autoridad y riesgo."
    },
    "acceptance_detects_wrong_implementation": {
      "result": true,
      "source_refs": [
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-022"
      ],
      "reason": "Los criterios detectarían sesión/MFA o readiness incorrectos."
    },
    "handoff_implementation_ready": {
      "result": true,
      "source_refs": [
        "supabase://programacion.input_family_assessments/run_id=949"
      ],
      "reason": "El handoff conserva calificadores y no inventa verdad de negocio."
    },
    "router_direct_consistency": {
      "result": true,
      "source_refs": [
        "supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975#manifest"
      ],
      "reason": "Mantiene el objetivo y alcance del Router."
    },
    "counterfactual_trajectory": {
      "result": true,
      "source_refs": [
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-015",
        "supabase://lf_ops.reglas/B2B-RULE-AUTH-022"
      ],
      "reason": "El PASS depende de conservar identidad pendiente, MFA, readiness y NO_WRITE."
    }
  },
  "source_refs": [
    "supabase://programacion.input_readiness_runs/949",
    "supabase://programacion.input_family_assessments/run_id=949",
    "supabase://lf_ops.pantallas/B2B-AUTH-001",
    "supabase://lf_ops.reglas/B2B-RULE-AUTH-015",
    "supabase://lf_ops.reglas/B2B-RULE-AUTH-022",
    "supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975#manifest"
  ],
  "resolved_context_refs": [
    "supabase://public.lf_eventos/21714#context_receipt"
  ],
  "unsupported_claims": [],
  "blocking_codes": [],
  "preserved_constraints": [
    "No inventar identidad",
    "Preservar MFA y sesión",
    "NO_WRITE/no promoción"
  ],
  "router_direct_consistency": "PASS",
  "counterfactual_result": "PASS",
  "next_gate": "REGISTER_SEMANTIC_JUDGE",
  "result": {
    "verdict": "PASS_INDEPENDENT_SEMANTIC",
    "candidate_sha256": "09e647fe47e111620bbfe7da95a2ac885f1e59f3f3f29f5782150371a17b2d8f",
    "scope_packet_sha256": "d5f6ba9a2b51b90d0dc0e96def4b31ac8592a609cee80b032d2d8565f8bc6ee8",
    "unsupported_claims": [],
    "blocking_codes": []
  }
}
$judge$::jsonb;
  v_result jsonb;
  v_status text;
  v_report_count integer;
BEGIN
  v_result := public.lf_profile_native_bridge_record_semantic_v1(
    v_execution_id,
    v_judge,
    'github://cristhianlujan/claude-persona-lf-patch@ad7457833074ff2cdee7e9863fae6ac36d32f16f/docs/profile-execution/EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975_semantic_judge_v3.json',
    v_execution_id
  );

  IF v_result->>'status' IS DISTINCT FROM 'SEMANTIC_JUDGE_RECORDED'
     OR coalesce((v_result->>'clean_step_count')::integer,0) <> 10
     OR v_result->>'next_step' IS DISTINCT FROM 'report_output' THEN
    RAISE EXCEPTION 'PROFILE_STEP70_RECORD_FAILED:%', v_result;
  END IF;

  SELECT status INTO v_status
  FROM public.lf_operation_execution_steps
  WHERE execution_id=v_execution_id
    AND step_id='semantic_judge';

  IF v_status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
    RAISE EXCEPTION 'PROFILE_STEP70_READBACK_FAILED:%', coalesce(v_status,'<missing>');
  END IF;

  SELECT count(*) INTO v_report_count
  FROM public.lf_operation_execution_steps
  WHERE execution_id=v_execution_id
    AND step_id='report_output';

  IF v_report_count <> 0 THEN
    RAISE EXCEPTION 'PROFILE_STEP80_PREMATURELY_PRESENT:%', v_report_count;
  END IF;
END
$step70$;
