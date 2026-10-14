-- A8Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier.
-- Evidence: raw output SHA-256 2fee538e7c6228fbd19d7ce5a01b88decd3afec213bb63170d52715fc7b09d30; every value asserted below is recomputed from the stored capture.
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision document).
BEGIN;
DO $a8q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '967dd1e0ef2274dc8d7dae8536816ca4d309a98ce81773b481e64b1356ff1213';
 v_raw_text text := $raw${
  "schema_version": "A8_RESEARCH_DECISION_OUTPUT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "research_decision": "REQUIRES_DECISION",
  "stop_criteria": {
    "decision_stable": false,
    "front_accounting_complete": true,
    "decision_changing_questions_open": true
  },
  "front_trace": [
    {
      "front_id": "A7-FRONT-001",
      "blockers": [
        "A5-DEC-001",
        "A5-DEC-003"
      ],
      "effect_on_decision": "BLOCKED. El alcance funcional del piloto, los destinatarios, los permisos aplicables y las condiciones previas a la aceptación no están determinados. Estas definiciones pueden modificar el alcance y los requisitos, por lo que impiden estabilizar la decisión de investigación."
    },
    {
      "front_id": "A7-FRONT-002",
      "blockers": [
        "A5-DEC-002",
        "A5-DEC-004"
      ],
      "effect_on_decision": "BLOCKED. La definición del ahorro, su base de comparación y su distinción respecto de la cuota carecen de autoridad confirmada. Resolver estas cuestiones puede cambiar materialmente los requisitos económicos y funcionales."
    },
    {
      "front_id": "A7-FRONT-003",
      "blockers": [
        "A5-DEC-003"
      ],
      "effect_on_decision": "BLOCKED. No están acreditados los estados de la oferta ni las condiciones que permiten comunicar el ahorro antes de aceptar. Esta incertidumbre impide establecer límites funcionales estables."
    },
    {
      "front_id": "A7-FRONT-004",
      "blockers": [
        "A5-DEC-002",
        "A5-DEC-003",
        "A5-DEC-004"
      ],
      "effect_on_decision": "BLOCKED. No existe evidencia suficiente para determinar los comportamientos ante información económica indeterminada, no disponible o incompatible con la oferta, ni sus posibles efectos colaterales. No pueden establecerse obligaciones definitivas ni descartarse impactos."
    },
    {
      "front_id": "A7-FRONT-005",
      "blockers": [
        "A5-DEC-004",
        "A5-DEC-005"
      ],
      "effect_on_decision": "BLOCKED. Los criterios para comprobar que el cliente comprende el ahorro y lo distingue de la cuota siguen pendientes. Sin criterios autorizados, no puede establecerse una condición verificable de aceptación."
    }
  ],
  "owner_decisions_required": [
    "A5-DEC-001",
    "A5-DEC-002",
    "A5-DEC-003",
    "A5-DEC-004",
    "A5-DEC-005"
  ],
  "evidence_refs": [
    "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
    "supabase://public.lf_eventos/20843",
    "gap:TARGET_AUTHORITY_NOT_SUPPLIED",
    "gap:SAVINGS_SEMANTICS_UNRESOLVED",
    "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED",
    "gap:INSTALLMENT_DISTINCTION_UNRESOLVED",
    "gap:ACCEPTANCE_EVIDENCE_MISSING",
    "A6-REQ-001",
    "A6-REQ-002",
    "A6-REQ-003",
    "A6-REQ-004",
    "A6-REQ-005",
    "dimension:functional",
    "dimension:data",
    "dimension:permissions",
    "dimension:state",
    "dimension:errors",
    "dimension:side_effects",
    "decision:A5-DEC-001",
    "decision:A5-DEC-002",
    "decision:A5-DEC-003",
    "decision:A5-DEC-004",
    "decision:A5-DEC-005",
    "front:A7-FRONT-001",
    "front:A7-FRONT-002",
    "front:A7-FRONT-003",
    "front:A7-FRONT-004",
    "front:A7-FRONT-005"
  ],
  "no_ready_claim": true,
  "decision_statement": "La investigación no puede detenerse con STOP. La contabilidad de los elementos suministrados por A6 está completa dentro del alcance documentado: cinco requisitos y seis dimensiones están vinculados a cinco frentes materiales. Sin embargo, los cinco frentes permanecen BLOCKED, la decisión no es estable y existen preguntas materiales abiertas capaces de modificar el resultado. Se selecciona REQUIRES_DECISION porque los cinco identificadores A5 pendientes afectan al menos un frente y requieren resolución mediante autoridad legítima. Esta clasificación no implica que deban generarse cinco nuevas aprobaciones humanas: primero corresponde verificar si existen reglas o decisiones vigentes que resuelvan las cuestiones; solo las alternativas materiales todavía no resueltas deben elevarse al propietario. También faltan evidencia de autoridad actual, identificación de implementación y línea base AS-IS. La cobertura completa de la entrada no demuestra cobertura completa del sistema real. No se han aprobado decisiones, declarado READY, cerrado frentes, inferido soluciones técnicas ni autorizado la implementación."
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (27034 bytes, after the A8Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"0cf6a2a57184774e0ba093b0dec28fdaa1c2c68c9355561d736f0f297fec8591","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"6ff3b7e34aaeaf95ecfca1b21376b7b313140eee2b538251cdea0da110094ed7","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"2fee538e7c6228fbd19d7ce5a01b88decd3afec213bb63170d52715fc7b09d30","request_sha256":"4b27dc75b21f17f5fc86ee7816cf773f1ddd7bc44979e0c08a4c2b55f8fb8bbb","run_id":"A8Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A8","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A8Q/A8Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a8q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;
 IF NOT (v_raw->>'schema_version'='A8_RESEARCH_DECISION_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND v_raw->>'research_decision' IN ('CONTINUE','REQUIRES_DECISION','BLOCKED') AND v_raw#>>'{stop_criteria,decision_stable}'='false' AND v_raw#>>'{stop_criteria,decision_changing_questions_open}'='true' AND (SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_sha256}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')='6bbeadcc8ac1c69d239aec02af75d6a0e153a745c1954703e6c4811c001173fa' AND jsonb_array_length(v_raw->'front_trace')=jsonb_array_length(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'front_trace') t WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') f WHERE f->>'front_id'=t->>'front_id' AND (SELECT jsonb_agg(x ORDER BY x) FROM jsonb_array_elements_text(f->'blockers') x) = (SELECT jsonb_agg(x ORDER BY x) FROM jsonb_array_elements_text(t->'blockers') x))) AND (SELECT count(DISTINCT t->>'front_id') FROM jsonb_array_elements(v_raw->'front_trace') t)=jsonb_array_length(v_raw->'front_trace') AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') f, jsonb_array_elements_text(f->'blockers') b WHERE NOT (v_raw->'owner_decisions_required') ? b) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_raw->'owner_decisions_required') d WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') f, jsonb_array_elements_text(f->'blockers') b WHERE b=d))) THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1118 AND checkpoint_code='A8Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A8Q' AND work_item_id=1118 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A8Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A8Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A8Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A8Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1118;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A8Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A8Q' AND work_item_id=1118;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A8Q' AND work_item_id=1118;
 IF v_m#>'{gpt_native_captures_v1,A8Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1118;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a8q_c2_cap$;
