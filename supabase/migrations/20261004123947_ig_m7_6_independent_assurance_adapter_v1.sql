-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.6 / PAULO-145
-- Thin consumer adapter: Gold B -> INDEPENDENT_ASSURANCE.
-- It does NOT adjudicate, issue its own receipt, create a judge, or create a parallel authority.
-- It prepares an exact review subject and consumes only a provider-bound EVIDENCE_LEDGER receipt.

create or replace function programacion.fn_input_gov_gold_b_prepare_review_v1(
  p_run_id bigint,
  p_family_code text,
  p_case_manifest jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','programacion','public'
as $function$
declare
  v_adr_state text;
  v_cap_status text;
  v_cap_version text;
  v_cap_manifest_sha text;
  v_subject_ref text;
  v_subject_sha text;
  v_p0_count integer;
begin
  if p_run_id is null or nullif(btrim(coalesce(p_family_code,'')),'') is null then
    return jsonb_build_object('result','BLOCKED','code','GOLD_B_SUBJECT_INVALID');
  end if;
  if p_case_manifest is null or jsonb_typeof(p_case_manifest)<>'object' then
    return jsonb_build_object('result','BLOCKED','code','GOLD_B_CASE_MANIFEST_INVALID');
  end if;

  select estado into v_adr_state
  from transversal.decision_log
  where adr='DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001';
  if v_adr_state is distinct from 'VIGENTE' then
    return jsonb_build_object('result','BLOCKED','code','M1_7_ADJUDICATION_AUTHORITY_NOT_CURRENT');
  end if;

  if not programacion.fn_input_readiness_run_is_current_cached_v2(p_run_id) then
    return jsonb_build_object('result','BLOCKED','code','GOLD_B_RUN_NOT_CURRENT','run_id',p_run_id);
  end if;

  select count(*) into v_p0_count
  from programacion.input_family_assessments
  where run_id=p_run_id and family_code=p_family_code and severity='P0';
  if v_p0_count<>1 then
    return jsonb_build_object('result','BLOCKED','code','GOLD_B_CRITICAL_CASE_NOT_EXACT','count',v_p0_count);
  end if;

  select r.status,c.version,c.manifest_sha256
    into v_cap_status,v_cap_version,v_cap_manifest_sha
  from public.lf_capability_registry r
  join public.lf_capability_current c using(capability_code)
  where r.capability_code='INDEPENDENT_ASSURANCE';
  if v_cap_status is distinct from 'ACTIVE'
     or coalesce(v_cap_manifest_sha,'') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_ASSURANCE_NOT_CURRENT');
  end if;

  if (p_case_manifest->>'run_id') is distinct from p_run_id::text
     or (p_case_manifest->>'family_code') is distinct from p_family_code
     or jsonb_typeof(p_case_manifest->'expected') is distinct from 'object'
     or jsonb_typeof(p_case_manifest->'oracle') is distinct from 'object'
     or jsonb_typeof(p_case_manifest->'evidence') is distinct from 'object'
     or coalesce(p_case_manifest->>'adjudication_sha256','') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('result','BLOCKED','code','GOLD_B_CASE_MANIFEST_BINDING_INVALID');
  end if;

  v_subject_ref:='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||p_run_id::text||'-'||p_family_code;
  v_subject_sha:=p_case_manifest->>'adjudication_sha256';

  return jsonb_build_object(
    'result','REVIEW_REQUIRED',
    'adapter_schema_version','INPUT_GOV_GOLD_B_INDEPENDENT_ADAPTER_V1',
    'consumer','IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6',
    'capability_code','INDEPENDENT_ASSURANCE',
    'capability_version',v_cap_version,
    'capability_manifest_sha256',v_cap_manifest_sha,
    'authority_ref','supabase://transversal.decision_log/DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
    'subject_type','INPUT_GOV_GOLD_B_CRITICAL_CASE',
    'subject_ref',v_subject_ref,
    'subject_sha256',v_subject_sha,
    'case_manifest',p_case_manifest,
    'required_receipt',jsonb_build_object(
      'ledger','private.lf_evidence_ledger_v1',
      'receipt_kind','AUDIT_VERDICT',
      'verification_state','VERIFIED',
      'independent',true,
      'independence_measure_state','INDEPENDENT',
      'self_adjudication','FORBIDDEN'
    )
  );
end
$function$;

comment on function programacion.fn_input_gov_gold_b_prepare_review_v1(bigint,text,jsonb)
is 'M7.6 thin adapter preparation. Packages an exact Gold B critical case for INDEPENDENT_ASSURANCE; never adjudicates or persists a verdict.';

create or replace function programacion.fn_input_gov_gold_b_consume_review_v1(
  p_run_id bigint,
  p_family_code text,
  p_case_manifest jsonb,
  p_receipt_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','public','private'
as $function$
declare
  v_prepare jsonb;
  v_receipt private.lf_evidence_ledger_v1%rowtype;
  v_curator_identity text;
  v_validator_identity text;
  v_reviewer_identity text;
begin
  v_prepare:=programacion.fn_input_gov_gold_b_prepare_review_v1(p_run_id,p_family_code,p_case_manifest);
  if v_prepare->>'result'<>'REVIEW_REQUIRED' then
    return v_prepare;
  end if;
  if p_receipt_id is null then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RECEIPT_REQUIRED');
  end if;

  select * into v_receipt
  from private.lf_evidence_ledger_v1
  where receipt_id=p_receipt_id;
  if not found then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RECEIPT_NOT_FOUND');
  end if;

  if v_receipt.capability_code is distinct from 'INDEPENDENT_ASSURANCE'
     or v_receipt.receipt_kind is distinct from 'AUDIT_VERDICT'
     or v_receipt.subject_type is distinct from v_prepare->>'subject_type'
     or v_receipt.subject_ref is distinct from v_prepare->>'subject_ref'
     or v_receipt.subject_sha256 is distinct from v_prepare->>'subject_sha256'
     or v_receipt.authority_ref is distinct from v_prepare->>'authority_ref'
     or v_receipt.verification_state is distinct from 'VERIFIED' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID');
  end if;

  select curator_identity,validator_identity
    into v_curator_identity,v_validator_identity
  from programacion.input_readiness_runs
  where id=p_run_id;

  v_reviewer_identity:=nullif(btrim(coalesce(v_receipt.receipt_payload->>'reviewer_identity','')),'');
  if v_reviewer_identity is null
     or v_reviewer_identity in (v_curator_identity,v_validator_identity) then
    return jsonb_build_object('result','BLOCKED','code','SELF_ADJUDICATION_REJECTED');
  end if;

  if v_receipt.receipt_payload->>'verdict' is distinct from 'PASS'
     or v_receipt.receipt_payload->'independent' is distinct from 'true'::jsonb
     or v_receipt.receipt_payload#>>'{independence_measure,state}' is distinct from 'INDEPENDENT'
     or v_receipt.receipt_payload->'expected' is distinct from p_case_manifest->'expected'
     or v_receipt.receipt_payload->'oracle' is distinct from p_case_manifest->'oracle'
     or v_receipt.receipt_payload->'evidence' is distinct from p_case_manifest->'evidence' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_CONTENT_INVALID');
  end if;

  return jsonb_build_object(
    'result','PASS',
    'adapter_schema_version','INPUT_GOV_GOLD_B_INDEPENDENT_ADAPTER_V1',
    'subject_ref',v_prepare->>'subject_ref',
    'subject_sha256',v_prepare->>'subject_sha256',
    'reviewer_identity',v_reviewer_identity,
    'receipt_id',v_receipt.receipt_id,
    'receipt_sha256',v_receipt.receipt_sha256,
    'authority_ref',v_receipt.authority_ref,
    'capability_code',v_receipt.capability_code,
    'verification_state',v_receipt.verification_state
  );
end
$function$;

revoke all on function programacion.fn_input_gov_gold_b_consume_review_v1(bigint,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function programacion.fn_input_gov_gold_b_consume_review_v1(bigint,text,jsonb,uuid) to service_role;

comment on function programacion.fn_input_gov_gold_b_consume_review_v1(bigint,text,jsonb,uuid)
is 'M7.6 thin consumer. Accepts only an exact VERIFIED EVIDENCE_LEDGER AUDIT_VERDICT produced under INDEPENDENT_ASSURANCE and M1.7 authority; rejects Curator/Validator self-adjudication.';
