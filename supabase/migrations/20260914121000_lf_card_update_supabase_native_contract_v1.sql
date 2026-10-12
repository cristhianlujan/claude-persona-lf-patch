-- LF_CARD_UPDATE_SUPABASE_NATIVE_CONTRACT_V1
-- Cards must live entirely in Supabase. External Card carriers are forbidden.
-- No provider write, Google Drive, Google Docs or GitHub content route is accepted by ACTUALIZACION_CARD_LF.

-- Contract/evidence vocabulary: remove external-provider semantics.
update public.lf_operation_step_judge_bindings b
set required_evidence_keys = case b.step_order
  when 30 then '["content_store_type","content_ref","parent_asset_code","parent_source_ref","supabase_authority_ref","content_binding_ref"]'::jsonb
  when 40 then '["parent_source_ref","content_ref","current_content_version","source_currentness","supabase_native_only"]'::jsonb
  when 50 then '["baseline_card_state","baseline_content_row_id","baseline_content_version","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_content_ref","baseline_reversible"]'::jsonb
  when 60 then '["defect","root_cause","minimal_patch_scope","preserved_constraints","authority_boundaries_preserved","supabase_content_route_preserved"]'::jsonb
  when 70 then '["positive_cases","negative_cases","adversarial_cases","stale_content_revision_cases","wrong_content_binding_cases","holdout"]'::jsonb
  when 80 then '["execution_id","card_code","current_source_policy_code","current_source_policy_version","current_source_policy_sha","supabase_authority_ref","content_binding_ref","content_row_id","current_content_version","content_sha256","change_scope_ref","regression_plan_ref","write_guard","pre_write_gate_passed"]'::jsonb
  when 90 then '["content_store_type","write_route","write_receipt","new_content_version","new_content_sha256","supersedes_content_row_id","optimistic_lock_applied"]'::jsonb
  when 100 then '["readback_content_row_id","readback_content_version","readback_content_hash","parent_source_preserved","independent_readback"]'::jsonb
  when 110 then '["content_binding_match","version_match","content_hash_match","identity_match","negative_regressions","source_policy_match"]'::jsonb
  when 130 then '["before_after_matrix","wrong_content_binding_negative","stale_content_revision_negative","missing_current_content_negative","holdout_result"]'::jsonb
  when 150 then '["result","card_code","content_ref","evidence_refs","open_blockers","next_gate"]'::jsonb
  else b.required_evidence_keys end,
    updated_by_execution_id='EXEC-CARD-UPDATE-I7-REMEDIATION-20260913-001',
    updated_at=now()
where b.operation_code='ACTUALIZACION_CARD_LF'
  and b.status='CANDIDATO_READ_ONLY'
  and b.step_order in (30,40,50,60,70,80,90,100,110,130,150);

