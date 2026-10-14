-- Stores the frozen A1Q_C2 GPT Native packet in unit_metadata (data only).
-- It does NOT change action specs, checkpoint status or any assertion. C2 stays PENDING until a real
-- GPT Native capture is verified. Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
BEGIN;
DO $a1q_c2_pkt$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A1Q';
 v_cp constant text := 'A1Q_C2';
 v_wi constant bigint := 1111;
 v_packet_sha constant text := '1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a';
 v_packet jsonb := $pkt${"checkpoint":"C2","deterministic_checks":{"forbidden_solution_patterns":["\\bredis\\b","\\bkafka\\b","\\bpostgres\\w*","\\breact\\b","\\bsql\\b","\\bapi\\b","\\bendpoint\\b","\\btrigger\\b","\\bmigraci\\w+","\\bmicroservic\\w+","\\brpc\\b","\\bedge function\\b","\\btabla\\b","\\bbase de datos\\b","\\bcomponente\\b"],"min_open_ambiguities":3,"no_solution_inferred_true":true,"request_ref_equals":"REQ-LF-A1Q-C2-PILOT-0001"},"evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input":{"input_literal":"Los clientes del marketplace deberían poder ver cuánto les ahorra negociar su deuda antes de aceptar una oferta. Hoy no lo entienden y abandonan. Que quede claro y que no se confunda con el monto de la cuota. Es urgente para el piloto.","input_sha256":"a1974eae630ef1eea450e6bd95248a73da785257de73b06e13fb727190e76987","request_ref":"REQ-LF-A1Q-C2-PILOT-0001"},"limits":{"checkpoint_transition":false,"db_write":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false,"transcript_is_provider_evidence":false},"output_contract":{"required_keys":["schema_version","request_identity","objective","target_hints","source_refs","provided_facts","constraints","ambiguities","no_solution_inferred"],"schema":"REQUEST_CONTEXT_V1","validator":"validate_wave1_boundary_contracts_v1.py::validate_request_context"},"owner_approval_doc":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md","packet_sha256":"1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a","producer_mode":"GPT_NATIVE","profile_source":{"ref":"profiles/programming_analysis_lf/SKILL.md","sha256":"91a7b47c3d84f1d5aea48f3fd475134d9c56c718461d1b649c4a89d53980508f"},"prompt_for_gpt":"Eres el productor de la etapa A1 (normalización) del perfil de análisis. Normaliza la solicitud literal de abajo. No infieras ninguna solución técnica ni identidad de historia. Conserva como ambigüedad todo lo que la solicitud no define. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: schema_version, request_identity, objective, target_hints, source_refs, provided_facts, constraints, ambiguities, no_solution_inferred. schema_version='REQUEST_CONTEXT_V1'. request_identity={request_ref (usa 'REQ-LF-A1Q-C2-PILOT-0001'), request_kind (USER_REQUEST|SYSTEM_REQUEST|ISSUE|HANDOFF|FILE|EVENT|OTHER)}. objective={problem_statement, desired_outcome} (textos no vacíos). ambigüedades: lista de {code, statement, materiality (MATERIAL|NON_MATERIAL|UNKNOWN), resolution_state (OPEN|RESOLVED_FROM_SOURCE)}. no_solution_inferred=true.\n\nSOLICITUD LITERAL:\nLos clientes del marketplace deberían poder ver cuánto les ahorra negociar su deuda antes de aceptar una oferta. Hoy no lo entienden y abandonan. Que quede claro y que no se confunda con el monto de la cuota. Es urgente para el piloto.","request_sha256":"a136daa7486437dc62b8757993b5213b3b6b2575bb32cb08e2a5217c84df3071","run_id":"A1Q_C2-GPTN-PILOT-0001","schema":"ANALYSIS_GPT_NATIVE_PACKET_V1","stage_output_selector":"A1","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A1Q/A1Q_C2","unit":"A1"}$pkt$::jsonb;
 v_m jsonb; v_before_specs jsonb; v_before_cps text; v_after_cps text; v_stored jsonb;
BEGIN
 IF v_packet->>'packet_sha256' IS DISTINCT FROM v_packet_sha OR v_packet->>'subject_ref' <> v_plan||'/A1Q/A1Q_C2'
  THEN RAISE EXCEPTION 'A1Q_C2_PACKET_IDENTITY'; END IF;
 IF encode(sha256(convert_to(v_packet#>>'{input,input_literal}','UTF8')),'hex') <> v_packet#>>'{input,input_sha256}'
  THEN RAISE EXCEPTION 'A1Q_C2_INPUT_SHA_MISMATCH'; END IF;
 IF (v_packet#>>'{limits,provider_attested}')::boolean IS NOT FALSE OR (v_packet#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
  THEN RAISE EXCEPTION 'A1Q_C2_LIMITS_NOT_FALSE'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A1Q_C2_NOT_PENDING'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_before_cps
  FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 IF v_m IS NULL THEN RAISE EXCEPTION 'A1Q_UNIT_NOT_FOUND'; END IF;
 IF v_m#>'{gpt_native_packets_v1,A1Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_packets_v1,A1Q_C2,packet_sha256}' <> v_packet_sha
  THEN RAISE EXCEPTION 'A1Q_C2_PACKET_DIFFERENT_ALREADY_STORED'; END IF;
 v_before_specs := v_m->'action_specs_v1';
 UPDATE programacion.engineering_plan_units
    SET unit_metadata = v_m || jsonb_build_object('gpt_native_packets_v1',
        COALESCE(v_m->'gpt_native_packets_v1','{}'::jsonb) || jsonb_build_object('A1Q_C2',v_packet))
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;
 v_stored := v_m#>'{gpt_native_packets_v1,A1Q_C2}';
 IF v_stored IS DISTINCT FROM v_packet THEN RAISE EXCEPTION 'A1Q_C2_PACKET_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_before_specs THEN RAISE EXCEPTION 'A1Q_C2_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_after_cps
  FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi;
 IF v_after_cps IS DISTINCT FROM v_before_cps THEN RAISE EXCEPTION 'A1Q_C2_CHECKPOINTS_CHANGED'; END IF;
END
$a1q_c2_pkt$;
COMMIT;
