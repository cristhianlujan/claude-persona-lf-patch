-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M6.1 / PAULO-048
-- Compact source receipt = ref + authority + lifecycle + observed SHA.
-- Full observed payload is never embedded in source_manifest. A separate fail-closed
-- archive API delegates persistence to the existing EVIDENCE_LEDGER capability.
-- No parallel resolver, state model, or evidence store is created.

create or replace function programacion.fn_input_source_manifest_identity_v1(p_manifest jsonb)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_bad integer;
  v_identity jsonb;
begin
  if jsonb_typeof(p_manifest)<>'array' then
    raise exception 'INPUT_SOURCE_MANIFEST_IDENTITY_REQUIRES_ARRAY';
  end if;

  select count(*) into v_bad
  from jsonb_array_elements(p_manifest) e(value)
  where jsonb_typeof(e.value)<>'object'
     or jsonb_typeof(e.value->'ref')<>'object'
     or not (e.value ? 'authority')
     or coalesce(e.value->>'observed_sha256','') !~ '^[0-9a-f]{64}$';
  if v_bad>0 then
    raise exception 'INPUT_SOURCE_MANIFEST_IDENTITY_INVALID_RECEIPT_COUNT:%',v_bad;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'ref',e.value->'ref',
        'authority',e.value->'authority',
        'observed_sha256',e.value->>'observed_sha256'
      )
      order by (e.value->'ref')::text
    ),
    '[]'::jsonb
  ) into v_identity
  from jsonb_array_elements(p_manifest) e(value);

  return v_identity;
end;
$function$;

create or replace function programacion.fn_input_source_lifecycle_receipt_v1(
  p_ref jsonb,
  p_observed jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','programacion'
as $function$
declare
  v_kind text:=coalesce(p_ref->>'kind','');
  v_code text:=nullif(p_ref->>'codigo','');
  v_raw_states jsonb:='[]'::jsonb;
  v_state_model_matches jsonb:='[]'::jsonb;
  v_rule_authority jsonb;
begin
  if v_kind='' or jsonb_typeof(p_ref)<>'object' then
    raise exception 'INPUT_SOURCE_LIFECYCLE_REF_INVALID';
  end if;
  if p_observed is null then
    raise exception 'INPUT_SOURCE_LIFECYCLE_OBSERVED_REQUIRED:%',v_kind;
  end if;

  if jsonb_typeof(p_observed)='object' then
    select case when s is null then '[]'::jsonb else jsonb_build_array(s) end
      into v_raw_states
    from (
      select coalesce(
        nullif(p_observed->>'estado',''),
        nullif(p_observed->>'status',''),
        nullif(p_observed->>'activa',''),
        nullif(p_observed->>'active','')
      ) s
    ) q;
  elsif jsonb_typeof(p_observed)='array' then
    select coalesce(jsonb_agg(to_jsonb(s) order by s),'[]'::jsonb)
      into v_raw_states
    from (
      select distinct coalesce(
        nullif(x.value->>'estado',''),
        nullif(x.value->>'status',''),
        nullif(x.value->>'activa',''),
        nullif(x.value->>'active','')
      ) s
      from jsonb_array_elements(p_observed) x(value)
    ) q
    where s is not null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'raw_state',c.estado_original,
      'document_state',c.estado_documental,
      'operational_state',c.estado_operativo,
      'runtime_state',c.runtime_estado,
      'migration_blocker',c.migration_blocker
    ) order by c.estado_original
  ),'[]'::jsonb)
  into v_state_model_matches
  from public.cat_estado_normalizacion_lf c
  where exists (
    select 1 from jsonb_array_elements_text(v_raw_states) s(value)
    where lower(s.value)=lower(c.estado_original)
  );

  if v_kind='RULE' and v_code is not null then
    v_rule_authority:=programacion.fn_source_rule_authority(array[v_code]);
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'schema_version','IG_SOURCE_LIFECYCLE_RECEIPT_V1',
    'source_kind',v_kind,
    'resolution_state','RESOLVED',
    'state_model_ref','POL-LF-STATE-MODEL',
    'raw_states',v_raw_states,
    'state_model_matches',v_state_model_matches,
    'rule_authority',v_rule_authority
  ));
end;
$function$;

