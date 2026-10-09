-- HUMAN_DECISION_POLICY_REGISTRY_V1
-- Canonical decision-class classification and authority routing.
-- Producers no longer choose authority_ref/reviewer_role/actions in canonical V2 adapters.
-- No real human authority is activated and no consumer cutover occurs here.

create table if not exists private.lf_human_decision_classes_v1 (
  decision_class text primary key,
  authority_domain text not null,
  description text not null,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text,
  check (decision_class ~ '^[A-Z][A-Z0-9_]*$'),
  check (authority_domain ~ '^[A-Z][A-Z0-9_]*$'),
  check (status in ('ACTIVE','DISABLED'))
);

create table if not exists private.lf_human_decision_classification_rules_v1 (
  rule_code text primary key,
  producer_code text not null,
  subject_type text not null,
  attribute_name text not null,
  attribute_value text,
  decision_class text not null
    references private.lf_human_decision_classes_v1(decision_class) on delete restrict,
  priority integer not null default 100,
  status text not null default 'ACTIVE',
  rule_sha256 text not null,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text,
  check (rule_code ~ '^[A-Z][A-Z0-9_]*$'),
  check (producer_code ~ '^[A-Z][A-Z0-9_]*$'),
  check (subject_type ~ '^[A-Z][A-Z0-9_]*$'),
  check (attribute_name in ('ANY','FAMILY_CODE','REQUIRED_REVIEWER_ROLE')),
  check (
    (attribute_name='ANY' and attribute_value is null)
    or
    (attribute_name<>'ANY' and nullif(btrim(coalesce(attribute_value,'')),'') is not null)
  ),
  check (priority between 1 and 1000),
  check (status in ('ACTIVE','DISABLED')),
  check (rule_sha256 ~ '^[0-9a-f]{64}$')
);

create unique index if not exists uq_lf_human_decision_classification_rule_match_v1
  on private.lf_human_decision_classification_rules_v1(
    producer_code,subject_type,attribute_name,coalesce(attribute_value,'')
  )
  where status='ACTIVE';

create table if not exists private.lf_human_decision_route_policies_v1 (
  policy_code text primary key,
  decision_class text not null
    references private.lf_human_decision_classes_v1(decision_class) on delete restrict,
  producer_code text not null,
  subject_type text not null,
  authority_domain text not null,
  required_authority_ref text,
  reviewer_role_mode text not null default 'STATIC',
  required_reviewer_role text,
  allowed_actions_mode text not null default 'STATIC',
  static_allowed_actions jsonb not null default '[]'::jsonb,
  status text not null default 'PENDING_AUTHORITY',
  policy_sha256 text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text,
  check (policy_code ~ '^[A-Z][A-Z0-9_]*$'),
  check (producer_code ~ '^[A-Z][A-Z0-9_]*$'),
  check (subject_type ~ '^[A-Z][A-Z0-9_]*$'),
  check (authority_domain ~ '^[A-Z][A-Z0-9_]*$'),
  check (reviewer_role_mode in ('STATIC','SOURCE')),
  check (allowed_actions_mode in ('STATIC','SOURCE')),
  check (jsonb_typeof(static_allowed_actions)='array'),
  check (status in ('PENDING_AUTHORITY','ACTIVE','DISABLED')),
  check (
    status<>'ACTIVE'
    or (
      nullif(btrim(coalesce(required_authority_ref,'')),'') is not null
      and (
        reviewer_role_mode='SOURCE'
        or nullif(btrim(coalesce(required_reviewer_role,'')),'') is not null
      )
      and (
        allowed_actions_mode='SOURCE'
        or jsonb_array_length(static_allowed_actions)>0
      )
    )
  ),
  check (policy_sha256 ~ '^[0-9a-f]{64}$'),
  check (jsonb_typeof(metadata)='object'),
  unique(decision_class,producer_code,subject_type)
);

