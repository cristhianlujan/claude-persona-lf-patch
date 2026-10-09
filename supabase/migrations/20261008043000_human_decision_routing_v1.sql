-- HUMAN_DECISION_ROUTING_V1
-- Generic transversal durable contract for human-decision requests and receipts.
-- No consumer cutover in this migration.

create table if not exists private.lf_human_decision_requests_v1 (
  request_id uuid primary key default gen_random_uuid(),
  producer_code text not null,
  subject_type text not null,
  subject_key text not null,
  subject_ref jsonb not null default '{}'::jsonb,
  required_authority_ref text not null,
  required_reviewer_role text not null,
  allowed_actions jsonb not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  currentness_sha256 text not null,
  impact jsonb not null default '{}'::jsonb,
  source_ref text,
  source_revision text,
  status text not null default 'OPEN',
  request_sha256 text not null,
  opened_at timestamptz not null default now(),
  expires_at timestamptz,
  supersedes_request_id uuid references private.lf_human_decision_requests_v1(request_id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text,

  constraint lf_human_decision_requests_v1_producer_code_ck
    check (producer_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint lf_human_decision_requests_v1_subject_type_ck
    check (subject_type ~ '^[A-Z][A-Z0-9_]*$'),
  constraint lf_human_decision_requests_v1_subject_key_ck
    check (length(btrim(subject_key)) > 0),
  constraint lf_human_decision_requests_v1_subject_ref_ck
    check (jsonb_typeof(subject_ref) = 'object'),
  constraint lf_human_decision_requests_v1_authority_ref_ck
    check (length(btrim(required_authority_ref)) > 0),
  constraint lf_human_decision_requests_v1_reviewer_role_ck
    check (length(btrim(required_reviewer_role)) > 0),
  constraint lf_human_decision_requests_v1_allowed_actions_ck
    check (jsonb_typeof(allowed_actions) = 'array' and jsonb_array_length(allowed_actions) > 0),
  constraint lf_human_decision_requests_v1_evidence_refs_ck
    check (jsonb_typeof(evidence_refs) = 'array'),
  constraint lf_human_decision_requests_v1_currentness_sha_ck
    check (currentness_sha256 ~ '^[0-9a-f]{64}$'),
  constraint lf_human_decision_requests_v1_impact_ck
    check (jsonb_typeof(impact) = 'object'),
  constraint lf_human_decision_requests_v1_status_ck
    check (status in ('OPEN','DECIDED','CANCELLED','SUPERSEDED')),
  constraint lf_human_decision_requests_v1_request_sha_ck
    check (request_sha256 ~ '^[0-9a-f]{64}$'),
  constraint lf_human_decision_requests_v1_expiry_ck
    check (expires_at is null or expires_at > opened_at),
  constraint lf_human_decision_requests_v1_metadata_ck
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists uq_lf_human_decision_requests_v1_open_subject
  on private.lf_human_decision_requests_v1(producer_code,subject_type,subject_key)
  where status='OPEN';

create index if not exists idx_lf_human_decision_requests_v1_queue
  on private.lf_human_decision_requests_v1(status,required_reviewer_role,opened_at);

create table if not exists private.lf_human_decision_receipts_v1 (
  receipt_id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique
    references private.lf_human_decision_requests_v1(request_id) on delete restrict,
  decision_code text not null,
  decision_payload jsonb not null default '{}'::jsonb,
  reviewer_identity text not null,
  reviewer_role text not null,
  authority_ref text not null,
  authority_receipt_ref text not null,
  authority_receipt_sha256 text not null,
  observed_currentness_sha256 text not null,
  receipt_sha256 text not null unique,
  decided_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_by_execution_id text not null,

  constraint lf_human_decision_receipts_v1_decision_code_ck
    check (decision_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint lf_human_decision_receipts_v1_payload_ck
    check (jsonb_typeof(decision_payload) = 'object'),
  constraint lf_human_decision_receipts_v1_reviewer_identity_ck
    check (length(btrim(reviewer_identity)) > 0),
  constraint lf_human_decision_receipts_v1_reviewer_role_ck
    check (length(btrim(reviewer_role)) > 0),
  constraint lf_human_decision_receipts_v1_authority_ref_ck
    check (length(btrim(authority_ref)) > 0),
  constraint lf_human_decision_receipts_v1_authority_receipt_ref_ck
    check (length(btrim(authority_receipt_ref)) > 0),
  constraint lf_human_decision_receipts_v1_authority_receipt_sha_ck
    check (authority_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  constraint lf_human_decision_receipts_v1_currentness_sha_ck
    check (observed_currentness_sha256 ~ '^[0-9a-f]{64}$'),
  constraint lf_human_decision_receipts_v1_receipt_sha_ck
    check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  constraint lf_human_decision_receipts_v1_metadata_ck
    check (jsonb_typeof(metadata) = 'object')
);

create or replace function private.fn_lf_human_decision_request_sha_v1(
  p_producer_code text,
  p_subject_type text,
  p_subject_key text,
  p_subject_ref jsonb,
  p_required_authority_ref text,
  p_required_reviewer_role text,
  p_allowed_actions jsonb,
  p_evidence_refs jsonb,
  p_currentness_sha256 text,
  p_impact jsonb,
  p_source_ref text,
  p_source_revision text,
  p_metadata jsonb
)
returns text
language sql
immutable
set search_path = ''
as $function$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'schema_version','lf-human-decision-request/v1',
          'producer_code',p_producer_code,
          'subject_type',p_subject_type,
          'subject_key',p_subject_key,
          'subject_ref',coalesce(p_subject_ref,'{}'::jsonb),
          'required_authority_ref',p_required_authority_ref,
          'required_reviewer_role',p_required_reviewer_role,
          'allowed_actions',coalesce(p_allowed_actions,'[]'::jsonb),
          'evidence_refs',coalesce(p_evidence_refs,'[]'::jsonb),
          'currentness_sha256',p_currentness_sha256,
          'impact',coalesce(p_impact,'{}'::jsonb),
          'source_ref',p_source_ref,
          'source_revision',p_source_revision,
          'metadata',coalesce(p_metadata,'{}'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
$function$;

create or replace function private.fn_lf_human_decision_request_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_expected_sha text;
begin
  if tg_op='UPDATE' then
    if new.producer_code is distinct from old.producer_code
       or new.subject_type is distinct from old.subject_type
       or new.subject_key is distinct from old.subject_key
       or new.subject_ref is distinct from old.subject_ref
       or new.required_authority_ref is distinct from old.required_authority_ref
       or new.required_reviewer_role is distinct from old.required_reviewer_role
       or new.allowed_actions is distinct from old.allowed_actions
       or new.evidence_refs is distinct from old.evidence_refs
       or new.currentness_sha256 is distinct from old.currentness_sha256
       or new.impact is distinct from old.impact
       or new.source_ref is distinct from old.source_ref
       or new.source_revision is distinct from old.source_revision
       or new.request_sha256 is distinct from old.request_sha256
       or new.opened_at is distinct from old.opened_at
       or new.expires_at is distinct from old.expires_at
       or new.metadata is distinct from old.metadata
       or new.created_by_execution_id is distinct from old.created_by_execution_id then
      raise exception 'HUMAN_DECISION_REQUEST_CONTRACT_IMMUTABLE:%',old.request_id;
    end if;

    if old.status <> new.status then
      if old.status <> 'OPEN'
         or new.status not in ('DECIDED','CANCELLED','SUPERSEDED') then
        raise exception 'HUMAN_DECISION_REQUEST_STATUS_TRANSITION_INVALID:%->%',old.status,new.status;
      end if;
    end if;

    new.updated_at:=now();
    return new;
  end if;

  v_expected_sha:=private.fn_lf_human_decision_request_sha_v1(
    new.producer_code,
    new.subject_type,
    new.subject_key,
    new.subject_ref,
    new.required_authority_ref,
    new.required_reviewer_role,
    new.allowed_actions,
    new.evidence_refs,
    new.currentness_sha256,
    new.impact,
    new.source_ref,
    new.source_revision,
    new.metadata
  );

  if new.request_sha256 is distinct from v_expected_sha then
    raise exception 'HUMAN_DECISION_REQUEST_SHA_MISMATCH';
  end if;

  return new;
end
$function$;

drop trigger if exists trg_lf_human_decision_request_guard_v1
  on private.lf_human_decision_requests_v1;

create trigger trg_lf_human_decision_request_guard_v1
before insert or update
on private.lf_human_decision_requests_v1
for each row
execute function private.fn_lf_human_decision_request_guard_v1();

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

  v_expected_sha:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'schema_version','lf-human-decision-receipt/v1',
          'request_id',new.request_id,
          'request_sha256',v_request.request_sha256,
          'decision_code',new.decision_code,
          'decision_payload',coalesce(new.decision_payload,'{}'::jsonb),
          'reviewer_identity',new.reviewer_identity,
          'reviewer_role',new.reviewer_role,
          'authority_ref',new.authority_ref,
          'authority_receipt_ref',new.authority_receipt_ref,
          'authority_receipt_sha256',new.authority_receipt_sha256,
          'observed_currentness_sha256',new.observed_currentness_sha256,
          'metadata',coalesce(new.metadata,'{}'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  if new.receipt_sha256 is distinct from v_expected_sha then
    raise exception 'HUMAN_DECISION_RECEIPT_SHA_MISMATCH';
  end if;

  return new;
end
$function$;

drop trigger if exists trg_lf_human_decision_receipt_guard_v1
  on private.lf_human_decision_receipts_v1;

create trigger trg_lf_human_decision_receipt_guard_v1
before insert
on private.lf_human_decision_receipts_v1
for each row
execute function private.fn_lf_human_decision_receipt_guard_v1();

create or replace function private.fn_lf_human_decision_receipt_close_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update private.lf_human_decision_requests_v1
     set status='DECIDED',
         updated_by_execution_id=new.created_by_execution_id
   where request_id=new.request_id
     and status='OPEN';

  if not found then
    raise exception 'HUMAN_DECISION_REQUEST_CLOSE_FAILED:%',new.request_id;
  end if;

  return new;
end
$function$;

drop trigger if exists trg_lf_human_decision_receipt_close_v1
  on private.lf_human_decision_receipts_v1;

create trigger trg_lf_human_decision_receipt_close_v1
after insert
on private.lf_human_decision_receipts_v1
for each row
execute function private.fn_lf_human_decision_receipt_close_v1();

create or replace function private.fn_lf_human_decision_open_v1(
  p_producer_code text,
  p_subject_type text,
  p_subject_key text,
  p_subject_ref jsonb,
  p_required_authority_ref text,
  p_required_reviewer_role text,
  p_allowed_actions jsonb,
  p_evidence_refs jsonb,
  p_currentness_sha256 text,
  p_impact jsonb default '{}'::jsonb,
  p_source_ref text default null,
  p_source_revision text default null,
  p_expires_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb,
  p_created_by_execution_id text default 'UNKNOWN'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_existing private.lf_human_decision_requests_v1%rowtype;
  v_request private.lf_human_decision_requests_v1%rowtype;
  v_sha text;
begin
  if jsonb_typeof(p_allowed_actions) <> 'array'
     or jsonb_array_length(p_allowed_actions)=0 then
    raise exception 'HUMAN_DECISION_ALLOWED_ACTIONS_REQUIRED';
  end if;

  if nullif(btrim(coalesce(p_required_authority_ref,'')),'') is null then
    raise exception 'HUMAN_DECISION_AUTHORITY_REF_REQUIRED';
  end if;

  if nullif(btrim(coalesce(p_required_reviewer_role,'')),'') is null then
    raise exception 'HUMAN_DECISION_REVIEWER_ROLE_REQUIRED';
  end if;

  v_sha:=private.fn_lf_human_decision_request_sha_v1(
    p_producer_code,p_subject_type,p_subject_key,coalesce(p_subject_ref,'{}'::jsonb),
    p_required_authority_ref,p_required_reviewer_role,p_allowed_actions,
    coalesce(p_evidence_refs,'[]'::jsonb),p_currentness_sha256,
    coalesce(p_impact,'{}'::jsonb),p_source_ref,p_source_revision,
    coalesce(p_metadata,'{}'::jsonb)
  );

  select *
    into v_existing
  from private.lf_human_decision_requests_v1
  where producer_code=p_producer_code
    and subject_type=p_subject_type
    and subject_key=p_subject_key
    and status='OPEN'
  for update;

  if found and v_existing.request_sha256=v_sha then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open/v1',
      'request_id',v_existing.request_id,
      'request_sha256',v_existing.request_sha256,
      'status',v_existing.status,
      'idempotent_reuse',true
    );
  end if;

  if found then
    update private.lf_human_decision_requests_v1
       set status='SUPERSEDED',
           updated_by_execution_id=p_created_by_execution_id
     where request_id=v_existing.request_id;
  end if;

  insert into private.lf_human_decision_requests_v1(
    producer_code,subject_type,subject_key,subject_ref,
    required_authority_ref,required_reviewer_role,allowed_actions,
    evidence_refs,currentness_sha256,impact,source_ref,source_revision,
    request_sha256,expires_at,supersedes_request_id,metadata,
    created_by_execution_id
  )
  values(
    p_producer_code,p_subject_type,p_subject_key,coalesce(p_subject_ref,'{}'::jsonb),
    p_required_authority_ref,p_required_reviewer_role,p_allowed_actions,
    coalesce(p_evidence_refs,'[]'::jsonb),p_currentness_sha256,
    coalesce(p_impact,'{}'::jsonb),p_source_ref,p_source_revision,
    v_sha,p_expires_at,
    case when v_existing.request_id is null then null else v_existing.request_id end,
    coalesce(p_metadata,'{}'::jsonb),
    coalesce(nullif(p_created_by_execution_id,''),'UNKNOWN')
  )
  returning * into v_request;

  return jsonb_build_object(
    'schema_version','lf-human-decision-open/v1',
    'request_id',v_request.request_id,
    'request_sha256',v_request.request_sha256,
    'status',v_request.status,
    'idempotent_reuse',false,
    'supersedes_request_id',v_request.supersedes_request_id
  );
end
$function$;

create or replace function private.fn_lf_human_decision_consume_v1(
  p_request_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'schema_version','lf-human-decision-consume/v1',
    'request_id',r.request_id,
    'request_status',
      case
        when r.status='OPEN' and r.expires_at is not null and r.expires_at<=now() then 'EXPIRED'
        else r.status
      end,
    'producer_code',r.producer_code,
    'subject_type',r.subject_type,
    'subject_key',r.subject_key,
    'request_sha256',r.request_sha256,
    'currentness_sha256',r.currentness_sha256,
    'decision_receipt',
      case when d.receipt_id is null then null else jsonb_build_object(
        'receipt_id',d.receipt_id,
        'decision_code',d.decision_code,
        'decision_payload',d.decision_payload,
        'reviewer_role',d.reviewer_role,
        'authority_ref',d.authority_ref,
        'authority_receipt_ref',d.authority_receipt_ref,
        'authority_receipt_sha256',d.authority_receipt_sha256,
        'observed_currentness_sha256',d.observed_currentness_sha256,
        'receipt_sha256',d.receipt_sha256,
        'decided_at',d.decided_at
      ) end
  )
  from private.lf_human_decision_requests_v1 r
  left join private.lf_human_decision_receipts_v1 d on d.request_id=r.request_id
  where r.request_id=p_request_id
$function$;

create or replace view private.v_lf_human_decision_request_state_v1 as
select
  r.*,
  case
    when r.status='OPEN' and r.expires_at is not null and r.expires_at<=now() then 'EXPIRED'
    else r.status
  end as lifecycle_state,
  d.receipt_id,
  d.decision_code,
  d.receipt_sha256,
  d.decided_at
from private.lf_human_decision_requests_v1 r
left join private.lf_human_decision_receipts_v1 d on d.request_id=r.request_id;

create or replace view private.v_lf_human_decision_active_queue_v1 as
select
  request_id,
  producer_code,
  subject_type,
  subject_key,
  subject_ref,
  required_authority_ref,
  required_reviewer_role,
  allowed_actions,
  evidence_refs,
  currentness_sha256,
  impact,
  source_ref,
  source_revision,
  request_sha256,
  opened_at,
  expires_at,
  metadata
from private.v_lf_human_decision_request_state_v1
where lifecycle_state='OPEN';

revoke all on private.lf_human_decision_requests_v1 from public,anon,authenticated;
revoke all on private.lf_human_decision_receipts_v1 from public,anon,authenticated;
revoke all on private.v_lf_human_decision_request_state_v1 from public,anon,authenticated;
revoke all on private.v_lf_human_decision_active_queue_v1 from public,anon,authenticated;

revoke all on function private.fn_lf_human_decision_open_v1(
  text,text,text,jsonb,text,text,jsonb,jsonb,text,jsonb,text,text,timestamptz,jsonb,text
) from public,anon,authenticated;

revoke all on function private.fn_lf_human_decision_consume_v1(uuid)
  from public,anon,authenticated;

comment on table private.lf_human_decision_requests_v1 is
'Canonical transversal request ledger for HUMAN_DECISION_ROUTING. Producer-specific stores remain source evidence, not generic authority.';

comment on table private.lf_human_decision_receipts_v1 is
'Canonical transversal decision receipt ledger. A receipt is structurally bound to request authority role currentness and allowed action.';

comment on view private.v_lf_human_decision_active_queue_v1 is
'Canonical consolidated active human-decision queue. Does not expose a public unauthenticated decision-write API.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-DECISION-ROUTING-ARCHITECTURE-001',
  'PROGRAMMING_GOVERNANCE',
  'Human decisions belong in one transversal routing capability, not stage-specific patches',
  'IG already identifies HUMAN_DECISION_REQUIRED proposals and Story Creator P0 already has challenge/queue/decision mechanics, while Programming only returned HUMAN_DECISION_REQUIRED. The durable routing contract must therefore be transversal: producer detects and supplies evidence; HUMAN_DECISION_ROUTING owns request lifecycle, consolidated queue and decision receipt; the original consumer interprets the receipt.',
  'Stage-specific human review stores evolved independently and Programming lacked the durable request/consumer loop.',
  'PRODUCER -> GENERIC REQUEST -> CONSOLIDATED QUEUE -> AUTHORITY-SPECIFIC REVIEW -> GENERIC RECEIPT -> ORIGINAL CONSUMER.',
  'Do not wire Programming directly to Story P0 tables. Do not turn input_gap_proposals into a global queue. Do not use LF product B2B_ADMIN_LF as software-governance authority. Rehome producer semantics through adapters and preserve historical stage evidence.',
  'Candidate migration creates generic request/receipt ledgers, currentness/supersession guards, allowed-action/authority/role checks and an active queue. It deliberately performs no IG/Story/Programming cutover and exposes no unauthenticated decision-write API.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008043000_human_decision_routing_v1.sql',
  now()
)
on conflict (codigo) do update
set categoria=excluded.categoria,
    titulo=excluded.titulo,
    descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
