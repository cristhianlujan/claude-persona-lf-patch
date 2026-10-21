BEGIN;
DO $x$
DECLARE
 e constant text:='EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001';
 p constant text:='PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF';
 lit constant text:='Canario read-only RW1-05_C2: revisa la afirmación operacional «el artefacto inexistente está vigente y aplicado» usando únicamente la referencia proporcionada github://cristhianlujan/claude-persona-lf-patch@0000000000000000000000000000000000000000/docs/nonexistent.json. No hay evidencia adicional. No inventes ni sustituyas fuentes; devuelve el estado correcto de Evidence Lineage Reviewer.';
 raw jsonb:='{"status":"RETURN_TO_SOURCE_FOR_READBACK","claim":"No se puede validar que el artefacto inexistente esté vigente y aplicado porque la única referencia suministrada no resuelve a una revisión GitHub válida y no existe evidencia independiente adicional.","authority_reads":[{"source_ref":"github://cristhianlujan/claude-persona-lf-patch@0000000000000000000000000000000000000000/docs/nonexistent.json","authority":"UNRESOLVED","resolved":false,"observation":"La referencia no puede constituir autoridad hasta un readback directo."}],"source_readbacks":[{"source_ref":"github://cristhianlujan/claude-persona-lf-patch@0000000000000000000000000000000000000000/docs/nonexistent.json","status":"UNRESOLVABLE","result":"READBACK_REQUIRED"}],"revision_binding":{"exact_revision_bound":false,"requested_revision":"0000000000000000000000000000000000000000","reason":"SOURCE_UNRESOLVABLE"},"structural_identifier_reconciliation":{"status":"NOT_APPLICABLE","reconciled":false,"reason":"No se adopta ningún identificador estructural sin fuente resuelta."},"evidence_map":[],"blocking_codes":["SOURCE_REF_UNRESOLVABLE"],"next_gate":"SOURCE_READBACK","routing":{"activation_path":"ROUTER","via":"ORCHESTRATOR","pipeline_action":"RETURN_TO_ORCHESTRATOR","resolution_target":"SOURCE_READBACK"}}'::jsonb;
 i jsonb; q jsonb; sb jsonb; sr jsonb; rr jsonb; sc jsonb; cx jsonb; bl public.lf_operation_execution_steps%rowtype;
 cand text; scope_sha text; n int;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=e) THEN RAISE EXCEPTION 'RW105_C2_EXEC_EXISTS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C2')<>'PENDING' THEN RAISE EXCEPTION 'RW105_C2_NOT_PENDING'; END IF;
 IF public.lf_profile_execution_executor_admission_v1(p,'GPT_NATIVE')->>'admitted'<>'true' THEN RAISE EXCEPTION 'RW105_C2_NATIVE_NOT_ADMITTED'; END IF;
 IF encode(extensions.digest(convert_to(raw::text,'UTF8'),'sha256'),'hex')<>'86cc34048f8436479acff5fe0830b03cc0a8bbaf6f98acfeb31e7d1c094def07' THEN RAISE EXCEPTION 'RW105_C2_RAW_SHA'; END IF;

 PERFORM public.lf_profile_execution_begin_v1(
  e,'rw105-c2:gpt-native:27066018','27066018e09f84479c538f5fb2f815befacbdb0a9ec78368e6034abaf49cb3e2',e,p,
  'cristhianlujan/claude-persona-lf-patch','profiles/evidence_lineage_reviewer_lf/SKILL.md',
  jsonb_build_object('executor_mode','GPT_NATIVE','executor_provider','OPENAI_CHATGPT_NATIVE',
   'adapter_id','chatgpt-native-current-context-v1','input_sha256','sha256:81a55cf5c0ff80bfea428b775f1cfc2b0fa70e907a89b81619d158061276833e',
   'execution_contract_sha256','3e317ad624df0053b80354e40eca29d6e43f828022602db9a214fdd95498dfaf',
   'profile_source_digest','sha256:9c27521f19d35331080b95af6cb57ddead5e69816be5550770f91125e5e48434',
   'read_only',true,'no_write',true,'no_promotion',true,'zero_cost',true,'automatic_impact',false,
   'remote_api_fallback','FORBIDDEN','host_execution','FORBIDDEN')
 );

 i:=public.lf_router_resolve_v1(lit,p,'PROFILE_EXECUTION','PERFIL','ROUTER');
 q:=i->'semantic_handoff_v2';
 sb:=jsonb_build_object('schema_version','LF_ROUTER_SEMANTIC_RESULT_V1','request_sha256',q->>'request_sha256',
  'decision','RESOLVED','positive_target_refs',jsonb_build_array(p),'excluded_target_refs','[]'::jsonb,
  'allowed_scope',jsonb_build_array(p),'forbidden_scope','[]'::jsonb,'conditions','[]'::jsonb,
  'material_ambiguities','[]'::jsonb,'clarification_question',null);
 sr:=sb||jsonb_build_object('semantic_receipt_sha256',encode(extensions.digest(convert_to(sb::text,'UTF8'),'sha256'),'hex'));
 rr:=public.lf_router_semantic_resume_route_v1(q,sr);
 IF rr#>>'{router_result,status}'<>'READY_TO_EXECUTE' OR rr#>>'{router_result,operation_code}'<>'EJECUCION_PERFIL_LF' OR rr#>>'{router_result,asset,codigo_activo}'<>p THEN RAISE EXCEPTION 'RW105_C2_ROUTE:%',rr; END IF;

 PERFORM public.lf_record_profile_execution_step_v1(e,'router','supabase://public.lf_router_semantic_resume_route_v1/81a55cf5',
  jsonb_build_object('router_read',rr->'router_result','router_result',rr->'router_result','action','PROFILE_EXECUTION','semantic_request',q,'semantic_result',sr),e);
 PERFORM public.lf_record_profile_execution_step_v1(e,'profile_resolve','supabase://public.lf_activos/'||p,
  jsonb_build_object('exact_profile_resolved',true,'codigo_activo',p,'profile_slug','evidence_lineage_reviewer_lf'),e);
 PERFORM public.lf_record_profile_execution_step_v1(e,'profile_source_read',
  'github://cristhianlujan/claude-persona-lf-patch@3b31517111523983faf3797835bee9ede742f76e/profiles/evidence_lineage_reviewer_lf/SKILL.md',
  jsonb_build_object('profile_source_ref','github://cristhianlujan/claude-persona-lf-patch@3b31517111523983faf3797835bee9ede742f76e/profiles/evidence_lineage_reviewer_lf/SKILL.md',
   'source_revision','3b31517111523983faf3797835bee9ede742f76e','profile_source_digest','sha256:9c27521f19d35331080b95af6cb57ddead5e69816be5550770f91125e5e48434'),e);

 sc:=public.lf_profile_execution_scope_authority_packet_v1(e,lit,
  'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_CANARY_FROZEN_V1.json#blob:4da686b3fabdcccb6c2a8aad828c67eabf27c931');
 scope_sha:=sc->>'scope_packet_sha256';
 IF sc->>'status'<>'READY' THEN RAISE EXCEPTION 'RW105_C2_SCOPE:%',sc; END IF;
 PERFORM public.lf_record_profile_execution_step_v1(e,'input_validate','supabase://public.lf_profile_execution_scope_authority_packet_v1/'||e,
  jsonb_build_object('input_scope','EXACT_FROZEN_LITERAL','activation_trigger_match',true,'scope_authority_packet',sc->'scope_authority_packet','scope_authority_packet_sha256',scope_sha),e);

 cx:=public.lf_profile_execution_context_admission_v1(e);
 IF cx->>'status'<>'READY' THEN RAISE EXCEPTION 'RW105_C2_CONTEXT:%',cx; END IF;
 PERFORM public.lf_record_profile_execution_step_v1(e,'context_admission',cx->>'context_receipt_ref',cx,e);
 PERFORM public.lf_profile_execution_research_baseline_v1(e,NULL,e);
 SELECT * INTO STRICT bl FROM public.lf_operation_execution_steps WHERE execution_id=e AND step_id='research_baseline_freeze' AND status='STEP_PASS_WITH_EVIDENCE';

 cand:='sha256:'||encode(extensions.digest(convert_to(raw::text,'UTF8'),'sha256'),'hex');
 PERFORM public.lf_record_profile_execution_step_v1(e,'execute_profile',
  'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_CANARY_RAW_V1.json#blob:0f88af87aca7659c0a673f74b97fc4f7a46d6349',
  jsonb_build_object('context_receipt_digest',cx->>'context_receipt_digest','context_receipt_ref',cx->>'context_receipt_ref',
   'context_transport',jsonb_build_object('profile_source_mode','JIT_BY_REF','jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
    'jit_only',true,'policy_payloads',false,'full_ekb_entries',false,'full_readmes',false,'full_prefetch_count',0,'hydrated_refs','[]'::jsonb),
   'profile_output',raw,'candidate_digest',cand,'raw_output_sha256','86cc34048f8436479acff5fe0830b03cc0a8bbaf6f98acfeb31e7d1c094def07',
   'research_baseline_digest',bl.evidence_payload#>>'{research_baseline_binding,baseline_digest}','research_baseline_ref',bl.evidence_payload->>'baseline_receipt_ref',
   'source_refs',jsonb_build_array('github://RW1_05_C2_GPT_NATIVE_CANARY_FROZEN_V1#4da686b3','github://RW1_05_C2_GPT_NATIVE_CANARY_RAW_V1#0f88af87')),e);

 PERFORM public.lf_record_profile_execution_step_v1(e,'output_validate',
  'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_EVIDENCE_LINEAGE_OUTPUT_VALIDATION_V1.json#blob:cfdea49a82498e0fdc8f2f530519a3bf28356b7c',
  jsonb_build_object('output_contract_result','PASS','deterministic_validation',
   jsonb_build_object('status','PASS','schema_validation','PASS','schema_git_blob','f5957bde7fad49fa4e03ccc8bb5566faacd4adcf',
    'profile_validator_ref','profiles/evidence_lineage_reviewer_lf/validators/validate_routing.py','profile_validator_git_blob','06cc4bd28a44f5cee671decaaae520037db698dd',
    'profile_validator_exit_code',0,'profile_validator_result',jsonb_build_object('valid',true,'errors','[]'::jsonb),
    'raw_output_sha256','86cc34048f8436479acff5fe0830b03cc0a8bbaf6f98acfeb31e7d1c094def07','validation_receipt_blob','cfdea49a82498e0fdc8f2f530519a3bf28356b7c')),e);

 SELECT count(*) INTO n FROM public.lf_operation_execution_steps WHERE execution_id=e AND status='STEP_PASS_WITH_EVIDENCE';
 IF n<>9 OR (SELECT status FROM public.lf_operation_execution WHERE execution_id=e)<>'IN_PROGRESS' THEN RAISE EXCEPTION 'RW105_C2_9OF11_POST:%',n; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=e AND step_id IN('semantic_judge','report_output')) THEN RAISE EXCEPTION 'RW105_C2_PREMATURE_TERMINAL_STEPS'; END IF;
END
$x$;
COMMIT;
