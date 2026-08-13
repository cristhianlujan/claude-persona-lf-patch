create or replace function private.fn_persist_lf_p0_execution_v1(p_bundle jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_execution jsonb;
  v_execution_id text;
  v_fingerprint text;
  v_existing text;
  v_item jsonb;
  v_is_pass boolean;
begin
  if p_bundle is null or jsonb_typeof(p_bundle) <> 'object' then
    raise exception using errcode = '22023', message = 'LF_P0_BUNDLE_OBJECT_REQUIRED';
  end if;

  v_execution := p_bundle->'execution';
  if jsonb_typeof(v_execution) <> 'object' then
    raise exception using errcode = '22023', message = 'LF_P0_EXECUTION_OBJECT_REQUIRED';
  end if;

  v_execution_id := v_execution->>'execution_id';
  if v_execution_id is null or v_execution_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$' then
    raise exception using errcode = '22023', message = 'LF_P0_EXECUTION_ID_INVALID';
  end if;

  if jsonb_typeof(p_bundle->'elements') <> 'array'
     or jsonb_typeof(p_bundle->'evidence_units') <> 'array'
     or jsonb_typeof(p_bundle->'element_evidence') <> 'array'
     or jsonb_typeof(p_bundle->'records') <> 'array'
     or jsonb_typeof(p_bundle->'artifacts') <> 'array'
     or jsonb_typeof(p_bundle->'transitions') <> 'array'
     or jsonb_array_length(p_bundle->'elements') = 0
     or jsonb_array_length(p_bundle->'records') = 0
     or jsonb_array_length(p_bundle->'artifacts') = 0
     or jsonb_array_length(p_bundle->'transitions') = 0 then
    raise exception using errcode = '22023', message = 'LF_P0_COMPLETE_GRAPH_REQUIRED';
  end if;

  v_is_pass := (v_execution->>'verdict') = 'PASS';

  if v_is_pass and exists (
    select 1
    from private.lf_p0_invalidated_loop_versions_v1
    where loop_version = v_execution->>'loop_version'
  ) then
    raise exception using errcode = '23514', message = 'LF_P0_INVALIDATED_LOOP_CANNOT_PASS';
  end if;

  if v_is_pass then
    if jsonb_array_length(p_bundle->'evidence_units') = 0
       or jsonb_array_length(p_bundle->'element_evidence') = 0 then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_EVIDENCE_REQUIRED';
    end if;

    if coalesce(v_execution->'dependencies', '{}'::jsonb) = '{}'::jsonb then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_DEPENDENCIES_REQUIRED';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_bundle->'elements') e
      where not exists (
        select 1
        from jsonb_array_elements(p_bundle->'element_evidence') l
        where l->>'element_id' = e->>'element_id'
      )
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_ELEMENT_WITHOUT_EVIDENCE';
    end if;

    if exists (
      select 1
      from (
        select l->>'evidence_unit_id' as evidence_unit_id, count(*) as c
        from jsonb_array_elements(p_bundle->'element_evidence') l
        group by l->>'evidence_unit_id'
        having count(*) <> 1
      ) d
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_EVIDENCE_OWNERSHIP_MUST_BE_EXCLUSIVE';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_bundle->'evidence_units') u
      where not exists (
        select 1
        from jsonb_array_elements(p_bundle->'element_evidence') l
        where l->>'evidence_unit_id' = u->>'evidence_unit_id'
      )
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_ORPHAN_EVIDENCE_UNIT';
    end if;

    if exists (
      select 1
      from unnest(array['SOURCE','CONFIGURATION','RECEIPT','MANIFEST','AUDIT']::text[]) required_role
      where not exists (
        select 1
        from jsonb_array_elements(p_bundle->'artifacts') a
        where a->>'artifact_role' = required_role
      )
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_REQUIRED_ARTIFACTS_MISSING';
    end if;

    if not exists (
      select 1
      from jsonb_array_elements(p_bundle->'artifacts') a
      where a->>'artifact_role' = 'SOURCE'
        and a->>'content_sha256' = v_execution->>'source_sha256'
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_SOURCE_HASH_NOT_LINKED';
    end if;

    if not exists (
      select 1
      from jsonb_array_elements(p_bundle->'artifacts') a
      where a->>'artifact_role' = 'CONFIGURATION'
        and a->>'content_sha256' = v_execution->>'configuration_sha256'
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_CONFIGURATION_HASH_NOT_LINKED';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_bundle->'records') r
      where r->>'record_kind' in ('RULE','VALIDATION')
        and nullif(r->>'rule_version','') is null
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_RULE_VERSION_REQUIRED';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_bundle->'records') r
      where r->>'record_kind' = 'VALIDATION'
        and r->>'status' <> 'PASS'
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_VALIDATION_NOT_PASS';
    end if;

    if not exists (
      select 1
      from jsonb_array_elements(p_bundle->'records') r
      where r->>'record_kind' = 'PASS_RESULT'
        and r->>'status' = 'PASS'
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_RESULT_NOT_PASS';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_bundle->'records') r
      where r->>'record_kind' in ('OMISSION','CONTAMINATION','RESIDUAL','EXCEPTION')
        and r->>'severity' in ('CRITICAL','HIGH','MEDIUM')
        and r->>'status' not in ('PASS','RESOLVED','CLOSED','NOT_APPLICABLE')
    ) then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_BLOCKING_RECORD_PRESENT';
    end if;

    if (
      select t->>'to_state'
      from jsonb_array_elements(p_bundle->'transitions') t
      order by (t->>'transition_ordinal')::integer desc
      limit 1
    ) <> 'COMPLETE' then
      raise exception using errcode = '23514', message = 'LF_P0_PASS_FINAL_TRANSITION_NOT_COMPLETE';
    end if;
  end if;

  v_fingerprint := encode(
    extensions.digest(pg_catalog.convert_to(p_bundle::text, 'UTF8'), 'sha256'),
    'hex'
  );

  select request_fingerprint_sha256
    into v_existing
  from private.lf_p0_execution_runs_v1
  where execution_id = v_execution_id;

  if found then
    if v_existing <> v_fingerprint then
      raise exception using errcode = '23505', message = 'LF_P0_EXECUTION_ID_CONFLICT';
    end if;

    insert into private.lf_p0_execution_persist_attempts_v1(
      execution_id, request_fingerprint_sha256, outcome
    )
    values (v_execution_id, v_fingerprint, 'IDEMPOTENT_REPLAY');

    return jsonb_build_object(
      'execution_id', v_execution_id,
      'outcome', 'IDEMPOTENT_REPLAY',
      'request_fingerprint_sha256', v_fingerprint
    );
  end if;

  insert into private.lf_p0_execution_runs_v1(
    execution_id, started_at, completed_at, terminal_state, verdict,
    source_ref, source_sha256, source_width, source_height, source_mime_type,
    code_head_sha, loop_version, configuration_id, configuration_sha256,
    languages, dependencies, acceptance_declared, autonomous_system_ready,
    p0_5_authorized, production_authorized, unresolved_critical,
    unresolved_high, unresolved_medium, mutation_escapes, request_fingerprint_sha256,
    supersedes_execution_id, supersession_reason
  ) values (
    v_execution_id, (v_execution->>'started_at')::timestamptz,
    nullif(v_execution->>'completed_at', '')::timestamptz,
    v_execution->>'terminal_state', v_execution->>'verdict',
    v_execution->>'source_ref', v_execution->>'source_sha256',
    (v_execution->>'source_width')::integer, (v_execution->>'source_height')::integer,
    v_execution->>'source_mime_type', v_execution->>'code_head_sha',
    v_execution->>'loop_version', v_execution->>'configuration_id',
    v_execution->>'configuration_sha256', v_execution->'languages',
    v_execution->'dependencies', coalesce((v_execution->>'acceptance_declared')::boolean, false),
    coalesce((v_execution->>'autonomous_system_ready')::boolean, false),
    coalesce((v_execution->>'p0_5_authorized')::boolean, false),
    coalesce((v_execution->>'production_authorized')::boolean, false),
    coalesce((v_execution->>'unresolved_critical')::integer, 0),
    coalesce((v_execution->>'unresolved_high')::integer, 0),
    coalesce((v_execution->>'unresolved_medium')::integer, 0),
    coalesce((v_execution->>'mutation_escapes')::integer, 0),
    v_fingerprint,
    nullif(v_execution->>'supersedes_execution_id', ''),
    nullif(v_execution->>'supersession_reason', '')
  );

  for v_item in select value from jsonb_array_elements(p_bundle->'elements') loop
    insert into private.lf_p0_execution_elements_v1(
      execution_id, element_id, parent_element_id, element_type, visible_text,
      bbox, cardinality, confidence, modality, payload
    ) values (
      v_execution_id, v_item->>'element_id', nullif(v_item->>'parent_element_id', ''),
      v_item->>'element_type', v_item->>'visible_text', v_item->'bbox',
      coalesce((v_item->>'cardinality')::integer, 1),
      nullif(v_item->>'confidence', '')::numeric, v_item->>'modality',
      coalesce(v_item->'payload', '{}'::jsonb)
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_bundle->'evidence_units') loop
    insert into private.lf_p0_execution_evidence_units_v1(
      execution_id, evidence_unit_id, evidence_kind, evidence_ref,
      content_sha256, bbox, modality, payload
    ) values (
      v_execution_id, v_item->>'evidence_unit_id', v_item->>'evidence_kind',
      v_item->>'evidence_ref', nullif(v_item->>'content_sha256', ''),
      v_item->'bbox', v_item->>'modality', coalesce(v_item->'payload', '{}'::jsonb)
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_bundle->'element_evidence') loop
    insert into private.lf_p0_execution_element_evidence_v1(
      execution_id, element_id, evidence_unit_id, relationship
    )
    values (
      v_execution_id, v_item->>'element_id',
      v_item->>'evidence_unit_id', v_item->>'relationship'
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_bundle->'records') loop
    insert into private.lf_p0_execution_records_v1(
      execution_id, record_kind, record_id, stage, rule_version, severity, status, payload
    ) values (
      v_execution_id, v_item->>'record_kind', v_item->>'record_id', v_item->>'stage',
      nullif(v_item->>'rule_version', ''), nullif(v_item->>'severity', ''),
      v_item->>'status', coalesce(v_item->'payload', '{}'::jsonb)
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_bundle->'artifacts') loop
    insert into private.lf_p0_execution_artifacts_v1(
      execution_id, artifact_id, artifact_role, artifact_ref, content_sha256,
      content_bytes, external_evidence_ref, payload
    ) values (
      v_execution_id, v_item->>'artifact_id', v_item->>'artifact_role',
      v_item->>'artifact_ref', v_item->>'content_sha256',
      nullif(v_item->>'content_bytes', '')::bigint,
      nullif(v_item->>'external_evidence_ref', ''),
      coalesce(v_item->'payload', '{}'::jsonb)
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_bundle->'transitions') loop
    insert into private.lf_p0_execution_transitions_v1(
      execution_id, transition_ordinal, from_state, to_state, occurred_at, reason, payload
    ) values (
      v_execution_id, (v_item->>'transition_ordinal')::integer,
      nullif(v_item->>'from_state', ''), v_item->>'to_state',
      (v_item->>'occurred_at')::timestamptz, v_item->>'reason',
      coalesce(v_item->'payload', '{}'::jsonb)
    );
  end loop;

  if not exists (
       select 1
       from private.lf_p0_execution_records_v1
       where execution_id = v_execution_id and record_kind = 'RULE'
     )
     or not exists (
       select 1
       from private.lf_p0_execution_records_v1
       where execution_id = v_execution_id and record_kind = 'VALIDATION'
     )
     or not exists (
       select 1
       from private.lf_p0_execution_records_v1
       where execution_id = v_execution_id and record_kind = 'PASS_RESULT'
     ) then
    raise exception using errcode = '23514', message = 'LF_P0_RULE_VALIDATION_PASS_RECORDS_REQUIRED';
  end if;

  if exists (
    select 1
    from private.lf_p0_execution_evidence_units_v1 u
    where u.execution_id = v_execution_id
      and not exists (
        select 1
        from private.lf_p0_execution_element_evidence_v1 l
        where l.execution_id = u.execution_id
          and l.evidence_unit_id = u.evidence_unit_id
      )
  ) then
    raise exception using errcode = '23514', message = 'LF_P0_ORPHAN_EVIDENCE_UNIT';
  end if;

  insert into private.lf_p0_execution_persist_attempts_v1(
    execution_id, request_fingerprint_sha256, outcome
  )
  values (v_execution_id, v_fingerprint, 'INSERTED');

  return jsonb_build_object(
    'execution_id', v_execution_id,
    'outcome', 'INSERTED',
    'request_fingerprint_sha256', v_fingerprint
  );
exception
  when others then
    raise;
end;
$$;

revoke all on function private.fn_persist_lf_p0_execution_v1(jsonb)
  from public, anon, authenticated;
grant execute on function private.fn_persist_lf_p0_execution_v1(jsonb)
  to service_role;

comment on function private.fn_persist_lf_p0_execution_v1(jsonb) is
  'Atomically persists one immutable P0 execution graph. PASS is fail-closed on evidence ownership, element evidence, required source/config/receipt/manifest/audit artifacts, validation status, rule versions, final COMPLETE transition, and invalidated loop versions.';