alter table private.lf_human_decision_classes_v1 enable row level security;
alter table private.lf_human_decision_classification_rules_v1 enable row level security;
alter table private.lf_human_decision_route_policies_v1 enable row level security;

revoke all on private.lf_human_decision_classes_v1 from public,anon,authenticated;
revoke all on private.lf_human_decision_classification_rules_v1 from public,anon,authenticated;
revoke all on private.lf_human_decision_route_policies_v1 from public,anon,authenticated;

create or replace function private.fn_lf_human_decision_rule_sha_v1(
  p_rule_code text,
  p_producer_code text,
  p_subject_type text,
  p_attribute_name text,
  p_attribute_value text,
  p_decision_class text,
  p_priority integer,
  p_status text
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
          'schema_version','lf-human-decision-classification-rule/v1',
          'rule_code',p_rule_code,
          'producer_code',p_producer_code,
          'subject_type',p_subject_type,
          'attribute_name',p_attribute_name,
          'attribute_value',p_attribute_value,
          'decision_class',p_decision_class,
          'priority',p_priority,
          'status',p_status
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
$function$;

create or replace function private.fn_lf_human_decision_route_policy_sha_v1(
  p_policy_code text,
  p_decision_class text,
  p_producer_code text,
  p_subject_type text,
  p_authority_domain text,
  p_required_authority_ref text,
  p_reviewer_role_mode text,
  p_required_reviewer_role text,
  p_allowed_actions_mode text,
  p_static_allowed_actions jsonb,
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
          'schema_version','lf-human-decision-route-policy/v1',
          'policy_code',p_policy_code,
          'decision_class',p_decision_class,
          'producer_code',p_producer_code,
          'subject_type',p_subject_type,
          'authority_domain',p_authority_domain,
          'required_authority_ref',p_required_authority_ref,
          'reviewer_role_mode',p_reviewer_role_mode,
          'required_reviewer_role',p_required_reviewer_role,
          'allowed_actions_mode',p_allowed_actions_mode,
          'static_allowed_actions',coalesce(p_static_allowed_actions,'[]'::jsonb),
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

create or replace function private.fn_lf_human_decision_rule_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_expected text;
begin
  v_expected:=private.fn_lf_human_decision_rule_sha_v1(
    new.rule_code,new.producer_code,new.subject_type,new.attribute_name,
    new.attribute_value,new.decision_class,new.priority,new.status
  );

  if new.rule_sha256 is distinct from v_expected then
    raise exception 'HUMAN_DECISION_CLASSIFICATION_RULE_SHA_MISMATCH';
  end if;

  if tg_op='UPDATE' then
    new.updated_at:=now();
  end if;

  return new;
end
$function$;

drop trigger if exists trg_lf_human_decision_rule_guard_v1
  on private.lf_human_decision_classification_rules_v1;

create trigger trg_lf_human_decision_rule_guard_v1
before insert or update
on private.lf_human_decision_classification_rules_v1
for each row
execute function private.fn_lf_human_decision_rule_guard_v1();

create or replace function private.fn_lf_human_decision_route_policy_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_expected text;
  v_class_domain text;
begin
  select authority_domain
    into v_class_domain
  from private.lf_human_decision_classes_v1
  where decision_class=new.decision_class
    and status='ACTIVE';

  if v_class_domain is null then
    raise exception 'HUMAN_DECISION_CLASS_NOT_ACTIVE:%',new.decision_class;
  end if;

  if new.authority_domain is distinct from v_class_domain then
    raise exception 'HUMAN_DECISION_AUTHORITY_DOMAIN_MISMATCH:%:%',
      new.authority_domain,v_class_domain;
  end if;

  v_expected:=private.fn_lf_human_decision_route_policy_sha_v1(
    new.policy_code,new.decision_class,new.producer_code,new.subject_type,
    new.authority_domain,new.required_authority_ref,new.reviewer_role_mode,
    new.required_reviewer_role,new.allowed_actions_mode,new.static_allowed_actions,
    new.status,new.metadata
  );

  if new.policy_sha256 is distinct from v_expected then
    raise exception 'HUMAN_DECISION_ROUTE_POLICY_SHA_MISMATCH';
  end if;

  if tg_op='UPDATE' then
    new.updated_at:=now();
  end if;

  return new;
end
$function$;

drop trigger if exists trg_lf_human_decision_route_policy_guard_v1
  on private.lf_human_decision_route_policies_v1;

create trigger trg_lf_human_decision_route_policy_guard_v1
before insert or update
on private.lf_human_decision_route_policies_v1
for each row
execute function private.fn_lf_human_decision_route_policy_guard_v1();

insert into private.lf_human_decision_classes_v1(
  decision_class,authority_domain,description,status,created_by_execution_id
)
values
  ('SOFTWARE_GOVERNANCE','LF_GOVERNANCE','Programming, CI/CD, governance, runtime-policy and engineering applicability decisions.','ACTIVE','HUMAN_DECISION_POLICY_REGISTRY_V1'),
  ('PRODUCT_LF','LF_PRODUCT','LF functional/product behavior and canonical product-domain decisions.','ACTIVE','HUMAN_DECISION_POLICY_REGISTRY_V1'),
  ('UX_UI','LF_UX','Human visual, cognitive and interface adjudication.','ACTIVE','HUMAN_DECISION_POLICY_REGISTRY_V1'),
  ('PRIVACY','LF_PRIVACY','Privacy, PII and privacy-governance human decisions.','ACTIVE','HUMAN_DECISION_POLICY_REGISTRY_V1'),
  ('SOFTWARE_SECURITY','LF_SOFTWARE_SECURITY','Software-security review and security-specific adjudication.','ACTIVE','HUMAN_DECISION_POLICY_REGISTRY_V1'),
  ('LEGAL','LF_LEGAL','Legal, contractual, consent and legal-copy decisions.','ACTIVE','HUMAN_DECISION_POLICY_REGISTRY_V1'),
  ('DATA_OPERATIONS','LF_DATA_OPERATIONS','Data and operational business decisions that require human authority.','ACTIVE','HUMAN_DECISION_POLICY_REGISTRY_V1')
on conflict(decision_class) do nothing;

do $seed$
declare
  v_rule record;
  v_sha text;
  v_policy record;
  v_policy_sha text;
begin
  for v_rule in
    select *
    from (values
      ('HDR_RULE_PROGRAMMING_ALL','PROGRAMMING','CHECKPOINT_VALIDATION_FAILURE','ANY',null::text,'SOFTWARE_GOVERNANCE',100),
      ('HDR_RULE_STORY_VISUAL','STORY_CREATOR_P0','VISUAL_REVIEW','REQUIRED_REVIEWER_ROLE','P0_VISUAL_ADJUDICATOR','UX_UI',300),
      ('HDR_RULE_STORY_PRIVACY','STORY_CREATOR_P0','VISUAL_REVIEW','REQUIRED_REVIEWER_ROLE','P0_PRIVACY_REVIEWER','PRIVACY',300),
      ('HDR_RULE_STORY_SECURITY','STORY_CREATOR_P0','VISUAL_REVIEW','REQUIRED_REVIEWER_ROLE','P0_SECURITY_REVIEWER','SOFTWARE_SECURITY',300),
      ('HDR_RULE_IG_FEATURE_FLAGS','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','FAMILY_CODE','FEATURE_FLAGS','PRODUCT_LF',300),
      ('HDR_RULE_IG_I18N','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','FAMILY_CODE','I18N_FORMATS','PRODUCT_LF',300),
      ('HDR_RULE_IG_STATES','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','FAMILY_CODE','STATES','PRODUCT_LF',300),
      ('HDR_RULE_IG_TRANSITIONS','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','FAMILY_CODE','TRANSITIONS','PRODUCT_LF',300),
      ('HDR_RULE_IG_PRIVACY','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','FAMILY_CODE','PRIVACY_PII','PRIVACY',300),
      ('HDR_RULE_IG_RUNTIME','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','FAMILY_CODE','RUNTIME_CONFIG','SOFTWARE_GOVERNANCE',300),
      ('HDR_RULE_IG_TESTING','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','FAMILY_CODE','TESTING_OBLIGATIONS','SOFTWARE_GOVERNANCE',300)
    ) as x(rule_code,producer_code,subject_type,attribute_name,attribute_value,decision_class,priority)
  loop
    v_sha:=private.fn_lf_human_decision_rule_sha_v1(
      v_rule.rule_code,v_rule.producer_code,v_rule.subject_type,
      v_rule.attribute_name,v_rule.attribute_value,v_rule.decision_class,
      v_rule.priority,'ACTIVE'
    );

    insert into private.lf_human_decision_classification_rules_v1(
      rule_code,producer_code,subject_type,attribute_name,attribute_value,
      decision_class,priority,status,rule_sha256,created_by_execution_id
    )
    values(
      v_rule.rule_code,v_rule.producer_code,v_rule.subject_type,
      v_rule.attribute_name,v_rule.attribute_value,v_rule.decision_class,
      v_rule.priority,'ACTIVE',v_sha,'HUMAN_DECISION_POLICY_REGISTRY_V1'
    )
    on conflict(rule_code) do nothing;
  end loop;

  for v_policy in
    select *
    from (values
      (
        'HDR_ROUTE_PROGRAMMING_SOFTWARE_GOVERNANCE',
        'SOFTWARE_GOVERNANCE','PROGRAMMING','CHECKPOINT_VALIDATION_FAILURE',
        'LF_GOVERNANCE','contract://LF_GOVERNANCE_SUPER_ADMIN_V1',
        'STATIC','SUPER_ADMIN_GOVERNANCE','STATIC',
        '["REVALIDATE","REPAIR_REQUIRED","REJECT","NOT_APPLICABLE_WITH_AUTHORITY"]'::jsonb,
        'PENDING_AUTHORITY',
        '{"blocker":"LF_GOVERNANCE_SUPER_ADMIN_V1_IS_CANDIDATE_READ_ONLY"}'::jsonb
      ),
      (
        'HDR_ROUTE_IG_SOFTWARE_GOVERNANCE',
        'SOFTWARE_GOVERNANCE','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL',
        'LF_GOVERNANCE','contract://LF_GOVERNANCE_SUPER_ADMIN_V1',
        'STATIC','SUPER_ADMIN_GOVERNANCE','STATIC',
        '["ACCEPT_PROPOSAL","REJECT_PROPOSAL","REQUEST_MORE_EVIDENCE"]'::jsonb,
        'PENDING_AUTHORITY',
        '{"blocker":"LF_GOVERNANCE_SUPER_ADMIN_V1_IS_CANDIDATE_READ_ONLY"}'::jsonb
      ),
      (
        'HDR_ROUTE_IG_PRODUCT_LF',
        'PRODUCT_LF','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL',
        'LF_PRODUCT',null,
        'STATIC',null,'STATIC',
        '["ACCEPT_PROPOSAL","REJECT_PROPOSAL","REQUEST_MORE_EVIDENCE"]'::jsonb,
        'PENDING_AUTHORITY',
        '{"blocker":"LF_PRODUCT_DECISION_AUTHORITY_NOT_MATERIALIZED"}'::jsonb
      ),
      (
        'HDR_ROUTE_IG_PRIVACY',
        'PRIVACY','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL',
        'LF_PRIVACY',null,
        'STATIC',null,'STATIC',
        '["ACCEPT_PROPOSAL","REJECT_PROPOSAL","REQUEST_MORE_EVIDENCE"]'::jsonb,
        'PENDING_AUTHORITY',
        '{"blocker":"LF_PRIVACY_DECISION_AUTHORITY_NOT_MATERIALIZED"}'::jsonb
      ),
      (
        'HDR_ROUTE_STORY_UX',
        'UX_UI','STORY_CREATOR_P0','VISUAL_REVIEW',
        'LF_UX',null,
        'SOURCE',null,'SOURCE','[]'::jsonb,
        'PENDING_AUTHORITY',
        '{"blocker":"LF_UX_DECISION_AUTHORITY_NOT_MATERIALIZED"}'::jsonb
      ),
      (
        'HDR_ROUTE_STORY_PRIVACY',
        'PRIVACY','STORY_CREATOR_P0','VISUAL_REVIEW',
        'LF_PRIVACY',null,
        'SOURCE',null,'SOURCE','[]'::jsonb,
        'PENDING_AUTHORITY',
        '{"blocker":"LF_PRIVACY_DECISION_AUTHORITY_NOT_MATERIALIZED"}'::jsonb
      ),
      (
        'HDR_ROUTE_STORY_SECURITY',
        'SOFTWARE_SECURITY','STORY_CREATOR_P0','VISUAL_REVIEW',
        'LF_SOFTWARE_SECURITY',null,
        'SOURCE',null,'SOURCE','[]'::jsonb,
        'PENDING_AUTHORITY',
        '{"blocker":"LF_SOFTWARE_SECURITY_DECISION_AUTHORITY_NOT_MATERIALIZED"}'::jsonb
      )
    ) as x(
      policy_code,decision_class,producer_code,subject_type,authority_domain,
      required_authority_ref,reviewer_role_mode,required_reviewer_role,
      allowed_actions_mode,static_allowed_actions,status,metadata
    )
  loop
    v_policy_sha:=private.fn_lf_human_decision_route_policy_sha_v1(
      v_policy.policy_code,v_policy.decision_class,v_policy.producer_code,
      v_policy.subject_type,v_policy.authority_domain,v_policy.required_authority_ref,
      v_policy.reviewer_role_mode,v_policy.required_reviewer_role,
      v_policy.allowed_actions_mode,v_policy.static_allowed_actions,
      v_policy.status,v_policy.metadata
    );

    insert into private.lf_human_decision_route_policies_v1(
      policy_code,decision_class,producer_code,subject_type,authority_domain,
      required_authority_ref,reviewer_role_mode,required_reviewer_role,
      allowed_actions_mode,static_allowed_actions,status,policy_sha256,metadata,
      created_by_execution_id
    )
    values(
      v_policy.policy_code,v_policy.decision_class,v_policy.producer_code,
      v_policy.subject_type,v_policy.authority_domain,v_policy.required_authority_ref,
      v_policy.reviewer_role_mode,v_policy.required_reviewer_role,
      v_policy.allowed_actions_mode,v_policy.static_allowed_actions,
      v_policy.status,v_policy_sha,v_policy.metadata,'HUMAN_DECISION_POLICY_REGISTRY_V1'
    )
    on conflict(policy_code) do nothing;
  end loop;
end
$seed$;

create or replace function private.fn_lf_human_decision_resolve_policy_v1(
  p_producer_code text,
  p_subject_type text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_rule private.lf_human_decision_classification_rules_v1%rowtype;
  v_policy private.lf_human_decision_route_policies_v1%rowtype;
  v_reviewer_role text;
  v_allowed_actions jsonb;
  v_lower_policy_active boolean;
begin
  if jsonb_typeof(coalesce(p_context,'{}'::jsonb)) <> 'object' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_CONTEXT_INVALID'
    );
  end if;

  select r.*
    into v_rule
  from private.lf_human_decision_classification_rules_v1 r
  where r.status='ACTIVE'
    and r.producer_code=p_producer_code
    and r.subject_type=p_subject_type
    and (
      r.attribute_name='ANY'
      or (r.attribute_name='FAMILY_CODE' and r.attribute_value=p_context->>'family_code')
      or (r.attribute_name='REQUIRED_REVIEWER_ROLE' and r.attribute_value=p_context->>'required_reviewer_role')
    )
  order by r.priority desc,r.rule_code
  limit 1;

  if not found then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_CLASS_UNRESOLVED',
      'producer_code',p_producer_code,
      'subject_type',p_subject_type
    );
  end if;

  select p.*
    into v_policy
  from private.lf_human_decision_route_policies_v1 p
  where p.decision_class=v_rule.decision_class
    and p.producer_code=p_producer_code
    and p.subject_type=p_subject_type
  limit 1;

  if not found then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_ROUTE_POLICY_NOT_FOUND',
      'decision_class',v_rule.decision_class,
      'classification_rule',v_rule.rule_code
    );
  end if;

  v_reviewer_role:=case
    when v_policy.reviewer_role_mode='SOURCE'
      then nullif(btrim(coalesce(p_context->>'required_reviewer_role','')),'')
    else nullif(btrim(coalesce(v_policy.required_reviewer_role,'')),'')
  end;

  v_allowed_actions:=case
    when v_policy.allowed_actions_mode='SOURCE'
      then p_context->'allowed_actions'
    else v_policy.static_allowed_actions
  end;

  if v_policy.status<>'ACTIVE' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_ROUTE_POLICY_NOT_ACTIVE',
      'decision_class',v_rule.decision_class,
      'classification_rule',v_rule.rule_code,
      'policy_code',v_policy.policy_code,
      'policy_status',v_policy.status,
      'authority_domain',v_policy.authority_domain,
      'required_authority_ref',v_policy.required_authority_ref,
      'required_reviewer_role',v_reviewer_role,
      'allowed_actions',coalesce(v_allowed_actions,'[]'::jsonb),
      'metadata',v_policy.metadata
    );
  end if;

  if nullif(btrim(coalesce(v_policy.required_authority_ref,'')),'') is null then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_AUTHORITY_REF_UNMATERIALIZED',
      'decision_class',v_rule.decision_class,
      'policy_code',v_policy.policy_code,
      'authority_domain',v_policy.authority_domain
    );
  end if;

  if v_reviewer_role is null then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_REVIEWER_ROLE_UNMATERIALIZED',
      'decision_class',v_rule.decision_class,
      'policy_code',v_policy.policy_code
    );
  end if;

  if jsonb_typeof(v_allowed_actions)<>'array'
     or jsonb_array_length(v_allowed_actions)=0 then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_ALLOWED_ACTIONS_UNMATERIALIZED',
      'decision_class',v_rule.decision_class,
      'policy_code',v_policy.policy_code
    );
  end if;

  select exists(
    select 1
    from private.lf_human_decision_authority_policies_v1 a
    where a.authority_ref=v_policy.required_authority_ref
      and a.reviewer_role=v_reviewer_role
      and a.status='ACTIVE'
  )
  into v_lower_policy_active;

  if not v_lower_policy_active then
    return jsonb_build_object(
      'schema_version','lf-human-decision-policy-resolution/v1',
      'state','BLOCKED',
      'blocker_code','DECISION_AUTHORITY_CHANNEL_POLICY_NOT_ACTIVE',
      'decision_class',v_rule.decision_class,
      'classification_rule',v_rule.rule_code,
      'policy_code',v_policy.policy_code,
      'authority_domain',v_policy.authority_domain,
      'required_authority_ref',v_policy.required_authority_ref,
      'required_reviewer_role',v_reviewer_role,
      'allowed_actions',v_allowed_actions
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-policy-resolution/v1',
    'state','ACTIVE',
    'decision_class',v_rule.decision_class,
    'classification_rule',v_rule.rule_code,
    'policy_code',v_policy.policy_code,
    'authority_domain',v_policy.authority_domain,
    'required_authority_ref',v_policy.required_authority_ref,
    'required_reviewer_role',v_reviewer_role,
    'allowed_actions',v_allowed_actions
  );
