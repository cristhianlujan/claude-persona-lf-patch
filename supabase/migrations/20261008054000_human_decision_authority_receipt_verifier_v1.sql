-- HUMAN_DECISION_AUTHORITY_RECEIPT_VERIFIER_V1
-- Adds a deterministic authority-receipt verifier/ingress for HUMAN_DECISION_ROUTING.
-- It does not activate any real human authority policy and does not cut over consumers.

create table if not exists private.lf_human_decision_authority_policies_v1 (
  authority_ref text not null,
  reviewer_role text not null,
  issuer_channel text not null,
  receipt_kind text not null default 'HUMAN_ROUTING_DECISION',
  status text not null default 'DISABLED',
  policy_sha256 text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text,
  primary key(authority_ref, reviewer_role),
  constraint lf_human_decision_authority_policies_v1_authority_ck
    check (length(btrim(authority_ref)) > 0),
  constraint lf_human_decision_authority_policies_v1_reviewer_ck
    check (length(btrim(reviewer_role)) > 0),
  constraint lf_human_decision_authority_policies_v1_channel_ck
    check (length(btrim(issuer_channel)) > 0),
  constraint lf_human_decision_authority_policies_v1_kind_ck
    check (receipt_kind='HUMAN_ROUTING_DECISION'),
  constraint lf_human_decision_authority_policies_v1_status_ck
    check (status in ('ACTIVE','DISABLED')),
  constraint lf_human_decision_authority_policies_v1_sha_ck
    check (policy_sha256 ~ '^[0-9a-f]{64}$'),
  constraint lf_human_decision_authority_policies_v1_metadata_ck
    check (jsonb_typeof(metadata)='object')
);

alter table private.lf_human_decision_authority_policies_v1 enable row level security;
revoke all on private.lf_human_decision_authority_policies_v1 from public,anon,authenticated;

