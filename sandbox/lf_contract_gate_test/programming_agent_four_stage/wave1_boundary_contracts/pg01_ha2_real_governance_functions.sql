-- Copied verbatim (pg_get_functiondef) from Supabase, read-only, 29-oct-2026. Registries are minimal sandbox mirrors.
CREATE TABLE public.lf_capability_current(capability_code text PRIMARY KEY,version text NOT NULL,manifest_sha256 text NOT NULL,previous_version text,promoted_at timestamptz DEFAULT now(),promoted_by_execution_id text,promotion_reason text);
CREATE TABLE public.lf_capability_version_registry(capability_code text,version text,version_major int,manifest jsonb,PRIMARY KEY(capability_code,version));
CREATE TABLE public.lf_capability_registry(capability_code text PRIMARY KEY,status text DEFAULT 'ACTIVE',entry_guard_required boolean DEFAULT true,entry_guard_code text DEFAULT 'ORCHESTRATOR_EXECUTION_GUARD_V1');
CREATE TABLE public.lf_operation_registry(operation_code text PRIMARY KEY,operation_family text,lifecycle_state_code text,version text);
CREATE TABLE private.lf_evidence_resolver_registry_v1(resolver_id text PRIMARY KEY,provider text,verification_method text,trust_level text,active boolean DEFAULT true);

