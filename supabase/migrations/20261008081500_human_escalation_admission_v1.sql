-- HUMAN_ESCALATION_ADMISSION_V1
-- Thin transversal admission gate that reuses existing automation/evidence capabilities.
-- Human routing is the last resort, never the first destination for uncertainty.

create table if not exists private.lf_human_escalation_policies_v1 (
  policy_code text primary key,
  producer_code text not null,
  subject_type text not null,
  reason_match_mode text not null default 'ANY',
  reason_code text,
  mode text not null,
  targeted_evidence_required boolean not null default false,
  safe_change_supported boolean not null default true,
  human_after_exhaustion boolean not null default false,
  status text not null default 'ACTIVE',
  policy_sha256 text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text,
  check (policy_code ~ '^[A-Z][A-Z0-9_]*$'),
  check (producer_code ~ '^[A-Z][A-Z0-9_]*$'),
  check (subject_type ~ '^[A-Z][A-Z0-9_]*$'),
  check (reason_match_mode in ('ANY','EXACT')),
  check (
    (reason_match_mode='ANY' and reason_code is null)
    or
    (reason_match_mode='EXACT' and nullif(btrim(coalesce(reason_code,'')),'') is not null)
  ),
  check (mode in ('EVIDENCE_THEN_HUMAN','PREQUALIFIED_HUMAN','AUTO_FIRST_NO_HUMAN')),
  check (status in ('ACTIVE','DISABLED')),
  check (policy_sha256 ~ '^[0-9a-f]{64}$'),
  check (jsonb_typeof(metadata)='object')
);

create unique index if not exists uq_lf_human_escalation_policy_match_v1
  on private.lf_human_escalation_policies_v1(
    producer_code,subject_type,reason_match_mode,coalesce(reason_code,'')
  )
  where status='ACTIVE';

alter table private.lf_human_escalation_policies_v1 enable row level security;
revoke all on private.lf_human_escalation_policies_v1 from public,anon,authenticated;