create or replace function programacion.fn_input_build_source_manifest(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','programacion'
as $function$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_manifest jsonb;
  v_graph jsonb;
  v_graph_ref jsonb:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH');
  v_graph_receipt jsonb;
  v_archive_contract jsonb:=jsonb_build_object(
    'capability_code','EVIDENCE_LEDGER',
    'producer_capability_code','SOURCE_RESOLUTION_POLICY',
    'resolver_id','LF_SUPABASE_READBACK_V1',
    'verification_method','SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'archive_api','programacion.fn_input_archive_source_observation_v1',
    'state','GOVERNED_EXECUTION_REQUIRED'
  );
begin
  select pantalla_id,version_id
    into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs
  where id=p_run_id;

  if v_pantalla_id is null then
    raise exception 'INPUT_READINESS_RUN_NOT_FOUND:%',p_run_id;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
  v_graph_receipt:=jsonb_build_object(
    'schema_version','IG_SOURCE_RECEIPT_V1',
    'ref',v_graph_ref,
    'authority','CANONICAL_COMPOSITE_GRAPH',
    'lifecycle',programacion.fn_input_source_lifecycle_receipt_v1(v_graph_ref,v_graph),
    'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph),
    'archive_contract',v_archive_contract
  );

  with refs as (
    select distinct e.ref
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.source_refs) e(ref)
    where a.run_id=p_run_id
      and coalesce(e.ref->>'kind','')<>'SCREEN_CANONICAL_GRAPH'
  ), full_receipts as (
    select
      r.ref,
      programacion.fn_input_resolve_source_ref(r.ref,v_pantalla_id,v_version_id) as full_receipt
    from refs r
  ), resolved as (
    select
      ref,
      jsonb_build_object(
        'schema_version','IG_SOURCE_RECEIPT_V1',
        'ref',ref,
        'authority',programacion.fn_input_source_authority_class(ref),
        'lifecycle',programacion.fn_input_source_lifecycle_receipt_v1(ref,full_receipt->'observed'),
        'observed_sha256',coalesce(
          nullif(full_receipt->>'observed_sha256',''),
          programacion.fn_v09_sha256_jsonb(full_receipt->'observed')
        ),
        'archive_contract',v_archive_contract
      ) as receipt
    from full_receipts
  ), all_receipts as (
    select ref::text sort_key,receipt from resolved
    union all
    select '{"kind":"SCREEN_CANONICAL_GRAPH"}'::text,v_graph_receipt
  )
  select coalesce(jsonb_agg(receipt order by sort_key),'[]'::jsonb)
    into v_manifest
  from all_receipts;

  if jsonb_array_length(v_manifest)=0 then
    raise exception 'SOURCE_MANIFEST_EMPTY:%',p_run_id;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_manifest) e(value)
    where e.value ? 'observed'
  ) then
    raise exception 'SOURCE_MANIFEST_FULL_OBSERVED_PAYLOAD_FORBIDDEN:%',p_run_id;
  end if;

  return v_manifest;
end;
$function$;

