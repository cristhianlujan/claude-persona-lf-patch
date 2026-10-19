-- A12Q_C3: stores the verified GPT Native blind-review capture (data) and closes the checkpoint under the owner-accepted C3 tier.
-- Evidence: review raw SHA-256 c3524bf34a751541a4c39fa97d702af23451c8d8372903362580373c2ba7d8fd; every value asserted is recomputed in SQL from the stored capture, the stored blinded packet and the stored C2 capture.
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision document).
BEGIN;
CREATE FUNCTION pg_temp.c3_check(p_r jsonb, p_packet jsonb, p_key jsonb) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE it jsonb; ch jsonb; x text; ids text[]; codes text[]; lit text := p_packet#>>'{input,input_literal}'; txt text; n int; v_real jsonb; v_decoy jsonb; failed text[];
BEGIN
 IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_r) k) IS DISTINCT FROM ARRAY['items','schema_version','unit']::text[] THEN RETURN 'TOP_KEYS'; END IF;
 IF p_r->>'schema_version' <> 'ANALYSIS_GPT_NATIVE_BLIND_REVIEW_V1' OR p_r->>'unit' <> 'A12Q' THEN RETURN 'SCHEMA_OR_UNIT'; END IF;
 ids := ARRAY(SELECT i->>'item_id' FROM jsonb_array_elements(p_packet->'items') i);
 IF jsonb_typeof(p_r->'items')<>'array' OR jsonb_array_length(p_r->'items')<>2 OR ARRAY(SELECT i->>'item_id' FROM jsonb_array_elements(p_r->'items') i) IS DISTINCT FROM ids THEN RETURN 'ITEMS_SHAPE'; END IF;
 codes := ARRAY(SELECT c->>'code' FROM jsonb_array_elements(p_packet->'checks') c);
 FOR it IN SELECT * FROM jsonb_array_elements(p_r->'items') LOOP
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(it) k) IS DISTINCT FROM ARRAY['checks','item_id','rationale','verdict']::text[] THEN RETURN 'ITEM_KEYS'; END IF;
  txt := (SELECT i->>'text' FROM jsonb_array_elements(p_packet->'items') i WHERE i->>'item_id'=it->>'item_id');
  IF jsonb_typeof(it->'checks')<>'array' OR ARRAY(SELECT c->>'code' FROM jsonb_array_elements(it->'checks') c) IS DISTINCT FROM codes THEN RETURN 'CHECK_CODES'; END IF;
  FOR ch IN SELECT * FROM jsonb_array_elements(it->'checks') LOOP
   IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(ch) k) IS DISTINCT FROM ARRAY['code','evidence_refs','note','result']::text[] OR ch->>'result' NOT IN ('PASS','FAIL') THEN RETURN 'CHECK_KEYS'; END IF;
   IF jsonb_typeof(ch->'evidence_refs')<>'array' OR jsonb_array_length(ch->'evidence_refs') NOT BETWEEN 1 AND 3
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(ch->'evidence_refs') e WHERE jsonb_typeof(e)<>'string' OR length(trim(e#>>'{}'))<8) THEN RETURN 'EVIDENCE_SHAPE'; END IF;
   FOR x IN SELECT e#>>'{}' FROM jsonb_array_elements(ch->'evidence_refs') e LOOP
    IF position(E'\n' in x)>0 OR (position(x in lit)=0 AND position(x in txt)=0) THEN RETURN 'EVIDENCE_NOT_VERBATIM'; END IF;
   END LOOP;
   IF jsonb_typeof(ch->'note')<>'string' OR length(trim(ch->>'note'))<10 THEN RETURN 'NOTE_SHORT'; END IF;
  END LOOP;
  IF it->>'verdict' IS DISTINCT FROM (CASE WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(it->'checks') c WHERE c->>'result'<>'PASS') THEN 'PASS' ELSE 'FAIL' END) THEN RETURN 'VERDICT_INCONSISTENT'; END IF;
  IF jsonb_typeof(it->'rationale')<>'string' OR length(trim(it->>'rationale'))<20 THEN RETURN 'RATIONALE_SHORT'; END IF;
 END LOOP;
 SELECT i INTO v_real FROM jsonb_array_elements(p_r->'items') i WHERE i->>'item_id'=p_key->>'real_item_id';
 SELECT i INTO v_decoy FROM jsonb_array_elements(p_r->'items') i WHERE i->>'item_id'=p_key->>'decoy_item_id';
 IF v_real->>'verdict'<>'PASS' THEN RETURN 'REAL_ITEM_NOT_PASS'; END IF;
 IF v_decoy->>'verdict'<>'FAIL' THEN RETURN 'DECOY_NOT_FAIL'; END IF;
 failed := ARRAY(SELECT c->>'code' FROM jsonb_array_elements(v_decoy->'checks') c WHERE c->>'result'='FAIL');
 IF NOT (ARRAY(SELECT jsonb_array_elements_text(p_key->'decoy_must_fail_checks')) <@ failed) THEN RETURN 'DECOY_REQUIRED_CHECK_NOT_FAIL'; END IF;
 RETURN 'PASS';
END $f$;
DO $a12q_c3_close_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := 'ef6a3328a8ec1153e9ecfe4b3d004b2d0ba98b8c80c52278c633cd023927de38';
 v_raw_text text := $raw${
"schema_version": "ANALYSIS_GPT_NATIVE_BLIND_REVIEW_V1",
"unit": "A12Q",
"items": [
{
"item_id": "ITEM_A",
"checks": [
{
"code": "SAME_CASES_BOTH_ARMS",
"result": "PASS",
"evidence_refs": [
"Se produjeron ambos brazos para los mismos siete casos históricos.",
"A10-HIST-001",
"A10-HIST-008"
],
"note": "Ambos brazos contienen exactamente los mismos siete case_id de la entrada y el baseline incluye los seis dominios fijos en cada caso."
},
{
"code": "CANDIDATE_FRONTS_TRIGGERED",
"result": "FAIL",
"evidence_refs": [
"lf_eventos://99999",
"lf_eventos://20397",
"github://cristhianlujan/claude-persona-lf-patch/pull/1800"
],
"note": "El frente BINDING_CONTRATOS del caso A10-HIST-001 utiliza lf_eventos://99999 como trigger_ref, referencia ausente de las source_refs de ese caso; las evidence_refs no presentan duplicados ni referencias ajenas."
},
{
"code": "COMPARISON_TOTALS_EXACT",
"result": "FAIL",
"evidence_refs": [
"El baseline incluye seis dominios fijos por caso, con 42 asignaciones en total.",
"El candidate contiene 12 frentes hipotéticos derivados de los asuntos, familias y referencias suministradas."
],
"note": "El objeto comparison declara baseline_total_domains=40 y candidate_total_fronts=9, pero los totales reales son 42 y 12; cases_compared=7 y baseline_fixed_domains_per_case=6 son correctos. No se identifican afirmaciones positivas de rendimiento ni READY."
}
],
"verdict": "FAIL",
"rationale": "La cobertura de casos y dominios fijos es correcta. Sin embargo, existe una referencia de activación no autorizada por la entrada y dos totales incorrectos en comparison. El ítem no supera los tres chequeos."
},
{
"item_id": "ITEM_B",
"checks": [
{
"code": "SAME_CASES_BOTH_ARMS",
"result": "PASS",
"evidence_refs": [
"Se produjeron ambos brazos para los mismos siete casos históricos.",
"A10-HIST-001",
"A10-HIST-008"
],
"note": "Los dos brazos contienen los siete case_id originales, sin casos adicionales ni faltantes, y cada registro baseline incluye exactamente los seis dominios fijos."
},
{
"code": "CANDIDATE_FRONTS_TRIGGERED",
"result": "PASS",
"evidence_refs": [
"github://cristhianlujan/claude-persona-lf-patch/pull/1800",
"supabase://programacion.fn_input_v58_build_assertions",
"supabase://programacion.fn_test_contract_generation_source"
],
"note": "Los doce frentes utilizan trigger_ref pertenecientes a las source_refs de sus respectivos casos; las evidence_refs también pertenecen a cada caso y no contienen duplicados."
},
{
"code": "COMPARISON_TOTALS_EXACT",
"result": "PASS",
"evidence_refs": [
"El baseline incluye seis dominios fijos por caso, con 42 asignaciones en total.",
"El candidate contiene 12 frentes hipotéticos derivados de los asuntos, familias y referencias suministradas.",
"Esta es una comparación estructural de cobertura declarada y cantidad de elementos, no una comparación de rendimiento, calidad, precisión, latencia o superioridad de un método."
],
"note": "Los cuatro enteros coinciden con los registros: siete casos comparados, seis dominios fijos por caso, 42 dominios baseline y doce frentes candidate; no se afirma calidad, costo, latencia, superioridad ni READY."
}
],
"verdict": "PASS",
"rationale": "El ítem supera los tres chequeos: cobertura idéntica de los siete casos, referencias de activación válidas y totales exactos. El resultado confirma únicamente conformidad estructural con los criterios solicitados, sin evaluar rendimiento ni acreditar las fuentes externas."
}
]
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","capture_method":"RENDERED_CHAT_TEXT_FROM_BROWSER_DOM","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acfecb7-e368-83e9-bdf1-5930a790eef4","chat_transcript_sha256":"248bee2072bc6383332582ccfa3e5083e7d74905502a47a22d00cc7ce3edf1ee","criterion_amendment":{"amended_criterion":"Revisor ciego verifica cobertura de ambos brazos y totales exactos de la comparación, sin calidad, costo ni latencia","approval_doc":"docs/programming-agent/ANALYSIS_C3_CRITERIA_AMENDMENT_A9_A12_A13_V1.md","approval_doc_sha256":"6bdce15ae7f8d3a8070f81e0a2e4e0cab2b51a8c5782a3b50f4844c3dd5098c4","approved_by":"owner","original_criterion":"Juez independiente calcula calidad, costo y sobreanálisis sin proxies"},"evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","limits":{"independent_review":false,"provider_attested":false,"real_execution_receipt":false},"packet_sha256":"ef6a3328a8ec1153e9ecfe4b3d004b2d0ba98b8c80c52278c633cd023927de38","producer_mode":"GPT_NATIVE_REVIEW","raw_output_sha256":"c3524bf34a751541a4c39fa97d702af23451c8d8372903362580373c2ba7d8fd","runtime_provider_attested":false,"schema":"ANALYSIS_GPT_NATIVE_C3_CAPTURE_V1","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A12Q/A12Q_C3"}$rec$::jsonb;
 v_m jsonb; v_pk jsonb; v_key jsonb; v_c2 jsonb; v_specs jsonb; v_cps_before text; v_cps_after text; v_res text; v_decoy text; v_old text; v_new text; v_e jsonb;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1122 AND checkpoint_code='A12Q_C3') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A12Q' AND work_item_id=1122 FOR UPDATE;
 v_pk := v_m#>'{gpt_native_packets_v1,A12Q_C3}'; v_key := v_m#>'{gpt_native_c3_keys_v1,A12Q_C3}'; v_c2 := v_m#>'{gpt_native_captures_v1,A12Q_C2}';
 IF v_pk IS NULL OR v_key IS NULL OR v_c2 IS NULL OR v_pk->>'packet_sha256' IS DISTINCT FROM v_packet_sha OR v_rec->>'packet_sha256' IS DISTINCT FROM v_packet_sha
  THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_PACKET_BINDING'; END IF;
 -- the packet's items must still derive from the stored C2 capture (real raw + exact replacements)
 v_decoy := v_c2->>'raw_output_text';
 IF encode(sha256(convert_to(v_decoy,'UTF8')),'hex') <> v_key->>'c2_raw_output_sha256' OR v_c2->>'raw_output_sha256' <> v_key->>'c2_raw_output_sha256' THEN RAISE EXCEPTION 'A12Q_C3_C2_BINDING'; END IF;
 FOR v_e IN SELECT * FROM jsonb_array_elements(v_key->'replacements') LOOP
  v_old := v_e->>0; v_new := v_e->>1; v_decoy := replace(v_decoy,v_old,v_new);
 END LOOP;
 IF (SELECT i->>'text' FROM jsonb_array_elements(v_pk->'items') i WHERE i->>'item_id'=v_key->>'real_item_id') IS DISTINCT FROM v_c2->>'raw_output_text'
    OR (SELECT i->>'text' FROM jsonb_array_elements(v_pk->'items') i WHERE i->>'item_id'=v_key->>'decoy_item_id') IS DISTINCT FROM v_decoy
  THEN RAISE EXCEPTION 'A12Q_C3_ITEMS_NOT_FROM_C2'; END IF;
 -- separate chat from the C2 producer
 IF v_rec->>'chat_transcript_ref' = v_c2->>'chat_transcript_ref' OR v_rec->>'chat_transcript_sha256' = v_c2->>'chat_transcript_sha256' OR length(coalesce(v_rec->>'chat_transcript_ref',''))<10 OR coalesce(v_rec->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'A12Q_C3_SAME_CHAT_OR_MISSING'; END IF;
 v_res := pg_temp.c3_check(v_raw_text::jsonb, v_pk, v_key);
 IF v_res<>'PASS' THEN RAISE EXCEPTION 'A12Q_C3_REVIEW_CHECK_FAILED:%', v_res; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,independent_review}')::boolean IS NOT FALSE OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
  THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_LIMITS'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A12Q_C3}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A12Q_C3,raw_output_sha256}' <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1122;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A12Q_C3',v_rec))
  WHERE plan_code=v_plan AND unit_code='A12Q' AND work_item_id=1122;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A12Q' AND work_item_id=1122;
 IF v_m#>'{gpt_native_captures_v1,A12Q_C3}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1122;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a12q_c3_close_cap$;
-- A12Q_C3 closure under the owner-approved GPT Native tier (docs/programming-agent/ANALYSIS_C3_TIER_ACCEPTANCE_DECISION_V1.md).
DO $a12q_c3_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A12Q';
 v_cp constant text := 'A12Q_C3';
 v_wi constant bigint := 1122;
 v_actor constant text := 'ANALYSIS_QUAL_C3_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_c3_gpt_blind_review_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C3_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '902811e79f8e8a10e8687d4387c32ae116250bb4ce12d2171444a85bfcdd2909';
 v_packet_sha constant text := 'ef6a3328a8ec1153e9ecfe4b3d004b2d0ba98b8c80c52278c633cd023927de38';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1122 and checkpoint_code=''A12Q_C3''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_key jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_pass jsonb; v_res text;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE') ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A12Q_C3_NOT_CURRENT'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A12Q_C3}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED' OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A12Q/A12Q_C3'
 THEN RAISE EXCEPTION 'A12Q_C3_PRESTATE_DRIFT'; END IF;
 v_cap:=v_m#>'{gpt_native_captures_v1,A12Q_C3}'; v_pk:=v_m#>'{gpt_native_packets_v1,A12Q_C3}'; v_key:=v_m#>'{gpt_native_c3_keys_v1,A12Q_C3}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_key IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha OR v_cap->>'packet_sha256' IS DISTINCT FROM v_packet_sha
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A12Q_C3_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256' THEN RAISE EXCEPTION 'A12Q_C3_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE OR (v_cap#>>'{limits,independent_review}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A12Q_C3_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_res := pg_temp.c3_check(v_raw, v_pk, v_key);
 IF v_res<>'PASS' THEN RAISE EXCEPTION 'A12Q_C3_CONTENT_CHECK_FAILED:%', v_res; END IF;
 IF v_cap->>'chat_transcript_ref' = v_m#>>'{gpt_native_captures_v1,A12Q_C2,chat_transcript_ref}' THEN RAISE EXCEPTION 'A12Q_C3_SAME_CHAT_AS_PRODUCER'; END IF;
 v_pass:=jsonb_build_object('capture_verified',true,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,'content_checks_passed',true,'owner_decision_recorded',true,'real_item_pass',true,'decoy_item_fail',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native blind review of the A12 stage output (real item PASS, decoy item FAIL) under the owner-approved C3 tier and bind its result',
  'expected_evidence_class',v_tier,
  'tier_acceptance',jsonb_build_object('tier',v_tier,'decision_ref',v_decision_doc||'@'||v_decision_sha,
    'replaces_expected_evidence_class','INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT','scope','C3_A1Q_TO_A14Q_ONLY',
    'limits',jsonb_build_object('provider_attested',false,'real_execution_receipt',false,'independent_review',false)),
  'target',jsonb_build_object('declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_artifacts',jsonb_build_array(v_art),'evidence_artifacts','[]'::jsonb,'mutation_artifacts',jsonb_build_array(v_art)),
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',v_pass),
  'verification_queries',jsonb_build_array(v_vq),
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A12Q_C3_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN','declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A12Q_C3}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A12Q_C3,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;
 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A12Q_C3_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true' THEN RAISE EXCEPTION 'A12Q_C3_READINESS_FAILED:%',v_ready; END IF;
 v_evidence:='supabase://programacion.engineering_plan_units/A12Q#unit_metadata.gpt_native_captures_v1.A12Q_C3'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';packet_sha256:'||v_packet_sha
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha;
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A12Q_C3_HEARTBEAT_START:%',v_out; END IF;
 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A12Q_C3_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'real_item_id',v_key->>'real_item_id','decoy_item_id',v_key->>'decoy_item_id',
    'c2_raw_output_sha256',v_key->>'c2_raw_output_sha256','separate_chat_from_c2_producer',true,
    'producer_mode','GPT_NATIVE_REVIEW','evidence_class',v_tier,'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','true_isolation_of_the_reviewer','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL THEN RAISE EXCEPTION 'A12Q_C3_RECEIPT_FAILED:%',v_receipt; END IF;
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A12Q_C3_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C3 closed under the owner-approved GPT Native in-chat review tier (blinded packet, separate chat); hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A12Q_C3_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A12Q_C1:DONE,A12Q_C2:DONE,A12Q_C3:DONE' THEN RAISE EXCEPTION 'A12Q_C3_POSTSTATE_FAILED'; END IF;
END $a12q_c3_close$;
COMMIT;
