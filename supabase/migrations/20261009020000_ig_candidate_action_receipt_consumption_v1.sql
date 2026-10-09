-- IG candidate action receipts, scoped to governed lf_ops transitions.
-- Reuses programacion.issue_provenance_receipt() and the existing authority
-- policy verifier. This migration DOES NOT create/activate an authority policy,
-- grant public access, emit a receipt, or activate a candidate.
--
-- Issuer contract (existing provenance channel, not an IG parallel engine):
-- receipt_kind=HUMAN_DECISION, subject_type=LF_IG_CANDIDATE_TRANSITION,
-- subject_ref=supabase://lf_ops/estados_transiciones/<transition_id>,
-- subject_sha256=context.currentness_sha256, decision=APPROVE,
-- action_code=PROMOTE_GOVERNED_CANDIDATE, screen_id, transition_id,
-- authority_ref, reviewer_role, currentness_sha256, expires_at_unix.
-- Only a channel permitted for HUMAN_DECISION and an independent ACTIVE
-- authority policy with exact action/subject/domain may authorize consumption.

create table if not exists private.lf_ig_candidate_action_consumptions_v1 (
  transition_id bigint primary key references lf_ops.estados_transiciones(transition_id),
  screen_id integer not null,
  receipt_id bigint not null unique references programacion.provenance_receipts(id),
  receipt_sha256 text not null check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  authorized_currentness_sha256 text not null check (authorized_currentness_sha256 ~ '^[0-9a-f]{64}$'),
  prior_status text not null check (prior_status='CANDIDATO'),
  resulting_status text not null check (resulting_status='VIGENTE'),
  created_at timestamptz not null default now()
);
alter table private.lf_ig_candidate_action_consumptions_v1 enable row level security;
revoke all on private.lf_ig_candidate_action_consumptions_v1 from public, anon, authenticated, service_role;

create or replace function private.fn_lf_ig_candidate_action_context_v1(
  p_screen_id integer,p_transition_id bigint
) returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_transition lf_ops.estados_transiciones%rowtype;
  v_decision public.lf_decisiones_gov%rowtype;
  v_screen_gate jsonb;
  v_digest text;
begin
  select * into v_transition from lf_ops.estados_transiciones
  where transition_id=p_transition_id and status='CANDIDATO';
  if not found then
    return jsonb_build_object('state','BLOCKED','code','CANDIDATE_NOT_CURRENT');
  end if;

  if not exists(
    select 1 from lf_ops.pantallas_estados pe
    where pe.pantalla_id=p_screen_id
      and pe.state_id in (v_transition.from_state_id,v_transition.to_state_id)
  ) then
    return jsonb_build_object('state','BLOCKED','code','CANDIDATE_SCREEN_MISMATCH');
  end if;

  select * into v_decision from public.lf_decisiones_gov d
  where (v_transition.source_decision_id is not null
     and d.id_decision=v_transition.source_decision_id)
     or (v_transition.source_decision_id is null
     and v_transition.source_decision_number is not null
     and d.decision_number=v_transition.source_decision_number);
  if not found or not (
    v_decision.estado_original='APROBADO_POR_OWNER'
    or v_decision.estado_normalizado='CANDIDATO_APROBADO_POR_OWNER'
  ) then
    return jsonb_build_object('state','BLOCKED','code','SOURCE_OWNER_APPROVAL_UNPROVEN');
  end if;

  v_screen_gate:=private.fn_lf_ig_candidate_promotion_authority_v1(p_screen_id,'TRANSITIONS');
  if v_screen_gate->>'state' is distinct from 'ACTION_AUTHORIZATION_GATE'
     or coalesce((v_screen_gate->>'human_queue_allowed')::boolean,true) then
    return jsonb_build_object('state','BLOCKED','code','SCREEN_CANDIDATE_GATE_NOT_READY');
  end if;

  v_digest:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version','lf-ig-candidate-action-subject/v1',
    'screen_id',p_screen_id,
    'transition',to_jsonb(v_transition),
    'source_decision',jsonb_build_object(
      'id_decision',v_decision.id_decision,
      'decision_number',v_decision.decision_number,
      'estado_original',v_decision.estado_original,
      'estado_normalizado',v_decision.estado_normalizado,
      'updated_at',v_decision.updated_at
    )
  ));
  return jsonb_build_object(
    'schema_version','lf-ig-candidate-action-context/v1',
    'state','READY_FOR_AUTHORIZATION',
    'transition_id',p_transition_id,
    'screen_id',p_screen_id,
    'action_code','PROMOTE_GOVERNED_CANDIDATE',
    'currentness_sha256',v_digest,
    'subject_ref','supabase://lf_ops/estados_transiciones/'||p_transition_id::text
  );