CREATE OR REPLACE FUNCTION public.fn_lf_operation_reserve_execution_v1(p_execution_id text, p_operation_code text, p_target_type text, p_target_code text, p_idempotency_key text, p_request_sha256 text, p_actor_execution_id text, p_target_repo text DEFAULT NULL::text, p_target_path text DEFAULT NULL::text, p_manifest jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_row public.lf_operation_execution%rowtype;
  v_inserted boolean := false;
begin
  if btrim(coalesce(p_execution_id,''))='' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_operation_code,''))='' then raise exception 'INVALID_OPERATION_CODE'; end if;
  if btrim(coalesce(p_target_type,''))='' or btrim(coalesce(p_target_code,''))='' then raise exception 'INVALID_TARGET'; end if;
  if btrim(coalesce(p_idempotency_key,''))='' or length(p_idempotency_key)>200 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  if coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_REQUEST_SHA256'; end if;
  if btrim(coalesce(p_actor_execution_id,''))='' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;
  if p_manifest is null or jsonb_typeof(p_manifest)<>'object' then raise exception 'INVALID_MANIFEST'; end if;
  insert into public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,target_repo,target_path,
    idempotency_key,request_sha256,manifest,created_by_execution_id
  ) values (
    p_execution_id,p_operation_code,p_target_type,p_target_code,p_target_repo,p_target_path,
    p_idempotency_key,p_request_sha256,p_manifest,p_actor_execution_id
  )
  on conflict (operation_code,idempotency_key) where idempotency_key is not null do nothing
  returning * into v_row;
  if v_row.execution_id is not null then
    v_inserted := true;
  else
    select * into v_row from public.lf_operation_execution where operation_code=p_operation_code and idempotency_key=p_idempotency_key;
  end if;
  if v_row.execution_id is null then raise exception 'IDEMPOTENCY_RESERVATION_UNAVAILABLE'; end if;
  if v_row.request_sha256 is distinct from p_request_sha256 then raise exception 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST'; end if;
  if v_row.target_type is distinct from p_target_type or v_row.target_code is distinct from p_target_code
     or v_row.target_repo is distinct from p_target_repo or v_row.target_path is distinct from p_target_path then
    raise exception 'IDEMPOTENCY_REPLAY_TARGET_MISMATCH';
  end if;
  return jsonb_build_object('result',case when v_inserted then 'RESERVED_NEW_EXECUTION' else 'REPLAY_EXISTING_EXECUTION' end,
    'execution_id',v_row.execution_id,'operation_code',v_row.operation_code,'idempotency_key',v_row.idempotency_key,
    'request_sha256',v_row.request_sha256,'status',v_row.status,'dispatch_permitted',v_inserted);
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_lf_orchestrator_dispatch_receipt_v1(p_orchestrator_execution_id text, p_consumer_execution_id text, p_capability_code text, p_plan_digest text, p_dispatch_scope jsonb, p_actor_execution_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  v_orch public.lf_operation_execution%rowtype; v_cons public.lf_operation_execution%rowtype;
  v_cap public.lf_capability_registry%rowtype; v_op public.lf_operation_registry%rowtype;
  v_payload jsonb; v_sha text; v_existing private.lf_orchestrator_dispatch_receipts_v1%rowtype; v_id uuid;
begin
  if btrim(coalesce(p_orchestrator_execution_id,''))='' or btrim(coalesce(p_consumer_execution_id,''))='' or btrim(coalesce(p_capability_code,''))='' then
    return jsonb_build_object('ready',false,'decision','BLOCK_INVALID_IDENTITY'); end if;
  if coalesce(p_plan_digest,'') !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_dispatch_scope) is distinct from 'object' then
    return jsonb_build_object('ready',false,'decision','BLOCK_INVALID_DISPATCH_CONTRACT'); end if;
  if p_actor_execution_id is distinct from p_orchestrator_execution_id then
    return jsonb_build_object('ready',false,'decision','BLOCK_ACTOR_NOT_ORCHESTRATOR'); end if;
  select * into v_orch from public.lf_operation_execution where execution_id=p_orchestrator_execution_id;
  if not found or v_orch.status<>'IN_PROGRESS' then return jsonb_build_object('ready',false,'decision','BLOCK_ORCHESTRATOR_EXECUTION_NOT_ACTIVE'); end if;
  select * into v_op from public.lf_operation_registry where operation_code=v_orch.operation_code;
  if not found or v_op.operation_family<>'ORCHESTRATION' or v_op.lifecycle_state_code<>'OP_OPERATIONAL' then
    return jsonb_build_object('ready',false,'decision','BLOCK_NOT_OPERATIONAL_ORCHESTRATOR','operation_code',v_orch.operation_code); end if;
  select * into v_cons from public.lf_operation_execution where execution_id=p_consumer_execution_id;
  if not found or v_cons.status<>'IN_PROGRESS' then return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_EXECUTION_NOT_ACTIVE'); end if;
  if v_cons.manifest->>'orchestrator_execution_id' is distinct from p_orchestrator_execution_id
     or v_cons.manifest->>'plan_digest' is distinct from p_plan_digest
     or v_cons.manifest->>'capability_code' is distinct from p_capability_code then
    return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_CROSSBIND_MISMATCH'); end if;
  select * into v_cap from public.lf_capability_registry where capability_code=p_capability_code and status='ACTIVE';
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_OR_INACTIVE_CAPABILITY'); end if;
  if not v_cap.entry_guard_required then return jsonb_build_object('ready',false,'decision','BLOCK_ENTRY_GUARD_POLICY_DISABLED'); end if;
  v_payload:=jsonb_build_object('schema_version','LF_ORCHESTRATOR_DISPATCH_RECEIPT_V1','orchestrator_execution_id',p_orchestrator_execution_id,
    'orchestrator_operation_code',v_orch.operation_code,'orchestrator_operation_version',v_op.version,'consumer_execution_id',p_consumer_execution_id,
    'capability_code',p_capability_code,'plan_digest',p_plan_digest,'dispatch_scope',p_dispatch_scope,'guard_code',v_cap.entry_guard_code);
  v_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from private.lf_orchestrator_dispatch_receipts_v1
   where orchestrator_execution_id=p_orchestrator_execution_id and consumer_execution_id=p_consumer_execution_id and capability_code=p_capability_code and plan_digest=p_plan_digest;
  if found then
    if v_existing.receipt_sha256<>v_sha then raise exception 'ORCHESTRATOR_DISPATCH_REPLAY_CONFLICT'; end if;
    return jsonb_build_object('ready',true,'decision','DISPATCH_RECEIPT_REPLAY','receipt_id',v_existing.receipt_id,'receipt_sha256',v_existing.receipt_sha256);
  end if;
  insert into private.lf_orchestrator_dispatch_receipts_v1(orchestrator_execution_id,consumer_execution_id,capability_code,plan_digest,dispatch_scope,
    orchestrator_operation_code,orchestrator_operation_version,guard_code,receipt_sha256,issued_by_execution_id)
  values (p_orchestrator_execution_id,p_consumer_execution_id,p_capability_code,p_plan_digest,p_dispatch_scope,
    v_orch.operation_code,v_op.version,v_cap.entry_guard_code,v_sha,p_actor_execution_id) returning receipt_id into v_id;
  return jsonb_build_object('ready',true,'decision','DISPATCH_RECEIPT_ISSUED','receipt_id',v_id,'receipt_sha256',v_sha,'guard_code',v_cap.entry_guard_code);
