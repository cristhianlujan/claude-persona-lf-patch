-- Stores the verified GPT Native capture for A1Q_C2 in unit_metadata (data only).
-- Does NOT change action specs, checkpoint status or assertions. The spec still requires REAL_EXECUTION_RECEIPT;
-- whether this tier may satisfy it is an owner decision that is not taken here. A1Q_C2 stays PENDING.
BEGIN;
DO $a1q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a';
 v_raw text := $raw${
  "schema_version": "REQUEST_CONTEXT_V1",
  "request_identity": {
    "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
    "request_kind": "USER_REQUEST"
  },
  "objective": {
    "problem_statement": "Según la solicitud, los clientes del marketplace no comprenden cuánto les ahorra negociar su deuda antes de aceptar una oferta y abandonan.",
    "desired_outcome": "Que los clientes comprendan cuánto les ahorra negociar su deuda antes de aceptar una oferta, sin confundir ese ahorro con el monto de la cuota, para el piloto."
  },
  "target_hints": [
    "clientes del marketplace",
    "negociación de deuda",
    "ahorro",
    "oferta antes de la aceptación",
    "monto de la cuota"
  ],
  "source_refs": [
    "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2.input.input_literal",
    "supabase://public.lf_eventos/20843"
  ],
  "provided_facts": [
    {
      "fact_code": "USER_REPORTED_LACK_OF_COMPREHENSION",
      "value": "La solicitud afirma que hoy los clientes no comprenden cuánto ahorran al negociar su deuda.",
      "source_ref": "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2.input.input_literal"
    },
    {
      "fact_code": "USER_REPORTED_ABANDONMENT",
      "value": "La solicitud afirma que los clientes abandonan; no aporta cifras ni evidencia cuantitativa.",
      "source_ref": "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2.input.input_literal"
    },
    {
      "fact_code": "USER_STATED_PILOT_URGENCY",
      "value": "La solicitud indica que el requerimiento es urgente para el piloto.",
      "source_ref": "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2.input.input_literal"
    }
  ],
  "constraints": [
    "El ahorro debe poder conocerse antes de aceptar una oferta.",
    "La información del ahorro no debe confundirse con el monto de la cuota.",
    "La necesidad se declara urgente para el piloto; no se proporciona fecha límite."
  ],
  "ambiguities": [
    {
      "code": "SAVINGS_MEANING_AND_BASIS",
      "statement": "No se define qué significa 'ahorro', respecto de qué importe se compara ni cómo se determina.",
      "materiality": "MATERIAL",
      "resolution_state": "OPEN"
    },
    {
      "code": "OFFER_AND_ACCEPTANCE_BOUNDARY",
      "statement": "No se especifica en qué momento de la negociación existe una oferta que el cliente puede aceptar.",
      "materiality": "MATERIAL",
      "resolution_state": "OPEN"
    },
    {
      "code": "CLIENT_CHANNEL_AND_SCOPE",
      "statement": "No se indican los canales, pantallas o segmentos de clientes del marketplace incluidos en el piloto.",
      "materiality": "MATERIAL",
      "resolution_state": "OPEN"
    },
    {
      "code": "INSTALLMENT_MEANING",
      "statement": "No se define qué representa el monto de la cuota ni en qué situaciones corresponde distinguirlo del ahorro.",
      "materiality": "MATERIAL",
      "resolution_state": "OPEN"
    },
    {
      "code": "ABANDONMENT_EVIDENCE",
      "statement": "No se aportan mediciones, causas verificadas ni alcance del abandono mencionado.",
      "materiality": "UNKNOWN",
      "resolution_state": "OPEN"
    },
    {
      "code": "COMPREHENSION_CRITERION",
      "statement": "No se define cómo se determinará que la diferencia entre ahorro y cuota resulta clara para el cliente.",
      "materiality": "MATERIAL",
      "resolution_state": "OPEN"
    },
    {
      "code": "PILOT_DEADLINE",
      "statement": "Se indica urgencia, pero no una fecha o hito preciso del piloto.",
      "materiality": "UNKNOWN",
      "resolution_state": "OPEN"
    }
  ],
  "no_solution_inferred": true
}
$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser; the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"707423ea3912f06ba78bca869b13251957d37c57698c202cfeb9e8932a7c7de1","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"a1974eae630ef1eea450e6bd95248a73da785257de73b06e13fb727190e76987","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"02420a0ebbc3416193b788a95895966837db15cd2d934b7691924ade94303fce","request_sha256":"a136daa7486437dc62b8757993b5213b3b6b2575bb32cb08e2a5217c84df3071","run_id":"A1Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A1","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A1Q/A1Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a1q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text; v_out jsonb;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw);
 IF encode(sha256(convert_to(v_raw,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_out := v_raw::jsonb;
 IF v_out#>>'{request_identity,request_ref}' <> 'REQ-LF-A1Q-C2-PILOT-0001' OR (v_out->>'no_solution_inferred')::boolean IS NOT TRUE
    OR (SELECT count(*) FROM jsonb_array_elements(v_out->'ambiguities') a WHERE a->>'resolution_state'='OPEN') < 3
  THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1111 AND checkpoint_code='A1Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A1Q' AND work_item_id=1111 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A1Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A1Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A1Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A1Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1111;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A1Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A1Q' AND work_item_id=1111;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A1Q' AND work_item_id=1111;
 IF v_m#>'{gpt_native_captures_v1,A1Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1111;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A1Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a1q_c2_cap$;
COMMIT;