create or replace function private.fn_lf_human_escalation_policy_sha_v1(
  p_policy_code text,
  p_producer_code text,
  p_subject_type text,
  p_reason_match_mode text,
  p_reason_code text,
  p_mode text,
  p_targeted_evidence_required boolean,
  p_safe_change_supported boolean,
  p_human_after_exhaustion boolean,
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
          'schema_version','lf-human-escalation-policy/v1',
          'policy_code',p_policy_code,
          'producer_code',p_producer_code,
          'subject_type',p_subject_type,
          'reason_match_mode',p_reason_match_mode,
          'reason_code',p_reason_code,
          'mode',p_mode,
          'targeted_evidence_required',p_targeted_evidence_required,
          'safe_change_supported',p_safe_change_supported,
          'human_after_exhaustion',p_human_after_exhaustion,
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

create or replace function private.fn_lf_human_escalation_policy_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_expected text;
begin
  v_expected:=private.fn_lf_human_escalation_policy_sha_v1(
    new.policy_code,new.producer_code,new.subject_type,new.reason_match_mode,
    new.reason_code,new.mode,new.targeted_evidence_required,
    new.safe_change_supported,new.human_after_exhaustion,new.status,new.metadata
  );

  if new.policy_sha256 is distinct from v_expected then
    raise exception 'HUMAN_ESCALATION_POLICY_SHA_MISMATCH';
  end if;

  if tg_op='UPDATE' then
    new.updated_at:=now();
  end if;

  return new;
end
$function$;

drop trigger if exists trg_lf_human_escalation_policy_guard_v1
  on private.lf_human_escalation_policies_v1;

create trigger trg_lf_human_escalation_policy_guard_v1
before insert or update
on private.lf_human_escalation_policies_v1
for each row
execute function private.fn_lf_human_escalation_policy_guard_v1();

do $seed$
declare
  v record;
  v_sha text;
begin
  for v in
    select *
    from (values
      (
        'HEA_PROGRAMMING_DEFAULT',
        'PROGRAMMING','CHECKPOINT_VALIDATION_FAILURE','ANY',null::text,
        'AUTO_FIRST_NO_HUMAN',false,true,false,
        '{"rule":"DETERMINISTIC_FAILURE_IS_NOT_HUMAN_BY_DEFAULT"}'::jsonb
      ),
      (
        'HEA_IG_APPLICABILITY_AUTHORITY',
        'INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','EXACT','APPLICABILITY_AUTHORITY_REQUIRED',
        'EVIDENCE_THEN_HUMAN',true,true,true,
        '{"rule":"EXHAUST_DECISION_CHANGING_EVIDENCE_BEFORE_AUTHORITY_ESCALATION"}'::jsonb
      ),
      (
        'HEA_IG_FEATURE_FLAG_SOURCE',
        'INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','EXACT','FEATURE_FLAG_CANONICAL_SOURCE_INCOMPLETE',
        'EVIDENCE_THEN_HUMAN',true,true,true,
        '{"rule":"EXHAUST_CANONICAL_SOURCE_EVIDENCE_BEFORE_HUMAN"}'::jsonb
      ),
      (
        'HEA_IG_BOOTSTRAP_EVIDENCE',
        'INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','EXACT','BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL',
        'EVIDENCE_THEN_HUMAN',true,true,true,
        '{"rule":"TARGETED_EVIDENCE_FIRST"}'::jsonb
      ),
      (
        'HEA_STORY_P0_PREQUALIFIED',
        'STORY_CREATOR_P0','VISUAL_REVIEW','ANY',null::text,
        'PREQUALIFIED_HUMAN',false,false,true,
        '{"rule":"ACTIVE_P0_CHALLENGE_IS_ALREADY_SPECIALIZED_PREQUALIFICATION"}'::jsonb
      )
    ) as x(
      policy_code,producer_code,subject_type,reason_match_mode,reason_code,
      mode,targeted_evidence_required,safe_change_supported,human_after_exhaustion,metadata
    )
  loop
    v_sha:=private.fn_lf_human_escalation_policy_sha_v1(
      v.policy_code,v.producer_code,v.subject_type,v.reason_match_mode,v.reason_code,
      v.mode,v.targeted_evidence_required,v.safe_change_supported,
      v.human_after_exhaustion,'ACTIVE',v.metadata
    );

    insert into private.lf_human_escalation_policies_v1(
      policy_code,producer_code,subject_type,reason_match_mode,reason_code,
      mode,targeted_evidence_required,safe_change_supported,human_after_exhaustion,
      status,policy_sha256,metadata,created_by_execution_id
    )
    values(
      v.policy_code,v.producer_code,v.subject_type,v.reason_match_mode,v.reason_code,
      v.mode,v.targeted_evidence_required,v.safe_change_supported,v.human_after_exhaustion,
      'ACTIVE',v_sha,v.metadata,'HUMAN_ESCALATION_ADMISSION_V1'
    )
    on conflict(policy_code) do nothing;
  end loop;
end
$seed$;

create or replace function private.fn_lf_human_escalation_policy_resolve_v1(
  p_producer_code text,
  p_subject_type text,
  p_reason_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_policy private.lf_human_escalation_policies_v1%rowtype;
begin
  select p.*
    into v_policy
  from private.lf_human_escalation_policies_v1 p
  where p.status='ACTIVE'
    and p.producer_code=p_producer_code
    and p.subject_type=p_subject_type
    and (
      (p.reason_match_mode='EXACT' and p.reason_code=p_reason_code)
      or
      p.reason_match_mode='ANY'
    )
  order by case when p.reason_match_mode='EXACT' then 0 else 1 end,p.policy_code
  limit 1;

  if not found then
    return jsonb_build_object(
      'schema_version','lf-human-escalation-policy-resolution/v1',
      'state','BLOCKED',
      'code','HUMAN_ESCALATION_POLICY_NOT_FOUND',
      'producer_code',p_producer_code,
      'subject_type',p_subject_type,
      'reason_code',p_reason_code
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-escalation-policy-resolution/v1',
    'state','RESOLVED',
    'policy_code',v_policy.policy_code,
    'mode',v_policy.mode,
    'targeted_evidence_required',v_policy.targeted_evidence_required,
    'safe_change_supported',v_policy.safe_change_supported,
    'human_after_exhaustion',v_policy.human_after_exhaustion,
    'metadata',v_policy.metadata
  );
end
$function$;

create or replace function public.lf_human_escalation_admission_v1(
  p_request jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_manifest jsonb;
  v_expected_target_version text;
  v_expected_target_sha text;
  v_expected_safe_version text;
  v_expected_safe_sha text;
  v_live_target_version text;
  v_live_target_sha text;
  v_live_safe_version text;
  v_live_safe_sha text;
  v_producer text;
  v_subject_type text;
  v_reason_code text;
  v_subject_ref text;
  v_currentness text;
  v_deterministic_state text;
  v_resolver_state text;
  v_prequalified boolean;
  v_policy jsonb;
  v_target_request jsonb;
  v_target_result jsonb;
  v_safe_request jsonb;
  v_safe_result jsonb;
  v_candidate_count integer:=0;
begin
  if p_request is null or jsonb_typeof(p_request)<>'object' then
    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','BLOCKED','code','INVALID_REQUEST','human_queue_allowed',false
    );
  end if;

  select vr.manifest
    into v_manifest
  from public.lf_capability_current c
  join public.lf_capability_version_registry vr
    on vr.capability_code=c.capability_code
   and vr.version=c.version
   and vr.manifest_sha256=c.manifest_sha256
  where c.capability_code='HUMAN_ESCALATION_ADMISSION';

  if not found then
    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','BLOCKED','code','CAPABILITY_NOT_CURRENT','human_queue_allowed',false
    );
  end if;

  v_expected_target_version:=v_manifest#>>'{dependencies,TARGETED_EVIDENCE_ACQUISITION,version}';
  v_expected_target_sha:=v_manifest#>>'{dependencies,TARGETED_EVIDENCE_ACQUISITION,manifest_sha256}';
  v_expected_safe_version:=v_manifest#>>'{dependencies,SAFE_CHANGE_ADMISSION,version}';
  v_expected_safe_sha:=v_manifest#>>'{dependencies,SAFE_CHANGE_ADMISSION,manifest_sha256}';

  select version,manifest_sha256
    into v_live_target_version,v_live_target_sha
  from public.lf_capability_current
  where capability_code='TARGETED_EVIDENCE_ACQUISITION';

  select version,manifest_sha256
    into v_live_safe_version,v_live_safe_sha
  from public.lf_capability_current
  where capability_code='SAFE_CHANGE_ADMISSION';

  if v_live_target_version is distinct from v_expected_target_version
     or v_live_target_sha is distinct from v_expected_target_sha
     or v_live_safe_version is distinct from v_expected_safe_version
     or v_live_safe_sha is distinct from v_expected_safe_sha then
    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','BLOCKED','code','DEPENDENCY_CURRENTNESS_DRIFT',
      'human_queue_allowed',false
    );
  end if;

  v_producer:=upper(coalesce(p_request->>'producer_code',''));
  v_subject_type:=upper(coalesce(p_request->>'subject_type',''));
  v_reason_code:=coalesce(p_request->>'reason_code','');
  v_subject_ref:=nullif(btrim(coalesce(p_request->>'subject_ref','')),'');
  v_currentness:=coalesce(p_request->>'currentness_sha256','');
  v_deterministic_state:=upper(coalesce(p_request->>'deterministic_state','UNKNOWN'));
  v_resolver_state:=upper(coalesce(p_request->>'resolver_state','UNKNOWN'));

  if jsonb_typeof(p_request->'prequalified_human') is distinct from 'boolean' then
    v_prequalified:=false;
  else
    v_prequalified:=(p_request->>'prequalified_human')::boolean;
  end if;

  if v_subject_ref is null
     or v_currentness !~ '^[0-9a-f]{64}$'
     or v_deterministic_state not in ('PASS','FAIL','UNRESOLVED','NOT_APPLICABLE','UNKNOWN')
     or v_resolver_state not in ('PROVEN_AVAILABLE','NONE','UNKNOWN') then
    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','BLOCKED','code','SOURCE_STATE_INVALID',
      'human_queue_allowed',false,'subject_ref',v_subject_ref
    );
  end if;

  v_policy:=private.fn_lf_human_escalation_policy_resolve_v1(
    v_producer,v_subject_type,v_reason_code
  );

  if v_policy->>'state'<>'RESOLVED' then
    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','BLOCKED','code',coalesce(v_policy->>'code','POLICY_UNRESOLVED'),
      'human_queue_allowed',false,'policy',v_policy,
      'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
    );
  end if;

  if v_deterministic_state in ('PASS','NOT_APPLICABLE') then
    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','NO_HUMAN_REQUIRED','code','DETERMINISTIC_OUTCOME_SUFFICIENT',
      'human_queue_allowed',false,'policy',v_policy,
      'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
    );
  end if;

  if v_resolver_state='PROVEN_AVAILABLE' then
    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','AUTO_RESOLVE_FIRST','code','PROVEN_RESOLVER_AVAILABLE',
      'human_queue_allowed',false,'policy',v_policy,
      'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
    );
  end if;

  if coalesce((v_policy->>'safe_change_supported')::boolean,false)
     and p_request ? 'safe_change_request'
     and p_request->'safe_change_request' is not null then
    v_safe_request:=p_request->'safe_change_request';

    if jsonb_typeof(v_safe_request)<>'object' then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','BLOCKED','code','SAFE_CHANGE_REQUEST_INVALID',
        'human_queue_allowed',false,'policy',v_policy
      );
    end if;

    v_safe_result:=public.lf_safe_change_admission_classify_v1(v_safe_request);

    if v_safe_result->>'classification'='AUTOMATIZABLE'
       and v_safe_result->>'execution_permission'='DOWNSTREAM_EXECUTION_ELIGIBLE' then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','AUTO_EXECUTION_ELIGIBLE','code','SAFE_CHANGE_ADMISSION_AUTOMATIZABLE',
        'human_queue_allowed',false,'policy',v_policy,'safe_change',v_safe_result,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    elsif v_safe_result->>'classification'='VERIFY_NO_CHANGE' then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','NO_HUMAN_REQUIRED','code','SAFE_CHANGE_VERIFY_NO_CHANGE',
        'human_queue_allowed',false,'policy',v_policy,'safe_change',v_safe_result,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    elsif v_safe_result->>'classification'='UNKNOWN' then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','BLOCKED','code','SAFE_CHANGE_UNKNOWN_NOT_HUMAN',
        'human_queue_allowed',false,'policy',v_policy,'safe_change',v_safe_result,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    end if;
  end if;

  if coalesce((v_policy->>'targeted_evidence_required')::boolean,false) then
    v_target_request:=p_request->'targeted_evidence_request';

    if jsonb_typeof(v_target_request)<>'object'
       or jsonb_typeof(v_target_request->'candidates')<>'array' then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','EVIDENCE_REQUIRED','code','TARGETED_EVIDENCE_REQUEST_REQUIRED',
        'human_queue_allowed',false,'policy',v_policy,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    end if;

    v_candidate_count:=jsonb_array_length(v_target_request->'candidates');

    if v_candidate_count=0 then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','EVIDENCE_REQUIRED','code','EVIDENCE_INVENTORY_NOT_PROVEN',
        'human_queue_allowed',false,'policy',v_policy,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    end if;

    v_target_result:=public.lf_targeted_evidence_acquisition_plan_v1(v_target_request);

    if v_target_result->>'state'='CONTINUE' then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','ACQUIRE_EVIDENCE','code','DECISION_CHANGING_EVIDENCE_AVAILABLE',
        'human_queue_allowed',false,'policy',v_policy,'targeted_evidence',v_target_result,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    end if;

    if v_target_result->>'code'='STOP_DECISION_RESOLVED' then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','NO_HUMAN_REQUIRED','code','TARGETED_EVIDENCE_DECISION_RESOLVED',
        'human_queue_allowed',false,'policy',v_policy,'targeted_evidence',v_target_result,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    end if;

    if v_target_result->>'code'='STOP_NO_DECISION_CHANGING_EVIDENCE'
       and coalesce((v_target_result->>'automation_options_exhausted')::boolean,false) then
      if coalesce((v_policy->>'human_after_exhaustion')::boolean,false) then
        return jsonb_build_object(
          'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
          'state','HUMAN_ELIGIBLE','code','AUTOMATION_OPTIONS_EXHAUSTED',
          'human_queue_allowed',true,'policy',v_policy,'targeted_evidence',v_target_result,
          'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
        );
      end if;

      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','BLOCKED_NO_HUMAN','code','AUTOMATION_EXHAUSTED_BUT_POLICY_FORBIDS_HUMAN',
        'human_queue_allowed',false,'policy',v_policy,'targeted_evidence',v_target_result,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    end if;

    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','BLOCKED','code','TARGETED_EVIDENCE_NOT_TERMINAL_FOR_HUMAN',
      'human_queue_allowed',false,'policy',v_policy,'targeted_evidence',v_target_result,
      'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
    );
  end if;

  if v_policy->>'mode'='PREQUALIFIED_HUMAN' then
    if v_prequalified and coalesce((v_policy->>'human_after_exhaustion')::boolean,false) then
      return jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','HUMAN_ELIGIBLE','code','SPECIALIZED_PREQUALIFICATION_CONFIRMED',
        'human_queue_allowed',true,'policy',v_policy,
        'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
      );
    end if;

    return jsonb_build_object(
      'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
      'state','NO_HUMAN_REQUIRED','code','SPECIALIZED_PREQUALIFICATION_ABSENT',
      'human_queue_allowed',false,'policy',v_policy,
      'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
    );
  end if;

  return jsonb_build_object(
    'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
    'state','BLOCKED_NO_HUMAN','code','NO_HUMAN_ROUTE_ADMITTED',
    'human_queue_allowed',false,'policy',v_policy,
    'subject_ref',v_subject_ref,'currentness_sha256',v_currentness
  );
