-- CANDIDATE ONLY. Existing runtime, existing semantic_judge.
-- No new operation, actor, table, migration deployment or profile stage.
-- Do not execute directly: materialize in the existing governed updater.
-- Exact live-function origin: pg_get_functiondef of
-- public.lf_profile_execution_trust_validation_v2(text,text,jsonb).
-- Requires the trusted source-first executor to anchor SOURCE_SNAPSHOT
-- evidence through the EXISTING ledger under the SAME execution_id.
-- Missing/duplicate/origin-mismatched ledger receipts fail closed.
-- A fabricated callable/dictionary alone is NEVER authority for PASS.
-- PRECONDITION NOT FULFILLED: no N1/N2 ledger receipt exists for current
-- SRCR run; this SQL must not be promoted without readback and tests.
-- Existing scope/sha/independence controls are preserved.

CREATE OR REPLACE FUNCTION public.lf_profile_execution_trust_validation_v2(p_execution_id text, p_step_id text, p_evidence_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  base jsonb;
  e public.lf_operation_execution%rowtype;
  input_step public.lf_operation_execution_steps%rowtype;
  execute_step public.lf_operation_execution_steps%rowtype;
  semantic_step public.lf_operation_execution_steps%rowtype;
  input_binding public.lf_operation_step_judge_bindings%rowtype;
  execute_binding public.lf_operation_step_judge_bindings%rowtype;
  semantic_binding public.lf_operation_step_judge_bindings%rowtype;
  packet jsonb;
  packet_body jsonb;
  expected_digest text;
  scope_digest text;
  candidate_digest text;
  semantic_result jsonb;
  canonical_read_judge jsonb;
  hard jsonb := '[]'::jsonb;
  n12_required jsonb;
  n12_observed jsonb;
  n12_datum jsonb;
  n12_audit jsonb;
  n12_level text;
  n12_matched integer;
  n12_count integer;
  n12_preimage jsonb;
begin
  base:=public.lf_profile_execution_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );
  if coalesce((base->>'valid')::boolean,false) is not true then
    return base;
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_V2_BINDING_INVALID',
      'details',jsonb_build_object('execution_id',p_execution_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if p_step_id='input_validate' then
    packet:=p_evidence_payload->'scope_authority_packet';
    scope_digest:=p_evidence_payload->>'scope_authority_packet_sha256';
    if jsonb_typeof(packet)<>'object'
       or coalesce(packet->>'packet_version','')<>'LF_SCOPE_AUTHORITY_PACKET_V1'
       or packet->>'execution_id' is distinct from p_execution_id
       or packet->>'subject_ref' is distinct from
          'supabase://public.lf_operation_execution/'||p_execution_id||'#manifest'
       or packet->>'canonicalization_rule' is distinct from
          'POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
       or jsonb_typeof(packet->'authorized_requirements')<>'array'
       or jsonb_array_length(packet->'authorized_requirements')=0
       or jsonb_typeof(packet->'constraints')<>'array'
       or jsonb_typeof(packet->'forbidden_changes')<>'array'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
    then
      hard:=hard||jsonb_build_array('scope_authority_packet_shape_invalid');
    else
      packet_body:=packet-'sha256';
      expected_digest:='sha256:'||
        encode(extensions.digest(convert_to(packet_body::text,'UTF8'),'sha256'),'hex');
      if scope_digest is distinct from expected_digest
         or packet->>'sha256' is distinct from expected_digest then
        hard:=hard||jsonb_build_array('scope_authority_packet_digest_mismatch');
      end if;
    end if;

  elsif p_step_id='semantic_judge' then
    select * into input_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='input_validate'
      and status='ACTIVE_ENFORCEMENT';
    select * into input_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='input_validate';

    select * into execute_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='execute_profile'
      and status='ACTIVE_ENFORCEMENT';
    select * into execute_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='execute_profile';

    if input_step.step_id is null
       or input_step.status<>input_binding.clean_result_value then
      hard:=hard||jsonb_build_array('input_validate_predecessor_not_clean');
    end if;
    if execute_step.step_id is null
       or execute_step.status<>execute_binding.clean_result_value then
      hard:=hard||jsonb_build_array('execute_profile_predecessor_not_clean');
    end if;

    scope_digest:=input_step.evidence_payload->>'scope_authority_packet_sha256';
    candidate_digest:=execute_step.evidence_payload->>'candidate_digest';
    semantic_result:=p_evidence_payload->'semantic_judge_result';
    canonical_read_judge:=public.lf_profile_execution_canonical_read_judge_v1(p_execution_id);

    if jsonb_typeof(semantic_result)<>'object'
       or semantic_result->>'status' is distinct from 'PASS'
       or semantic_result->>'verdict' is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or semantic_result->>'validator_status' is distinct from 'PASS'
       or coalesce((semantic_result->>'producer_independence_proven')::boolean,false) is not true
       or not (
         coalesce((semantic_result->>'model_call_count')::integer,0)=1
         or (
           coalesce((semantic_result->>'model_call_count')::integer,-1)=0
           and semantic_result->>'judge_mode'='DETERMINISTIC_CANONICAL_READ_V1'
           and canonical_read_judge->>'status'='PASS'
           and semantic_result is not distinct from canonical_read_judge
         )
       )
       or coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or 'sha256:'||coalesce(semantic_result->>'candidate_sha256','')
          is distinct from candidate_digest
       or 'sha256:'||coalesce(semantic_result->>'scope_packet_sha256','')
          is distinct from scope_digest
       or jsonb_typeof(semantic_result->'result')<>'object'
       or semantic_result#>>'{result,verdict}'
          is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or semantic_result#>>'{result,candidate_sha256}'
          is distinct from semantic_result->>'candidate_sha256'
       or semantic_result#>>'{result,scope_packet_sha256}'
          is distinct from semantic_result->>'scope_packet_sha256'
       or jsonb_typeof(p_evidence_payload->'unsupported_claims')<>'array'
       or jsonb_array_length(p_evidence_payload->'unsupported_claims')<>0
       or jsonb_typeof(semantic_result#>'{result,unsupported_claims}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,unsupported_claims}')<>0
       or jsonb_typeof(semantic_result#>'{result,blocking_codes}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,blocking_codes}')<>0
    then
      hard:=hard||jsonb_build_array('semantic_judge_v2_not_pass');
    end if;

    -- N1/N2 is checked INSIDE the existing semantic_judge for profile
    -- outputs that declare material design-blocking uncertainties. This
    -- does not impose the same placement on any other adopting profile.
    n12_required:=execute_step.evidence_payload#>'{profile_output,current_uncertainties}';
    if jsonb_typeof(n12_required)='array' and exists(
      select 1 from jsonb_array_elements(n12_required) x
       where x.value->>'impact'='DESIGN_BLOCKING'
    ) then
      n12_observed:=semantic_result#>'{result,n1_n2_audit}';
      select count(*) into n12_count
        from jsonb_array_elements(n12_required) x
       where x.value->>'impact'='DESIGN_BLOCKING';
      if jsonb_typeof(n12_observed) is distinct from 'array' then
        hard:=hard||jsonb_build_array('n1_n2_ledger_coverage_missing');
      elsif jsonb_array_length(n12_observed)<>2*n12_count then
        hard:=hard||jsonb_build_array('n1_n2_ledger_coverage_missing');
      else
        for n12_datum in
          select value from jsonb_array_elements(n12_required)
           where value->>'impact'='DESIGN_BLOCKING'
        loop
          if nullif(n12_datum->>'uncertainty_id','') is null then
            hard:=hard||jsonb_build_array('n1_n2_datum_identity_missing');
          else
            for n12_level in select unnest(array['N1','N2']) loop
              select count(*) into n12_matched
                from jsonb_array_elements(n12_observed) a
               where a->>'datum_id'=n12_datum->>'uncertainty_id'
                 and a->>'level'=n12_level;
              if n12_matched<>1 then
                hard:=hard||jsonb_build_array('n1_n2_observation_not_unique');
              else
                select value into n12_audit
                  from jsonb_array_elements(n12_observed)
                 where value->>'datum_id'=n12_datum->>'uncertainty_id'
                   and value->>'level'=n12_level
                 limit 1;
                -- Source-digest is calculated by the ledger verifier from
                -- the exact provider result; producer-written values are
                -- compared but cannot themselves create a verified receipt.
                n12_preimage:=jsonb_build_object(
                  'datum_id',n12_audit->>'datum_id',
                  'level',n12_audit->>'level',
                  'source_locator',n12_audit->>'source_locator',
                  'candidate_sha256',semantic_result->>'candidate_sha256',
                  'row_count',n12_audit->'row_count',
                  'sample_records',n12_audit->'sample_records'
                );
                select count(*) into n12_matched
                  from private.lf_evidence_ledger_v1 l
                  join private.lf_evidence_resolver_registry_v1 rr
                    on rr.resolver_id=l.resolver_id
                   and rr.provider=l.provider
                   and rr.verification_method=l.verification_method
                   and rr.trust_level='TRUSTED_PROVIDER_BOUND'
                   and rr.active
                 where l.execution_id=p_execution_id
                   and l.receipt_kind='SOURCE_SNAPSHOT'
                   and l.subject_type='PROFILE_N1_N2_SOURCE'
                   and l.verification_state='VERIFIED'
                   and l.provider='SUPABASE'
                   and l.verified_at is not null
                   and l.created_by_execution_id<>p_execution_id
                   and l.receipt_payload->>'schema_version'='PROFILE_N1_N2_READBACK_V1'
                   and l.receipt_payload->>'datum_id'=n12_audit->>'datum_id'
                   and l.receipt_payload->>'level'=n12_level
                   and l.receipt_payload->>'source_locator'=n12_audit->>'source_locator'
                   and l.receipt_payload->>'candidate_sha256'=semantic_result->>'candidate_sha256'
                   and l.receipt_payload->'row_count'=n12_audit->'row_count'
                   and l.receipt_payload->'sample_records'=n12_audit->'sample_records'
                   and l.receipt_payload->>'source_result_sha256'
                     =encode(extensions.digest(convert_to(n12_preimage::text,'UTF8'),'sha256'),'hex')
                   and l.subject_sha256
                     =encode(extensions.digest(convert_to(n12_preimage::text,'UTF8'),'sha256'),'hex')
                   and l.subject_ref=n12_audit->>'independent_source_ref'
                   and l.verification_payload->>'provider_readback_verified'='true'
                   and l.verification_payload->>'digest_recomputed'='true';
                if n12_matched<>1 then
                  hard:=hard||jsonb_build_array('n1_n2_independent_source_not_ledger_verified');
                end if;
              end if;
            end loop;
          end if;
        end loop;
      end if;
    end if;

  elsif p_step_id='report_output' then
    select * into semantic_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='semantic_judge'
      and status='ACTIVE_ENFORCEMENT';
    select * into semantic_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='semantic_judge';

    if semantic_step.step_id is null
       or semantic_step.status<>semantic_binding.clean_result_value then
      hard:=hard||jsonb_build_array('semantic_judge_predecessor_not_clean');
    end if;

    if p_evidence_payload->>'result' is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or p_evidence_payload->>'profile_code' is distinct from e.target_code
       or p_evidence_payload->>'execution_id' is distinct from p_execution_id
       or coalesce((p_evidence_payload->>'no_write_performed')::boolean,false) is not true
       or p_evidence_payload->>'candidate_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
       or p_evidence_payload->>'scope_packet_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'
    then
      hard:=hard||jsonb_build_array('report_output_semantic_binding_invalid');
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','PROFILE_EXECUTION_SERVER_VALIDATION_V2_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','PROFILE_EXECUTION_SERVER_VALIDATED_V2',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$function$