create or replace function private.fn_lf_human_decision_authority_policy_sha_v1(
  p_authority_ref text,
  p_reviewer_role text,
  p_issuer_channel text,
  p_receipt_kind text,
  p_status text,
  p_metadata jsonb
)
returns text
language sql
immutable
set search_path=''
as $function$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'schema_version','lf-human-decision-authority-policy/v1',
          'authority_ref',p_authority_ref,
          'reviewer_role',p_reviewer_role,
          'issuer_channel',p_issuer_channel,
          'receipt_kind',p_receipt_kind,
          'status',p_status,
          'metadata',coalesce(p_metadata,'{}'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
$function$;

create or replace function private.fn_lf_human_decision_authority_policy_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_expected text;
  v_allowed text[];
begin
  select pc.allowed_kinds
    into v_allowed
  from programacion.provenance_channels pc
  where pc.channel_code=new.issuer_channel;

  if v_allowed is null then
    raise exception 'HUMAN_DECISION_AUTHORITY_CHANNEL_NOT_FOUND:%',new.issuer_channel;
  end if;

  if not (new.receipt_kind = any(v_allowed)) then
    raise exception 'HUMAN_DECISION_AUTHORITY_CHANNEL_KIND_NOT_ALLOWED:%:%',
      new.issuer_channel,new.receipt_kind;
  end if;

  v_expected:=private.fn_lf_human_decision_authority_policy_sha_v1(
    new.authority_ref,new.reviewer_role,new.issuer_channel,new.receipt_kind,
    new.status,new.metadata
  );

  if new.policy_sha256 is distinct from v_expected then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_SHA_MISMATCH';
  end if;

  if tg_op='UPDATE' then
    new.updated_at:=now();
  end if;

  return new;
end
$function$;

drop trigger if exists trg_lf_human_decision_authority_policy_guard_v1
  on private.lf_human_decision_authority_policies_v1;

create trigger trg_lf_human_decision_authority_policy_guard_v1
before insert or update
on private.lf_human_decision_authority_policies_v1
for each row
execute function private.fn_lf_human_decision_authority_policy_guard_v1();

-- Extend the existing provenance guard with a richer human-routing receipt kind.
-- Existing receipt kinds keep their prior validation semantics unchanged.
create or replace function programacion.fn_guard_provenance_receipt_insert()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_token text;
  v_token_sha text;
  v_allowed text[];
  v_head text;
  v_payload jsonb;
  v_digest text;
begin
  v_token := current_setting('programacion.provenance_channel_token', true);
  if length(coalesce(v_token,'')) < 32 then
    raise exception 'verified provenance receipt requires external channel token';
  end if;

  v_token_sha := encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');

  select allowed_kinds
    into v_allowed
  from programacion.provenance_channels
  where channel_code=new.issuer_channel
    and secret_sha256=v_token_sha;

  if v_allowed is null then
    raise exception 'verified provenance channel/token mismatch';
  end if;

  if not (new.receipt_kind = any(v_allowed)) then
    raise exception 'channel % is not authorized for receipt kind %',
      new.issuer_channel,new.receipt_kind;
  end if;

  if length(btrim(coalesce(new.issuer_identity,'')))=0
     or length(btrim(coalesce(new.verification_ref,'')))=0
     or length(btrim(coalesce(new.subject_type,'')))=0
     or length(btrim(coalesce(new.subject_ref,'')))=0 then
    raise exception 'verified provenance receipt identity/reference fields are required';
  end if;

  if new.execution_id is not null then
    select head_sha into v_head
    from programacion.ejecuciones
    where id=new.execution_id;

    if v_head is null then
      raise exception 'provenance receipt execution % not found',new.execution_id;
    end if;

    if new.head_sha is distinct from v_head then
      raise exception 'provenance receipt HEAD mismatch';
    end if;

    if new.payload->>'execution_id' is distinct from new.execution_id::text then
      raise exception 'provenance receipt payload execution mismatch';
    end if;
  end if;

  if new.payload->>'head_sha' is distinct from new.head_sha
     or new.payload->>'subject_type' is distinct from new.subject_type
     or new.payload->>'subject_ref' is distinct from new.subject_ref
     or new.payload->>'subject_sha256' is distinct from new.subject_sha256 then
    raise exception 'provenance receipt payload envelope mismatch';
  end if;

  if new.receipt_kind='AUDIT_VERDICT' then
    if new.payload->>'verdict' not in ('PASS','FAIL','BLOCKED')
       or new.payload->'independent' is distinct from 'true'::jsonb
       or length(btrim(coalesce(new.payload->>'auditor_identity','')))=0 then
      raise exception 'AUDIT_VERDICT receipt requires independent auditor verdict';
    end if;

  elsif new.receipt_kind='HUMAN_DECISION' then
    if new.payload->>'decision' not in ('APPROVE','REJECT')
       or length(btrim(coalesce(new.payload->>'actor_identity','')))=0
       or length(btrim(coalesce(new.payload->>'approval_ref','')))=0 then
      raise exception 'HUMAN_DECISION receipt requires actor/approval provenance';
    end if;

  elsif new.receipt_kind='HUMAN_ROUTING_DECISION' then
    if new.subject_type is distinct from 'HUMAN_DECISION_ROUTING_REQUEST'
       or coalesce(new.payload->>'request_id','') is distinct from new.subject_ref
       or coalesce(new.payload->>'request_sha256','') is distinct from new.subject_sha256
       or coalesce(new.payload->>'request_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(new.payload->>'currentness_sha256','') !~ '^[0-9a-f]{64}$'
       or length(btrim(coalesce(new.payload->>'action_code','')))=0
       or length(btrim(coalesce(new.payload->>'actor_identity','')))=0
       or length(btrim(coalesce(new.payload->>'approval_ref','')))=0
       or length(btrim(coalesce(new.payload->>'reviewer_role','')))=0
       or length(btrim(coalesce(new.payload->>'authority_ref','')))=0
       or jsonb_typeof(new.payload->'decision_payload') is distinct from 'object' then
      raise exception 'HUMAN_ROUTING_DECISION receipt contract invalid';
    end if;

  elsif new.receipt_kind='PLAYWRIGHT_RUN' then
    if new.payload->>'status' not in ('PASS','FAIL','BLOCKED','NOT_APPLICABLE')
       or length(btrim(coalesce(new.payload->>'run_ref','')))=0 then
      raise exception 'PLAYWRIGHT_RUN receipt requires externally verified run_ref/status';
    end if;

  elsif new.receipt_kind='EVIDENCE_VERIFICATION' then
    if new.payload->>'verification_status' not in ('VERIFIED','REJECTED')
       or length(btrim(coalesce(new.payload->>'verifier_identity','')))=0 then
      raise exception 'EVIDENCE_VERIFICATION receipt requires verifier provenance';
    end if;
  end if;

  v_payload:=jsonb_build_object(
    'schema_version',1,
    'receipt_kind',new.receipt_kind,
    'execution_id',new.execution_id,
    'head_sha',new.head_sha,
    'subject_type',new.subject_type,
    'subject_ref',new.subject_ref,
    'subject_sha256',new.subject_sha256,
    'issuer_channel',new.issuer_channel,
    'issuer_identity',new.issuer_identity,
    'verification_ref',new.verification_ref,
    'payload',new.payload
  );

  v_digest:=programacion.fn_v09_sha256_jsonb(v_payload);

  if new.receipt_sha256 is distinct from v_digest then
    raise exception 'verified provenance receipt digest mismatch';
  end if;

  return new;
end
$function$;

create or replace function private.fn_lf_human_decision_assert_authority_receipt_v1(
  p_request_id uuid,
  p_decision_code text,
  p_reviewer_role text,
  p_authority_ref text,
  p_authority_receipt_ref text,
  p_authority_receipt_sha256 text,
  p_observed_currentness_sha256 text
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_request private.lf_human_decision_requests_v1%rowtype;
  v_provenance_id bigint;
  v_prov programacion.provenance_receipts%rowtype;
  v_policy private.lf_human_decision_authority_policies_v1%rowtype;
  v_digest text;
begin
  select * into strict v_request
  from private.lf_human_decision_requests_v1
  where request_id=p_request_id;

  if coalesce(p_authority_receipt_ref,'') !~ '^supabase://programacion/provenance_receipts/[0-9]+$' then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_REF_INVALID';
  end if;

  v_provenance_id:=split_part(p_authority_receipt_ref,'/',5)::bigint;

  select * into strict v_prov
  from programacion.provenance_receipts
  where id=v_provenance_id;

  if v_prov.receipt_kind is distinct from 'HUMAN_ROUTING_DECISION'
     or v_prov.subject_type is distinct from 'HUMAN_DECISION_ROUTING_REQUEST'
     or v_prov.subject_ref is distinct from v_request.request_id::text
     or v_prov.subject_sha256 is distinct from v_request.request_sha256 then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_SUBJECT_MISMATCH';
  end if;

  v_digest:=programacion.fn_v09_sha256_jsonb(
    jsonb_build_object(
      'schema_version',1,
      'receipt_kind',v_prov.receipt_kind,
      'execution_id',v_prov.execution_id,
      'head_sha',v_prov.head_sha,
      'subject_type',v_prov.subject_type,
      'subject_ref',v_prov.subject_ref,
      'subject_sha256',v_prov.subject_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'issuer_identity',v_prov.issuer_identity,
      'verification_ref',v_prov.verification_ref,
      'payload',v_prov.payload
    )
  );

  if v_prov.receipt_sha256 is distinct from v_digest
     or p_authority_receipt_sha256 is distinct from v_prov.receipt_sha256 then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_DIGEST_MISMATCH';
  end if;

  if v_prov.payload->>'request_id' is distinct from v_request.request_id::text
     or v_prov.payload->>'request_sha256' is distinct from v_request.request_sha256
     or v_prov.payload->>'currentness_sha256' is distinct from p_observed_currentness_sha256
     or p_observed_currentness_sha256 is distinct from v_request.currentness_sha256
     or v_prov.payload->>'reviewer_role' is distinct from p_reviewer_role
     or p_reviewer_role is distinct from v_request.required_reviewer_role
     or v_prov.payload->>'authority_ref' is distinct from p_authority_ref
     or p_authority_ref is distinct from v_request.required_authority_ref
     or v_prov.payload->>'action_code' is distinct from p_decision_code then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_BINDING_MISMATCH';
  end if;

  select * into v_policy
  from private.lf_human_decision_authority_policies_v1
  where authority_ref=p_authority_ref
    and reviewer_role=p_reviewer_role
    and status='ACTIVE';

  if not found then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_NOT_ACTIVE:%:%',
      p_authority_ref,p_reviewer_role;
  end if;

  if v_policy.issuer_channel is distinct from v_prov.issuer_channel
     or v_policy.receipt_kind is distinct from v_prov.receipt_kind then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_RECEIPT_MISMATCH';
  end if;

  if v_policy.policy_sha256 is distinct from
     private.fn_lf_human_decision_authority_policy_sha_v1(
       v_policy.authority_ref,v_policy.reviewer_role,v_policy.issuer_channel,
       v_policy.receipt_kind,v_policy.status,v_policy.metadata
     ) then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_INTEGRITY_MISMATCH';
  end if;

  return true;
end
$function$;

create or replace function private.fn_lf_human_decision_receipt_sha_v1(
  p_request_id uuid,
  p_request_sha256 text,
  p_decision_code text,
  p_decision_payload jsonb,
  p_reviewer_identity text,
  p_reviewer_role text,
  p_authority_ref text,
  p_authority_receipt_ref text,
  p_authority_receipt_sha256 text,
  p_observed_currentness_sha256 text,
  p_metadata jsonb
)
returns text
language sql
immutable
set search_path=''
as $function$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'schema_version','lf-human-decision-receipt/v1',
          'request_id',p_request_id,
          'request_sha256',p_request_sha256,
          'decision_code',p_decision_code,
          'decision_payload',coalesce(p_decision_payload,'{}'::jsonb),
          'reviewer_identity',p_reviewer_identity,
          'reviewer_role',p_reviewer_role,
          'authority_ref',p_authority_ref,
          'authority_receipt_ref',p_authority_receipt_ref,
          'authority_receipt_sha256',p_authority_receipt_sha256,
          'observed_currentness_sha256',p_observed_currentness_sha256,
          'metadata',coalesce(p_metadata,'{}'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
$function$;

create or replace function private.fn_lf_human_decision_receipt_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request private.lf_human_decision_requests_v1%rowtype;
  v_action_allowed boolean;
  v_expected_sha text;
begin
  select *
    into strict v_request
  from private.lf_human_decision_requests_v1
  where request_id=new.request_id
  for update;

  if v_request.status <> 'OPEN' then
    raise exception 'HUMAN_DECISION_REQUEST_NOT_OPEN:%',v_request.status;
  end if;

  if v_request.expires_at is not null and v_request.expires_at <= now() then
    raise exception 'HUMAN_DECISION_REQUEST_EXPIRED:%',v_request.request_id;
  end if;

  if new.reviewer_role is distinct from v_request.required_reviewer_role then
    raise exception 'HUMAN_DECISION_REVIEWER_ROLE_MISMATCH';
  end if;

  if new.authority_ref is distinct from v_request.required_authority_ref then
    raise exception 'HUMAN_DECISION_AUTHORITY_REF_MISMATCH';
  end if;

  if new.observed_currentness_sha256 is distinct from v_request.currentness_sha256 then
    raise exception 'HUMAN_DECISION_CURRENTNESS_STALE';
  end if;

  select exists(
    select 1
    from jsonb_array_elements_text(v_request.allowed_actions) a(value)
    where a.value=new.decision_code
  )
  into v_action_allowed;

  if not v_action_allowed then
    raise exception 'HUMAN_DECISION_ACTION_NOT_ALLOWED:%',new.decision_code;
  end if;

  perform private.fn_lf_human_decision_assert_authority_receipt_v1(
    new.request_id,
    new.decision_code,
    new.reviewer_role,
    new.authority_ref,
    new.authority_receipt_ref,
    new.authority_receipt_sha256,
    new.observed_currentness_sha256
  );

  v_expected_sha:=private.fn_lf_human_decision_receipt_sha_v1(
    new.request_id,
    v_request.request_sha256,
    new.decision_code,
    new.decision_payload,
    new.reviewer_identity,
    new.reviewer_role,
    new.authority_ref,
    new.authority_receipt_ref,
    new.authority_receipt_sha256,
    new.observed_currentness_sha256,
    new.metadata
  );

  if new.receipt_sha256 is distinct from v_expected_sha then
    raise exception 'HUMAN_DECISION_RECEIPT_SHA_MISMATCH';
  end if;

  return new;
end
$function$;

create unique index if not exists uq_lf_human_decision_receipts_v1_authority_receipt
  on private.lf_human_decision_receipts_v1(authority_receipt_ref);

create or replace function private.fn_lf_human_decision_record_verified_v1(
  p_request_id uuid,
  p_provenance_receipt_id bigint,
  p_created_by_execution_id text default 'HUMAN_DECISION_AUTHORITY_VERIFIER_V1'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_request private.lf_human_decision_requests_v1%rowtype;
  v_prov programacion.provenance_receipts%rowtype;
  v_policy private.lf_human_decision_authority_policies_v1%rowtype;
  v_authority_receipt_ref text;
  v_generic_receipt_sha text;
  v_provenance_digest text;
begin
  select * into strict v_request
  from private.lf_human_decision_requests_v1
  where request_id=p_request_id
  for update;

  if v_request.status <> 'OPEN' then
    raise exception 'HUMAN_DECISION_REQUEST_NOT_OPEN:%',v_request.status;
  end if;

  if v_request.expires_at is not null and v_request.expires_at <= now() then
    raise exception 'HUMAN_DECISION_REQUEST_EXPIRED:%',v_request.request_id;
  end if;

  select * into strict v_prov
  from programacion.provenance_receipts
  where id=p_provenance_receipt_id;

  if v_prov.receipt_kind is distinct from 'HUMAN_ROUTING_DECISION'
     or v_prov.subject_type is distinct from 'HUMAN_DECISION_ROUTING_REQUEST'
     or v_prov.subject_ref is distinct from v_request.request_id::text
     or v_prov.subject_sha256 is distinct from v_request.request_sha256 then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_SUBJECT_MISMATCH';
  end if;

  v_provenance_digest:=programacion.fn_v09_sha256_jsonb(
    jsonb_build_object(
      'schema_version',1,
      'receipt_kind',v_prov.receipt_kind,
      'execution_id',v_prov.execution_id,
      'head_sha',v_prov.head_sha,
      'subject_type',v_prov.subject_type,
      'subject_ref',v_prov.subject_ref,
      'subject_sha256',v_prov.subject_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'issuer_identity',v_prov.issuer_identity,
      'verification_ref',v_prov.verification_ref,
      'payload',v_prov.payload
    )
  );

  if v_prov.receipt_sha256 is distinct from v_provenance_digest then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_DIGEST_MISMATCH';
  end if;

  if v_prov.payload->>'request_id' is distinct from v_request.request_id::text
     or v_prov.payload->>'request_sha256' is distinct from v_request.request_sha256
     or v_prov.payload->>'currentness_sha256' is distinct from v_request.currentness_sha256
     or v_prov.payload->>'reviewer_role' is distinct from v_request.required_reviewer_role
     or v_prov.payload->>'authority_ref' is distinct from v_request.required_authority_ref then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_BINDING_MISMATCH';
  end if;

  if not exists(
    select 1
    from jsonb_array_elements_text(v_request.allowed_actions) a(value)
    where a.value=v_prov.payload->>'action_code'
  ) then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_ACTION_NOT_ALLOWED:%',
      v_prov.payload->>'action_code';
  end if;

  select *
    into v_policy
  from private.lf_human_decision_authority_policies_v1
  where authority_ref=v_request.required_authority_ref
    and reviewer_role=v_request.required_reviewer_role
    and status='ACTIVE';

  if not found then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_NOT_ACTIVE:%:%',
      v_request.required_authority_ref,v_request.required_reviewer_role;
  end if;

  if v_policy.issuer_channel is distinct from v_prov.issuer_channel
     or v_policy.receipt_kind is distinct from v_prov.receipt_kind then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_RECEIPT_MISMATCH';
  end if;

  if v_policy.policy_sha256 is distinct from
     private.fn_lf_human_decision_authority_policy_sha_v1(
       v_policy.authority_ref,v_policy.reviewer_role,v_policy.issuer_channel,
       v_policy.receipt_kind,v_policy.status,v_policy.metadata
     ) then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_INTEGRITY_MISMATCH';
  end if;

  v_authority_receipt_ref:='supabase://programacion/provenance_receipts/'||v_prov.id::text;

  v_generic_receipt_sha:=private.fn_lf_human_decision_receipt_sha_v1(
    v_request.request_id,
    v_request.request_sha256,
    v_prov.payload->>'action_code',
    v_prov.payload->'decision_payload',
    v_prov.payload->>'actor_identity',
    v_prov.payload->>'reviewer_role',
    v_prov.payload->>'authority_ref',
    v_authority_receipt_ref,
    v_prov.receipt_sha256,
    v_prov.payload->>'currentness_sha256',
    jsonb_build_object(
      'authority_policy_sha256',v_policy.policy_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'provenance_receipt_id',v_prov.id
    )
  );

  insert into private.lf_human_decision_receipts_v1(
    request_id,decision_code,decision_payload,reviewer_identity,reviewer_role,
    authority_ref,authority_receipt_ref,authority_receipt_sha256,
    observed_currentness_sha256,receipt_sha256,metadata,created_by_execution_id
  )
  values(
    v_request.request_id,
    v_prov.payload->>'action_code',
    v_prov.payload->'decision_payload',
    v_prov.payload->>'actor_identity',
    v_prov.payload->>'reviewer_role',
    v_prov.payload->>'authority_ref',
    v_authority_receipt_ref,
    v_prov.receipt_sha256,
    v_prov.payload->>'currentness_sha256',
    v_generic_receipt_sha,
    jsonb_build_object(
      'authority_policy_sha256',v_policy.policy_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'provenance_receipt_id',v_prov.id
    ),
    p_created_by_execution_id
  );

  return private.fn_lf_human_decision_consume_v1(v_request.request_id);
end
$function$;

revoke all on function private.fn_lf_human_decision_record_verified_v1(uuid,bigint,text)
  from public,anon,authenticated;

comment on table private.lf_human_decision_authority_policies_v1 is
'Explicit authority-to-reviewer-to-provenance-channel policy for HUMAN_DECISION_ROUTING. No authority is inferred from a role label.';

comment on function private.fn_lf_human_decision_record_verified_v1(uuid,bigint,text) is
'Consumes an append-only provenance receipt only when request, currentness, reviewer role, authority reference, action and active authority policy all bind exactly.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-DECISION-AUTHORITY-RECEIPT-VERIFIER-001',
  'PROGRAMMING_GOVERNANCE',
  'Human decision receipt ingress must verify provenance plus explicit authority policy before recording a generic decision',
  'HUMAN_DECISION_ROUTING now has a deterministic verifier design that accepts only append-only provenance receipts of kind HUMAN_ROUTING_DECISION, exact request/currentness/action binding and an ACTIVE policy matching authority_ref + reviewer_role + issuer_channel.',
  'The routing core previously stored authority_receipt_ref/sha structurally but had no deterministic proof that the referenced receipt came from an allowed authority/channel pair.',
  'EXTERNAL AUTHORITY CHANNEL -> APPEND-ONLY PROVENANCE RECEIPT -> ACTIVE AUTHORITY POLICY -> EXACT BINDING VERIFIER -> GENERIC DECISION RECEIPT.',
  'Never accept a generic decision receipt unless its table guard verifies an append-only provenance receipt plus an ACTIVE authority policy. fn_lf_human_decision_record_verified_v1 is the canonical ingress; direct inserts are structurally subject to the same provenance/policy checks. Keep policies disabled/absent until the real authority contract is authorized.',
  'Candidate migration adds the policy registry, richer provenance receipt kind validation, exact verifier ingress and one-use authority receipt binding. No real authority policy is activated.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008054000_human_decision_authority_receipt_verifier_v1.sql',
  now()
)
on conflict(codigo) do update
set descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
 then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_REF_INVALID';
  end if;

  v_provenance_id:=split_part(p_authority_receipt_ref,'/',5)::bigint;

  select * into strict v_prov
  from programacion.provenance_receipts
  where id=v_provenance_id;

  if v_prov.receipt_kind is distinct from 'HUMAN_ROUTING_DECISION'
     or v_prov.subject_type is distinct from 'HUMAN_DECISION_ROUTING_REQUEST'
     or v_prov.subject_ref is distinct from v_request.request_id::text
     or v_prov.subject_sha256 is distinct from v_request.request_sha256 then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_SUBJECT_MISMATCH';
  end if;

  v_digest:=programacion.fn_v09_sha256_jsonb(
    jsonb_build_object(
      'schema_version',1,
      'receipt_kind',v_prov.receipt_kind,
      'execution_id',v_prov.execution_id,
      'head_sha',v_prov.head_sha,
      'subject_type',v_prov.subject_type,
      'subject_ref',v_prov.subject_ref,
      'subject_sha256',v_prov.subject_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'issuer_identity',v_prov.issuer_identity,
      'verification_ref',v_prov.verification_ref,
      'payload',v_prov.payload
    )
  );

  if v_prov.receipt_sha256 is distinct from v_digest
     or p_authority_receipt_sha256 is distinct from v_prov.receipt_sha256 then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_DIGEST_MISMATCH';
  end if;

  if v_prov.payload->>'request_id' is distinct from v_request.request_id::text
     or v_prov.payload->>'request_sha256' is distinct from v_request.request_sha256
     or v_prov.payload->>'currentness_sha256' is distinct from p_observed_currentness_sha256
     or p_observed_currentness_sha256 is distinct from v_request.currentness_sha256
     or v_prov.payload->>'reviewer_role' is distinct from p_reviewer_role
     or p_reviewer_role is distinct from v_request.required_reviewer_role
     or v_prov.payload->>'authority_ref' is distinct from p_authority_ref
     or p_authority_ref is distinct from v_request.required_authority_ref
     or v_prov.payload->>'action_code' is distinct from p_decision_code then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_BINDING_MISMATCH';
  end if;

  select * into v_policy
  from private.lf_human_decision_authority_policies_v1
  where authority_ref=p_authority_ref
    and reviewer_role=p_reviewer_role
    and status='ACTIVE';

  if not found then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_NOT_ACTIVE:%:%',
      p_authority_ref,p_reviewer_role;
  end if;

  if v_policy.issuer_channel is distinct from v_prov.issuer_channel
     or v_policy.receipt_kind is distinct from v_prov.receipt_kind then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_RECEIPT_MISMATCH';
  end if;

  if v_policy.policy_sha256 is distinct from
     private.fn_lf_human_decision_authority_policy_sha_v1(
       v_policy.authority_ref,v_policy.reviewer_role,v_policy.issuer_channel,
       v_policy.receipt_kind,v_policy.status,v_policy.metadata
     ) then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_INTEGRITY_MISMATCH';
  end if;

  return true;
end
$function$;

create or replace function private.fn_lf_human_decision_receipt_sha_v1(
  p_request_id uuid,
  p_request_sha256 text,
  p_decision_code text,
  p_decision_payload jsonb,
  p_reviewer_identity text,
  p_reviewer_role text,
  p_authority_ref text,
  p_authority_receipt_ref text,
  p_authority_receipt_sha256 text,
  p_observed_currentness_sha256 text,
  p_metadata jsonb
)
returns text
language sql
immutable
set search_path=''
as $function$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'schema_version','lf-human-decision-receipt/v1',
          'request_id',p_request_id,
          'request_sha256',p_request_sha256,
          'decision_code',p_decision_code,
          'decision_payload',coalesce(p_decision_payload,'{}'::jsonb),
          'reviewer_identity',p_reviewer_identity,
          'reviewer_role',p_reviewer_role,
          'authority_ref',p_authority_ref,
          'authority_receipt_ref',p_authority_receipt_ref,
          'authority_receipt_sha256',p_authority_receipt_sha256,
          'observed_currentness_sha256',p_observed_currentness_sha256,
          'metadata',coalesce(p_metadata,'{}'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
$function$;

create or replace function private.fn_lf_human_decision_receipt_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request private.lf_human_decision_requests_v1%rowtype;
  v_action_allowed boolean;
  v_expected_sha text;
begin
  select *
    into strict v_request
  from private.lf_human_decision_requests_v1
  where request_id=new.request_id
  for update;

  if v_request.status <> 'OPEN' then
    raise exception 'HUMAN_DECISION_REQUEST_NOT_OPEN:%',v_request.status;
  end if;

  if v_request.expires_at is not null and v_request.expires_at <= now() then
    raise exception 'HUMAN_DECISION_REQUEST_EXPIRED:%',v_request.request_id;
  end if;

  if new.reviewer_role is distinct from v_request.required_reviewer_role then
    raise exception 'HUMAN_DECISION_REVIEWER_ROLE_MISMATCH';
  end if;

  if new.authority_ref is distinct from v_request.required_authority_ref then
    raise exception 'HUMAN_DECISION_AUTHORITY_REF_MISMATCH';
  end if;

  if new.observed_currentness_sha256 is distinct from v_request.currentness_sha256 then
    raise exception 'HUMAN_DECISION_CURRENTNESS_STALE';
  end if;

  select exists(
    select 1
    from jsonb_array_elements_text(v_request.allowed_actions) a(value)
    where a.value=new.decision_code
  )
  into v_action_allowed;

  if not v_action_allowed then
    raise exception 'HUMAN_DECISION_ACTION_NOT_ALLOWED:%',new.decision_code;
  end if;

  v_expected_sha:=private.fn_lf_human_decision_receipt_sha_v1(
    new.request_id,
    v_request.request_sha256,
    new.decision_code,
    new.decision_payload,
    new.reviewer_identity,
    new.reviewer_role,
    new.authority_ref,
    new.authority_receipt_ref,
    new.authority_receipt_sha256,
    new.observed_currentness_sha256,
    new.metadata
  );

  if new.receipt_sha256 is distinct from v_expected_sha then
    raise exception 'HUMAN_DECISION_RECEIPT_SHA_MISMATCH';
  end if;

  return new;
end
$function$;

create unique index if not exists uq_lf_human_decision_receipts_v1_authority_receipt
  on private.lf_human_decision_receipts_v1(authority_receipt_ref);

create or replace function private.fn_lf_human_decision_record_verified_v1(
  p_request_id uuid,
  p_provenance_receipt_id bigint,
  p_created_by_execution_id text default 'HUMAN_DECISION_AUTHORITY_VERIFIER_V1'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_request private.lf_human_decision_requests_v1%rowtype;
  v_prov programacion.provenance_receipts%rowtype;
  v_policy private.lf_human_decision_authority_policies_v1%rowtype;
  v_authority_receipt_ref text;
  v_generic_receipt_sha text;
  v_provenance_digest text;
begin
  select * into strict v_request
  from private.lf_human_decision_requests_v1
  where request_id=p_request_id
  for update;

  if v_request.status <> 'OPEN' then
    raise exception 'HUMAN_DECISION_REQUEST_NOT_OPEN:%',v_request.status;
  end if;

  if v_request.expires_at is not null and v_request.expires_at <= now() then
    raise exception 'HUMAN_DECISION_REQUEST_EXPIRED:%',v_request.request_id;
  end if;

  select * into strict v_prov
  from programacion.provenance_receipts
  where id=p_provenance_receipt_id;

  if v_prov.receipt_kind is distinct from 'HUMAN_ROUTING_DECISION'
     or v_prov.subject_type is distinct from 'HUMAN_DECISION_ROUTING_REQUEST'
     or v_prov.subject_ref is distinct from v_request.request_id::text
     or v_prov.subject_sha256 is distinct from v_request.request_sha256 then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_SUBJECT_MISMATCH';
  end if;

  v_provenance_digest:=programacion.fn_v09_sha256_jsonb(
    jsonb_build_object(
      'schema_version',1,
      'receipt_kind',v_prov.receipt_kind,
      'execution_id',v_prov.execution_id,
      'head_sha',v_prov.head_sha,
      'subject_type',v_prov.subject_type,
      'subject_ref',v_prov.subject_ref,
      'subject_sha256',v_prov.subject_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'issuer_identity',v_prov.issuer_identity,
      'verification_ref',v_prov.verification_ref,
      'payload',v_prov.payload
    )
  );

  if v_prov.receipt_sha256 is distinct from v_provenance_digest then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_DIGEST_MISMATCH';
  end if;

  if v_prov.payload->>'request_id' is distinct from v_request.request_id::text
     or v_prov.payload->>'request_sha256' is distinct from v_request.request_sha256
     or v_prov.payload->>'currentness_sha256' is distinct from v_request.currentness_sha256
     or v_prov.payload->>'reviewer_role' is distinct from v_request.required_reviewer_role
     or v_prov.payload->>'authority_ref' is distinct from v_request.required_authority_ref then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_BINDING_MISMATCH';
  end if;

  if not exists(
    select 1
    from jsonb_array_elements_text(v_request.allowed_actions) a(value)
    where a.value=v_prov.payload->>'action_code'
  ) then
    raise exception 'HUMAN_DECISION_AUTHORITY_RECEIPT_ACTION_NOT_ALLOWED:%',
      v_prov.payload->>'action_code';
  end if;

  select *
    into v_policy
  from private.lf_human_decision_authority_policies_v1
  where authority_ref=v_request.required_authority_ref
    and reviewer_role=v_request.required_reviewer_role
    and status='ACTIVE';

  if not found then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_NOT_ACTIVE:%:%',
      v_request.required_authority_ref,v_request.required_reviewer_role;
  end if;

  if v_policy.issuer_channel is distinct from v_prov.issuer_channel
     or v_policy.receipt_kind is distinct from v_prov.receipt_kind then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_RECEIPT_MISMATCH';
  end if;

  if v_policy.policy_sha256 is distinct from
     private.fn_lf_human_decision_authority_policy_sha_v1(
       v_policy.authority_ref,v_policy.reviewer_role,v_policy.issuer_channel,
       v_policy.receipt_kind,v_policy.status,v_policy.metadata
     ) then
    raise exception 'HUMAN_DECISION_AUTHORITY_POLICY_INTEGRITY_MISMATCH';
  end if;

  v_authority_receipt_ref:='supabase://programacion/provenance_receipts/'||v_prov.id::text;

  v_generic_receipt_sha:=private.fn_lf_human_decision_receipt_sha_v1(
    v_request.request_id,
    v_request.request_sha256,
    v_prov.payload->>'action_code',
    v_prov.payload->'decision_payload',
    v_prov.payload->>'actor_identity',
    v_prov.payload->>'reviewer_role',
    v_prov.payload->>'authority_ref',
    v_authority_receipt_ref,
    v_prov.receipt_sha256,
    v_prov.payload->>'currentness_sha256',
    jsonb_build_object(
      'authority_policy_sha256',v_policy.policy_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'provenance_receipt_id',v_prov.id
    )
  );

  insert into private.lf_human_decision_receipts_v1(
    request_id,decision_code,decision_payload,reviewer_identity,reviewer_role,
    authority_ref,authority_receipt_ref,authority_receipt_sha256,
    observed_currentness_sha256,receipt_sha256,metadata,created_by_execution_id
  )
  values(
    v_request.request_id,
    v_prov.payload->>'action_code',
    v_prov.payload->'decision_payload',
    v_prov.payload->>'actor_identity',
    v_prov.payload->>'reviewer_role',
    v_prov.payload->>'authority_ref',
    v_authority_receipt_ref,
    v_prov.receipt_sha256,
    v_prov.payload->>'currentness_sha256',
    v_generic_receipt_sha,
    jsonb_build_object(
      'authority_policy_sha256',v_policy.policy_sha256,
      'issuer_channel',v_prov.issuer_channel,
      'provenance_receipt_id',v_prov.id
    ),
    p_created_by_execution_id
  );

  return private.fn_lf_human_decision_consume_v1(v_request.request_id);
end
$function$;

revoke all on function private.fn_lf_human_decision_record_verified_v1(uuid,bigint,text)
  from public,anon,authenticated;

comment on table private.lf_human_decision_authority_policies_v1 is
'Explicit authority-to-reviewer-to-provenance-channel policy for HUMAN_DECISION_ROUTING. No authority is inferred from a role label.';

comment on function private.fn_lf_human_decision_record_verified_v1(uuid,bigint,text) is
'Consumes an append-only provenance receipt only when request, currentness, reviewer role, authority reference, action and active authority policy all bind exactly.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-DECISION-AUTHORITY-RECEIPT-VERIFIER-001',
  'PROGRAMMING_GOVERNANCE',
  'Human decision receipt ingress must verify provenance plus explicit authority policy before recording a generic decision',
  'HUMAN_DECISION_ROUTING now has a deterministic verifier design that accepts only append-only provenance receipts of kind HUMAN_ROUTING_DECISION, exact request/currentness/action binding and an ACTIVE policy matching authority_ref + reviewer_role + issuer_channel.',
  'The routing core previously stored authority_receipt_ref/sha structurally but had no deterministic proof that the referenced receipt came from an allowed authority/channel pair.',
  'EXTERNAL AUTHORITY CHANNEL -> APPEND-ONLY PROVENANCE RECEIPT -> ACTIVE AUTHORITY POLICY -> EXACT BINDING VERIFIER -> GENERIC DECISION RECEIPT.',
  'Never create a generic decision receipt directly from service-role input. Use fn_lf_human_decision_record_verified_v1 and require an ACTIVE authority policy. Keep policies disabled/absent until the real authority contract is authorized.',
  'Candidate migration adds the policy registry, richer provenance receipt kind validation, exact verifier ingress and one-use authority receipt binding. No real authority policy is activated.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008054000_human_decision_authority_receipt_verifier_v1.sql',
  now()
)
on conflict(codigo) do update
set descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