end
$function$;

revoke all on function public.lf_human_escalation_admission_v1(jsonb)
  from public,anon,authenticated;
grant execute on function public.lf_human_escalation_admission_v1(jsonb)
  to service_role;

create or replace function private.fn_lf_human_decision_open_ig_v3(
  p_proposal_id bigint,
  p_targeted_evidence_request jsonb,
  p_safe_change_request jsonb default null,
  p_created_by_execution_id text default 'INPUT_GOVERNANCE_ADAPTER_V3'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_p programacion.input_gap_proposals%rowtype;
  v_currentness text;
  v_target jsonb;
  v_admission jsonb;
begin
  select * into strict v_p
  from programacion.input_gap_proposals
  where id=p_proposal_id;

  if v_p.status<>'HUMAN_DECISION_REQUIRED'
     or v_p.proposal_kind<>'HUMAN_DECISION_REQUIRED'
     or v_p.validator_outcome<>'PASS' then
    raise exception 'IG_HUMAN_DECISION_SOURCE_NOT_ELIGIBLE:%:%:%',
      v_p.status,v_p.proposal_kind,v_p.validator_outcome;
  end if;

  v_currentness:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'proposal_id',v_p.id,
          'run_id',v_p.run_id,
          'family_code',v_p.family_code,
          'gap_code',v_p.gap_code,
          'proposed_payload',v_p.proposed_payload,
          'stage_impact',v_p.stage_impact,
          'validator_sha256',v_p.validator_sha256,
          'validated_at',v_p.validated_at
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  if jsonb_typeof(p_targeted_evidence_request)<>'object' then
    v_target:=null;
  else
    v_target:=jsonb_build_object(
      'consumer_ref','INPUT_GOVERNANCE:PROPOSAL:'||v_p.id::text,
      'unresolved_reasons',jsonb_build_array(v_p.gap_code),
      'current_evidence',coalesce(p_targeted_evidence_request->'current_evidence','[]'::jsonb),
      'candidates',coalesce(p_targeted_evidence_request->'candidates','[]'::jsonb)
    );
  end if;

  v_admission:=public.lf_human_escalation_admission_v1(
    jsonb_strip_nulls(
      jsonb_build_object(
        'producer_code','INPUT_GOVERNANCE',
        'subject_type','INPUT_GAP_PROPOSAL',
        'reason_code',v_p.gap_code,
        'subject_ref','supabase://programacion/input_gap_proposals/'||v_p.id::text,
        'currentness_sha256',v_currentness,
        'deterministic_state','UNRESOLVED',
        'resolver_state','NONE',
        'prequalified_human',false,
        'targeted_evidence_request',v_target,
        'safe_change_request',p_safe_change_request
      )
    )
  );

  if v_admission->>'state'<>'HUMAN_ELIGIBLE'
     or coalesce((v_admission->>'human_queue_allowed')::boolean,false) is not true then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'admission',v_admission
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-open-ig-v3/v1',
    'opened',true,
    'proposal_id',v_p.id,
    'admission',v_admission,
    'routing',private.fn_lf_human_decision_open_ig_v2(
      p_proposal_id,p_created_by_execution_id
    )
  );
