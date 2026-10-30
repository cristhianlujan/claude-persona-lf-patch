-- LF SRCR N1/N2 source-first + existing profile execution quality gate.
-- CANDIDATE STAGED FOR TRAIN: no direct SQL apply, no new actor, no direct
-- profile promotion. Gate only applies to the existing SRCR profile execution
-- when a future governed run has the explicit gate marker SOURCE_FIRST_V1.
-- Prior runs and all other profiles remain under previous rule.
-- Source reader requires an independently authorized EVIDENCE_LEDGER actor.
-- Never issue VERIFIED from model-authored data.

-- Candidate for governed ACTUALIZACION_DB_LF Train ONLY. Do not execute directly.
-- Source-first readback is performed by SQL, not by the producer or the judge.
-- No new orchestrator, table, model call, pipeline or authorization shortcut.
-- The caller MUST already possess a separate, legitimately governed
-- EVIDENCE_LEDGER actor execution linked to the exact profile execution.
create or replace function public.lf_srcr_n1n2_source_first_ledger_v1(
  p_execution_id text,
  p_uncertainty_id text,
  p_codigo_activo text,
  p_ledger_execution_id text
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','public','private','extensions'
as $srcr$
declare
  v_run public.lf_operation_execution%rowtype;
  v_ledger public.lf_operation_execution%rowtype;
  v_exec public.lf_operation_execution_steps%rowtype;
  v_source public.lf_operation_execution_steps%rowtype;
  v_target text;
  v_source_head text;
  v_candidate text;
  v_level text;
  v_table text;
  v_kind text;
  v_query text;
  v_rows jsonb;
  v_n integer;
  v_data jsonb;
  v_preimage jsonb;
  v_digest text;
  v_subject text;
  v_observed timestamptz;
  v_proof jsonb;
  v_results jsonb := '[]'::jsonb;
  v_expected jsonb;
  v_existing private.lf_evidence_ledger_v1%rowtype;
  v_existing_count integer;
begin
  select * into v_run from public.lf_operation_execution
   where execution_id=p_execution_id and operation_code='EJECUCION_PERFIL_LF'
     and target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
     and status='IN_PROGRESS';
  if not found then raise exception 'BLOCK_SRCR_SOURCE_EXECUTION_NOT_GOVERNED'; end if;

  select * into v_ledger from public.lf_operation_execution
   where execution_id=p_ledger_execution_id
     and status='IN_PROGRESS' and manifest->>'capability_code'='EVIDENCE_LEDGER'
     and manifest->>'producer_execution_id'=p_execution_id;
  if not found then raise exception 'BLOCK_SRCR_LEDGER_ACTOR_NOT_BOUND_TO_PRODUCER'; end if;

  if p_uncertainty_id is null or btrim(p_uncertainty_id)=''
     or p_codigo_activo !~ '^[A-Z0-9][A-Z0-9_-]{1,127}$' then
    raise exception 'BLOCK_SRCR_SOURCE_IDENTITY_INVALID';
  end if;

  select * into v_exec from public.lf_operation_execution_steps
   where execution_id=p_execution_id and step_id='execute_profile'
     and status='STEP_PASS_WITH_EVIDENCE';
  if not found then raise exception 'BLOCK_SRCR_EXECUTE_PROFILE_NOT_CLEAN'; end if;

  select * into v_source from public.lf_operation_execution_steps
   where execution_id=p_execution_id and step_id='profile_source_read'
     and status='STEP_PASS_WITH_EVIDENCE';
  if not found then raise exception 'BLOCK_SRCR_PROFILE_SOURCE_NOT_CLEAN'; end if;
  v_source_head:=v_source.evidence_payload->>'source_revision';
  v_candidate:=regexp_replace(v_exec.evidence_payload->>'candidate_digest','^sha256:','');
  if v_source_head !~ '^[a-f0-9]{40}$' or v_candidate !~ '^[a-f0-9]{64}$' then
    raise exception 'BLOCK_SRCR_PROFILE_SOURCE_DIGEST_INVALID';
  end if;

  select value into v_expected
    from jsonb_array_elements(
      case when jsonb_typeof(v_exec.evidence_payload#>'{profile_output,current_uncertainties}')='array'
           then v_exec.evidence_payload#>'{profile_output,current_uncertainties}'
           else '[]'::jsonb end
    ) as item
   where item.value->>'uncertainty_id'=p_uncertainty_id
     and item.value->>'impact'='DESIGN_BLOCKING';
  if not found then raise exception 'BLOCK_SRCR_MATERIAL_UNCERTAINTY_NOT_FOUND'; end if;

  for v_level,v_table,v_kind in
    select * from (values
      ('N1'::text,'v_lf_fuente_operativa_busqueda'::text,'VIEW'::text),
      ('N2'::text,'lf_activos'::text,'BASE_TABLE'::text)
    ) as level_source(level,source_name,source_kind)
  loop
    v_query:=format(
      'SELECT codigo_activo,nombre_canonico,owner_name,estado_documental,estado_operativo FROM public.%I WHERE codigo_activo=%L',
      v_table,p_codigo_activo
    );
    if not exists(
      select 1
        from jsonb_array_elements(
          case when jsonb_typeof(v_expected#>'{cascade,catalog_queries}')='array'
            then v_expected#>'{cascade,catalog_queries}' else '[]'::jsonb end
        ) item
       where item.value->>'level'=v_level
         and item.value#>>'{readback,query}'=v_query
         and item.value#>>'{readback,source}'=v_table
    ) then raise exception 'BLOCK_SRCR_PRODUCER_QUERY_NOT_SOURCE_BOUND:%',v_level; end if;

    if v_level='N1' then
      select count(*)::integer,coalesce(jsonb_agg(
        jsonb_build_object(
          'codigo_activo',codigo_activo,
          'nombre_canonico',nombre_canonico,
          'owner_name',owner_name,
          'estado_documental',estado_documental,
          'estado_operativo',estado_operativo
        )),'[]'::jsonb)
        into v_n,v_rows
      from public.v_lf_fuente_operativa_busqueda
      where codigo_activo=p_codigo_activo;
    else
      select count(*)::integer,coalesce(jsonb_agg(
        jsonb_build_object(
          'codigo_activo',codigo_activo,
          'nombre_canonico',nombre_canonico,
          'owner_name',owner_name,
          'estado_documental',estado_documental,
          'estado_operativo',estado_operativo
        )),'[]'::jsonb)
        into v_n,v_rows
      from public.lf_activos where codigo_activo=p_codigo_activo;
    end if;

    if v_n>1 then raise exception 'BLOCK_SRCR_NON_UNIQUE_CANONICAL_ASSET:%',v_level; end if;
    v_observed:=clock_timestamp();
    v_preimage:=jsonb_build_object(
      'datum_id',p_uncertainty_id,'level',v_level,
      'source_locator',v_query,'candidate_sha256',v_candidate,
      'row_count',v_n,'sample_records',v_rows
    );
    v_digest:=encode(extensions.digest(convert_to(v_preimage::text,'UTF8'),'sha256'),'hex');
    v_subject:=format('supabase://public.%s/%s#%s',v_table,p_codigo_activo,v_level);
    v_data:=jsonb_build_object(
      'schema_version','PROFILE_N1_N2_READBACK_V1',
      'datum_id',p_uncertainty_id,'level',v_level,'source',v_table,
      'source_kind',v_kind,'source_locator',v_query,'query',v_query,
      'candidate_sha256',v_candidate,'row_count',v_n,
      'result_kind',case when v_n=0 then 'EMPTY' else 'ROWS' end,
      'sample_records',v_rows,'source_result_sha256',v_digest,
      'observed_at',v_observed,'source_revision',v_source_head
    );

    -- Idempotent replay: do a fresh provider SELECT, then reuse a previously
    -- VERIFIED receipt only when its exact typed source digest is unchanged.
    select count(*) into v_existing_count
      from private.lf_evidence_ledger_v1
     where execution_id=p_execution_id
       and gate_code='PROFILE_EXECUTION_SRCR_N1_N2_SOURCE'
       and subject_ref=v_subject;
    if v_existing_count>1 then
      raise exception 'BLOCK_SRCR_LEDGER_DUPLICATE_SOURCE_RECEIPT';
    end if;
    if v_existing_count=1 then
      select * into v_existing from private.lf_evidence_ledger_v1
       where execution_id=p_execution_id
         and gate_code='PROFILE_EXECUTION_SRCR_N1_N2_SOURCE'
         and subject_ref=v_subject;
      if v_existing.subject_sha256 is distinct from v_digest
         or v_existing.created_by_execution_id is distinct from p_ledger_execution_id
         or v_existing.verification_state is distinct from 'VERIFIED'
         or v_existing.provider is distinct from 'SUPABASE' then
        raise exception 'BLOCK_SRCR_LEDGER_REPLAY_SOURCE_DRIFT';
      end if;
      v_proof:=jsonb_build_object(
        'verification_state','VERIFIED',
        'receipt_id',v_existing.receipt_id,
        'receipt_sha256',v_existing.receipt_sha256
      );
    else
      v_proof:=public.fn_lf_evidence_ledger_anchor_v1(
        p_execution_id,'EVIDENCE_LEDGER','PROFILE_EXECUTION_SRCR_N1_N2_SOURCE',
        'SOURCE_SNAPSHOT','PROFILE_N1_N2_SOURCE',v_subject,v_digest,v_source_head,
        'supabase://public.lf_activos','LF_SUPABASE_READBACK_V1','SUPABASE',
        v_query,'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
        jsonb_build_object('provider_readback_verified',true,'digest_recomputed',true,
          'readback_at',v_observed,'source_name',v_table,'source_kind',v_kind),
        v_data,p_ledger_execution_id
      );
    end if;
    if v_proof->>'verification_state' is distinct from 'VERIFIED' then
      raise exception 'BLOCK_SRCR_LEDGER_VERIFICATION_NOT_VERIFIED';
    end if;
    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'level',v_level,'datum_id',p_uncertainty_id,'readback',v_data,
      'independent_source_ref',v_subject,
      'ledger_receipt_id',v_proof->>'receipt_id',
      'ledger_receipt_sha256',v_proof->>'receipt_sha256'
    ));
  end loop;

  return jsonb_build_object(
    'schema_version','LF_SRCR_N1_N2_SOURCE_FIRST_LEDGER_V1',
    'execution_id',p_execution_id,'candidate_sha256',v_candidate,
    'datum_id',p_uncertainty_id,'asset_code',p_codigo_activo,
    'receipt_count',jsonb_array_length(v_results),
    'readbacks',v_results
  );
end
$srcr$;

-- A source-reader cannot be called by an untrusted model or anonymous role.
revoke all on function public.lf_srcr_n1n2_source_first_ledger_v1(text,text,text,text) from public;
revoke all on function public.lf_srcr_n1n2_source_first_ledger_v1(text,text,text,text) from anon;
revoke all on function public.lf_srcr_n1n2_source_first_ledger_v1(text,text,text,text) from authenticated;
grant execute on function public.lf_srcr_n1n2_source_first_ledger_v1(text,text,text,text) to service_role;

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

-- Reuse existing EJECUCION_PERFIL_LF recorder as the only profile write owner.
-- Material N1/N2 source snapshots are obtained BEFORE output_validate is
-- recorded clean and BEFORE the independent semantic_judge reads them.
-- The model cannot pass a ledger actor ID or a purported source result.
create or replace function public.lf_record_profile_execution_step_v1(
  p_execution_id text,p_step_id text,p_evidence_ref text,
  p_evidence_payload jsonb,p_actor_execution_id text
) returns jsonb
language plpgsql set search_path to 'pg_catalog','public'
as $function$
declare
  v_trust jsonb;
  v_target text;
  v_manifest jsonb;
  v_uncertainties jsonb;
  v_item jsonb;
  v_q jsonb;
  v_asset_code text;
  v_ledger_id text;
  v_count integer;
begin
  if p_step_id='output_validate' then
    select target_code,manifest into v_target,v_manifest
      from public.lf_operation_execution
     where execution_id=p_execution_id and operation_code='EJECUCION_PERFIL_LF'
       and status='IN_PROGRESS';
    if v_target='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       and v_manifest->>'srcr_n1n2_ledger_gate'='SOURCE_FIRST_V1' then
      v_ledger_id:=nullif(v_manifest->>'evidence_ledger_execution_id','');
      if v_ledger_id is null then
        raise exception 'BLOCK_SRCR_LEDGER_ACTOR_NOT_BOUND';
      end if;
      select evidence_payload#>'{profile_output,current_uncertainties}'
        into v_uncertainties
        from public.lf_operation_execution_steps
       where execution_id=p_execution_id and step_id='execute_profile'
         and status='STEP_PASS_WITH_EVIDENCE';
      if jsonb_typeof(v_uncertainties) is distinct from 'array' then
        raise exception 'BLOCK_SRCR_SOURCE_UNCERTAINTIES_NOT_AVAILABLE';
      end if;
      for v_item in select value from jsonb_array_elements(v_uncertainties)
        where value->>'impact'='DESIGN_BLOCKING'
      loop
        select count(*) into v_count
          from jsonb_array_elements(
            case when jsonb_typeof(v_item#>'{cascade,catalog_queries}')='array'
              then v_item#>'{cascade,catalog_queries}'
              else '[]'::jsonb end
          ) as j where j.value->>'level'='N2';
        if v_count<>1 then
          raise exception 'BLOCK_SRCR_N2_QUERY_NOT_UNIQUE';
        end if;
        select j.value into v_q
          from jsonb_array_elements(v_item#>'{cascade,catalog_queries}') as j
         where j.value->>'level'='N2' limit 1;
        v_asset_code:=substring(v_q#>>'{readback,query}'
          from 'WHERE codigo_activo=''([A-Z0-9][A-Z0-9_-]{1,127})'');
        if v_asset_code is null then
          raise exception 'BLOCK_SRCR_N2_NOT_CANONICAL_ASSET_LOOKUP';
        end if;
        perform public.lf_srcr_n1n2_source_first_ledger_v1(
          p_execution_id,v_item->>'uncertainty_id',v_asset_code,v_ledger_id
        );
      end loop;
    end if;
  end if;

  v_trust:=public.lf_profile_execution_trust_validation_v2(
    p_execution_id,p_step_id,p_evidence_payload
  );
  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_profile_execution_step_v1'
  );
end
$function$;

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
    if e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       and e.manifest->>'srcr_n1n2_ledger_gate'='SOURCE_FIRST_V1'
       and jsonb_typeof(n12_required)='array' and exists(
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
                   and l.capability_code='EVIDENCE_LEDGER'
                   and l.gate_code='PROFILE_EXECUTION_SRCR_N1_N2_SOURCE'
                   and l.source_head_sha=(
                     select evidence_payload->>'source_revision'
                       from public.lf_operation_execution_steps
                      where execution_id=p_execution_id
                        and step_id='profile_source_read'
                        and status='STEP_PASS_WITH_EVIDENCE'
                   )
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