end; $function$;

CREATE OR REPLACE FUNCTION public.fn_lf_capability_orchestrator_entry_guard_v1(p_consumer_execution_id text, p_capability_code text, p_plan_digest text, p_dispatch_receipt_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  v_r private.lf_orchestrator_dispatch_receipts_v1%rowtype; v_orch public.lf_operation_execution%rowtype; v_cons public.lf_operation_execution%rowtype;
  v_cap public.lf_capability_registry%rowtype; v_op public.lf_operation_registry%rowtype; v_payload jsonb; v_sha text;
begin
  if p_dispatch_receipt_id is null then return jsonb_build_object('ready',false,'decision','BLOCK_MISSING_ORCHESTRATOR_DISPATCH_RECEIPT'); end if;
  select * into v_r from private.lf_orchestrator_dispatch_receipts_v1 where receipt_id=p_dispatch_receipt_id;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_ORCHESTRATOR_DISPATCH_RECEIPT'); end if;
  if v_r.consumer_execution_id<>p_consumer_execution_id or v_r.capability_code<>p_capability_code or v_r.plan_digest<>p_plan_digest then
    return jsonb_build_object('ready',false,'decision','BLOCK_DISPATCH_RECEIPT_CROSSBIND_MISMATCH'); end if;
  select * into v_cap from public.lf_capability_registry where capability_code=p_capability_code and status='ACTIVE';
  if not found or not v_cap.entry_guard_required or v_cap.entry_guard_code<>v_r.guard_code then
    return jsonb_build_object('ready',false,'decision','BLOCK_ENTRY_GUARD_POLICY_MISMATCH'); end if;
  select * into v_orch from public.lf_operation_execution where execution_id=v_r.orchestrator_execution_id;
  select * into v_cons from public.lf_operation_execution where execution_id=p_consumer_execution_id;
  if v_orch.execution_id is null or v_orch.status<>'IN_PROGRESS' then return jsonb_build_object('ready',false,'decision','BLOCK_ORCHESTRATOR_EXECUTION_NOT_ACTIVE'); end if;
  if v_cons.execution_id is null or v_cons.status<>'IN_PROGRESS' then return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_EXECUTION_NOT_ACTIVE'); end if;
  select * into v_op from public.lf_operation_registry where operation_code=v_orch.operation_code;
  if not found or v_op.operation_family<>'ORCHESTRATION' or v_op.lifecycle_state_code<>'OP_OPERATIONAL' then
    return jsonb_build_object('ready',false,'decision','BLOCK_NOT_OPERATIONAL_ORCHESTRATOR'); end if;
  if v_cons.manifest->>'orchestrator_execution_id' is distinct from v_r.orchestrator_execution_id
     or v_cons.manifest->>'plan_digest' is distinct from p_plan_digest
     or v_cons.manifest->>'capability_code' is distinct from p_capability_code then
    return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_CROSSBIND_MISMATCH'); end if;
  v_payload:=jsonb_build_object('schema_version','LF_ORCHESTRATOR_DISPATCH_RECEIPT_V1','orchestrator_execution_id',v_r.orchestrator_execution_id,
    'orchestrator_operation_code',v_r.orchestrator_operation_code,'orchestrator_operation_version',v_r.orchestrator_operation_version,
    'consumer_execution_id',v_r.consumer_execution_id,'capability_code',v_r.capability_code,'plan_digest',v_r.plan_digest,
    'dispatch_scope',v_r.dispatch_scope,'guard_code',v_r.guard_code);
  v_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  if v_sha<>v_r.receipt_sha256 then return jsonb_build_object('ready',false,'decision','BLOCK_DISPATCH_RECEIPT_DIGEST_MISMATCH'); end if;
  return jsonb_build_object('ready',true,'decision','ORCHESTRATOR_ENTRY_ACCEPTED','orchestrator_execution_id',v_r.orchestrator_execution_id,'receipt_id',v_r.receipt_id,'guard_code',v_r.guard_code);
end; $function$;

CREATE OR REPLACE FUNCTION private.fn_lf_capability_bind_core_v1(p_execution_id text, p_capability_code text, p_expected_manifest_sha256 text, p_actor_execution_id text)
 RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''
AS $function$
declare
  v_exec public.lf_operation_execution%rowtype; v_current public.lf_capability_current%rowtype; v_binding public.lf_capability_binding%rowtype;
  v_step_count integer := 0; v_lease_active boolean := false; v_current_major integer; v_bound_major integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_execution_id || ':' || p_capability_code,0));
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_EXECUTION'); end if;
  select count(*)::int into v_step_count from public.lf_operation_execution_steps where execution_id=p_execution_id;
  v_lease_active := v_exec.lease_owner is not null and (v_exec.lease_expires_at is null or v_exec.lease_expires_at > now());
  select * into v_current from public.lf_capability_current where capability_code=p_capability_code;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_NO_CURRENT_CAPABILITY'); end if;
  if p_expected_manifest_sha256 is null or p_expected_manifest_sha256 <> v_current.manifest_sha256 then
    return jsonb_build_object('ready',false,'decision','BLOCK_CURRENTNESS_MISMATCH','expected',p_expected_manifest_sha256,'observed',v_current.manifest_sha256); end if;
  select * into v_binding from public.lf_capability_binding where execution_id=p_execution_id and capability_code=p_capability_code;
  if not found then
    if v_step_count<>0 then return jsonb_build_object('ready',false,'decision','LEGACY_EXECUTION_MIGRATION_GATE','step_count',v_step_count); end if;
    if v_lease_active then return jsonb_build_object('ready',false,'decision','BLOCK_ACTIVE_LEASE_UNBOUND'); end if;
    insert into public.lf_capability_binding(execution_id,capability_code,bound_version,bound_manifest_sha256,binding_mode,binding_state,step_count_at_bind,rebind_count,bound_by_execution_id,last_checked_by_execution_id)
    values(p_execution_id,p_capability_code,v_current.version,v_current.manifest_sha256,'INITIAL','BOUND',0,0,p_actor_execution_id,p_actor_execution_id);
    return jsonb_build_object('ready',true,'decision','BOUND_CURRENT','version',v_current.version,'manifest_sha256',v_current.manifest_sha256);
  end if;
  if v_binding.bound_version=v_current.version and v_binding.bound_manifest_sha256=v_current.manifest_sha256 then
    update public.lf_capability_binding set last_checked_at=now(),last_checked_by_execution_id=p_actor_execution_id where execution_id=p_execution_id and capability_code=p_capability_code;
    return jsonb_build_object('ready',true,'decision','READY_CURRENT','version',v_current.version,'manifest_sha256',v_current.manifest_sha256);
  end if;
  return jsonb_build_object('ready',false,'decision','SANDBOX_TRUNCATED_BRANCH');