end
$function$;

create or replace function private.fn_lf_human_decision_open_story_p0_v3(
  p_challenge_id text,
  p_created_by_execution_id text default 'STORY_CREATOR_P0_ADAPTER_V3'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_c private.v_lf_p0_human_review_active_queue_v1%rowtype;
  v_currentness text;
  v_admission jsonb;
begin
  select * into strict v_c
  from private.v_lf_p0_human_review_active_queue_v1
  where challenge_id=p_challenge_id;

  v_currentness:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'challenge_id',v_c.challenge_id,
          'source_head_sha',v_c.source_head_sha,
          'source_sha256',v_c.source_sha256,
          'visual_output_sha256',v_c.visual_output_sha256,
          'packet_manifest_sha256',v_c.packet_manifest_sha256,
          'semantic_fingerprint',v_c.semantic_fingerprint,
          'pending_human_count',v_c.pending_human_count,
          'required_reviewer_role',v_c.required_reviewer_role
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_admission:=public.lf_human_escalation_admission_v1(
    jsonb_build_object(
      'producer_code','STORY_CREATOR_P0',
      'subject_type','VISUAL_REVIEW',
      'reason_code',v_c.required_reviewer_role,
      'subject_ref','supabase://private/lf_p0_human_review_challenges_v1/'||v_c.challenge_id,
      'currentness_sha256',v_currentness,
      'deterministic_state','UNRESOLVED',
      'resolver_state','NONE',
      'prequalified_human',coalesce(v_c.pending_human_count,0)>0
    )
  );

  if v_admission->>'state'<>'HUMAN_ELIGIBLE'
     or coalesce((v_admission->>'human_queue_allowed')::boolean,false) is not true then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-story-p0-v3/v1',
      'opened',false,
      'challenge_id',v_c.challenge_id,
      'admission',v_admission
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-open-story-p0-v3/v1',
    'opened',true,
    'challenge_id',v_c.challenge_id,
    'admission',v_admission,
    'routing',private.fn_lf_human_decision_open_story_p0_v2(
      p_challenge_id,p_created_by_execution_id
    )
  );