end
$function$;

create or replace function private.fn_lf_ig_candidate_action_receipt_verify_v1(
 p_screen_id integer,p_transition_id bigint,p_receipt_id bigint
) returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
 v_context jsonb;
 v_receipt programacion.provenance_receipts%rowtype;
 v_policy private.lf_human_decision_authority_policies_v1%rowtype;
 v_expected_digest text;
 v_expiry_epoch bigint;
begin
  v_context:=private.fn_lf_ig_candidate_action_context_v1(p_screen_id,p_transition_id);
  if v_context->>'state' is distinct from 'READY_FOR_AUTHORIZATION' then
    return jsonb_build_object('state','BLOCKED','code','CANDIDATE_CONTEXT_NOT_READY','context',v_context);
  end if;
  if p_receipt_id is null then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_REQUIRED');
  end if;
  select * into v_receipt from programacion.provenance_receipts where id=p_receipt_id;
  if not found then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_NOT_FOUND');
  end if;
  if v_receipt.receipt_kind is distinct from 'HUMAN_DECISION'
     or v_receipt.subject_type is distinct from 'LF_IG_CANDIDATE_TRANSITION'
     or v_receipt.subject_ref is distinct from v_context->>'subject_ref'
     or v_receipt.subject_sha256 is distinct from v_context->>'currentness_sha256' then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_SUBJECT_OR_CURRENTNESS_MISMATCH');
  end if;
  if v_receipt.payload->>'decision' is distinct from 'APPROVE'
     or v_receipt.payload->>'action_code' is distinct from 'PROMOTE_GOVERNED_CANDIDATE'
     or v_receipt.payload->>'screen_id' is distinct from p_screen_id::text
     or v_receipt.payload->>'transition_id' is distinct from p_transition_id::text
     or v_receipt.payload->>'currentness_sha256' is distinct from v_context->>'currentness_sha256'
     or nullif(btrim(coalesce(v_receipt.payload->>'authority_ref','')),'') is null
     or nullif(btrim(coalesce(v_receipt.payload->>'reviewer_role','')),'') is null
     or nullif(btrim(coalesce(v_receipt.payload->>'actor_identity','')),'') is null
     or nullif(btrim(coalesce(v_receipt.payload->>'approval_ref','')),'') is null then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_PAYLOAD_MISMATCH');
  end if;
  if coalesce(v_receipt.payload->>'expires_at_unix','') !~ '^[0-9]{10}$' then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_EXPIRY_INVALID');
  end if;
  v_expiry_epoch:=(v_receipt.payload->>'expires_at_unix')::bigint;
  if to_timestamp(v_expiry_epoch)<=clock_timestamp()
     or to_timestamp(v_expiry_epoch)<=v_receipt.created_at then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_EXPIRED');
  end if;

  v_expected_digest:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,'receipt_kind',v_receipt.receipt_kind,
    'execution_id',v_receipt.execution_id,'head_sha',v_receipt.head_sha,
    'subject_type',v_receipt.subject_type,'subject_ref',v_receipt.subject_ref,
    'subject_sha256',v_receipt.subject_sha256,'issuer_channel',v_receipt.issuer_channel,
    'issuer_identity',v_receipt.issuer_identity,'verification_ref',v_receipt.verification_ref,
    'payload',v_receipt.payload
  ));
  if v_receipt.receipt_sha256 is distinct from v_expected_digest then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_DIGEST_MISMATCH');
  end if;

  select * into v_policy from private.lf_human_decision_authority_policies_v1
  where authority_ref=v_receipt.payload->>'authority_ref'
    and reviewer_role=v_receipt.payload->>'reviewer_role'
    and status='ACTIVE';
  if not found then
    return jsonb_build_object('state','BLOCKED','code','ACTION_AUTHORITY_POLICY_NOT_ACTIVE');
  end if;
  if v_policy.issuer_channel is distinct from v_receipt.issuer_channel
     or v_policy.receipt_kind is distinct from v_receipt.receipt_kind
     or v_policy.metadata->>'authority_domain' is distinct from 'LF_GOVERNANCE'
     or v_policy.metadata->>'action_code' is distinct from 'PROMOTE_GOVERNED_CANDIDATE'
     or v_policy.metadata->>'subject_type' is distinct from 'LF_IG_CANDIDATE_TRANSITION'
     or v_policy.policy_sha256 is distinct from
       private.fn_lf_human_decision_authority_policy_sha_v1(
         v_policy.authority_ref,v_policy.reviewer_role,v_policy.issuer_channel,
         v_policy.receipt_kind,v_policy.status,v_policy.metadata
       ) then
    return jsonb_build_object('state','BLOCKED','code','ACTION_AUTHORITY_POLICY_MISMATCH');
  end if;

  if exists(select 1 from private.lf_ig_candidate_action_consumptions_v1
            where transition_id=p_transition_id or receipt_id=p_receipt_id) then
    return jsonb_build_object('state','BLOCKED','code','ACTION_RECEIPT_ALREADY_CONSUMED');
  end if;
  return jsonb_build_object(
    'schema_version','lf-ig-candidate-action-receipt/v1',
    'state','VERIFIED','action_code','PROMOTE_GOVERNED_CANDIDATE',
    'transition_id',p_transition_id,'screen_id',p_screen_id,
    'receipt_id',p_receipt_id,'receipt_sha256',v_receipt.receipt_sha256,
    'currentness_sha256',v_context->>'currentness_sha256'
  );
