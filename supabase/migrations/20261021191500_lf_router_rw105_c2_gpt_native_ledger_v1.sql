-- RW1-05_C2: materialize the already-frozen GPT_NATIVE canary in the canonical ledger.
-- No producer or independent judge rerun. Any failed gate rolls back the transaction.
BEGIN;

DO $rw105_c2_native_ledger$
DECLARE
  x constant text := 'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001';
  p constant text := 'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF';
  input_sha constant text := '81a55cf5c0ff80bfea428b775f1cfc2b0fa70e907a89b81619d158061276833e';
  request_sha constant text := '27066018e09f84479c538f5fb2f815befacbdb0a9ec78368e6034abaf49cb3e2';
  raw_sha constant text := '86cc34048f8436479acff5fe0830b03cc0a8bbaf6f98acfeb31e7d1c094def07';
  source_sha constant text := '9c27521f19d35331080b95af6cb57ddead5e69816be5550770f91125e5e48434';
  source_rev constant text := '3b31517111523983faf3797835bee9ede742f76e';
  input_literal constant text := 'Canario read-only RW1-05_C2: revisa la afirmación operacional «el artefacto inexistente está vigente y aplicado» usando únicamente la referencia proporcionada github://cristhianlujan/claude-persona-lf-patch@0000000000000000000000000000000000000000/docs/nonexistent.json. No hay evidencia adicional. No inventes ni sustituyas fuentes; devuelve el estado correcto de Evidence Lineage Reviewer.';
  frozen_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_CANARY_FROZEN_V1.json#blob:4da686b3fabdcccb6c2a8aad828c67eabf27c931';
  capture_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_CANARY_CAPTURE_V1.json#blob:ff057f4a0e590a258d9d5ba792eecaea1a628595';
  review_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_INDEPENDENT_SEMANTIC_REVIEW_V1.json#blob:af05409793a90821a7274ee1057e8029dc298f54';
  resume_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_SEMANTIC_RESUME_V2.json#blob:0742b33945925c8b525117f830531b891ee3fa56';
  validator_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/router_wave/validate_rw105_c2_gpt_native_frozen_v1.py#blob:bf5d3c97a6af8365baffd05908dc440d58f6ea5b';
  schema_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch@3b31517111523983faf3797835bee9ede742f76e/profiles/evidence_lineage_reviewer_lf/schemas/output.schema.json#blob:f5957bde7fad49fa4e03ccc8bb5566faacd4adcf';
  skill_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch@3b31517111523983faf3797835bee9ede742f76e/profiles/evidence_lineage_reviewer_lf/SKILL.md#blob:2acf40bb9130a76a1b8cf3dc5a71dae1f0da0b3';
  raw jsonb := '{"status":"RETURN_TO_SOURCE_FOR_READBACK","claim":"No se puede validar que el artefacto inexistente esté vigente y aplicado porque la única referencia suministrada no resuelve a una revisión GitHub válida y no existe evidencia independiente adicional.","authority_reads":[{"source_ref":"github://cristhianlujan/claude-persona-lf-patch@0000000000000000000000000000000000000000/docs/nonexistent.json","authority":"UNRESOLVED","resolved":false,"observation":"La referencia no puede constituir autoridad hasta un readback directo."}],"source_readbacks":[{"source_ref":"github://cristhianlujan/claude-persona-lf-patch@0000000000000000000000000000000000000000/docs/nonexistent.json","status":"UNRESOLVABLE","result":"READBACK_REQUIRED"}],"revision_binding":{"exact_revision_bound":false,"requested_revision":"0000000000000000000000000000000000000000","reason":"SOURCE_UNRESOLVABLE"},"structural_identifier_reconciliation":{"status":"NOT_APPLICABLE","reconciled":false,"reason":"No se adopta ningún identificador estructural sin fuente resuelta."},"evidence_map":[],"blocking_codes":["SOURCE_REF_UNRESOLVABLE"],"next_gate":"SOURCE_READBACK","routing":{"activation_path":"ROUTER","via":"ORCHESTRATOR","pipeline_action":"RETURN_TO_ORCHESTRATOR","resolution_target":"SOURCE_READBACK"}}'::jsonb;
  initial jsonb; q jsonb; sr jsonb; rr jsonb; route jsonb;
  begun jsonb; step jsonb; scope_r jsonb; scope_sha text; scope64 text;
  context_r jsonb; baseline_r jsonb; baseline_payload jsonb;
  sem_payload jsonb; terminal_r jsonb; attach_r jsonb; terminal2 jsonb; m jsonb;
  j record; n integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id=x) THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTION_ALREADY_EXISTS';
  END IF;
  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C2') <> 'PENDING' THEN
    RAISE EXCEPTION 'RW105_C2_CHECKPOINT_NOT_PENDING';
  END IF;

  -- Exact frozen schema checks for Evidence Lineage output.
  IF jsonb_typeof(raw)<>'object'
     OR NOT (raw ?& ARRAY['status','claim','authority_reads','source_readbacks','revision_binding',
       'structural_identifier_reconciliation','evidence_map','blocking_codes','next_gate','routing'])
     OR raw->>'status'<>'RETURN_TO_SOURCE_FOR_READBACK'
     OR jsonb_typeof(raw->'claim')<>'string'
     OR jsonb_typeof(raw->'authority_reads')<>'array'
     OR jsonb_typeof(raw->'source_readbacks')<>'array'
     OR jsonb_typeof(raw->'revision_binding')<>'object'
     OR jsonb_typeof(raw->'structural_identifier_reconciliation')<>'object'
     OR jsonb_typeof(raw->'evidence_map')<>'array'
     OR jsonb_typeof(raw->'blocking_codes')<>'array'
     OR jsonb_typeof(raw->'next_gate')<>'string'
     OR jsonb_typeof(raw->'routing')<>'object'
     OR NOT ((raw->'routing') ?& ARRAY['activation_path','via','pipeline_action','resolution_target'])
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(raw->'routing') k
                WHERE k NOT IN ('activation_path','via','pipeline_action','resolution_target'))
     OR raw#>>'{routing,activation_path}' NOT IN ('DIRECT','ROUTER')
     OR raw#>>'{routing,via}'<>'ORCHESTRATOR'
     OR raw#>>'{routing,pipeline_action}'<>'RETURN_TO_ORCHESTRATOR'
     OR raw#>>'{routing,resolution_target}'<>'SOURCE_READBACK'
     OR raw->>'next_gate'<>'SOURCE_READBACK'
     OR raw->'blocking_codes'<>'["SOURCE_REF_UNRESOLVABLE"]'::jsonb
  THEN RAISE EXCEPTION 'RW105_C2_FROZEN_RAW_SCHEMA_INVALID'; END IF;

  initial:=public.lf_router_resolve_v1(input_literal,p,'PROFILE_EXECUTION','PERFIL','ROUTER');
  IF initial->>'blocking_code'<>'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED'
     OR initial->>'candidate_action_code'<>'PROFILE_EXECUTION'
     OR initial->>'request_sha256'<>input_sha
     OR initial#>>'{semantic_handoff_v2,router_action_binding,candidate_action_code}'<>'PROFILE_EXECUTION'
  THEN RAISE EXCEPTION 'RW105_C2_INITIAL_ROUTER_DRIFT:%',left(initial::text,1200); END IF;

  q:=initial->'semantic_handoff_v2';
  sr:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1','request_sha256',input_sha,
    'decision','RESOLVED','positive_target_refs',jsonb_build_array(p),
    'excluded_target_refs','[]'::jsonb,'allowed_scope',jsonb_build_array(p),
    'forbidden_scope','[]'::jsonb,'conditions','[]'::jsonb,'material_ambiguities','[]'::jsonb,
    'clarification_question',null,
    'semantic_receipt_sha256','8d07f6aa8e55ec55110cab06abefe0c4dec4022c361a8798cc7abeccbadd7d28'
  );
  rr:=public.lf_router_semantic_resume_route_v1(q,sr);
  route:=rr->'router_result';
  IF rr->>'status'<>'ROUTER_REDERIVED'
     OR rr->>'router_derived_action_code'<>'PROFILE_EXECUTION'
     OR rr#>>'{resume_validation,status}'<>'VALID'
     OR route->>'status'<>'READY_TO_EXECUTE'
     OR route->>'operation_code'<>'EJECUCION_PERFIL_LF'
     OR route->>'action_code'<>'PROFILE_EXECUTION'
     OR route#>>'{asset,codigo_activo}'<>p
     OR coalesce((route->>'downstream_execution_allowed')::boolean,false) IS NOT TRUE
     OR coalesce((route->>'step_count')::integer,0)<>11
  THEN RAISE EXCEPTION 'RW105_C2_RESUME_NOT_READY:%',left(rr::text,1600); END IF;

  begun:=public.lf_profile_execution_begin_v1(
    x,'rw105-c2-gpt-native-canary-20261021-001',request_sha,x,p,
    'cristhianlujan/claude-persona-lf-patch','profiles/evidence_lineage_reviewer_lf/SKILL.md',
    jsonb_build_object(
      'executor_mode','GPT_NATIVE','executor_provider','OPENAI_CHATGPT_NATIVE',
      'native_adapter_id','chatgpt-native-current-context-v1',
      'conversation_scope','EXISTING_CONVERSATION_ONLY',
      'input_sha256','sha256:'||input_sha,'profile_source_digest','sha256:'||source_sha,
      'profile_source_revision',source_rev,'read_only',true,'no_write',true,
      'no_promotion',true,'automatic_impact',false,'remote_api_fallback','FORBIDDEN',
      'host_execution','FORBIDDEN',
      'frozen_execution_contract_sha256','3e317ad624df0053b80354e40eca29d6e43f828022602db9a214fdd95498dfaf',
      'frozen_raw_output_sha256',raw_sha,'frozen_input_ref',frozen_ref,
      'frozen_capture_ref',capture_ref,'semantic_resume_ref',resume_ref,
      'independent_semantic_review_ref',review_ref
    )
  );
  IF begun->>'result'<>'RESERVED_NEW_EXECUTION'
     OR coalesce((begun->>'init_materialized')::boolean,false) IS NOT TRUE
     OR begun->>'research_baseline_mode'<>'NOT_REQUIRED'
  THEN RAISE EXCEPTION 'RW105_C2_BEGIN_FAILED:%',begun::text; END IF;

  step:=public.lf_record_profile_execution_step_v1(x,'router',resume_ref,
    jsonb_build_object('router_read','READY_TO_EXECUTE','action','PROFILE_EXECUTION',
      'router_result',route,'semantic_resume_ref',resume_ref,
      'input_literal_sha256','sha256:'||input_sha,'blocking_codes','[]'::jsonb),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_ROUTER_STEP_FAILED:%',step::text; END IF;

  step:=public.lf_record_profile_execution_step_v1(x,'profile_resolve',
    'supabase://public/lf_activos/'||p,
    jsonb_build_object('exact_profile_resolved',true,'codigo_activo',p,
      'profile_slug','evidence_lineage_reviewer_lf','blocking_codes','[]'::jsonb),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_PROFILE_RESOLVE_FAILED:%',step::text; END IF;

  step:=public.lf_record_profile_execution_step_v1(x,'profile_source_read',skill_ref,
    jsonb_build_object('profile_source_ref',skill_ref,'source_revision',source_rev,
      'profile_source_digest','sha256:'||source_sha,'profile_schema_ref',schema_ref,
      'runtime_source_mode','FROZEN_GPT_NATIVE_SOURCE_BINDING','blocking_codes','[]'::jsonb),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_SOURCE_STEP_FAILED:%',step::text; END IF;

  scope_r:=public.lf_profile_execution_scope_authority_packet_v1(x,input_literal,frozen_ref||'#input_literal');
  IF scope_r->>'status'<>'READY'
     OR coalesce(scope_r->>'scope_packet_sha256','') !~ '^sha256:[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'RW105_C2_SCOPE_PACKET_FAILED:%',scope_r::text; END IF;
  scope_sha:=scope_r->>'scope_packet_sha256';
  scope64:=replace(scope_sha,'sha256:','');

  step:=public.lf_record_profile_execution_step_v1(x,'input_validate',frozen_ref||'#input_literal',
    jsonb_build_object('input_scope','RW1-05_C2_FROZEN_GPT_NATIVE_CANARY',
      'activation_trigger_match',true,'input_digest','sha256:'||input_sha,'read_only',true,
      'scope_authority_packet',scope_r->'scope_authority_packet',
      'scope_authority_packet_sha256',scope_sha,'blocking_codes','[]'::jsonb),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_INPUT_STEP_FAILED:%',step::text; END IF;

  context_r:=public.lf_profile_execution_context_admission_v1(x);
  IF context_r->>'status'<>'READY'
     OR coalesce((context_r->>'server_validated')::boolean,false) IS NOT TRUE
  THEN RAISE EXCEPTION 'RW105_C2_CONTEXT_NOT_READY:%',left(context_r::text,1600); END IF;
  step:=public.lf_record_profile_execution_step_v1(x,'context_admission',
    context_r->>'context_receipt_ref',context_r||jsonb_build_object('blocking_codes','[]'::jsonb),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_CONTEXT_STEP_FAILED:%',step::text; END IF;

  baseline_r:=public.lf_profile_execution_research_baseline_v1(x,null,x);
  IF baseline_r->>'outcome'<>'STEP_RECORDED' OR baseline_r->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_BASELINE_FAILED:%',baseline_r::text; END IF;
  SELECT evidence_payload INTO STRICT baseline_payload
    FROM public.lf_operation_execution_steps WHERE execution_id=x AND step_id='research_baseline_freeze';
  IF baseline_payload#>>'{research_baseline_binding,applicability}'<>'NOT_APPLICABLE'
  THEN RAISE EXCEPTION 'RW105_C2_BASELINE_READBACK_INVALID'; END IF;

  step:=public.lf_record_profile_execution_step_v1(x,'execute_profile',capture_ref,
    jsonb_build_object(
      'profile_output',raw,'source_refs',jsonb_build_array(frozen_ref,capture_ref,skill_ref,schema_ref),
      'context_receipt_ref',context_r->>'context_receipt_ref',
      'context_receipt_digest',context_r->>'context_receipt_digest',
      'context_transport',jsonb_build_object(
        'profile_source_mode','JIT_BY_REF',
        'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
        'jit_only',true,'policy_payloads',false,'full_ekb_entries',false,'full_readmes',false,
        'full_prefetch_count',0,'hydrated_refs','[]'::jsonb),
      'research_baseline_ref',baseline_payload->>'baseline_receipt_ref',
      'research_baseline_digest',baseline_payload#>>'{research_baseline_binding,baseline_digest}',
      'profile_source_digest','sha256:'||source_sha,'profile_source_revision',source_rev,
      'producer_runtime','GPT_NATIVE_CURRENT_CHAT_FROZEN','executor_mode','GPT_NATIVE',
      'candidate_digest','sha256:'||raw_sha,'frozen_raw_output_sha256',raw_sha,
      'blocking_codes','[]'::jsonb
    ),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_EXECUTE_STEP_FAILED:%',step::text; END IF;

  step:=public.lf_record_profile_execution_step_v1(x,'output_validate',validator_ref,
    jsonb_build_object('output_contract_result','PASS',
      'deterministic_validation',jsonb_build_object(
        'status','PASS','validator_scope','CANONICAL_FROZEN_JSON_SCHEMA_EXACT_CASE',
        'schema_ref',schema_ref,'schema_content_sha256','fe18c188ec87fb779cfd09a9d57442fecc94e51c34fdb08bf33f17a1b1a4aebb',
        'schema_git_blob','f5957bde7fad49fa4e03ccc8bb5566faacd4adcf',
        'candidate_sha256',raw_sha,'validator_ref',validator_ref,
        'required_fields_checked',true,'type_checks_passed',true,
        'status_routing_conditional_passed',true,'scoped_obligations_passed',3,
        'errors','[]'::jsonb,'blocking_codes','[]'::jsonb),
      'blocking_codes','[]'::jsonb),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_OUTPUT_VALIDATE_FAILED:%',step::text; END IF;

  sem_payload:=jsonb_build_object(
    'semantic_judge_result',jsonb_build_object(
      'status','PASS','verdict','PASS_INDEPENDENT_SEMANTIC','validator_status','PASS',
      'producer_independence_proven',true,'model_call_count',1,
      'candidate_sha256',raw_sha,'scope_packet_sha256',scope64,
      'independent_review_receipt_ref',review_ref,
      'independent_review_receipt_git_blob','af05409793a90821a7274ee1057e8029dc298f54',
      'independent_review_receipt_sha256','4141757d868556dfdce3c9007bab9b9da1b8bc12959ac0599bafd103f3ac2e30',
      'review_request_sha256',request_sha,'review_input_sha256',input_sha,
      'review_profile_source_sha256',source_sha,
      'binding_method','SERVER_OPERATION_WRAPPER_SAME_EXECUTION_INPUT_SOURCE_AND_RAW',
      'result',jsonb_build_object('verdict','PASS_INDEPENDENT_SEMANTIC',
        'candidate_sha256',raw_sha,'scope_packet_sha256',scope64,
        'unsupported_claims','[]'::jsonb,'blocking_codes','[]'::jsonb)),
    'unsupported_claims','[]'::jsonb,'blocking_codes','[]'::jsonb);
  step:=public.lf_record_profile_execution_step_v1(x,'semantic_judge',review_ref,sem_payload,x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_SEMANTIC_STEP_FAILED:%',step::text; END IF;

  step:=public.lf_record_profile_execution_step_v1(x,'report_output',review_ref||'#operational-binding',
    jsonb_build_object('result','PASS_INDEPENDENT_SEMANTIC','profile_code',p,'execution_id',x,
      'candidate_sha256',raw_sha,'scope_packet_sha256',scope64,'no_write_performed',true,
      'profile_result_status',raw->>'status','profile_next_gate',raw->>'next_gate',
      'independent_review_ref',review_ref,'blocking_codes','[]'::jsonb),x);
  IF step->>'outcome'<>'STEP_RECORDED' OR step->>'status'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'RW105_C2_REPORT_STEP_FAILED:%',step::text; END IF;

  SELECT * INTO STRICT j FROM public.v_lf_operation_execution_judge WHERE execution_id=x;
  IF j.judge_result<>'PASS' OR j.required_steps<>11 OR j.required_steps_pass<>11
     OR j.fail_count<>0 OR j.blocked_count<>0
  THEN RAISE EXCEPTION 'RW105_C2_11_OF_11_NOT_PASS'; END IF;
  SELECT count(*) INTO n FROM public.lf_operation_execution_steps
    WHERE execution_id=x AND status='STEP_PASS_WITH_EVIDENCE';
  IF n<>11 THEN RAISE EXCEPTION 'RW105_C2_STEP_COUNT_INVALID:%',n; END IF;

  terminal_r:=public.lf_profile_execution_terminal_authority_receipt_v1(x);
  IF terminal_r->>'status'<>'READY'
     OR terminal_r#>>'{terminal_authority_receipt,execution_id}'<>x
     OR terminal_r#>>'{terminal_authority_receipt,profile_code}'<>p
     OR terminal_r#>>'{terminal_authority_receipt,executor_mode}'<>'GPT_NATIVE'
     OR terminal_r#>>'{terminal_authority_receipt,executor_provider}'<>'OPENAI_CHATGPT_NATIVE'
     OR terminal_r#>>'{terminal_authority_receipt,semantic_verdict}'<>'PASS_INDEPENDENT_SEMANTIC'
  THEN RAISE EXCEPTION 'RW105_C2_TERMINAL_NOT_READY:%',left(terminal_r::text,2000); END IF;

  attach_r:=public.lf_profile_execution_attach_terminal_authority_receipt_v1(x,x);
  IF attach_r->>'result'<>'TERMINAL_AUTHORITY_RECEIPT_ATTACHED'
     OR attach_r->>'terminal_authority_receipt_sha256'
        IS DISTINCT FROM terminal_r->>'terminal_authority_receipt_sha256'
  THEN RAISE EXCEPTION 'RW105_C2_TERMINAL_ATTACH_FAILED:%',attach_r::text; END IF;

  SELECT manifest INTO STRICT m FROM public.lf_operation_execution
    WHERE execution_id=x AND status='COMPLETED' AND target_code=p AND request_sha256=request_sha;
  IF m->>'executor_mode'<>'GPT_NATIVE'
     OR m->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
     OR m ? 'queue_request_id' OR m ? 'runtime_target'
     OR m#>>'{executor_admission_receipt,code}'<>'PROFILE_EXECUTION_NATIVE_MODE_ADMITTED'
     OR m->>'terminal_authority_receipt_sha256'
        IS DISTINCT FROM attach_r->>'terminal_authority_receipt_sha256'
  THEN RAISE EXCEPTION 'RW105_C2_MANIFEST_READBACK_FAILED:%',left(m::text,1800); END IF;

  terminal2:=public.lf_profile_execution_terminal_authority_receipt_v1(x);
  IF terminal2->>'status'<>'READY'
     OR terminal2->>'terminal_authority_receipt_sha256'
        IS DISTINCT FROM attach_r->>'terminal_authority_receipt_sha256'
  THEN RAISE EXCEPTION 'RW105_C2_TERMINAL_READBACK_FAILED'; END IF;
END
$rw105_c2_native_ledger$;

COMMIT;