end
$function$;

create or replace function private.fn_lf_human_decision_open_programming_v3(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_targeted_evidence_request jsonb default null,
  p_safe_change_request jsonb default null,
  p_created_by_execution_id text default 'PROGRAMMING_HUMAN_DECISION_ADAPTER_V3'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_work_item_id bigint;
  v_c programacion.engineering_work_checkpoints%rowtype;
  v_b programacion.programming_checkpoint_bindings%rowtype;
  v_admission jsonb;
  v_target jsonb;
begin
  select pu.work_item_id
    into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'PROGRAMMING_HUMAN_DECISION_WORK_ITEM_NOT_FOUND';
  end if;

  select * into strict v_c
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and checkpoint_code=p_checkpoint_code;

  select * into strict v_b
  from programacion.programming_checkpoint_bindings
  where plan_code=p_plan_code
    and unit_code=p_unit_code
    and checkpoint_code=p_checkpoint_code
    and enabled;

  if jsonb_typeof(p_targeted_evidence_request)='object' then
    v_target:=jsonb_build_object(
      'consumer_ref',concat_ws(':','PROGRAMMING',p_run_id::text,p_plan_code,p_unit_code,p_checkpoint_code),
      'unresolved_reasons',jsonb_build_array(v_b.failure_code),
      'current_evidence',coalesce(p_targeted_evidence_request->'current_evidence','[]'::jsonb),
      'candidates',coalesce(p_targeted_evidence_request->'candidates','[]'::jsonb)
    );
  end if;

  v_admission:=public.lf_human_escalation_admission_v1(
    jsonb_strip_nulls(
      jsonb_build_object(
        'producer_code','PROGRAMMING',
        'subject_type','CHECKPOINT_VALIDATION_FAILURE',
        'reason_code',v_b.failure_code,
        'subject_ref',concat_ws(':',p_run_id::text,p_plan_code,p_unit_code,p_checkpoint_code),
        'currentness_sha256',coalesce(v_c.assertion_receipt_sha256,repeat('0',64)),
        'deterministic_state',
          case
            when v_c.assertion_receipt->>'result'='PASS' then 'PASS'
            when v_c.assertion_receipt->>'result'='FAIL' then 'FAIL'
            else 'UNKNOWN'
          end,
        'resolver_state','NONE',
        'prequalified_human',false,
        'targeted_evidence_request',v_target,
        'safe_change_request',p_safe_change_request
      )
    )
  );

  if v_admission->>'state'<>'HUMAN_ELIGIBLE'
     or coalesce((v_admission->>'human_queue_allowed')::boolean,false) is not true then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-programming-v3/v1',
      'opened',false,
      'run_id',p_run_id,
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'admission',v_admission
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-open-programming-v3/v1',
    'opened',true,
    'admission',v_admission,
    'routing',private.fn_lf_human_decision_open_programming_v2(
      p_run_id,p_plan_code,p_unit_code,p_checkpoint_code,p_created_by_execution_id
    )
  );