update public.lf_operation_step_contracts c
set required_evidence_keys = case c.step_order
  when 30 then '["content_store_type","content_ref","parent_asset_code","parent_source_ref","supabase_authority_ref","content_binding_ref"]'::jsonb
  when 40 then '["parent_source_ref","content_ref","current_content_version","source_currentness","supabase_native_only"]'::jsonb
  when 50 then '["baseline_card_state","baseline_content_row_id","baseline_content_version","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_content_ref","baseline_reversible"]'::jsonb
  when 60 then '["defect","root_cause","minimal_patch_scope","preserved_constraints","authority_boundaries_preserved","supabase_content_route_preserved"]'::jsonb
  when 70 then '["positive_cases","negative_cases","adversarial_cases","stale_content_revision_cases","wrong_content_binding_cases","holdout"]'::jsonb
  when 80 then '["execution_id","card_code","current_source_policy_code","current_source_policy_version","current_source_policy_sha","supabase_authority_ref","content_binding_ref","content_row_id","current_content_version","content_sha256","change_scope_ref","regression_plan_ref","write_guard","pre_write_gate_passed"]'::jsonb
  when 90 then '["content_store_type","write_route","write_receipt","new_content_version","new_content_sha256","supersedes_content_row_id","optimistic_lock_applied"]'::jsonb
  when 100 then '["readback_content_row_id","readback_content_version","readback_content_hash","parent_source_preserved","independent_readback"]'::jsonb
  when 110 then '["content_binding_match","version_match","content_hash_match","identity_match","negative_regressions","source_policy_match"]'::jsonb
  when 130 then '["before_after_matrix","wrong_content_binding_negative","stale_content_revision_negative","missing_current_content_negative","holdout_result"]'::jsonb
  when 150 then '["result","card_code","content_ref","evidence_refs","open_blockers","next_gate"]'::jsonb
  else c.required_evidence_keys end,
    output_payload = case when c.step_order in (30,40,50,60,70,80,90,100,110,130,150) then
      case c.step_order
        when 30 then '["content_store_type","content_ref","parent_asset_code","parent_source_ref","supabase_authority_ref","content_binding_ref"]'::jsonb
        when 40 then '["parent_source_ref","content_ref","current_content_version","source_currentness","supabase_native_only"]'::jsonb
        when 50 then '["baseline_card_state","baseline_content_row_id","baseline_content_version","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_content_ref","baseline_reversible"]'::jsonb
        when 60 then '["defect","root_cause","minimal_patch_scope","preserved_constraints","authority_boundaries_preserved","supabase_content_route_preserved"]'::jsonb
        when 70 then '["positive_cases","negative_cases","adversarial_cases","stale_content_revision_cases","wrong_content_binding_cases","holdout"]'::jsonb
        when 80 then '["execution_id","card_code","current_source_policy_code","current_source_policy_version","current_source_policy_sha","supabase_authority_ref","content_binding_ref","content_row_id","current_content_version","content_sha256","change_scope_ref","regression_plan_ref","write_guard","pre_write_gate_passed"]'::jsonb
        when 90 then '["content_store_type","write_route","write_receipt","new_content_version","new_content_sha256","supersedes_content_row_id","optimistic_lock_applied"]'::jsonb
        when 100 then '["readback_content_row_id","readback_content_version","readback_content_hash","parent_source_preserved","independent_readback"]'::jsonb
        when 110 then '["content_binding_match","version_match","content_hash_match","identity_match","negative_regressions","source_policy_match"]'::jsonb
        when 130 then '["before_after_matrix","wrong_content_binding_negative","stale_content_revision_negative","missing_current_content_negative","holdout_result"]'::jsonb
        when 150 then '["result","card_code","content_ref","evidence_refs","open_blockers","next_gate"]'::jsonb end
      else c.output_payload end,
    purpose = case c.step_order
      when 30 then 'Resolve canonical Supabase Card content binding'
      when 40 then 'Read parent relation and current Supabase Card content only'
      when 50 then 'Freeze reversible Supabase Card content baseline'
      when 80 then 'Bind source policy, Supabase authority, exact current content revision and optimistic write guard before write'
      when 90 then 'Insert a new immutable Supabase Card content version under optimistic lock'
      when 100 then 'Read back the newly inserted Supabase Card content version independently'
      else c.purpose end,
    notes=case c.step_order
      when 80 then 'External Card carriers are forbidden. Gate validates current lf_card_content_versions row/version/SHA and EXPECTED_CURRENT_CONTENT_ROW_AND_SHA.'
      when 90 then 'No external provider dispatch. Supabase immutable version insert only.'
      else c.notes end,
    updated_by_execution_id='EXEC-CARD-UPDATE-I7-REMEDIATION-20260913-001',
    updated_at=now()
where c.operation_code='ACTUALIZACION_CARD_LF'
  and c.status='CANDIDATO_READ_ONLY'
  and c.step_order in (30,40,50,60,70,80,90,100,110,130,150);

update public.lf_operation_judges
set pass_if='["source policy v1.4 exact","Supabase authority exact","content binding exact","current content revision exact","change_scope present","regression_plan present","Supabase context exact","optimistic write guard planned"]'::jsonb,
    fail_if='["source policy stale","Supabase authority missing","content binding missing","external Card carrier present","change_scope missing","regression_plan missing","current content revision stale","optimistic write guard missing"]'::jsonb,
    updated_by_execution_id='EXEC-CARD-UPDATE-I7-REMEDIATION-20260913-001',
    updated_at=now()
