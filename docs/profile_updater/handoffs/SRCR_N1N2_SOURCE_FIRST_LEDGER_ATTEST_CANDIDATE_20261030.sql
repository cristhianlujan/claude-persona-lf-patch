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