end
$function$;

revoke all on function private.fn_lf_human_escalation_policy_resolve_v1(text,text,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_ig_v3(bigint,jsonb,jsonb,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_story_p0_v3(text,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_programming_v3(bigint,text,text,text,jsonb,jsonb,text)
  from public,anon,authenticated;

do $cap$
declare
  v_exec text:='HUMAN_ESCALATION_ADMISSION_V1';
  v_target_version text;
  v_target_sha text;
  v_safe_version text;
  v_safe_sha text;
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing text;
  v_promote jsonb;
begin
  select version,manifest_sha256
    into v_target_version,v_target_sha
  from public.lf_capability_current
  where capability_code='TARGETED_EVIDENCE_ACQUISITION';

  select version,manifest_sha256
    into v_safe_version,v_safe_sha
  from public.lf_capability_current
  where capability_code='SAFE_CHANGE_ADMISSION';

  if v_target_version is null or v_safe_version is null then
    raise exception 'HUMAN_ESCALATION_REQUIRED_DEPENDENCY_NOT_CURRENT';
  end if;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','HUMAN_ESCALATION_ADMISSION',
    'version','1.0.0',
    'owner','LF_GOVERNANCE',
    'contract',jsonb_build_object(
      'input','producer/subject/reason + exact source currentness + deterministic/resolver state + optional safe-change request + targeted-evidence request',
      'output','NO_HUMAN_REQUIRED|AUTO_RESOLVE_FIRST|AUTO_EXECUTION_ELIGIBLE|ACQUIRE_EVIDENCE|HUMAN_ELIGIBLE|EVIDENCE_REQUIRED|BLOCKED|BLOCKED_NO_HUMAN',
      'authority','READ_ONLY_FAIL_CLOSED_PRE_HUMAN_ADMISSION',
      'human_queue_allowed_only_on','HUMAN_ELIGIBLE'
    ),
    'delivery',jsonb_build_object(
      'mode','SUPABASE_NATIVE_READ_ONLY_CLASSIFIER',
      'function','public.lf_human_escalation_admission_v1',
      'policy_registry','private.lf_human_escalation_policies_v1'
    ),
    'dependencies',jsonb_build_object(
      'TARGETED_EVIDENCE_ACQUISITION',jsonb_build_object(
        'version',v_target_version,'manifest_sha256',v_target_sha
      ),
      'SAFE_CHANGE_ADMISSION',jsonb_build_object(
        'version',v_safe_version,'manifest_sha256',v_safe_sha
      )
    ),
    'compatibility',jsonb_build_object(
      'domain_agnostic',true,
      'executes_change',false,
      'executes_acquisition',false,
      'human_router_owner',false,
      'unknown_state','FAIL_CLOSED',
      'recommendation_is_human_escalation',false,
      'empty_candidate_inventory_proves_exhaustion',false
    ),
    'usage',jsonb_build_object(
      'classify','public.lf_human_escalation_admission_v1',
      'ig_canonical_adapter','private.fn_lf_human_decision_open_ig_v3',
      'story_canonical_adapter','private.fn_lf_human_decision_open_story_p0_v3',
      'programming_canonical_adapter','private.fn_lf_human_decision_open_programming_v3'
    ),
    'stop_rule',jsonb_build_object(
      'pass_or_not_applicable','NO_HUMAN_REQUIRED',
      'proven_resolver','AUTO_RESOLVE_FIRST',
      'safe_automatizable','AUTO_EXECUTION_ELIGIBLE',
      'decision_changing_evidence_available','ACQUIRE_EVIDENCE',
      'evidence_inventory_missing','EVIDENCE_REQUIRED',
      'exhausted_and_policy_allows','HUMAN_ELIGIBLE',
      'unknown_or_unproven','BLOCKED'
    )
  );

  v_manifest_sha:=encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  )
  values(
    'HUMAN_ESCALATION_ADMISSION',
    'Human Escalation Admission',
    'TRANSVERSAL',
    'LF_GOVERNANCE',
    'ACTIVE',
    'Read-only fail-closed gate that exhausts deterministic resolution and decision-changing evidence before human routing.',
    v_exec,v_exec,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  on conflict(capability_code) do update
  set capability_name=excluded.capability_name,
      capability_kind=excluded.capability_kind,
      owner_scope=excluded.owner_scope,
      status=excluded.status,
      description=excluded.description,
      entry_guard_required=excluded.entry_guard_required,
      entry_guard_code=excluded.entry_guard_code,
      updated_at=now(),
      updated_by_execution_id=v_exec;

  select manifest_sha256
    into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_ESCALATION_ADMISSION'
    and version='1.0.0';

  if v_existing is not null and v_existing<>v_manifest_sha then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_0_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_ESCALATION_ADMISSION','1.0.0',1,0,0,
    'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008081500_human_escalation_admission_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://public/lf_human_escalation_admission_v1',
    v_exec
  )
  on conflict(capability_code,version) do nothing;

  v_promote:=public.fn_lf_capability_promote_v1(
    'HUMAN_ESCALATION_ADMISSION','1.0.0',null,v_exec,
    'Read-only fail-closed pre-human gate; no decision, repair, acquisition, runtime or production effect.'
  );

  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'HUMAN_ESCALATION_ADMISSION_PROMOTION_FAILED:%',v_promote::text;
  end if;
end
$cap$;

do $routing_version$
declare
  v_manifest jsonb;
  v_sha text;
  v_existing text;
  v_hea_version text;
  v_hea_sha text;
begin
  select manifest
    into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.2'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_2_REQUIRED';
  end if;

  select version,manifest_sha256
    into v_hea_version,v_hea_sha
  from public.lf_capability_current
  where capability_code='HUMAN_ESCALATION_ADMISSION';

  if v_hea_version is null then
    raise exception 'HUMAN_ESCALATION_ADMISSION_CURRENT_REQUIRED';
  end if;

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.3"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{dependencies,HUMAN_ESCALATION_ADMISSION}',
    jsonb_build_object('version',v_hea_version,'manifest_sha256',v_hea_sha),true);
  v_manifest:=jsonb_set(v_manifest,'{usage,ig_open}','"private.fn_lf_human_decision_open_ig_v3"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{usage,story_open}','"private.fn_lf_human_decision_open_story_p0_v3"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{usage,programming_open}','"private.fn_lf_human_decision_open_programming_v3"'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,pre_human_admission_current}','true'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,human_queue_requires_admission}','true'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,consumer_cutover}','false'::jsonb,true);
  v_manifest:=jsonb_set(v_manifest,'{currentness,current_pointer}','false'::jsonb,true);

  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  select manifest_sha256
    into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.3';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_3_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_DECISION_ROUTING','1.0.3',1,0,3,
    'RELEASED','1.0.2',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008081500_human_escalation_admission_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://public/lf_human_escalation_admission_v1',
    'HUMAN_ESCALATION_ADMISSION_V1'
  )
  on conflict(capability_code,version) do nothing;

  if exists(
    select 1 from public.lf_capability_current
    where capability_code='HUMAN_DECISION_ROUTING'
  ) then
    raise exception 'HUMAN_DECISION_ROUTING_CURRENT_POINTER_PREMATURE';
  end if;
