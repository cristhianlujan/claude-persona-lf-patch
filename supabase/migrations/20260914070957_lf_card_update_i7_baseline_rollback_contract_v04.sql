-- LF_CARD_UPDATE_I7_BASELINE_ROLLBACK_CONTRACT_V0_4
update public.lf_operation_step_judge_bindings
set required_evidence_keys='["baseline_card_state","baseline_carrier_revision","baseline_block_excerpt_hash","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_carrier_type","baseline_carrier_ref","baseline_block_anchor_or_path","baseline_anchor_start_index","baseline_last_bound_paragraph_end_index","baseline_reversible"]'::jsonb,
    updated_by_execution_id='EXEC-CARD-UPDATE-I7-REMEDIATION-20260913-001',updated_at=now()
where operation_code='ACTUALIZACION_CARD_LF' and step_id='baseline_read' and step_order=50 and status='CANDIDATO_READ_ONLY';

update public.lf_operation_step_contracts
set output_payload='["baseline_card_state","baseline_carrier_revision","baseline_block_excerpt_hash","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_carrier_type","baseline_carrier_ref","baseline_block_anchor_or_path","baseline_anchor_start_index","baseline_last_bound_paragraph_end_index","baseline_reversible"]'::jsonb,
    required_evidence_keys='["baseline_card_state","baseline_carrier_revision","baseline_block_excerpt_hash","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_carrier_type","baseline_carrier_ref","baseline_block_anchor_or_path","baseline_anchor_start_index","baseline_last_bound_paragraph_end_index","baseline_reversible"]'::jsonb,
    notes=coalesce(notes,'')||' I7 v0.4: full reversible baseline content, bounded range and baseline_reversible=true are mandatory before pre-write.',
    updated_by_execution_id='EXEC-CARD-UPDATE-I7-REMEDIATION-20260913-001',updated_at=now()
where operation_code='ACTUALIZACION_CARD_LF' and step_id='baseline_read' and step_order=50 and status='CANDIDATO_READ_ONLY';

create or replace function public.lf_validate_card_reversible_baseline_v1(p_execution_id text,p_evidence_payload jsonb)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare v_execution public.lf_operation_execution%rowtype; v_card public.lf_activos%rowtype; v_binding jsonb; v_hash text; v_state text; v_expected_revision text; v_expected_anchor text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then return jsonb_build_object('valid',false,'code','BASELINE_EXECUTION_INVALID'); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','BASELINE_CARD_NOT_FOUND'); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then return jsonb_build_object('valid',false,'code','BASELINE_BINDING_MISSING'); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then return jsonb_build_object('valid',false,'code','BASELINE_PAYLOAD_INVALID'); end if;
  v_hash:=encode(extensions.digest(coalesce(p_evidence_payload->>'baseline_canonical_content',''),'sha256'),'hex');
  v_state:=v_card.estado_documental||'/'||v_card.estado_operativo||'/'||v_card.runtime_estado||'/'||v_card.impacto_automatico;
  v_expected_revision:=case when (v_binding->>'carrier_type')='GITHUB_FILE' then v_binding->>'provider_blob_sha' else v_binding->>'provider_revision_id' end;
  v_expected_anchor:=case when (v_binding->>'carrier_type')='GITHUB_FILE' then v_binding->>'path' else v_binding->>'block_anchor' end;
  if p_evidence_payload->'baseline_reversible' is distinct from 'true'::jsonb or nullif(p_evidence_payload->>'baseline_canonical_content','') is null or (p_evidence_payload->>'baseline_content_sha256') is distinct from v_hash or (p_evidence_payload->>'baseline_content_sha256') is distinct from (v_binding->>'content_sha256') or (p_evidence_payload->>'baseline_block_excerpt_hash') is distinct from (v_binding->>'content_sha256') or (p_evidence_payload->>'baseline_content_chars')::integer is distinct from length(p_evidence_payload->>'baseline_canonical_content') or (p_evidence_payload->>'baseline_identity') is distinct from v_execution.target_code or (p_evidence_payload->>'baseline_card_state') is distinct from v_state or (p_evidence_payload->>'baseline_carrier_type') is distinct from (v_binding->>'carrier_type') or (p_evidence_payload->>'baseline_carrier_ref') is distinct from (v_binding->>'carrier_ref') or (p_evidence_payload->>'baseline_block_anchor_or_path') is distinct from v_expected_anchor or (p_evidence_payload->>'baseline_carrier_revision') is distinct from v_expected_revision or (p_evidence_payload->>'baseline_anchor_start_index')::integer is distinct from (v_binding->>'anchor_start_index')::integer or (p_evidence_payload->>'baseline_last_bound_paragraph_end_index')::integer is distinct from (v_binding->>'last_bound_paragraph_end_index')::integer then return jsonb_build_object('valid',false,'code','BASELINE_REVERSIBILITY_OR_IDENTITY_MISMATCH'); end if;
  return jsonb_build_object('valid',true,'code','BASELINE_REVERSIBLE_EXACT','content_sha256',v_hash,'content_chars',length(p_evidence_payload->>'baseline_canonical_content'));
