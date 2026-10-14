-- A3Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier.
-- Evidence: raw output SHA-256 30150806da0208b9e9e3caad77878e7faa930fc6b7293ef7ee0e82782ea29e0a; every value asserted below is recomputed from the stored capture.
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision document).
BEGIN;
DO $a3q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '31f91c187a95d6d09e279c5fa78ae66e70a911e3f4ef85bd6c25435ddf0b97ea';
 v_raw_text text := $raw${
  "schema_version": "A3_TARGETED_EVIDENCE_OUTPUT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "evidence_items": [
    {
      "source_ref": "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
      "read_status": "READ",
      "observed_fields": {
        "packet_sha256": "1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a",
        "request_sha256": "a136daa7486437dc62b8757993b5213b3b6b2575bb32cb08e2a5217c84df3071",
        "input_sha256": "a1974eae630ef1eea450e6bd95248a73da785257de73b06e13fb727190e76987"
      },
      "currentness_basis": "READ_IN_THIS_RUN"
    },
    {
      "source_ref": "supabase://public.lf_eventos/20843",
      "read_status": "READ",
      "observed_fields": {
        "evento_tipo": "HANDOFF_DEEP_CONTEXT",
        "created_by_execution_id": "ANALYSIS_QUAL_C2_GPT_HANDOFF_V1|A1Q_C2",
        "payload_packet_sha256": "1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a"
      },
      "currentness_basis": "READ_IN_THIS_RUN"
    }
  ],
  "source_refs": [
    "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
    "supabase://public.lf_eventos/20843"
  ],
  "currentness_refs": [
    "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
    "supabase://public.lf_eventos/20843"
  ],
  "target_granularity": "Capacidad funcional de comunicación y comprensión del ahorro en la negociación de deuda, antes de aceptar una oferta. Pantalla, canal, segmento y alcance exactos no identificados.",
  "authority_state": "UNKNOWN",
  "implementation_state": "UNKNOWN",
  "target_resolution": {
    "authority_state": "UNKNOWN",
    "implementation_state": "UNKNOWN",
    "resolved": false,
    "reason": "Las dos fuentes fueron leídas y los hashes de paquete coinciden exactamente. Sin embargo, ambas describen el paquete de entrada y su evento de traspaso, no la autoridad funcional ni la implementación del objetivo. No existe evidencia suministrada que permita identificar el objeto funcional exacto, su autoridad vigente, su implementación actual o su inexistencia."
  },
  "authority_binding_refs": [],
  "as_is_baseline_or_new_implementation_evidence": {
    "kind": "NONE_SUPPLIED",
    "refs": []
  },
  "unresolved_material_gaps": [
    {
      "gap_code": "TARGET_IDENTITY_UNRESOLVED",
      "statement": "No se identifica la capacidad funcional canónica, pantalla, canal o segmento exacto afectado por la solicitud."
    },
    {
      "gap_code": "TARGET_AUTHORITY_NOT_SUPPLIED",
      "statement": "No se suministran reglas, contratos o decisiones vigentes que acrediten la autoridad funcional aplicable a la comunicación del ahorro."
    },
    {
      "gap_code": "IMPLEMENTATION_STATE_UNVERIFIED",
      "statement": "No se aporta evidencia que demuestre si la funcionalidad existe actualmente o si se trata de una implementación nueva."
    },
    {
      "gap_code": "AS_IS_BASELINE_MISSING",
      "statement": "No existe una línea base verificable del comportamiento actual ni evidencia que permita identificar el cambio respecto de ese comportamiento."
    },
    {
      "gap_code": "SAVINGS_SEMANTICS_UNRESOLVED",
      "statement": "No se define el significado del ahorro, su importe de comparación ni las condiciones bajo las cuales puede comunicarse."
    },
    {
      "gap_code": "OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED",
      "statement": "No está acreditado el estado de la oferta ni el momento exacto anterior a la aceptación en el que corresponde informar el ahorro."
    },
    {
      "gap_code": "INSTALLMENT_DISTINCTION_UNRESOLVED",
      "statement": "No se dispone de una definición autorizada del monto de la cuota ni de su relación con el ahorro."
    },
    {
      "gap_code": "ACCEPTANCE_EVIDENCE_MISSING",
      "statement": "No se aportan criterios verificables que permitan determinar si los clientes comprenden la diferencia entre ahorro y cuota."
    }
  ],
  "sufficiency_verdict": "NEED_MORE_EVIDENCE",
  "stop_reason": "Se completó la investigación mínima autorizada: dos fuentes consultadas, dos lecturas satisfactorias y coincidencia exacta entre packet_sha256 y payload_packet_sha256. READ_IN_THIS_RUN acredita la consulta de esas fuentes, no la vigencia de la autoridad del objetivo. Ambas fuentes documentan el traspaso del pipeline de análisis y no resuelven las ocho brechas materiales identificadas. No corresponde declarar SUFFICIENT, inferir una solución técnica ni fabricar una línea base AS-IS. Se detiene la investigación al alcanzar el límite de las dos fuentes suministradas."
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (12479 bytes, after the A3Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"373dc4fc199831abaa862a81e172abb01a3e4a8ef532ea8f9e4efba9769b2ee0","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"e35bee22e553786d96110a89bc559a19577e066e904b627d80cd45458f9fdf28","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"30150806da0208b9e9e3caad77878e7faa930fc6b7293ef7ee0e82782ea29e0a","request_sha256":"aa729c4210c35ed03a6dbed15822a4eaa15930a5eb905657110532aae8a56a93","run_id":"A3Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A3","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A3Q/A3Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a3q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;
 IF NOT (v_raw->>'schema_version'='A3_TARGETED_EVIDENCE_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND jsonb_array_length(v_raw->'evidence_items')=2 AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'evidence_items') e WHERE e->>'read_status'<>'READ' OR e->>'currentness_basis'<>'READ_IN_THIS_RUN') AND v_raw->>'sufficiency_verdict'<>'SUFFICIENT' AND v_raw->>'authority_state'='UNKNOWN' AND v_raw->>'implementation_state'='UNKNOWN' AND v_raw#>>'{as_is_baseline_or_new_implementation_evidence,kind}'='NONE_SUPPLIED' AND jsonb_array_length(v_raw->'unresolved_material_gaps')>=1 AND (SELECT e#>>'{observed_fields,packet_sha256}' FROM jsonb_array_elements(v_raw->'evidence_items') e WHERE e->>'source_ref'='supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2') IS NOT DISTINCT FROM (SELECT u.unit_metadata#>>'{gpt_native_packets_v1,A1Q_C2,packet_sha256}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A1Q') AND (SELECT e#>>'{observed_fields,payload_packet_sha256}' FROM jsonb_array_elements(v_raw->'evidence_items') e WHERE e->>'source_ref'='supabase://public.lf_eventos/20843') IS NOT DISTINCT FROM (SELECT ev.payload->>'packet_sha256' FROM public.lf_eventos ev WHERE ev.id=20843 AND ev.evento_tipo='HANDOFF_DEEP_CONTEXT')) THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1113 AND checkpoint_code='A3Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A3Q' AND work_item_id=1113 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A3Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A3Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A3Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A3Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1113;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A3Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A3Q' AND work_item_id=1113;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A3Q' AND work_item_id=1113;
 IF v_m#>'{gpt_native_captures_v1,A3Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1113;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a3q_c2_cap$;
-- A3Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
DO $a3q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A3Q';
 v_cp constant text := 'A3Q_C2';
 v_wi constant bigint := 1113;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a3q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_packet_sha constant text := '31f91c187a95d6d09e279c5fa78ae66e70a911e3f4ef85bd6c25435ddf0b97ea';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1113 and checkpoint_code=''A3Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A3Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A3Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A3Q/A3Q_C2'
 THEN RAISE EXCEPTION 'A3Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A3Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A3Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A3Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A3Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A3Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=jsonb_array_length(v_raw->'unresolved_material_gaps');
 IF NOT (v_raw->>'schema_version'='A3_TARGETED_EVIDENCE_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND jsonb_array_length(v_raw->'evidence_items')=2 AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'evidence_items') e WHERE e->>'read_status'<>'READ' OR e->>'currentness_basis'<>'READ_IN_THIS_RUN') AND v_raw->>'sufficiency_verdict'<>'SUFFICIENT' AND v_raw->>'authority_state'='UNKNOWN' AND v_raw->>'implementation_state'='UNKNOWN' AND v_raw#>>'{as_is_baseline_or_new_implementation_evidence,kind}'='NONE_SUPPLIED' AND jsonb_array_length(v_raw->'unresolved_material_gaps')>=1 AND (SELECT e#>>'{observed_fields,packet_sha256}' FROM jsonb_array_elements(v_raw->'evidence_items') e WHERE e->>'source_ref'='supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2') IS NOT DISTINCT FROM (SELECT u.unit_metadata#>>'{gpt_native_packets_v1,A1Q_C2,packet_sha256}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A1Q') AND (SELECT e#>>'{observed_fields,payload_packet_sha256}' FROM jsonb_array_elements(v_raw->'evidence_items') e WHERE e->>'source_ref'='supabase://public.lf_eventos/20843') IS NOT DISTINCT FROM (SELECT ev.payload->>'packet_sha256' FROM public.lf_eventos ev WHERE ev.id=20843 AND ev.evento_tipo='HANDOFF_DEEP_CONTEXT'))
 THEN RAISE EXCEPTION 'A3Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A3Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_pass:=jsonb_build_object('capture_verified',true,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A3 stage output under the owner-approved equivalent tier and bind its result',
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
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A3Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A3Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A3Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A3Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A3Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A3Q#unit_metadata.gpt_native_captures_v1.A3Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A3Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A3Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','sufficiency_verdict',v_raw->>'sufficiency_verdict','unresolved_material_gaps',v_open,'live_reads_match_supabase',true,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A3Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A3Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier; hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A3Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A3Q_C1:DONE,A3Q_C2:DONE,A3Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A3Q_C2_POSTSTATE_FAILED'; END IF;
END $a3q_c2_close$;
COMMIT;