end
$routing_version$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-ESCALATION-MINIMIZE-BEFORE-QUEUE-001',
  'PROGRAMMING_GOVERNANCE',
  'Human queue admission must exhaust automatic resolution and decision-changing evidence first',
  'Human escalation is now a separate transversal admission concern before HUMAN_DECISION_ROUTING. Deterministic PASS/NOT_APPLICABLE, proven resolvers, safe-change AUTOMATIZABLE, and available targeted evidence all prevent queue admission. Empty evidence candidate inventory does not prove exhaustion. Programming deterministic failures are not human by default. Story P0 may enter only from its already-specialized active challenge prequalification.',
  'Routing HUMAN_DECISION_REQUIRED directly to a human queue conflates uncertainty with irreducible human judgment and can create large avoidable review debt.',
  'SOURCE -> HUMAN_ESCALATION_ADMISSION -> automatic outcome/evidence acquisition OR HUMAN_ELIGIBLE -> HUMAN_DECISION_ROUTING.',
  'Canonical V3 adapters must be used for future cutover. Never call human routing directly from a recommendation or generic FAIL. Require HUMAN_ELIGIBLE and human_queue_allowed=true. Unknown/unproven states block rather than escalate.',
  'Migration materializes HUMAN_ESCALATION_ADMISSION 1.0.0 as ACTIVE/CURRENT, seeds fail-closed producer policies and releases HUMAN_DECISION_ROUTING 1.0.3 with V3 adapters while keeping its current pointer and consumer cutover disabled.',
  'HIGH','ACTIVO',
  'capability://HUMAN_ESCALATION_ADMISSION@1.0.0',
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