create or replace function programacion.fn_input_archive_source_observation_v1(
  p_run_id bigint,
  p_ref jsonb,
  p_source_execution_id text,
  p_ledger_execution_id text,
  p_source_head_sha text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public','programacion'
as $function$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_ref_sha text;
  v_full jsonb;
  v_observed jsonb;
  v_observed_sha text;
  v_authority jsonb;
  v_lifecycle jsonb;
  v_compact jsonb;
  v_authority_ref text;
  v_subject_ref text;
  v_provider_ref text;
  v_allowed boolean:=false;
begin
  if jsonb_typeof(p_ref)<>'object' or coalesce(p_ref->>'kind','')='' then
    raise exception 'INPUT_SOURCE_ARCHIVE_REF_INVALID';
  end if;

  select pantalla_id,version_id
    into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs
  where id=p_run_id;
  if v_pantalla_id is null then
    raise exception 'INPUT_SOURCE_ARCHIVE_RUN_NOT_FOUND:%',p_run_id;
  end if;

  if p_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
    v_allowed:=true;
    v_observed:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
    v_authority:=to_jsonb('CANONICAL_COMPOSITE_GRAPH'::text);
  else
    select exists(
      select 1
      from programacion.input_family_assessments a
      cross join lateral jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) e(value)
      where a.run_id=p_run_id and e.value=p_ref
    ) into v_allowed;
    if not v_allowed then
      raise exception 'INPUT_SOURCE_ARCHIVE_REF_NOT_BOUND_TO_RUN:%',p_run_id;
    end if;
    v_full:=programacion.fn_input_resolve_source_ref(p_ref,v_pantalla_id,v_version_id);
    v_observed:=v_full->'observed';
    v_authority:=to_jsonb(programacion.fn_input_source_authority_class(p_ref));
  end if;

  if not v_allowed or v_observed is null then
    raise exception 'INPUT_SOURCE_ARCHIVE_OBSERVED_UNRESOLVED:%',p_run_id;
  end if;

  v_observed_sha:=programacion.fn_v09_sha256_jsonb(v_observed);
  v_lifecycle:=programacion.fn_input_source_lifecycle_receipt_v1(p_ref,v_observed);
  v_ref_sha:=programacion.fn_v09_sha256_jsonb(p_ref);

  select cv.manifest#>>'{currentness,authority_ref}'
    into v_authority_ref
  from public.lf_capability_current cc
  join public.lf_capability_version_registry cv
    on cv.capability_code=cc.capability_code and cv.version=cc.version
  where cc.capability_code='SOURCE_RESOLUTION_POLICY';
  if v_authority_ref is null then
    raise exception 'INPUT_SOURCE_ARCHIVE_SOURCE_RESOLUTION_AUTHORITY_NOT_CURRENT';
  end if;

  v_subject_ref:=format('supabase://programacion/input_readiness_runs/%s/source/%s',p_run_id,v_ref_sha);
  v_provider_ref:=format('supabase://programacion/input_readiness_runs/%s',p_run_id);
  v_compact:=jsonb_build_object(
    'schema_version','IG_SOURCE_RECEIPT_V1',
    'ref',p_ref,
    'authority',v_authority,
    'lifecycle',v_lifecycle,
    'observed_sha256',v_observed_sha,
    'archive_role','OBSERVED_PAYLOAD_OUTSIDE_SOURCE_MANIFEST'
  );

  return public.fn_lf_evidence_ledger_anchor_v1(
    p_source_execution_id,
    'SOURCE_RESOLUTION_POLICY',
    'IG_SOURCE_OBSERVATION_ARCHIVE',
    'SOURCE_OBSERVATION',
    'IG_SOURCE_OBSERVATION_V1',
    v_subject_ref,
    v_observed_sha,
    p_source_head_sha,
    v_authority_ref,
    'LF_SUPABASE_READBACK_V1',
    'SUPABASE',
    v_provider_ref,
    'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,
      'digest_recomputed',true,
      'source_ref',p_ref,
      'observed',v_observed,
      'observed_sha256',v_observed_sha,
      'lifecycle',v_lifecycle,
      'implementation_head_sha',p_source_head_sha
    ),
    v_compact,
    p_ledger_execution_id
  );
end;
$function$;

comment on function programacion.fn_input_source_manifest_identity_v1(jsonb) is
  'M6.1 logical source-manifest identity: ref + authority + observed_sha256; format-only full/compact differences do not stale historical runs.';
comment on function programacion.fn_input_source_lifecycle_receipt_v1(jsonb,jsonb) is
  'M6.1 compact lifecycle projection reusing POL-LF-STATE-MODEL and fn_source_rule_authority; creates no private lifecycle model.';
comment on function programacion.fn_input_archive_source_observation_v1(bigint,jsonb,text,text,text) is
  'M6.1 governed archive adapter: full observed payload goes only to EVIDENCE_LEDGER verification_payload using SOURCE_RESOLUTION_POLICY producer execution; fails closed without valid orchestrator-bound executions.';
comment on function programacion.fn_input_build_source_manifest(bigint) is
  'M6.1 compact source manifest: IG_SOURCE_RECEIPT_V1 entries contain ref + authority + lifecycle + observed_sha256 + archive contract; full observed payload forbidden.';

-- Backward-compatible currentness: compare stable logical source identity, not
-- historical transport shape. Real source changes still change observed_sha256.
do $patch_currentness$
declare
  v_reg regprocedure:='programacion.fn_input_run_source_currentness_v1(bigint)'::regprocedure;
  v_def text;
  v_next text;
  v_expected_md5 text:='2b32089f2d2d1a0a8f8b894f66fe370b';
  v_decl_old text:=$decl_old$
  v_current_sha text;
  v_lifecycle_ok boolean:=false;
$decl_old$;
  v_decl_new text:=$decl_new$
  v_current_sha text;
  v_stored_identity_sha text;
  v_lifecycle_ok boolean:=false;
$decl_new$;
  v_compare_old text:=$compare_old$
  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  v_manifest_ok := v_current_sha=v_run.source_snapshot_sha256
                   AND v_current_manifest=v_run.source_manifest;
