-- HUMAN_DECISION_ROUTING_ADAPTERS_V1
-- Producer adapters only. They project existing stage-owned human-decision sources
-- into HUMAN_DECISION_ROUTING without changing the producer's own authority/store.
-- No consumer cutover and no generic decision-write ingress in this migration.

create or replace function private.fn_lf_human_decision_current_for_subject_v1(
  p_producer_code text,
  p_subject_type text,
  p_subject_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_request_id uuid;
begin
  select r.request_id
    into v_request_id
  from private.lf_human_decision_requests_v1 r
  where r.producer_code=p_producer_code
    and r.subject_type=p_subject_type
    and r.subject_key=p_subject_key
  order by
    case r.status when 'OPEN' then 0 when 'DECIDED' then 1 else 2 end,
    r.opened_at desc
  limit 1;

  if v_request_id is null then
    return jsonb_build_object(
      'schema_version','lf-human-decision-current-subject/v1',
      'found',false,
      'producer_code',p_producer_code,
      'subject_type',p_subject_type,
      'subject_key',p_subject_key
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-current-subject/v1',
    'found',true,
    'producer_code',p_producer_code,
    'subject_type',p_subject_type,
    'subject_key',p_subject_key,
    'routing',private.fn_lf_human_decision_consume_v1(v_request_id)
  );
end
$function$;

create or replace function private.fn_lf_human_decision_open_ig_v1(
  p_proposal_id bigint,
  p_required_authority_ref text,
  p_required_reviewer_role text,
  p_allowed_actions jsonb,
  p_created_by_execution_id text default 'INPUT_GOVERNANCE_ADAPTER_V1'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_p programacion.input_gap_proposals%rowtype;
  v_currentness text;
  v_evidence jsonb;
begin
  select * into strict v_p
  from programacion.input_gap_proposals
  where id=p_proposal_id;

  if v_p.status <> 'HUMAN_DECISION_REQUIRED'
     or v_p.proposal_kind <> 'HUMAN_DECISION_REQUIRED'
     or v_p.validator_outcome <> 'PASS' then
    raise exception 'IG_HUMAN_DECISION_SOURCE_NOT_ELIGIBLE:%:%:%',
      v_p.status,v_p.proposal_kind,v_p.validator_outcome;
  end if;

  if jsonb_typeof(p_allowed_actions) <> 'array'
     or jsonb_array_length(p_allowed_actions)=0 then
    raise exception 'IG_HUMAN_DECISION_ALLOWED_ACTIONS_REQUIRED';
  end if;

  v_currentness:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'proposal_id',v_p.id,
          'run_id',v_p.run_id,
          'assessment_id',v_p.assessment_id,
          'family_code',v_p.family_code,
          'gap_code',v_p.gap_code,
          'proposal_kind',v_p.proposal_kind,
          'proposed_payload',v_p.proposed_payload,
          'canonical_target',v_p.canonical_target,
          'source_refs',v_p.source_refs,
          'evidence_refs',v_p.evidence_refs,
          'stage_impact',v_p.stage_impact,
          'curator_sha256',v_p.curator_sha256,
          'validator_sha256',v_p.validator_sha256,
          'validated_at',v_p.validated_at
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_evidence:=coalesce(v_p.source_refs,'[]'::jsonb)
    || coalesce(v_p.evidence_refs,'[]'::jsonb)
    || jsonb_build_array(
         jsonb_build_object(
           'kind','IG_VALIDATOR_EVIDENCE',
           'validator_identity',v_p.validator_identity,
           'validator_sha256',v_p.validator_sha256,
           'payload',v_p.validator_evidence
         )
       );

  return private.fn_lf_human_decision_open_v1(
    'INPUT_GOVERNANCE',
    'INPUT_GAP_PROPOSAL',
    v_p.id::text,
    jsonb_build_object(
      'proposal_id',v_p.id,
      'run_id',v_p.run_id,
      'assessment_id',v_p.assessment_id,
      'family_code',v_p.family_code,
      'gap_code',v_p.gap_code
    ),
    p_required_authority_ref,
    p_required_reviewer_role,
    p_allowed_actions,
    v_evidence,
    v_currentness,
    v_p.stage_impact,
    'supabase://programacion/input_gap_proposals/'||v_p.id::text,
    coalesce(v_p.validator_sha256,v_p.curator_sha256),
    null,
    jsonb_build_object(
      'adapter','INPUT_GOVERNANCE_ADAPTER_V1',
      'source_status',v_p.status,
      'validator_outcome',v_p.validator_outcome,
      'proposal_kind',v_p.proposal_kind
    ),
    p_created_by_execution_id
  );
end
$function$;

create or replace function private.fn_lf_human_decision_consume_ig_v1(
  p_proposal_id bigint
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  select private.fn_lf_human_decision_current_for_subject_v1(
    'INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL',p_proposal_id::text
  )
$function$;

create or replace function private.fn_lf_human_decision_open_story_p0_v1(
  p_challenge_id text,
  p_required_authority_ref text,
  p_created_by_execution_id text default 'STORY_CREATOR_P0_ADAPTER_V1'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_c private.v_lf_p0_human_review_active_queue_v1%rowtype;
  v_currentness text;
  v_subject_key text;
  v_evidence jsonb;
begin
  select * into strict v_c
  from private.v_lf_p0_human_review_active_queue_v1
  where challenge_id=p_challenge_id;

  if v_c.expires_at is not null and v_c.expires_at <= now() then
    raise exception 'STORY_HUMAN_REVIEW_CHALLENGE_EXPIRED:%',v_c.challenge_id;
  end if;

  if nullif(btrim(coalesce(v_c.required_reviewer_role,'')),'') is null then
    raise exception 'STORY_HUMAN_REVIEW_ROLE_REQUIRED';
  end if;

  if coalesce(array_length(v_c.reviewer_actions,1),0)=0 then
    raise exception 'STORY_HUMAN_REVIEW_ACTIONS_REQUIRED';
  end if;

  v_subject_key:=coalesce(
    nullif(btrim(v_c.review_scope_key),''),
    concat_ws(':',v_c.review_lane,v_c.review_subject)
  );

  v_currentness:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'challenge_id',v_c.challenge_id,
          'review_id',v_c.review_id,
          'execution_id',v_c.execution_id,
          'source_head_sha',v_c.source_head_sha,
          'source_sha256',v_c.source_sha256,
          'visual_output_sha256',v_c.visual_output_sha256,
          'packet_manifest_sha256',v_c.packet_manifest_sha256,
          'browser_review_sha256',v_c.browser_review_sha256,
          'semantic_fingerprint',v_c.semantic_fingerprint,
          'pending_human_count',v_c.pending_human_count,
          'delta',v_c.delta,
          'review_mode',v_c.review_mode,
          'review_scope_key',v_c.review_scope_key
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_evidence:=jsonb_build_array(
    jsonb_build_object(
      'kind','P0_REVIEW_EVIDENCE_STORE',
      'ref',v_c.evidence_store_ref
    ),
    jsonb_build_object(
      'kind','P0_SOURCE_EVIDENCE',
      'object_id',v_c.source_evidence_object_id,
      'sha256',v_c.source_sha256
    ),
    jsonb_build_object(
      'kind','P0_VISUAL_OUTPUT',
      'object_id',v_c.visual_output_object_id,
      'sha256',v_c.visual_output_sha256
    ),
    jsonb_build_object(
      'kind','P0_PACKET_MANIFEST',
      'object_id',v_c.packet_manifest_object_id,
      'sha256',v_c.packet_manifest_sha256
    )
  );

  if v_c.browser_review_object_id is not null then
    v_evidence:=v_evidence || jsonb_build_array(
      jsonb_build_object(
        'kind','P0_BROWSER_REVIEW',
        'object_id',v_c.browser_review_object_id,
        'sha256',v_c.browser_review_sha256,
        'head_sha',v_c.browser_head_sha
      )
    );
  end if;

  return private.fn_lf_human_decision_open_v1(
    'STORY_CREATOR_P0',
    'VISUAL_REVIEW',
    v_subject_key,
    jsonb_build_object(
      'challenge_id',v_c.challenge_id,
      'review_id',v_c.review_id,
      'execution_id',v_c.execution_id,
      'review_lane',v_c.review_lane,
      'review_subject',v_c.review_subject,
      'review_scope_key',v_c.review_scope_key
    ),
    p_required_authority_ref,
    v_c.required_reviewer_role,
    to_jsonb(v_c.reviewer_actions),
    v_evidence,
    v_currentness,
    jsonb_build_object(
      'pending_human_count',v_c.pending_human_count,
      'changed_count',v_c.changed_count,
      'uncertain_count',v_c.uncertain_count,
      'inferred_count',v_c.inferred_count,
      'delta',v_c.delta,
      'review_mode',v_c.review_mode
    ),
    'supabase://private/lf_p0_human_review_challenges_v1/'||v_c.challenge_id,
    v_c.semantic_fingerprint,
    v_c.expires_at,
    jsonb_build_object(
      'adapter','STORY_CREATOR_P0_ADAPTER_V1',
      'challenge_id',v_c.challenge_id,
      'dual_review_required',v_c.dual_review_required,
      'data_classification',v_c.data_classification,
      'carry_forward_safe',v_c.carry_forward_safe,
      'convergence_justification',v_c.convergence_justification
    ),
    p_created_by_execution_id
  );
end
$function$;

create or replace function private.fn_lf_human_decision_consume_story_p0_v1(
  p_challenge_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_request_id uuid;
begin
  select r.request_id
    into v_request_id
  from private.lf_human_decision_requests_v1 r
  where r.producer_code='STORY_CREATOR_P0'
    and r.subject_type='VISUAL_REVIEW'
    and r.subject_ref->>'challenge_id'=p_challenge_id
  order by r.opened_at desc
  limit 1;

  if v_request_id is null then
    return jsonb_build_object(
      'schema_version','lf-human-decision-story-p0-consume/v1',
      'found',false,
      'challenge_id',p_challenge_id
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-story-p0-consume/v1',
    'found',true,
    'challenge_id',p_challenge_id,
    'routing',private.fn_lf_human_decision_consume_v1(v_request_id)
  );
end
$function$;

create or replace function private.fn_lf_human_decision_open_programming_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_required_authority_ref text,
  p_required_reviewer_role text,
  p_allowed_actions jsonb,
  p_created_by_execution_id text default 'PROGRAMMING_HUMAN_DECISION_ADAPTER_V1'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_work_item_id bigint;
  v_run_status text;
  v_run_unit_status text;
  v_current_checkpoint text;
  v_c programacion.engineering_work_checkpoints%rowtype;
  v_b programacion.programming_checkpoint_bindings%rowtype;
  v_rule_mode text;
  v_subject_key text;
  v_evidence jsonb;
begin
  select r.status,ru.status,pu.work_item_id
    into v_run_status,v_run_unit_status,v_work_item_id
  from programacion.programming_simple_runs r
  join programacion.programming_simple_run_units ru
    on ru.run_id=r.id
  join programacion.engineering_plan_units pu
    on pu.plan_code=ru.plan_code and pu.unit_code=ru.unit_code
  where r.id=p_run_id
    and ru.plan_code=p_plan_code
    and ru.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'PROGRAMMING_HUMAN_DECISION_RUN_UNIT_NOT_FOUND';
  end if;

  if v_run_status <> 'RUNNING' or v_run_unit_status <> 'RUNNING' then
    raise exception 'PROGRAMMING_HUMAN_DECISION_ACTIVE_RUN_REQUIRED:%:%',
      v_run_status,v_run_unit_status;
  end if;

  select c.checkpoint_code
    into v_current_checkpoint
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current_checkpoint is distinct from p_checkpoint_code then
    raise exception 'PROGRAMMING_HUMAN_DECISION_NOT_CURRENT:%:%',
      p_checkpoint_code,coalesce(v_current_checkpoint,'(none)');
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

  select rule_mode
    into v_rule_mode
  from programacion.programming_validation_registry
  where validation_code=v_b.validation_code
    and status='ACTIVE';

  if v_rule_mode is distinct from 'HUMAN_DECISION' then
    raise exception 'PROGRAMMING_HUMAN_DECISION_RULE_MODE_REQUIRED:%',coalesce(v_rule_mode,'(none)');
  end if;

  if coalesce(v_c.assertion_receipt->>'schema_version','') <> 'PROGRAMMING_VALIDATION_RECEIPT_V1'
     or coalesce(v_c.assertion_receipt->>'result','') <> 'FAIL'
     or coalesce(v_c.assertion_receipt->>'plan_code','') <> p_plan_code
     or coalesce(v_c.assertion_receipt->>'unit_code','') <> p_unit_code
     or coalesce(v_c.assertion_receipt->>'checkpoint_code','') <> p_checkpoint_code
     or coalesce(v_c.assertion_receipt->>'validation_code','') <> v_b.validation_code
     or coalesce(jsonb_typeof(v_c.assertion_receipt->'run_id'),'') <> 'number'
     or (v_c.assertion_receipt->>'run_id')::bigint <> p_run_id
     or coalesce(v_c.assertion_receipt_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'PROGRAMMING_HUMAN_DECISION_CURRENT_FAIL_RECEIPT_REQUIRED';
  end if;

  if jsonb_typeof(p_allowed_actions) <> 'array'
     or jsonb_array_length(p_allowed_actions)=0 then
    raise exception 'PROGRAMMING_HUMAN_DECISION_ALLOWED_ACTIONS_REQUIRED';
  end if;

  v_subject_key:=concat_ws(':',p_run_id::text,p_plan_code,p_unit_code,p_checkpoint_code);

  v_evidence:=jsonb_build_array(
    jsonb_build_object(
      'kind','PROGRAMMING_VALIDATION_RECEIPT',
      'evidence_ref',v_c.assertion_receipt->>'evidence_ref',
      'receipt_sha256',v_c.assertion_receipt_sha256,
      'validation_code',v_b.validation_code,
      'failure_code',v_b.failure_code
    )
  );

  return private.fn_lf_human_decision_open_v1(
    'PROGRAMMING',
    'CHECKPOINT_VALIDATION_FAILURE',
    v_subject_key,
    jsonb_build_object(
      'run_id',p_run_id,
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'validation_code',v_b.validation_code,
      'failure_code',v_b.failure_code,
      'failure_receipt_sha256',v_c.assertion_receipt_sha256
    ),
    p_required_authority_ref,
    p_required_reviewer_role,
    p_allowed_actions,
    v_evidence,
    v_c.assertion_receipt_sha256,
    jsonb_build_object('implementation','BLOCKED'),
    'supabase://programacion/engineering_work_checkpoints/'||v_work_item_id::text||'/'||p_checkpoint_code,
    v_c.assertion_receipt_sha256,
    null,
    jsonb_build_object(
      'adapter','PROGRAMMING_HUMAN_DECISION_ADAPTER_V1',
      'rule_mode',v_rule_mode,
      'validation_code',v_b.validation_code,
      'failure_code',v_b.failure_code
    ),
    p_created_by_execution_id
  );
end
$function$;

create or replace function private.fn_lf_human_decision_consume_programming_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  select private.fn_lf_human_decision_current_for_subject_v1(
    'PROGRAMMING',
    'CHECKPOINT_VALIDATION_FAILURE',
    concat_ws(':',p_run_id::text,p_plan_code,p_unit_code,p_checkpoint_code)
  )
$function$;

revoke all on function private.fn_lf_human_decision_current_for_subject_v1(text,text,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_ig_v1(bigint,text,text,jsonb,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_consume_ig_v1(bigint)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_story_p0_v1(text,text,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_consume_story_p0_v1(text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_open_programming_v1(bigint,text,text,text,text,text,jsonb,text)
  from public,anon,authenticated;
revoke all on function private.fn_lf_human_decision_consume_programming_v1(bigint,text,text,text)
  from public,anon,authenticated;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-DECISION-PRODUCER-ADAPTERS-001',
  'PROGRAMMING_GOVERNANCE',
  'IG Story P0 and Programming project into one human-decision routing contract through source-owned adapters',
  'The three producers keep their native evidence and state. Adapters project only eligible source objects into HUMAN_DECISION_ROUTING: IG requires validated HUMAN_DECISION_REQUIRED proposal; Story P0 requires an active unexpired challenge and reuses its reviewer role/actions; Programming requires an active current FAIL receipt whose admitted rule mode is HUMAN_DECISION.',
  'Without source-specific eligibility guards, a generic queue can detach a decision from the producer state that justified it.',
  'SOURCE-OWNED STATE -> ELIGIBILITY GUARD -> CURRENTNESS HASH -> GENERIC REQUEST; RECEIPT READBACK -> SOURCE-SPECIFIC CONSUMER ADAPTER.',
  'Do not mutate IG proposals, Story P0 challenges or Programming checkpoints from the routing adapter. Do not cut over producer state transitions until authority-receipt verification and decision-ingress adapters are proven.',
  'Candidate adapter migration defines open/consume adapters for all three producers and revokes public/anon/authenticated execution. It does not create decision receipts and does not cut over existing consumers.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008050500_human_decision_routing_adapters_v1.sql',
  now()
),
(
  'HUMAN-DECISION-AUTHORITY-RECEIPT-VERIFICATION-001',
  'PROGRAMMING_GOVERNANCE',
  'Generic human-decision receipt structure does not replace authority-specific receipt verification',
  'The core receipt guard binds decision code, reviewer role, authority_ref, currentness and receipt hash, but the authority_receipt_ref/sha pair still requires an authority-specific verified ingress before any producer can cut over to consuming decisions automatically.',
  'A syntactically valid authority receipt reference can be mistaken for proof that the reviewer was actually authorized.',
  'AUTHORITY-SPECIFIC AUTHENTICATION -> VERIFIED AUTHORITY RECEIPT -> GENERIC DECISION RECEIPT -> PRODUCER CONSUMPTION.',
  'Keep IG Story and Programming cutover disabled until each routed authority has a deterministic receipt verifier or governed ingress. Do not let a service-role insert alone count as human authorization.',
  'Core tables/functions are live but expose no public/authenticated decision-write API. Producer adapters are projection/readback only. This remains the explicit cutover blocker.',
  'HIGH','ACTIVO',
  'supabase://private/lf_human_decision_receipts_v1',
  now()
)
on conflict (codigo) do update
set categoria=excluded.categoria,titulo=excluded.titulo,descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,patron=excluded.patron,prevencion=excluded.prevencion,
    validacion=excluded.validacion,severidad=excluded.severidad,estado=excluded.estado,
    source_ref=excluded.source_ref,updated_at=excluded.updated_at;