where operation_code='ACTUALIZACION_CARD_LF'
  and judge_code='JUDGE-ACTUALIZACION-CARD-LF-PREWRITE-TRUST-v2'
  and status='CANDIDATO_READ_ONLY';

create or replace function public.lf_validate_card_reversible_baseline_v1(p_execution_id text,p_evidence_payload jsonb)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_binding jsonb;
  v_content public.lf_card_content_versions%rowtype;
  v_state text;
  v_hash text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','BASELINE_EXECUTION_INVALID');
  end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','BASELINE_CARD_NOT_FOUND'); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if v_binding is null or (v_binding->>'carrier_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT' or (v_binding->>'carrier_authority')::boolean is distinct from true then
    return jsonb_build_object('valid',false,'code','EXTERNAL_CARD_CARRIER_FORBIDDEN');
  end if;
  select * into v_content from public.lf_card_content_versions where id=(v_binding->>'content_row_id')::bigint and card_code=v_execution.target_code and status='CURRENT';
  if not found then return jsonb_build_object('valid',false,'code','BASELINE_CURRENT_CONTENT_NOT_EXACT'); end if;
  if v_content.content_sha256 is distinct from encode(extensions.digest(v_content.content_text,'sha256'),'hex') or v_content.content_chars is distinct from length(v_content.content_text) then
    return jsonb_build_object('valid',false,'code','BASELINE_CURRENT_CONTENT_INTEGRITY_FAILED');
  end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then return jsonb_build_object('valid',false,'code','BASELINE_PAYLOAD_INVALID'); end if;
  v_hash:=encode(extensions.digest(coalesce(p_evidence_payload->>'baseline_canonical_content',''),'sha256'),'hex');
  v_state:=v_card.estado_documental||'/'||v_card.estado_operativo||'/'||v_card.runtime_estado||'/'||v_card.impacto_automatico;
  if p_evidence_payload->'baseline_reversible' is distinct from 'true'::jsonb
     or (p_evidence_payload->>'baseline_identity') is distinct from v_execution.target_code
     or (p_evidence_payload->>'baseline_card_state') is distinct from v_state
     or (p_evidence_payload->>'baseline_content_row_id')::bigint is distinct from v_content.id
     or (p_evidence_payload->>'baseline_content_version') is distinct from v_content.content_version
     or (p_evidence_payload->>'baseline_content_ref') is distinct from ('supabase://public/lf_card_content_versions/'||v_content.id)
     or (p_evidence_payload->>'baseline_canonical_content') is distinct from v_content.content_text
     or (p_evidence_payload->>'baseline_content_chars')::integer is distinct from v_content.content_chars
     or (p_evidence_payload->>'baseline_content_sha256') is distinct from v_content.content_sha256
     or v_hash is distinct from v_content.content_sha256 then
    return jsonb_build_object('valid',false,'code','BASELINE_SUPABASE_CONTENT_MISMATCH');
  end if;
  return jsonb_build_object('valid',true,'code','BASELINE_SUPABASE_REVERSIBLE_EXACT','content_row_id',v_content.id,'content_version',v_content.content_version,'content_sha256',v_content.content_sha256);
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('valid',false,'code','BASELINE_EVIDENCE_TYPE_INVALID');
end;
$function$;

create or replace function public.lf_validate_card_update_trust_v1(p_execution_id text,p_step_id text,p_evidence_payload jsonb)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_binding jsonb;
  v_content public.lf_card_content_versions%rowtype;
  v_policy_version text;
  v_policy_sha text;
  v_policy_count integer;
  v_change_ref text;
  v_regression_ref text;
  v_binding_ref text;
  v_assertions jsonb:=jsonb_build_array('source policy v1.4 exact','Supabase authority exact','content binding exact','current content revision exact','change_scope present','regression_plan present','Supabase context exact','optimistic write guard planned');