$compare_old$;
  v_compare_new text:=$compare_new$
  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(
    programacion.fn_input_source_manifest_identity_v1(v_current_manifest)
  );
  v_stored_identity_sha:=programacion.fn_v09_sha256_jsonb(
    programacion.fn_input_source_manifest_identity_v1(v_run.source_manifest)
  );
  v_manifest_ok := v_current_sha=v_stored_identity_sha;
$compare_new$;
  v_return_old text:=$return_old$
        'current_sha256',v_current_sha,
        'stored_sha256',v_run.source_snapshot_sha256
$return_old$;
  v_return_new text:=$return_new$
        'current_sha256',v_current_sha,
        'stored_sha256',v_stored_identity_sha,
        'stored_snapshot_sha256',v_run.source_snapshot_sha256,
        'comparison_contract','IG_SOURCE_MANIFEST_IDENTITY_V1'
$return_new$;
begin
  v_def:=pg_get_functiondef(v_reg);
  if md5(v_def)<>v_expected_md5 then
    raise exception 'M6_1_CURRENTNESS_BASELINE_DRIFT expected=% actual=%',v_expected_md5,md5(v_def);
  end if;
  v_next:=replace(v_def,v_decl_old,v_decl_new);
  if v_next=v_def then raise exception 'M6_1_CURRENTNESS_DECL_ANCHOR_NOT_FOUND'; end if;
  v_def:=v_next;
  v_next:=replace(v_def,v_compare_old,v_compare_new);
  if v_next=v_def then raise exception 'M6_1_CURRENTNESS_COMPARE_ANCHOR_NOT_FOUND'; end if;
  v_def:=v_next;
  v_next:=replace(v_def,v_return_old,v_return_new);
  if v_next=v_def then raise exception 'M6_1_CURRENTNESS_RETURN_ANCHOR_NOT_FOUND'; end if;
  execute v_next;
end;
$patch_currentness$;

-- Deterministic candidate checks. Runs 373/374 were source-current immediately
-- before M6.1 and therefore prove old full manifests remain logically current.
do $verify$
declare
  v_run_id bigint;
  v_old jsonb;
  v_new jsonb;
  v_old_bytes integer;
  v_new_bytes integer;
  v_ref jsonb;
  v_blocked boolean:=false;
begin
  foreach v_run_id in array array[373::bigint,374::bigint]
  loop
    select source_manifest,pg_column_size(source_manifest)
      into v_old,v_old_bytes
    from programacion.input_readiness_runs where id=v_run_id;
    if v_old is null then raise exception 'M6_1_COMPAT_RUN_MISSING:%',v_run_id; end if;

    v_new:=programacion.fn_input_build_source_manifest(v_run_id);
    v_new_bytes:=pg_column_size(v_new);
    if exists(select 1 from jsonb_array_elements(v_new) e(value) where e.value?'observed') then
      raise exception 'M6_1_FULL_PAYLOAD_REMAINS:%',v_run_id;
    end if;
    if programacion.fn_input_source_manifest_identity_v1(v_old)
       is distinct from programacion.fn_input_source_manifest_identity_v1(v_new) then
      raise exception 'M6_1_LOGICAL_IDENTITY_DRIFT:%',v_run_id;
    end if;
    if v_new_bytes>=v_old_bytes then
      raise exception 'M6_1_MANIFEST_NOT_SMALLER run=% old=% new=%',v_run_id,v_old_bytes,v_new_bytes;
    end if;
    if coalesce((programacion.fn_input_run_source_currentness_v1(v_run_id)->>'source_current')::boolean,false) is not true then
      raise exception 'M6_1_HISTORICAL_CURRENTNESS_REGRESSION:%',v_run_id;
    end if;
  end loop;

  select e.value into v_ref
  from programacion.input_family_assessments a
  cross join lateral jsonb_array_elements(a.source_refs) e(value)
  where a.run_id=373 and e.value->>'kind'<>'SCREEN_CANONICAL_GRAPH'
  limit 1;
  if v_ref is null then raise exception 'M6_1_ARCHIVE_NEGATIVE_REF_MISSING'; end if;

  begin
    perform programacion.fn_input_archive_source_observation_v1(
      373,v_ref,'M6-1-NO-SOURCE-EXEC','M6-1-NO-LEDGER-EXEC','0814f8188de110a8c05469194a8e12bcc4d24b54'
    );
  exception when others then
    if sqlerrm like 'BLOCK_LF_EVIDENCE_LEDGER_EXECUTION_INVALID%' then
      v_blocked:=true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'M6_1_ARCHIVE_FAIL_CLOSED_NEGATIVE_DID_NOT_BLOCK';
  end if;
end;
$verify$;