end
$function$;

create or replace function private.fn_lf_ig_candidate_promotion_consume_v1(
 p_screen_id integer,p_transition_id bigint,p_receipt_id bigint
) returns jsonb language plpgsql volatile security definer set search_path='' as $function$
declare
 v_old_status text;
 v_verified jsonb;
 v_updated bigint;
begin
  select status into v_old_status from lf_ops.estados_transiciones
  where transition_id=p_transition_id for update;
  if v_old_status is distinct from 'CANDIDATO' then
    return jsonb_build_object('state','BLOCKED','code','CANDIDATE_NOT_CURRENT');
  end if;
  v_verified:=private.fn_lf_ig_candidate_action_receipt_verify_v1(
    p_screen_id,p_transition_id,p_receipt_id);
  if v_verified->>'state' is distinct from 'VERIFIED' then
    return v_verified;
  end if;

  insert into private.lf_ig_candidate_action_consumptions_v1(
    transition_id,screen_id,receipt_id,receipt_sha256,
    authorized_currentness_sha256,prior_status,resulting_status
  ) values (
    p_transition_id,p_screen_id,p_receipt_id,v_verified->>'receipt_sha256',
    v_verified->>'currentness_sha256','CANDIDATO','VIGENTE'
  );
  update lf_ops.estados_transiciones set status='VIGENTE'
  where transition_id=p_transition_id and status='CANDIDATO';
  get diagnostics v_updated=row_count;
  if v_updated<>1 then
    raise exception 'IG_CANDIDATE_PROMOTION_CONCURRENT_SOURCE_DRIFT';
  end if;
  return jsonb_build_object(
    'state','PROMOTED','action_code','PROMOTE_GOVERNED_CANDIDATE',
    'transition_id',p_transition_id,'screen_id',p_screen_id,
    'receipt_id',p_receipt_id,
    'authorized_currentness_sha256',v_verified->>'currentness_sha256'
  );
end
$function$;

revoke all on function private.fn_lf_ig_candidate_action_context_v1(integer,bigint)
from public,anon,authenticated,service_role;
revoke all on function private.fn_lf_ig_candidate_action_receipt_verify_v1(integer,bigint,bigint)
from public,anon,authenticated,service_role;
revoke all on function private.fn_lf_ig_candidate_promotion_consume_v1(integer,bigint,bigint)
from public,anon,authenticated,service_role;