begin
  if p_step_id is distinct from 'pre_write_execution_binding_gate' then
    return jsonb_build_object('valid',true,'code','TRUST_GATE_NOT_APPLICABLE','server_assertions',v_assertions,'server_hard_fails','[]'::jsonb);
  end if;
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_EXECUTION_IDENTITY_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','CARD_TRUST_TARGET_NOT_FOUND','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if v_binding is null or (v_binding->>'carrier_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT' or (v_binding->>'carrier_authority')::boolean is distinct from true
     or (v_card.metadata->'source_governance'->>'external_card_carriers_allowed')::boolean is distinct from false then
    return jsonb_build_object('valid',false,'code','EXTERNAL_CARD_CARRIER_FORBIDDEN','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('external Card carrier present'));
  end if;
  select * into v_content from public.lf_card_content_versions where id=(v_binding->>'content_row_id')::bigint and card_code=v_execution.target_code and status='CURRENT';
  if not found then return jsonb_build_object('valid',false,'code','CARD_TRUST_CURRENT_CONTENT_NOT_EXACT','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  if v_content.content_sha256 is distinct from encode(extensions.digest(v_content.content_text,'sha256'),'hex') or v_content.content_chars is distinct from length(v_content.content_text)
     or (v_binding->>'content_version') is distinct from v_content.content_version or (v_binding->>'content_sha256') is distinct from v_content.content_sha256 then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CURRENT_CONTENT_INTEGRITY_OR_BINDING_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  select count(*),min(policy_version),min(policy_sha) into v_policy_count,v_policy_version,v_policy_sha from public.v_lf_operation_policy_snapshot where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_count<>1 or v_policy_version is distinct from 'v1.4-transversal-supabase-authority-visual-support' or v_policy_sha is distinct from '5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_NOT_EXACT','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  select evidence_ref into v_change_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope' and status='STEP_PASS_WITH_EVIDENCE';
  select evidence_ref into v_regression_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan' and status='STEP_PASS_WITH_EVIDENCE';
  if v_change_ref is null or v_regression_ref is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REFS_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  v_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1';
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object'
     or (p_evidence_payload->>'execution_id') is distinct from p_execution_id
     or (p_evidence_payload->>'card_code') is distinct from v_execution.target_code
     or (p_evidence_payload->>'current_source_policy_code') is distinct from 'POL-LF-SOURCE-RESOLUTION'
     or (p_evidence_payload->>'current_source_policy_version') is distinct from v_policy_version
     or (p_evidence_payload->>'current_source_policy_sha') is distinct from v_policy_sha
     or (p_evidence_payload->>'supabase_authority_ref') is distinct from (v_binding->>'operational_authority_ref')
     or (p_evidence_payload->>'content_binding_ref') is distinct from v_binding_ref
     or (p_evidence_payload->>'content_row_id')::bigint is distinct from v_content.id
     or (p_evidence_payload->>'current_content_version') is distinct from v_content.content_version
     or (p_evidence_payload->>'content_sha256') is distinct from v_content.content_sha256
     or (p_evidence_payload->>'change_scope_ref') is distinct from v_change_ref
     or (p_evidence_payload->>'regression_plan_ref') is distinct from v_regression_ref
     or (p_evidence_payload->>'write_guard') is distinct from 'EXPECTED_CURRENT_CONTENT_ROW_AND_SHA'
     or p_evidence_payload->'pre_write_gate_passed' is distinct from 'true'::jsonb then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_SUPABASE_PREWRITE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  return jsonb_build_object('valid',true,'code','CARD_TRUST_SUPABASE_EXACT','server_assertions',v_assertions,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('content_row_id',v_content.id,'content_version',v_content.content_version,'content_sha256',v_content.content_sha256));
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('valid',false,'code','CARD_TRUST_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
end;
$function$;

create or replace function public.lf_validate_card_update_step_evidence_v5(p_execution_id text,p_step_id text,p_evidence_payload jsonb)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_binding jsonb;
  v_content public.lf_card_content_versions%rowtype;
  v_parent_count integer;
  v_parent_code text;
  v_parent_ref text;
  v_binding_ref text;
  v_baseline jsonb;
  v_assertions jsonb:=jsonb_build_array('required evidence present','prior required steps clean','Supabase operational authority preserved','external carrier not used as authority');
begin
  if p_step_id='pre_write_execution_binding_gate' then return public.lf_validate_card_update_trust_v1(p_execution_id,p_step_id,p_evidence_payload); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then return jsonb_build_object('valid',false,'code','CARD_STEP_EXECUTION_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','CARD_STEP_TARGET_NOT_FOUND','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if v_binding is null or (v_binding->>'carrier_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT' or (v_card.metadata->'source_governance'->>'external_card_carriers_allowed')::boolean is distinct from false then return jsonb_build_object('valid',false,'code','EXTERNAL_CARD_CARRIER_FORBIDDEN','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('external carrier used as authority')); end if;
  select * into v_content from public.lf_card_content_versions where id=(v_binding->>'content_row_id')::bigint and card_code=v_execution.target_code and status='CURRENT';
  if not found or v_content.content_sha256 is distinct from encode(extensions.digest(v_content.content_text,'sha256'),'hex') or v_content.content_chars is distinct from length(v_content.content_text) then return jsonb_build_object('valid',false,'code','CARD_STEP_CURRENT_CONTENT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  select count(*),min(relacionado_codigo) into v_parent_count,v_parent_code from public.lf_activo_relaciones where codigo_activo=v_execution.target_code and relacion_tipo='HIJO_DE';
  if v_parent_count<>1 or v_parent_code is null then return jsonb_build_object('valid',false,'code','CARD_STEP_PARENT_NOT_EXACT','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  v_parent_ref:='supabase://public/lf_activos/'||v_parent_code;
  v_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1';
  if p_step_id='router' then
    if (select count(*) from public.lf_router_action_registry where asset_type='CARD' and action_code='CARD_UPDATE' and status in ('ACTIVE','CANDIDATO_READ_ONLY'))<>0 or (p_evidence_payload->>'action') is distinct from 'CARD_UPDATE' or (p_evidence_payload->>'router_state') is distinct from 'CANDIDATO_READ_ONLY_NO_ROUTER' then return jsonb_build_object('valid',false,'code','CARD_STEP_ROUTER_STATE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='card_resolve' then
    if (p_evidence_payload->>'card_code') is distinct from v_execution.target_code or (p_evidence_payload->>'card_id')::bigint is distinct from v_card.id or p_evidence_payload->'exact_card_resolved' is distinct from 'true'::jsonb or p_evidence_payload->'active_before' is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_STEP_CARD_RESOLVE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='carrier_resolve' then
    if (p_evidence_payload->>'content_store_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT' or (p_evidence_payload->>'content_ref') is distinct from ('supabase://public/lf_card_content_versions/'||v_content.id) or (p_evidence_payload->>'parent_asset_code') is distinct from v_parent_code or (p_evidence_payload->>'parent_source_ref') is distinct from v_parent_ref or (p_evidence_payload->>'supabase_authority_ref') is distinct from (v_binding->>'operational_authority_ref') or (p_evidence_payload->>'content_binding_ref') is distinct from v_binding_ref then return jsonb_build_object('valid',false,'code','CARD_STEP_SUPABASE_CONTENT_RESOLVE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='parent_source_read' then
    if (p_evidence_payload->>'parent_source_ref') is distinct from v_parent_ref or (p_evidence_payload->>'content_ref') is distinct from ('supabase://public/lf_card_content_versions/'||v_content.id) or (p_evidence_payload->>'current_content_version') is distinct from v_content.content_version or (p_evidence_payload->>'source_currentness') is distinct from 'SUPABASE_CURRENT' or p_evidence_payload->'supabase_native_only' is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_STEP_SUPABASE_CURRENTNESS_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='baseline_read' then
    v_baseline:=public.lf_validate_card_reversible_baseline_v1(p_execution_id,p_evidence_payload);
    if (v_baseline->'valid') is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_STEP_BASELINE_REVERSIBILITY_FAILED','baseline_validation',v_baseline,'server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='change_scope' then
    if nullif(p_evidence_payload->>'defect','') is null or nullif(p_evidence_payload->>'root_cause','') is null or jsonb_typeof(p_evidence_payload->'minimal_patch_scope') is distinct from 'array' or jsonb_array_length(p_evidence_payload->'minimal_patch_scope')=0 or jsonb_typeof(p_evidence_payload->'preserved_constraints') is distinct from 'array' or jsonb_array_length(p_evidence_payload->'preserved_constraints')=0 or p_evidence_payload->'authority_boundaries_preserved' is distinct from 'true'::jsonb or p_evidence_payload->'supabase_content_route_preserved' is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_STEP_CHANGE_SCOPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='regression_plan' then
    if jsonb_typeof(p_evidence_payload->'positive_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'negative_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'adversarial_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'stale_content_revision_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'wrong_content_binding_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'holdout') is distinct from 'array' or jsonb_array_length(p_evidence_payload->'positive_cases')=0 or jsonb_array_length(p_evidence_payload->'negative_cases')=0 or jsonb_array_length(p_evidence_payload->'adversarial_cases')=0 or jsonb_array_length(p_evidence_payload->'stale_content_revision_cases')=0 or jsonb_array_length(p_evidence_payload->'wrong_content_binding_cases')=0 or jsonb_array_length(p_evidence_payload->'holdout')=0 then return jsonb_build_object('valid',false,'code','CARD_STEP_REGRESSION_PLAN_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  else
    return jsonb_build_object('valid',false,'code','CARD_STEP_NOT_SUPPORTED_BY_V5','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  return jsonb_build_object('valid',true,'code','CARD_STEP_SUPABASE_EXACT','server_assertions',v_assertions,'server_hard_fails','[]'::jsonb,'content_row_id',v_content.id,'content_version',v_content.content_version);
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
end;
$function$;

create or replace function public.lf_record_card_operation_step_v1(p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,p_actor_execution_id text)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare v_step_order integer; v_server_validation jsonb;
begin
  select step_order into v_step_order from public.lf_operation_steps where operation_code='ACTUALIZACION_CARD_LF' and step_id=p_step_id and active is true;
  if v_step_order is null then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;
  if v_step_order>80 then
    v_server_validation:=jsonb_build_object('valid',false,'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I7','details',jsonb_build_object('step_order',v_step_order,'ceiling_step_order',80),'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested'));
  else
    v_server_validation:=public.lf_validate_card_update_step_evidence_v5(p_execution_id,p_step_id,p_evidence_payload);
  end if;
  return public.lf_record_operation_step_core_v1(p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,'ACTUALIZACION_CARD_LF','CARD','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',v_server_validation,true,'lf_record_card_operation_step_v1');
end;
$function$;

create or replace function public.lf_prepare_card_carrier_write_intent_v1(p_execution_id text)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_binding jsonb;
  v_content public.lf_card_content_versions%rowtype;
  v_step80 public.lf_operation_execution_steps%rowtype;
  v_intent jsonb;
  v_hash text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','CARD_WRITE_INTENT_EXECUTION_INVALID'); end if;
  select * into v_step80 from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate' and step_order=80 and status='STEP_PASS_WITH_EVIDENCE';
  if not found or (v_step80.evidence_payload->'trust_validation'->>'code') is distinct from 'CARD_TRUST_SUPABASE_EXACT' then return jsonb_build_object('outcome','BLOCKED','code','CARD_WRITE_INTENT_PREWRITE_NOT_EXACT'); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if (v_binding->>'carrier_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT' then return jsonb_build_object('outcome','BLOCKED','code','EXTERNAL_CARD_CARRIER_FORBIDDEN'); end if;
  select * into v_content from public.lf_card_content_versions where id=(v_binding->>'content_row_id')::bigint and card_code=v_execution.target_code and status='CURRENT';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','CARD_WRITE_INTENT_CURRENT_CONTENT_MISSING'); end if;
  v_intent:=jsonb_build_object('intent_schema','LF_CARD_SUPABASE_CONTENT_WRITE_INTENT_V1','execution_id',p_execution_id,'operation_code','ACTUALIZACION_CARD_LF','card_code',v_execution.target_code,'content_store_type','SUPABASE_NATIVE_CARD_CONTENT','write_route','SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT','current_content_row_id',v_content.id,'current_content_version',v_content.content_version,'current_content_sha256',v_content.content_sha256,'write_guard','EXPECTED_CURRENT_CONTENT_ROW_AND_SHA','write_precondition',jsonb_build_object('content_row_id',v_content.id,'content_version',v_content.content_version,'content_sha256',v_content.content_sha256),'write_authorized',false,'candidate_only',true,'generated_from','SUPABASE_OPERATION_PLUS_CURRENT_CONTENT_BINDING');
  v_hash:=encode(extensions.digest(v_intent::text,'sha256'),'hex');
  return v_intent||jsonb_build_object('intent_sha256',v_hash,'outcome','INTENT_PREPARED_NO_WRITE','authorization_ceiling','NO_WRITE');
end;
$function$;

create or replace function public.lf_prepare_card_rollback_intent_v1(p_execution_id text)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_baseline public.lf_operation_execution_steps%rowtype;
  v_readback public.lf_operation_execution_steps%rowtype;
  v_baseline_check jsonb;
  v_current public.lf_card_content_versions%rowtype;
  v_intent jsonb;
  v_hash text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_EXECUTION_IDENTITY_INVALID'); end if;
  select * into v_baseline from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='baseline_read' and step_order=50 and status='STEP_PASS_WITH_EVIDENCE';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_REVERSIBLE_BASELINE_NOT_AVAILABLE'); end if;
  v_baseline_check:=public.lf_validate_card_reversible_baseline_v1(p_execution_id,v_baseline.evidence_payload);
  if (v_baseline_check->'valid') is distinct from 'true'::jsonb then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_BASELINE_NOT_EXACT','baseline_validation',v_baseline_check); end if;
  select * into v_readback from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='carrier_readback' and step_order=100 and status='STEP_PASS_WITH_EVIDENCE';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_POST_WRITE_READBACK_NOT_AVAILABLE'); end if;
  select * into v_current from public.lf_card_content_versions where id=(v_readback.evidence_payload->>'readback_content_row_id')::bigint and card_code=v_execution.target_code and status='CURRENT';
  if not found or (v_readback.evidence_payload->>'readback_content_version') is distinct from v_current.content_version or (v_readback.evidence_payload->>'readback_content_hash') is distinct from v_current.content_sha256 then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_CURRENT_CONTENT_READBACK_MISMATCH'); end if;
  v_intent:=jsonb_build_object('intent_schema','LF_CARD_SUPABASE_ROLLBACK_INTENT_V1','execution_id',p_execution_id,'card_code',v_execution.target_code,'write_route','SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT','write_guard','EXPECTED_CURRENT_CONTENT_ROW_AND_SHA','write_precondition',jsonb_build_object('content_row_id',v_current.id,'content_version',v_current.content_version,'content_sha256',v_current.content_sha256),'restore_content',v_baseline.evidence_payload->>'baseline_canonical_content','restore_content_sha256',v_baseline.evidence_payload->>'baseline_content_sha256','restore_from_content_row_id',v_baseline.evidence_payload->>'baseline_content_row_id','write_authorized',false,'rollback_write_executed',false);
  v_hash:=encode(extensions.digest(v_intent::text,'sha256'),'hex');
  return v_intent||jsonb_build_object('intent_sha256',v_hash,'outcome','ROLLBACK_INTENT_PREPARED_NO_WRITE','authorization_ceiling','NO_WRITE');
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_READBACK_TYPE_INVALID');
end;
$function$;

revoke execute on function public.lf_validate_card_update_step_evidence_v5(text,text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_validate_card_update_step_evidence_v4(text,text,jsonb) from public,anon,authenticated,service_role;
revoke execute on function public.lf_validate_card_update_step_evidence_v3(text,text,jsonb) from public,anon,authenticated,service_role;
revoke execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_validate_card_reversible_baseline_v1(text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;
revoke execute on function public.lf_prepare_card_carrier_write_intent_v1(text) from public,anon,authenticated;
revoke execute on function public.lf_prepare_card_rollback_intent_v1(text) from public,anon,authenticated;
grant execute on function public.lf_validate_card_update_step_evidence_v5(text,text,jsonb) to service_role;
grant execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) to service_role;
grant execute on function public.lf_validate_card_reversible_baseline_v1(text,jsonb) to service_role;
grant execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) to service_role;
grant execute on function public.lf_prepare_card_carrier_write_intent_v1(text) to service_role;
grant execute on function public.lf_prepare_card_rollback_intent_v1(text) to service_role;
