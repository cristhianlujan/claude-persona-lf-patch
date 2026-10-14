-- A2Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier.
-- Evidence: raw output SHA-256 381a76bccf5e26696460897a68a87b1960ad6882c065b0c171953334d54ebcde; every value asserted below is recomputed from the stored capture.
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision document).
BEGIN;
DO $a2q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := 'a34a7f990b9363d7c38a67eea63a9582f71d1584611d98ee3c0cc620b0b696c7';
 v_raw_text text := $raw${
  "schema_version": "A2_CLASSIFICATION_OUTPUT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "classification": {
    "target_granularity": "Capacidad funcional de comunicación y comprensión del ahorro en la negociación de deuda, antes de aceptar una oferta. Pantalla, canal, segmento y alcance exactos no identificados.",
    "change_type": "Cambio funcional orientado a claridad de información económica previa a la aceptación de una oferta. No se determina si corresponde modificar una capacidad existente o introducir una nueva.",
    "depth": "L3",
    "authority_state": "UNKNOWN",
    "implementation_state": "UNKNOWN"
  },
  "signals": {
    "materiality_level": "HIGH",
    "scope_bounded": "UNKNOWN",
    "authority_state": "UNKNOWN",
    "reversibility_state": "UNKNOWN",
    "currentness_decision": "UNKNOWN_FAIL_CLOSED",
    "material_contradiction": false,
    "known_cross_scope_impact": "UNKNOWN",
    "unresolved_material_signal_count": 5,
    "required_specialist_count": 0
  },
  "signal_sources": [
    {
      "signal": "materiality_level",
      "source_ref": "ambiguity:SAVINGS_MEANING_AND_BASIS"
    },
    {
      "signal": "scope_bounded",
      "source_ref": "ambiguity:CLIENT_CHANNEL_AND_SCOPE"
    },
    {
      "signal": "authority_state",
      "source_ref": "NO_SOURCE_SUPPLIED"
    },
    {
      "signal": "reversibility_state",
      "source_ref": "NO_SOURCE_SUPPLIED"
    },
    {
      "signal": "currentness_decision",
      "source_ref": "NO_SOURCE_SUPPLIED"
    },
    {
      "signal": "material_contradiction",
      "source_ref": "supabase://public.lf_eventos/20843"
    },
    {
      "signal": "known_cross_scope_impact",
      "source_ref": "ambiguity:CLIENT_CHANNEL_AND_SCOPE"
    },
    {
      "signal": "unresolved_material_signal_count",
      "source_ref": "supabase://public.lf_eventos/20843"
    },
    {
      "signal": "required_specialist_count",
      "source_ref": "NO_SOURCE_SUPPLIED"
    }
  ],
  "depth_reason": "L3 por materialidad HIGH: la solicitud afecta la comprensión de importes económicos antes de aceptar una oferta de negociación de deuda. La definición del ahorro y su base de comparación son materialmente desconocidas, al igual que el significado de la cuota, el límite entre oferta y aceptación, el alcance del piloto y el criterio de comprensión. Existen cinco ambigüedades explícitamente clasificadas MATERIAL y OPEN. No se observa una contradicción factual explícita, pero tampoco existe evidencia suficiente para determinar alcance entre procesos, autoridad vigente, implementación existente, reversibilidad o actualidad de las fuentes. La cantidad 0 de especialistas refleja únicamente que ninguno está identificado expresamente en el contexto, no que se haya demostrado que no son necesarios. La regla de precedencia exige L3 por materialidad HIGH, independientemente de las demás señales. No se infiere una solución técnica.",
  "evidence_refs": [
    "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2.input.input_literal",
    "supabase://public.lf_eventos/20843",
    "ambiguity:SAVINGS_MEANING_AND_BASIS",
    "ambiguity:OFFER_AND_ACCEPTANCE_BOUNDARY",
    "ambiguity:CLIENT_CHANNEL_AND_SCOPE",
    "ambiguity:INSTALLMENT_MEANING",
    "ambiguity:COMPREHENSION_CRITERION"
  ]
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (6543 bytes, after the A2Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"69298175b961e043b541034553f7edd71b807fc29d954d12a05dd7b480ff6d38","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"02420a0ebbc3416193b788a95895966837db15cd2d934b7691924ade94303fce","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"381a76bccf5e26696460897a68a87b1960ad6882c065b0c171953334d54ebcde","request_sha256":"ba264f710396a97ae48b345a46789df1dcb06e8180f2ac12c04d4be2eb4ebb5a","run_id":"A2Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A2","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A2Q/A2Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a2q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;
 IF NOT (v_raw->>'schema_version'='A2_CLASSIFICATION_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw#>>'{classification,depth}' IN ('L2','L3') AND v_raw#>>'{classification,authority_state}'='UNKNOWN' AND v_raw#>>'{classification,implementation_state}'='UNKNOWN' AND (v_raw#>>'{signals,unresolved_material_signal_count}')::int>=1 AND jsonb_array_length(v_raw->'signal_sources')=9 AND jsonb_array_length(v_raw->'evidence_refs')>=1) THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1112 AND checkpoint_code='A2Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A2Q' AND work_item_id=1112 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A2Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A2Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A2Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A2Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1112;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A2Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A2Q' AND work_item_id=1112;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A2Q' AND work_item_id=1112;
 IF v_m#>'{gpt_native_captures_v1,A2Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1112;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a2q_c2_cap$;
-- A2Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
DO $a2q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A2Q';
 v_cp constant text := 'A2Q_C2';
 v_wi constant bigint := 1112;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a2q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_packet_sha constant text := 'a34a7f990b9363d7c38a67eea63a9582f71d1584611d98ee3c0cc620b0b696c7';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1112 and checkpoint_code=''A2Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A2Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A2Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A2Q/A2Q_C2'
 THEN RAISE EXCEPTION 'A2Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A2Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A2Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A2Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A2Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A2Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=(v_raw#>>'{signals,unresolved_material_signal_count}')::int;
 IF NOT (v_raw->>'schema_version'='A2_CLASSIFICATION_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw#>>'{classification,depth}' IN ('L2','L3') AND v_raw#>>'{classification,authority_state}'='UNKNOWN' AND v_raw#>>'{classification,implementation_state}'='UNKNOWN' AND (v_raw#>>'{signals,unresolved_material_signal_count}')::int>=1 AND jsonb_array_length(v_raw->'signal_sources')=9 AND jsonb_array_length(v_raw->'evidence_refs')>=1)
 THEN RAISE EXCEPTION 'A2Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A2Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_pass:=jsonb_build_object('capture_verified',true,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A2 stage output under the owner-approved equivalent tier and bind its result',
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
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A2Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A2Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A2Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A2Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A2Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A2Q#unit_metadata.gpt_native_captures_v1.A2Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A2Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A2Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','depth',v_raw#>>'{classification,depth}','unresolved_material_signal_count',v_open,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A2Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A2Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier; hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A2Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A2Q_C1:DONE,A2Q_C2:DONE,A2Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A2Q_C2_POSTSTATE_FAILED'; END IF;
END $a2q_c2_close$;
COMMIT;