-- A8Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
DO $a8q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A8Q';
 v_cp constant text := 'A8Q_C2';
 v_wi constant bigint := 1118;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a8q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_packet_sha constant text := '967dd1e0ef2274dc8d7dae8536816ca4d309a98ce81773b481e64b1356ff1213';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1118 and checkpoint_code=''A8Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A8Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A8Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A8Q/A8Q_C2'
 THEN RAISE EXCEPTION 'A8Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A8Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A8Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A8Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A8Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A8Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=jsonb_array_length(v_raw->'front_trace');
 IF NOT (v_raw->>'schema_version'='A8_RESEARCH_DECISION_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND v_raw->>'research_decision' IN ('CONTINUE','REQUIRES_DECISION','BLOCKED') AND v_raw#>>'{stop_criteria,decision_stable}'='false' AND v_raw#>>'{stop_criteria,decision_changing_questions_open}'='true' AND (SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_sha256}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')='6bbeadcc8ac1c69d239aec02af75d6a0e153a745c1954703e6c4811c001173fa' AND jsonb_array_length(v_raw->'front_trace')=jsonb_array_length(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'front_trace') t WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') f WHERE f->>'front_id'=t->>'front_id' AND (SELECT jsonb_agg(x ORDER BY x) FROM jsonb_array_elements_text(f->'blockers') x) = (SELECT jsonb_agg(x ORDER BY x) FROM jsonb_array_elements_text(t->'blockers') x))) AND (SELECT count(DISTINCT t->>'front_id') FROM jsonb_array_elements(v_raw->'front_trace') t)=jsonb_array_length(v_raw->'front_trace') AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') f, jsonb_array_elements_text(f->'blockers') b WHERE NOT (v_raw->'owner_decisions_required') ? b) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_raw->'owner_decisions_required') d WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(((SELECT u7.unit_metadata#>>'{gpt_native_captures_v1,A7Q_C2,raw_output_text}' FROM programacion.engineering_plan_units u7 WHERE u7.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u7.unit_code='A7Q')::jsonb)->'material_fronts') f, jsonb_array_elements_text(f->'blockers') b WHERE b=d)))
 THEN RAISE EXCEPTION 'A8Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A8Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_pass:=jsonb_build_object('capture_verified',true,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A8 stage output under the owner-approved equivalent tier and bind its result',
  'expected_evidence_class',v_tier,
  'tier_acceptance',jsonb_build_object('tier',v_tier,'decision_ref',v_decision_doc||'@'||v_decision_sha,
    'replaces_expected_evidence_class','REAL_EXECUTION_RECEIPT','scope','C2_ONLY',
    'limits',jsonb_build_object('provider_attested',false,'real_execution_receipt',false,'independent_review',false)),
  'target',jsonb_build_object('declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_artifacts',jsonb_build_array(v_art),'evidence_artifacts','[]'::jsonb,
    'mutation_artifacts',jsonb_build_array(v_art)),
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',v_pass),
  'verification_queries',jsonb_build_array(v_vq),
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A8Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A8Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A8Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A8Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A8Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A8Q#unit_metadata.gpt_native_captures_v1.A8Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A8Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A8Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','fronts_traced',v_open,'stop_forbidden',true,'research_decision',v_raw->>'research_decision','linked_to_stored_a7_fronts',true,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A8Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A8Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier; hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A8Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A8Q_C1:DONE,A8Q_C2:DONE,A8Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A8Q_C2_POSTSTATE_FAILED'; END IF;
END $a8q_c2_close$;
COMMIT;