end
$function$;

create or replace function private.fn_lf_human_decision_open_ig_v2(
  p_proposal_id bigint,
  p_created_by_execution_id text default 'INPUT_GOVERNANCE_ADAPTER_V2'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_p programacion.input_gap_proposals%rowtype;
  v_route jsonb;
begin
  select * into strict v_p
  from programacion.input_gap_proposals
  where id=p_proposal_id;

  v_route:=private.fn_lf_human_decision_resolve_policy_v1(
    'INPUT_GOVERNANCE',
    'INPUT_GAP_PROPOSAL',
    jsonb_build_object('family_code',v_p.family_code)
  );

  if v_route->>'state'<>'ACTIVE' then
    raise exception 'HUMAN_DECISION_ROUTE_NOT_ACTIVE:%:%',
      coalesce(v_route->>'blocker_code','UNKNOWN'),
      coalesce(v_route->>'decision_class','UNRESOLVED');
  end if;

  return private.fn_lf_human_decision_open_ig_v1(
    p_proposal_id,
    v_route->>'required_authority_ref',
    v_route->>'required_reviewer_role',
    v_route->'allowed_actions',
    p_created_by_execution_id
  );
end
$function$;

create or replace function private.fn_lf_human_decision_open_story_p0_v2(
  p_challenge_id text,
  p_created_by_execution_id text default 'STORY_CREATOR_P0_ADAPTER_V2'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_c private.v_lf_p0_human_review_active_queue_v1%rowtype;
  v_route jsonb;
begin
  select * into strict v_c
  from private.v_lf_p0_human_review_active_queue_v1
  where challenge_id=p_challenge_id;

  v_route:=private.fn_lf_human_decision_resolve_policy_v1(
    'STORY_CREATOR_P0',
    'VISUAL_REVIEW',
    jsonb_build_object(
      'required_reviewer_role',v_c.required_reviewer_role,
      'allowed_actions',v_c.reviewer_actions
    )
  );

  if v_route->>'state'<>'ACTIVE' then
    raise exception 'HUMAN_DECISION_ROUTE_NOT_ACTIVE:%:%',
      coalesce(v_route->>'blocker_code','UNKNOWN'),
      coalesce(v_route->>'decision_class','UNRESOLVED');
  end if;

  if v_route->>'required_reviewer_role' is distinct from v_c.required_reviewer_role then
    raise exception 'HUMAN_DECISION_SOURCE_REVIEWER_ROLE_DRIFT';
  end if;

  return private.fn_lf_human_decision_open_story_p0_v1(
    p_challenge_id,
    v_route->>'required_authority_ref',
    p_created_by_execution_id
  );
end
$function$;

create or replace function private.fn_lf_human_decision_open_programming_v2(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_created_by_execution_id text default 'PROGRAMMING_HUMAN_DECISION_ADAPTER_V2'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_route jsonb;
begin
  v_route:=private.fn_lf_human_decision_resolve_policy_v1(
    'PROGRAMMING',
    'CHECKPOINT_VALIDATION_FAILURE',
    '{}'::jsonb
  );

  if v_route->>'state'<>'ACTIVE' then
    raise exception 'HUMAN_DECISION_ROUTE_NOT_ACTIVE:%:%',
      coalesce(v_route->>'blocker_code','UNKNOWN'),
      coalesce(v_route->>'decision_class','UNRESOLVED');
  end if;

  return private.fn_lf_human_decision_open_programming_v1(
    p_run_id,p_plan_code,p_unit_code,p_checkpoint_code,
    v_route->>'required_authority_ref',
    v_route->>'required_reviewer_role',
    v_route->'allowed_actions',
    p_created_by_execution_id
  );
end
$function$;

revoke all on function private.fn_lf_human_decision_resolve_policy_v1(text,text,jsonb)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_ig_v2(bigint,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_story_p0_v2(text,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_programming_v2(bigint,text,text,text,text)
  from public,anon,authenticated;

comment on function private.fn_lf_human_decision_resolve_policy_v1(text,text,jsonb) is
'Canonical decision-class and route resolver. Producers supply source context only; authority, reviewer and actions come from governed routing policy. Unknown sources fail closed.';

comment on function private.fn_lf_human_decision_open_programming_v2(bigint,text,text,text,text) is
'Canonical Programming human-decision adapter. No caller-supplied authority_ref, reviewer_role or allowed_actions.';

do $cap$
declare
  v_manifest jsonb;
  v_sha text;
  v_existing text;
begin
  select manifest into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.1'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_1_REQUIRED';
  end if;

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.2"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{contract,decision_class_registry}','"private.lf_human_decision_classes_v1"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{contract,classification_registry}','"private.lf_human_decision_classification_rules_v1"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{contract,route_policy_registry}','"private.lf_human_decision_route_policies_v1"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{contract,policy_resolver}','"private.fn_lf_human_decision_resolve_policy_v1"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{usage,ig_open}','"private.fn_lf_human_decision_open_ig_v2"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{usage,story_open}','"private.fn_lf_human_decision_open_story_p0_v2"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{usage,programming_open}','"private.fn_lf_human_decision_open_programming_v2"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,decision_policy_registry_live}','true'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,free_form_authority_in_canonical_adapters}','false'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,authority_policy_active}','false'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,consumer_cutover}','false'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,current_pointer}','false'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,cutover_blocker}','"HUMAN-DECISION-AUTHORITY-POLICY-ACTIVATION-001"'::jsonb,true);

  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  select manifest_sha256 into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.2';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_DECISION_ROUTING_VERSION_1_0_2_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_DECISION_ROUTING','1.0.2',1,0,2,
    'RELEASED','1.0.1',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008072000_human_decision_policy_registry_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_human_decision_resolve_policy_v1',
    'HUMAN_DECISION_POLICY_REGISTRY_V1'
  )
  on conflict(capability_code,version) do nothing;

  if exists(
    select 1 from public.lf_capability_current
    where capability_code='HUMAN_DECISION_ROUTING'
  ) then
    raise exception 'HUMAN_DECISION_ROUTING_CURRENT_POINTER_PREMATURE';
  end if;
end
$cap$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-DECISION-POLICY-RESOLUTION-NO-PRODUCER-AUTHORITY-001',
  'PROGRAMMING_GOVERNANCE',
  'Human-decision producers must not choose their own authority',
  'Canonical V2 producer adapters accept only source identity/context. Decision class, authority domain, authority reference, reviewer role and allowed actions are resolved by governed classification and route-policy registries. Unknown classes and inactive routes fail closed.',
  'V1 adapters accepted authority_ref/reviewer_role/action inputs from the caller, which was safe while internal and gated but would become an architectural authority-injection risk if used for cutover.',
  'SOURCE CONTEXT -> DECISION CLASS -> ROUTE POLICY -> AUTHORITY/ROLE/ACTIONS -> HUMAN_DECISION_ROUTING.',
  'Use V2 adapters for future cutover. Keep V1 only as an internal compatibility layer called by V2 after resolution. Never activate a route policy until its authority contract and lower-level provenance-channel policy are both governed.',
  'Migration seeds deterministic classifications for current Programming, Story P0 and IG decision families, creates fail-closed policy resolution and releases HUMAN_DECISION_ROUTING 1.0.2 with current_pointer=false and consumer_cutover=false.',
  'HIGH','ACTIVO',
  'capability://HUMAN_DECISION_ROUTING@1.0.2',
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