end; $function$;

CREATE OR REPLACE FUNCTION public.fn_lf_capability_bind_from_orchestrator_v1(p_execution_id text, p_capability_code text, p_expected_manifest_sha256 text, p_plan_digest text, p_dispatch_receipt_id uuid, p_actor_execution_id text)
 RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''
AS $function$
declare v_guard jsonb; v_bind jsonb;
begin
  v_guard:=public.fn_lf_capability_orchestrator_entry_guard_v1(p_execution_id,p_capability_code,p_plan_digest,p_dispatch_receipt_id);
  if coalesce((v_guard->>'ready')::boolean,false) is not true then return v_guard; end if;
  v_bind:=private.fn_lf_capability_bind_core_v1(p_execution_id,p_capability_code,p_expected_manifest_sha256,p_actor_execution_id);
  return jsonb_build_object('ready',coalesce((v_bind->>'ready')::boolean,false),'entry_guard',v_guard,'binding',v_bind);
end; $function$;

CREATE OR REPLACE FUNCTION public.lf_independent_review_begin_v3(p_execution_id text, p_subject_type text, p_subject_ref text, p_subject_sha256 text, p_source_head_sha text, p_subject_receipt_id uuid, p_producer_execution_id text, p_expected_capability_manifest_sha256 text, p_plan_digest text, p_dispatch_receipt_id uuid, p_request_sha256 text, p_idempotency_key text, p_actor_execution_id text, p_manifest jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  v_subject private.lf_evidence_ledger_v1%rowtype; v_current public.lf_capability_current%rowtype;
  v_version public.lf_capability_version_registry%rowtype; v_reserve jsonb; v_bind jsonb; v_manifest jsonb;
begin
  if nullif(btrim(coalesce(p_subject_type,'')),'') is null then return jsonb_build_object('result','BLOCKED','code','SUBJECT_TYPE_MISSING'); end if;
  if jsonb_typeof(coalesce(p_manifest->'required_dimensions','null'::jsonb))<>'array' or jsonb_array_length(p_manifest->'required_dimensions')=0 then
    return jsonb_build_object('result','BLOCKED','code','REQUIRED_DIMENSIONS_MISSING'); end if;
  if coalesce((p_manifest->>'review_required')::boolean,true) is not true then return jsonb_build_object('result','BLOCKED','code','REVIEW_NOT_REQUIRED'); end if;
  if coalesce(p_subject_sha256,'') !~ '^[0-9a-f]{64}$' or coalesce(p_source_head_sha,'') !~ '^[0-9a-f]{40}$' then
    return jsonb_build_object('result','BLOCKED','code','SUBJECT_HASH_INVALID'); end if;
  if nullif(btrim(p_subject_ref),'') is null or nullif(btrim(p_producer_execution_id),'') is null then
    return jsonb_build_object('result','BLOCKED','code','SUBJECT_OR_PRODUCER_IDENTITY_MISSING'); end if;
  if p_execution_id=p_producer_execution_id then return jsonb_build_object('result','BLOCKED','code','BUILDER_REVIEWER_NOT_INDEPENDENT'); end if;
  select * into v_subject from private.lf_evidence_ledger_v1 where receipt_id=p_subject_receipt_id;
  if not found or v_subject.verification_state<>'VERIFIED' or v_subject.subject_type<>p_subject_type or v_subject.subject_ref<>p_subject_ref
     or v_subject.subject_sha256<>p_subject_sha256 or v_subject.source_head_sha<>p_source_head_sha then
    return jsonb_build_object('result','BLOCKED','code','SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID'); end if;
  select * into v_current from public.lf_capability_current where capability_code='INDEPENDENT_ASSURANCE';
  if not found then return jsonb_build_object('result','BLOCKED','code','BLOCK_NO_CURRENT_CAPABILITY'); end if;
  if v_current.manifest_sha256<>p_expected_capability_manifest_sha256 then return jsonb_build_object('result','BLOCKED','code','BLOCK_CURRENTNESS_MISMATCH'); end if;
  select * into v_version from public.lf_capability_version_registry where capability_code='INDEPENDENT_ASSURANCE' and version=v_current.version;
  if not found or coalesce(v_version.manifest#>>'{contract,subject_contract,mode}','')<>'CONTRACT_DRIVEN_ANY_SUBJECT'
     or coalesce((v_version.manifest#>>'{contract,subject_contract,subject_type_whitelist}')::boolean,true) is not false then
    return jsonb_build_object('result','BLOCKED','code','GENERIC_SUBJECT_CONTRACT_NOT_CURRENT'); end if;
  v_manifest:=p_manifest||jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','capability_manifest_sha256',v_current.manifest_sha256,
    'subject_type',p_subject_type,'subject_ref',p_subject_ref,'subject_sha256',p_subject_sha256,'source_head_sha',p_source_head_sha,
    'subject_receipt_id',p_subject_receipt_id::text,'producer_execution_id',p_producer_execution_id,'review_required',true,
    'required_dimensions',p_manifest->'required_dimensions','runtime_activation',false,'production_activation',false,'business_effect_allowed',false);
  v_reserve:=public.fn_lf_operation_reserve_execution_v1(p_execution_id,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',p_subject_type,p_subject_ref,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,null,null,v_manifest);
  if v_reserve->>'status'<>'IN_PROGRESS' then raise exception 'BLOCK_T_INDEP_REVIEW_RESERVATION:%',v_reserve; end if;
  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(p_execution_id,'INDEPENDENT_ASSURANCE',p_expected_capability_manifest_sha256,
    p_plan_digest,p_dispatch_receipt_id,p_actor_execution_id);
  if coalesce((v_bind->>'ready')::boolean,false) is not true then raise exception 'BLOCK_T_INDEP_CAPABILITY_BIND:%',v_bind; end if;
  update public.lf_operation_execution set manifest=manifest||jsonb_build_object('capability_binding_receipt',v_bind),
      updated_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id where execution_id=p_execution_id;
  return v_reserve||jsonb_build_object('capability_binding_receipt',v_bind,'subject_receipt_id',p_subject_receipt_id::text,'next_step','route_bind');
end
$function$;