exception when invalid_text_representation or numeric_value_out_of_range then return jsonb_build_object('valid',false,'code','BASELINE_EVIDENCE_TYPE_INVALID'); end;
$function$;

create or replace function public.lf_prepare_card_rollback_intent_v1(p_execution_id text)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare v_execution public.lf_operation_execution%rowtype; v_card public.lf_activos%rowtype; v_binding jsonb; v_baseline public.lf_operation_execution_steps%rowtype; v_readback public.lf_operation_execution_steps%rowtype; v_baseline_check jsonb; v_current_revision text; v_intent jsonb; v_hash text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_EXECUTION_IDENTITY_INVALID'); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_CARD_NOT_FOUND'); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if (v_binding->>'carrier_type') is distinct from 'GOOGLE_DOC_EMBEDDED_BLOCK' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_PROVIDER_NOT_IMPLEMENTED','scope','GOOGLE_DOC_ONLY'); end if;
  select * into v_baseline from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='baseline_read' and step_order=50;
  if not found or v_baseline.status is distinct from 'STEP_PASS_WITH_EVIDENCE' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_REVERSIBLE_BASELINE_NOT_AVAILABLE'); end if;
  v_baseline_check:=public.lf_validate_card_reversible_baseline_v1(p_execution_id,v_baseline.evidence_payload);
  if (v_baseline_check->'valid') is distinct from 'true'::jsonb then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_BASELINE_NOT_EXACT','baseline_validation',v_baseline_check); end if;
  select * into v_readback from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='carrier_readback' and step_order=100;
  if not found or v_readback.status is distinct from 'STEP_PASS_WITH_EVIDENCE' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_POST_WRITE_READBACK_NOT_AVAILABLE'); end if;
  v_current_revision:=v_readback.evidence_payload->>'readback_carrier_revision';
  if nullif(v_current_revision,'') is null then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_CURRENT_REVISION_MISSING'); end if;
  v_intent:=jsonb_build_object('intent_schema','LF_CARD_ROLLBACK_INTENT_V1','execution_id',p_execution_id,'card_code',v_execution.target_code,'carrier_type','GOOGLE_DOC_EMBEDDED_BLOCK','carrier_ref',v_binding->>'carrier_ref','provider_guard_kind','requiredRevisionId','provider_precondition',jsonb_build_object('requiredRevisionId',v_current_revision),'bounded_target',jsonb_build_object('document_id',v_binding->>'document_id','tab_id',v_binding->>'tab_id','block_anchor',v_binding->>'block_anchor','anchor_start_index',v_baseline.evidence_payload->>'baseline_anchor_start_index','last_bound_paragraph_end_index',v_baseline.evidence_payload->>'baseline_last_bound_paragraph_end_index'),'restore_content',v_baseline.evidence_payload->>'baseline_canonical_content','restore_content_sha256',v_baseline.evidence_payload->>'baseline_content_sha256','baseline_evidence_ref',v_baseline.evidence_ref,'post_write_readback_ref',v_readback.evidence_ref,'provider_call_authorized',false,'rollback_write_executed',false,'requires_fresh_provider_revision_match',true);
  v_hash:=encode(extensions.digest(v_intent::text,'sha256'),'hex');
  return v_intent||jsonb_build_object('intent_sha256',v_hash,'outcome','ROLLBACK_INTENT_PREPARED_NO_WRITE','authorization_ceiling','NO_PROVIDER_CALL');
end;
$function$;
revoke execute on function public.lf_validate_card_reversible_baseline_v1(text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_prepare_card_rollback_intent_v1(text) from public,anon,authenticated;
grant execute on function public.lf_validate_card_reversible_baseline_v1(text,jsonb) to service_role;
grant execute on function public.lf_prepare_card_rollback_intent_v1(text) to service_role;