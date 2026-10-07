begin;

-- Programming context snapshot runtime guard v1.
-- Reuses DECISION_CONTEXT_ASOF for storage and readback.
-- Adds a programming-specific validation wrapper; no new store and no parallel context engine.

create or replace function programacion.fn_programming_context_snapshot_validate_v1(p_context jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, programacion, extensions
as $fn$
declare
  v_snapshot jsonb;
  v_scope jsonb;
  v_front jsonb;
  v_item jsonb;
  v_scope_id text;
  v_front_ref jsonb;
  v_missing text[];
  v_count integer;
begin
  if private.fn_lf_decision_context_asof_payload_valid_v1(p_context) is not true then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','GENERIC_CONTEXT_INVALID');
  end if;

  v_snapshot := p_context #> '{extensions,programming_context_snapshot}';
  if jsonb_typeof(v_snapshot) <> 'object' then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SNAPSHOT_MISSING');
  end if;

  if v_snapshot->>'schema_version' is distinct from 'PROGRAMMING_CONTEXT_SNAPSHOT_V1' then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SNAPSHOT_VERSION');
  end if;

  if not (v_snapshot ?& array[
    'objective','target','target_granularity','authority_state','implementation_state',
    'requirements','authority_bindings','applicable_rules','applicable_invariants','preserve',
    'material_front_coverage','implementability_schema','decision_context','analysis_stop_rule',
    'scope_front_matrix','scope_readiness','human_decision_queue','package_readiness',
    'unresolved_material_items','source_refs','currentness_refs',
    'snapshot_schema_digest_sha256','authority_fingerprint_sha256','source_snapshot_sha256'
  ]) then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SNAPSHOT_REQUIRED_FIELD_MISSING');
  end if;

  if coalesce(v_snapshot->>'authority_state','') not in ('EXISTING','NEW','UNKNOWN')
     or coalesce(v_snapshot->>'implementation_state','') not in ('EXISTING','NEW','UNKNOWN') then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_TARGET_STATE_INVALID');
  end if;

  if coalesce(v_snapshot->>'snapshot_schema_digest_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(v_snapshot->>'authority_fingerprint_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(v_snapshot->>'source_snapshot_sha256','') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SNAPSHOT_DIGEST_INVALID');
  end if;

  foreach v_item in array array[
    v_snapshot->'requirements',
    v_snapshot->'authority_bindings',
    v_snapshot->'applicable_rules',
    v_snapshot->'applicable_invariants',
    v_snapshot->'preserve',
    v_snapshot->'scope_front_matrix',
    v_snapshot->'scope_readiness',
    v_snapshot->'human_decision_queue',
    v_snapshot->'unresolved_material_items',
    v_snapshot->'source_refs',
    v_snapshot->'currentness_refs'
  ] loop
    if jsonb_typeof(v_item) <> 'array' then
      return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SNAPSHOT_ARRAY_INVALID');
    end if;
  end loop;

  if jsonb_array_length(v_snapshot->'scope_readiness') = 0 then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SCOPE_READINESS_EMPTY');
  end if;

  -- Scope readiness and human-decision queue invariants.
  for v_scope in select value from jsonb_array_elements(v_snapshot->'scope_readiness')
  loop
    if jsonb_typeof(v_scope)<>'object'
       or not (v_scope ?& array['scope_id','scope_kind','status','depends_on_scope_ids','material_front_refs','authority_refs','blockers','reason'])
       or jsonb_typeof(v_scope->'depends_on_scope_ids')<>'array'
       or jsonb_typeof(v_scope->'material_front_refs')<>'array'
       or jsonb_typeof(v_scope->'authority_refs')<>'array'
       or jsonb_typeof(v_scope->'blockers')<>'array'
       or coalesce(v_scope->>'status','') not in ('READY','NEED_MORE_EVIDENCE','REQUIRES_DECISION','BLOCKED','NOT_APPLICABLE') then
      return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SCOPE_READINESS_ITEM_INVALID');
    end if;

    v_scope_id := v_scope->>'scope_id';

    if v_scope->>'status'='REQUIRES_DECISION' then
      select count(*) into v_count
      from jsonb_array_elements(v_snapshot->'human_decision_queue') q
      where q->>'status'='PENDING_OWNER_DECISION'
        and q->>'owner_scope'='SUPER_ADMIN'
        and jsonb_typeof(q->'scope_refs')='array'
        and (q->'scope_refs') ? v_scope_id;
      if v_count=0 then
        return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_HUMAN_DECISION_PACKET_MISSING','scope_id',v_scope_id);
      end if;
    end if;

    if v_scope->>'status'='READY' then
      select count(*) into v_count
      from jsonb_array_elements(v_snapshot->'human_decision_queue') q
      where q->>'status'='PENDING_OWNER_DECISION'
        and jsonb_typeof(q->'scope_refs')='array'
        and (q->'scope_refs') ? v_scope_id;
      if v_count<>0 then
        return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_READY_SCOPE_HAS_PENDING_HUMAN_DECISION','scope_id',v_scope_id);
      end if;
    end if;
  end loop;

  for v_item in select value from jsonb_array_elements(v_snapshot->'human_decision_queue')
  loop
    if jsonb_typeof(v_item)<>'object'
       or not (v_item ?& array['decision_code','scope_refs','material_question','options','recommendation','risk_if_deferred','authority_refs','evidence_refs','currentness_refs','owner_scope','resume_condition','status'])
       or jsonb_typeof(v_item->'scope_refs')<>'array'
       or jsonb_typeof(v_item->'options')<>'array'
       or jsonb_typeof(v_item->'authority_refs')<>'array'
       or jsonb_typeof(v_item->'evidence_refs')<>'array'
       or jsonb_typeof(v_item->'currentness_refs')<>'array'
       or coalesce(v_item->>'status','') not in ('PENDING_OWNER_DECISION','RESOLVED')
       or coalesce(v_item->>'owner_scope','')<>'SUPER_ADMIN' then
      return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_HUMAN_DECISION_PACKET_INVALID');
    end if;
  end loop;

  -- Material-front contract shape.
  if jsonb_typeof(v_snapshot->'material_front_coverage')<>'object'
     or v_snapshot#>>'{material_front_coverage,schema_version}' is distinct from 'MATERIAL_FRONT_COVERAGE_V1'
     or jsonb_typeof(v_snapshot#>'{material_front_coverage,material_fronts}')<>'array'
     or coalesce((v_snapshot#>>'{material_front_coverage,all_material_fronts_accounted}')::boolean,false) is not true then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_MATERIAL_FRONT_COVERAGE_INVALID');
  end if;

  for v_front in select value from jsonb_array_elements(v_snapshot#>'{material_front_coverage,material_fronts}')
  loop
    if jsonb_typeof(v_front)<>'object'
       or not (v_front ?& array['front_id','front_kind','status','closure','source_signal_refs','scope_refs','authority_refs','evidence_refs','currentness_refs','blockers','reason'])
       or jsonb_typeof(v_front->'source_signal_refs')<>'array'
       or jsonb_typeof(v_front->'scope_refs')<>'array'
       or jsonb_typeof(v_front->'authority_refs')<>'array'
       or jsonb_typeof(v_front->'evidence_refs')<>'array'
       or jsonb_typeof(v_front->'currentness_refs')<>'array'
       or jsonb_typeof(v_front->'blockers')<>'array'
       or coalesce(v_front->>'status','') not in ('REQUIRED','REUSE_AS_IS','NOT_APPLICABLE')
       or coalesce(v_front->>'closure','') not in ('CLOSED','BLOCKED') then
      return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_MATERIAL_FRONT_ITEM_INVALID');
    end if;
  end loop;

  -- Bidirectional scope/front matrix: every referenced front must have exactly one row.
  for v_scope in select value from jsonb_array_elements(v_snapshot->'scope_readiness')
  loop
    v_scope_id := v_scope->>'scope_id';
    for v_front_ref in select value from jsonb_array_elements(v_scope->'material_front_refs')
    loop
      select count(*) into v_count
      from jsonb_array_elements(v_snapshot->'scope_front_matrix') m
      where m->>'scope_id'=v_scope_id
        and m->>'front_id'=trim(both '"' from v_front_ref::text)
        and jsonb_typeof(m)='object'
        and m ?& array['scope_id','front_id','front_status','front_closure','effect_on_scope','evidence_refs','reason'];
      if v_count<>1 then
        return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_SCOPE_FRONT_MATRIX_INCOMPLETE','scope_id',v_scope_id,'front_id',trim(both '"' from v_front_ref::text),'count',v_count);
      end if;
    end loop;
  end loop;

  -- Implementability must be materially typed, not a prose/skeletal placeholder.
  if jsonb_typeof(v_snapshot->'implementability_schema')<>'object'
     or v_snapshot#>>'{implementability_schema,schema_version}' is distinct from 'IMPLEMENTABILITY_SCHEMA_V1'
     or jsonb_typeof(v_snapshot#>'{implementability_schema,requirements}')<>'array'
     or jsonb_typeof(v_snapshot#>'{implementability_schema,canonical_implementation_bindings}')<>'array'
     or jsonb_typeof(v_snapshot#>'{implementability_schema,unresolved_material_items}')<>'array'
     or jsonb_typeof(v_snapshot#>'{implementability_schema,source_refs}')<>'array'
     or jsonb_typeof(v_snapshot#>'{implementability_schema,currentness_refs}')<>'array'
     or coalesce(v_snapshot#>>'{implementability_schema,implementability_fingerprint_sha256}','') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_IMPLEMENTABILITY_SCHEMA_INVALID');
  end if;

  -- Decision context must carry the full A5 contract, not a summary.
  if jsonb_typeof(v_snapshot->'decision_context')<>'object'
     or v_snapshot#>>'{decision_context,schema_version}' is distinct from 'ANALYSIS_DECISION_CONTEXT_V1'
     or not ((v_snapshot->'decision_context') ?& array[
       'decision_id','subject_ref','scope_refs','material_question','status','options_considered',
       'selected_option_ref','rationale','authority_refs','evidence_refs','currentness_refs',
       'unresolved_questions','adr_disposition','adr_ref','persistence_ref','decision_fingerprint_sha256'
     ]) then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_DECISION_CONTEXT_INVALID');
  end if;

  if coalesce(v_snapshot#>>'{decision_context,decision_fingerprint_sha256}','') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_DECISION_CONTEXT_FINGERPRINT_INVALID');
  end if;

  if jsonb_typeof(v_snapshot->'analysis_stop_rule')<>'object'
     or not ((v_snapshot->'analysis_stop_rule') ?& array[
       'decision','decision_stable','material_front_coverage_ref','all_material_fronts_accounted',
       'unresolved_decision_changing_questions','additional_available_evidence_capable_of_changing_material_decision',
       'evidence_refs','reason'
     ]) then
    return jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1','state','BLOCKED','code','PROGRAMMING_STOP_RULE_INVALID');
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1',
    'state','VALID',
    'code','PROGRAMMING_CONTEXT_VALID',
    'subject_ref',p_context#>>'{subject,ref}',
    'snapshot_schema_digest_sha256',v_snapshot->>'snapshot_schema_digest_sha256'
  );
exception when others then
  return jsonb_build_object(
    'schema_version','PROGRAMMING_CONTEXT_SNAPSHOT_VALIDATION_V1',
    'state','BLOCKED',
    'code','PROGRAMMING_CONTEXT_VALIDATOR_ERROR',
    'sqlstate',sqlstate
  );
end
$fn$;

create or replace function programacion.fn_programming_context_record_v1(
  p_context jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, programacion, extensions
as $fn$
declare
  v_validation jsonb;
  v_receipt jsonb;
begin
  v_validation := programacion.fn_programming_context_snapshot_validate_v1(p_context);
  if v_validation->>'state' is distinct from 'VALID' then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_CONTEXT_RECORD_RECEIPT_V1',
      'state','BLOCKED',
      'code','PROGRAMMING_CONTEXT_SNAPSHOT_INVALID',
      'validation',v_validation
    );
  end if;

  v_receipt := public.fn_lf_decision_context_asof_record_v1(p_context,p_actor_execution_id);
  return v_receipt || jsonb_build_object('programming_context_validation',v_validation);
end
$fn$;

create or replace function programacion.fn_programming_context_resolve_v1(
  p_consumer_code text,
  p_subject_ref text,
  p_as_of timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, programacion, extensions
as $fn$
declare
  v_resolution jsonb;
  v_validation jsonb;
begin
  v_resolution := public.fn_lf_decision_context_asof_resolve_v1(p_consumer_code,p_subject_ref,p_as_of);
  if v_resolution->>'state' is distinct from 'RESOLVED' then
    return v_resolution;
  end if;

  v_validation := programacion.fn_programming_context_snapshot_validate_v1(v_resolution->'context');
  if v_validation->>'state' is distinct from 'VALID' then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_CONTEXT_RESOLUTION_V1',
      'state','BLOCKED',
      'code','PROGRAMMING_CONTEXT_SNAPSHOT_INVALID',
      'context_id',v_resolution->>'context_id',
      'context_sha256',v_resolution->>'context_sha256',
      'validation',v_validation
    );
  end if;

  return v_resolution || jsonb_build_object('programming_context_validation',v_validation);
end
$fn$;

comment on function programacion.fn_programming_context_snapshot_validate_v1(jsonb)
is 'Programming-specific runtime conformance guard over the generic DECISION_CONTEXT_ASOF payload. No new store; validates PROGRAMMING_CONTEXT_SNAPSHOT_V1 before record/admission.';

comment on function programacion.fn_programming_context_record_v1(jsonb,text)
is 'Guarded A9 record wrapper: validates PROGRAMMING_CONTEXT_SNAPSHOT_V1 then delegates storage to public.fn_lf_decision_context_asof_record_v1.';

comment on function programacion.fn_programming_context_resolve_v1(text,text,timestamptz)
is 'Guarded PG-01 resolve wrapper: delegates immutable as-of read then revalidates the programming snapshot before admission.';

commit;
