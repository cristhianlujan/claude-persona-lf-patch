-- P0 visual execution persistence v1.
-- Private, append-only storage for a reconstructable execution graph.

create table private.lf_p0_execution_runs_v1 (
  execution_id text primary key,
  started_at timestamptz not null,
  completed_at timestamptz,
  terminal_state text not null check (terminal_state in ('COMPLETE', 'BLOCKED', 'FAILED')),
  verdict text not null check (verdict in ('PASS', 'BLOCKED', 'FAIL')),
  source_ref text not null,
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  source_width integer not null check (source_width > 0),
  source_height integer not null check (source_height > 0),
  source_mime_type text not null check (source_mime_type like 'image/%'),
  code_head_sha text not null check (code_head_sha ~ '^[0-9a-f]{40}$'),
  loop_version text not null,
  configuration_id text not null,
  configuration_sha256 text not null check (configuration_sha256 ~ '^[0-9a-f]{64}$'),
  languages jsonb not null check (jsonb_typeof(languages) = 'array' and jsonb_array_length(languages) > 0),
  dependencies jsonb not null check (jsonb_typeof(dependencies) = 'object'),
  acceptance_declared boolean not null default false check (acceptance_declared = false),
  autonomous_system_ready boolean not null default false check (autonomous_system_ready = false),
  p0_5_authorized boolean not null default false check (p0_5_authorized = false),
  production_authorized boolean not null default false check (production_authorized = false),
  unresolved_critical integer not null default 0 check (unresolved_critical >= 0),
  unresolved_high integer not null default 0 check (unresolved_high >= 0),
  unresolved_medium integer not null default 0 check (unresolved_medium >= 0),
  mutation_escapes integer not null default 0 check (mutation_escapes >= 0),
  request_fingerprint_sha256 text not null check (request_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  check (completed_at is null or completed_at >= started_at),
  check (verdict <> 'PASS' or (terminal_state = 'COMPLETE' and completed_at is not null and unresolved_critical = 0 and unresolved_high = 0 and unresolved_medium = 0 and mutation_escapes = 0))
);

create table private.lf_p0_execution_elements_v1 (
  execution_id text not null references private.lf_p0_execution_runs_v1(execution_id) on delete restrict,
  element_id text not null,
  parent_element_id text,
  element_type text not null,
  visible_text text,
  bbox jsonb not null check (jsonb_typeof(bbox) = 'object' and bbox ?& array['x','y','width','height'] and (bbox->>'x')::integer >= 0 and (bbox->>'y')::integer >= 0 and (bbox->>'width')::integer > 0 and (bbox->>'height')::integer > 0),
  cardinality integer not null default 1 check (cardinality > 0),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  modality text not null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (execution_id, element_id),
  foreign key (execution_id, parent_element_id) references private.lf_p0_execution_elements_v1(execution_id, element_id) deferrable initially deferred
);

create table private.lf_p0_execution_evidence_units_v1 (
  execution_id text not null references private.lf_p0_execution_runs_v1(execution_id) on delete restrict,
  evidence_unit_id text not null,
  evidence_kind text not null,
  evidence_ref text not null,
  content_sha256 text check (content_sha256 is null or content_sha256 ~ '^[0-9a-f]{64}$'),
  bbox jsonb check (bbox is null or jsonb_typeof(bbox) = 'object'),
  modality text not null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (execution_id, evidence_unit_id),
  unique (execution_id, evidence_ref)
);

create table private.lf_p0_execution_element_evidence_v1 (
  execution_id text not null,
  element_id text not null,
  evidence_unit_id text not null,
  relationship text not null check (relationship in ('SUPPORTS','BOUNDARY','CONTROL','ICON','TEXT_TOKEN')),
  created_at timestamptz not null default clock_timestamp(),
  primary key (execution_id, evidence_unit_id),
  foreign key (execution_id, element_id) references private.lf_p0_execution_elements_v1(execution_id, element_id) on delete restrict,
  foreign key (execution_id, evidence_unit_id) references private.lf_p0_execution_evidence_units_v1(execution_id, evidence_unit_id) on delete restrict
);

create table private.lf_p0_execution_records_v1 (
  execution_id text not null references private.lf_p0_execution_runs_v1(execution_id) on delete restrict,
  record_kind text not null check (record_kind in ('RULE','VALIDATION','OMISSION','CONTAMINATION','RESIDUAL','EXCEPTION','PASS_RESULT')),
  record_id text not null,
  stage text not null,
  rule_version text,
  severity text check (severity is null or severity in ('CRITICAL','HIGH','MEDIUM','LOW','INFO')),
  status text not null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (execution_id, record_kind, record_id)
);

create table private.lf_p0_execution_artifacts_v1 (
  execution_id text not null references private.lf_p0_execution_runs_v1(execution_id) on delete restrict,
  artifact_id text not null,
  artifact_role text not null check (artifact_role in ('RECEIPT','MANIFEST','SOURCE','CONFIGURATION','BENCHMARK','AUDIT','EXTERNAL_PACKET')),
  artifact_ref text not null,
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  content_bytes bigint check (content_bytes is null or content_bytes > 0),
  external_evidence_ref text references private.lf_p0_external_durable_evidence_v1(external_evidence_ref) on delete restrict,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (execution_id, artifact_id),
  unique (execution_id, artifact_role, content_sha256)
);

create table private.lf_p0_execution_transitions_v1 (
  execution_id text not null references private.lf_p0_execution_runs_v1(execution_id) on delete restrict,
  transition_ordinal integer not null check (transition_ordinal >= 0),
  from_state text,
  to_state text not null,
  occurred_at timestamptz not null,
  reason text not null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (execution_id, transition_ordinal)
);

create table private.lf_p0_execution_persist_attempts_v1 (
  attempt_id uuid primary key default gen_random_uuid(),
  execution_id text not null references private.lf_p0_execution_runs_v1(execution_id) on delete restrict,
  request_fingerprint_sha256 text not null check (request_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
  outcome text not null check (outcome in ('INSERTED','IDEMPOTENT_REPLAY')),
  attempted_at timestamptz not null default clock_timestamp()
);

create table private.lf_p0_invalidated_loop_versions_v1 (
  loop_version text primary key,
  invalidated_at timestamptz not null,
  reason text not null,
  source_ref text not null,
  created_at timestamptz not null default clock_timestamp()
);

insert into private.lf_p0_invalidated_loop_versions_v1(loop_version, invalidated_at, reason, source_ref) values
('p0-v4-r2-pre-atomicity','2026-08-12T00:00:00Z'::timestamptz,'Sibling contamination, unjustified fragmentation and zero-assignment visual omissions invalidate prior PASS results.','sandbox/story_creator_p0_visual/v1.1/evals/p0-closed-loop-runtime-config-v4.json'),
('unversioned-pr137-head-f51ddc0c9b0f854bec4dc9fa68672e2a7ac5d022','2026-08-12T00:00:00Z'::timestamptz,'Sibling contamination, unjustified fragmentation and zero-assignment visual omissions invalidate prior PASS results.','sandbox/story_creator_p0_visual/v1.1/evals/p0-closed-loop-runtime-config-v4.json');

create or replace function private.fn_lf_p0_forbid_mutation_v1()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '55000', message = 'LF_P0_APPEND_ONLY_MUTATION_FORBIDDEN';
end;
$$;

do $append_only$
declare relation_name text;
begin
  foreach relation_name in array array['lf_p0_execution_runs_v1','lf_p0_execution_elements_v1','lf_p0_execution_evidence_units_v1','lf_p0_execution_element_evidence_v1','lf_p0_execution_records_v1','lf_p0_execution_artifacts_v1','lf_p0_execution_transitions_v1','lf_p0_execution_persist_attempts_v1','lf_p0_invalidated_loop_versions_v1']
  loop
    execute format('create trigger %I before update or delete on private.%I for each row execute function private.fn_lf_p0_forbid_mutation_v1()', relation_name || '_append_only', relation_name);
    execute format('alter table private.%I enable row level security', relation_name);
    execute format('revoke all on private.%I from public, anon, authenticated', relation_name);
  end loop;
end;
$append_only$;

create or replace function private.fn_persist_lf_p0_execution_v1(p_bundle jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_execution jsonb; v_execution_id text; v_fingerprint text; v_existing text; v_item jsonb;
begin
  if p_bundle is null or jsonb_typeof(p_bundle) <> 'object' then raise exception using errcode='22023', message='LF_P0_BUNDLE_OBJECT_REQUIRED'; end if;
  v_execution := p_bundle->'execution';
  if jsonb_typeof(v_execution) <> 'object' then raise exception using errcode='22023', message='LF_P0_EXECUTION_OBJECT_REQUIRED'; end if;
  v_execution_id := v_execution->>'execution_id';
  if v_execution_id is null or v_execution_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$' then raise exception using errcode='22023', message='LF_P0_EXECUTION_ID_INVALID'; end if;
  if jsonb_typeof(p_bundle->'elements') <> 'array' or jsonb_typeof(p_bundle->'evidence_units') <> 'array' or jsonb_typeof(p_bundle->'element_evidence') <> 'array' or jsonb_typeof(p_bundle->'records') <> 'array' or jsonb_typeof(p_bundle->'artifacts') <> 'array' or jsonb_typeof(p_bundle->'transitions') <> 'array' or jsonb_array_length(p_bundle->'elements')=0 or jsonb_array_length(p_bundle->'records')=0 or jsonb_array_length(p_bundle->'artifacts')=0 or jsonb_array_length(p_bundle->'transitions')=0 then raise exception using errcode='22023', message='LF_P0_COMPLETE_GRAPH_REQUIRED'; end if;
  v_fingerprint := encode(extensions.digest(pg_catalog.convert_to(p_bundle::text,'UTF8'),'sha256'),'hex');
  select request_fingerprint_sha256 into v_existing from private.lf_p0_execution_runs_v1 where execution_id=v_execution_id;
  if found then
    if v_existing <> v_fingerprint then raise exception using errcode='23505', message='LF_P0_EXECUTION_ID_CONFLICT'; end if;
    insert into private.lf_p0_execution_persist_attempts_v1(execution_id,request_fingerprint_sha256,outcome) values(v_execution_id,v_fingerprint,'IDEMPOTENT_REPLAY');
    return jsonb_build_object('execution_id',v_execution_id,'outcome','IDEMPOTENT_REPLAY','request_fingerprint_sha256',v_fingerprint);
  end if;
  if (v_execution->>'verdict')='PASS' and exists(select 1 from private.lf_p0_invalidated_loop_versions_v1 where loop_version=v_execution->>'loop_version') then raise exception using errcode='23514', message='LF_P0_INVALIDATED_LOOP_CANNOT_PASS'; end if;
  insert into private.lf_p0_execution_runs_v1(execution_id,started_at,completed_at,terminal_state,verdict,source_ref,source_sha256,source_width,source_height,source_mime_type,code_head_sha,loop_version,configuration_id,configuration_sha256,languages,dependencies,acceptance_declared,autonomous_system_ready,p0_5_authorized,production_authorized,unresolved_critical,unresolved_high,unresolved_medium,mutation_escapes,request_fingerprint_sha256)
  values(v_execution_id,(v_execution->>'started_at')::timestamptz,nullif(v_execution->>'completed_at','')::timestamptz,v_execution->>'terminal_state',v_execution->>'verdict',v_execution->>'source_ref',v_execution->>'source_sha256',(v_execution->>'source_width')::integer,(v_execution->>'source_height')::integer,v_execution->>'source_mime_type',v_execution->>'code_head_sha',v_execution->>'loop_version',v_execution->>'configuration_id',v_execution->>'configuration_sha256',v_execution->'languages',v_execution->'dependencies',coalesce((v_execution->>'acceptance_declared')::boolean,false),coalesce((v_execution->>'autonomous_system_ready')::boolean,false),coalesce((v_execution->>'p0_5_authorized')::boolean,false),coalesce((v_execution->>'production_authorized')::boolean,false),coalesce((v_execution->>'unresolved_critical')::integer,0),coalesce((v_execution->>'unresolved_high')::integer,0),coalesce((v_execution->>'unresolved_medium')::integer,0),coalesce((v_execution->>'mutation_escapes')::integer,0),v_fingerprint);
  for v_item in select value from jsonb_array_elements(p_bundle->'elements') loop insert into private.lf_p0_execution_elements_v1(execution_id,element_id,parent_element_id,element_type,visible_text,bbox,cardinality,confidence,modality,payload) values(v_execution_id,v_item->>'element_id',nullif(v_item->>'parent_element_id',''),v_item->>'element_type',v_item->>'visible_text',v_item->'bbox',coalesce((v_item->>'cardinality')::integer,1),nullif(v_item->>'confidence','')::numeric,v_item->>'modality',coalesce(v_item->'payload','{}'::jsonb)); end loop;
  for v_item in select value from jsonb_array_elements(p_bundle->'evidence_units') loop insert into private.lf_p0_execution_evidence_units_v1(execution_id,evidence_unit_id,evidence_kind,evidence_ref,content_sha256,bbox,modality,payload) values(v_execution_id,v_item->>'evidence_unit_id',v_item->>'evidence_kind',v_item->>'evidence_ref',nullif(v_item->>'content_sha256',''),v_item->'bbox',v_item->>'modality',coalesce(v_item->'payload','{}'::jsonb)); end loop;
  for v_item in select value from jsonb_array_elements(p_bundle->'element_evidence') loop insert into private.lf_p0_execution_element_evidence_v1(execution_id,element_id,evidence_unit_id,relationship) values(v_execution_id,v_item->>'element_id',v_item->>'evidence_unit_id',v_item->>'relationship'); end loop;
  for v_item in select value from jsonb_array_elements(p_bundle->'records') loop insert into private.lf_p0_execution_records_v1(execution_id,record_kind,record_id,stage,rule_version,severity,status,payload) values(v_execution_id,v_item->>'record_kind',v_item->>'record_id',v_item->>'stage',nullif(v_item->>'rule_version',''),nullif(v_item->>'severity',''),v_item->>'status',coalesce(v_item->'payload','{}'::jsonb)); end loop;
  for v_item in select value from jsonb_array_elements(p_bundle->'artifacts') loop insert into private.lf_p0_execution_artifacts_v1(execution_id,artifact_id,artifact_role,artifact_ref,content_sha256,content_bytes,external_evidence_ref,payload) values(v_execution_id,v_item->>'artifact_id',v_item->>'artifact_role',v_item->>'artifact_ref',v_item->>'content_sha256',nullif(v_item->>'content_bytes','')::bigint,nullif(v_item->>'external_evidence_ref',''),coalesce(v_item->'payload','{}'::jsonb)); end loop;
  for v_item in select value from jsonb_array_elements(p_bundle->'transitions') loop insert into private.lf_p0_execution_transitions_v1(execution_id,transition_ordinal,from_state,to_state,occurred_at,reason,payload) values(v_execution_id,(v_item->>'transition_ordinal')::integer,nullif(v_item->>'from_state',''),v_item->>'to_state',(v_item->>'occurred_at')::timestamptz,v_item->>'reason',coalesce(v_item->'payload','{}'::jsonb)); end loop;
  if not exists(select 1 from private.lf_p0_execution_records_v1 where execution_id=v_execution_id and record_kind='RULE') or not exists(select 1 from private.lf_p0_execution_records_v1 where execution_id=v_execution_id and record_kind='VALIDATION') or not exists(select 1 from private.lf_p0_execution_records_v1 where execution_id=v_execution_id and record_kind='PASS_RESULT') then raise exception using errcode='23514', message='LF_P0_RULE_VALIDATION_PASS_RECORDS_REQUIRED'; end if;
  if exists(select 1 from private.lf_p0_execution_evidence_units_v1 u where u.execution_id=v_execution_id and not exists(select 1 from private.lf_p0_execution_element_evidence_v1 l where l.execution_id=u.execution_id and l.evidence_unit_id=u.evidence_unit_id)) then raise exception using errcode='23514', message='LF_P0_ORPHAN_EVIDENCE_UNIT'; end if;
  insert into private.lf_p0_execution_persist_attempts_v1(execution_id,request_fingerprint_sha256,outcome) values(v_execution_id,v_fingerprint,'INSERTED');
  return jsonb_build_object('execution_id',v_execution_id,'outcome','INSERTED','request_fingerprint_sha256',v_fingerprint);
end;
$$;

create or replace function private.fn_reconstruct_lf_p0_execution_v1(p_execution_id text)
returns jsonb language sql stable security definer set search_path = '' as $$
select case when r.execution_id is null then null else jsonb_build_object(
  'execution',to_jsonb(r)-'request_fingerprint_sha256',
  'request_fingerprint_sha256',r.request_fingerprint_sha256,
  'elements',coalesce((select jsonb_agg(to_jsonb(e)-'execution_id' order by e.element_id) from private.lf_p0_execution_elements_v1 e where e.execution_id=r.execution_id),'[]'::jsonb),
  'evidence_units',coalesce((select jsonb_agg(to_jsonb(u)-'execution_id' order by u.evidence_unit_id) from private.lf_p0_execution_evidence_units_v1 u where u.execution_id=r.execution_id),'[]'::jsonb),
  'element_evidence',coalesce((select jsonb_agg(to_jsonb(l)-'execution_id' order by l.evidence_unit_id) from private.lf_p0_execution_element_evidence_v1 l where l.execution_id=r.execution_id),'[]'::jsonb),
  'records',coalesce((select jsonb_agg(to_jsonb(v)-'execution_id' order by v.record_kind,v.record_id) from private.lf_p0_execution_records_v1 v where v.execution_id=r.execution_id),'[]'::jsonb),
  'artifacts',coalesce((select jsonb_agg(to_jsonb(a)-'execution_id' order by a.artifact_id) from private.lf_p0_execution_artifacts_v1 a where a.execution_id=r.execution_id),'[]'::jsonb),
  'transitions',coalesce((select jsonb_agg(to_jsonb(t)-'execution_id' order by t.transition_ordinal) from private.lf_p0_execution_transitions_v1 t where t.execution_id=r.execution_id),'[]'::jsonb),
  'persist_attempts',coalesce((select jsonb_agg(to_jsonb(p) order by p.attempted_at,p.attempt_id) from private.lf_p0_execution_persist_attempts_v1 p where p.execution_id=r.execution_id),'[]'::jsonb)
) end from (select * from private.lf_p0_execution_runs_v1 where execution_id=p_execution_id) r;
$$;

revoke all on function private.fn_lf_p0_forbid_mutation_v1() from public, anon, authenticated;
revoke all on function private.fn_persist_lf_p0_execution_v1(jsonb) from public, anon, authenticated;
revoke all on function private.fn_reconstruct_lf_p0_execution_v1(text) from public, anon, authenticated;
grant execute on function private.fn_persist_lf_p0_execution_v1(jsonb) to service_role;
grant execute on function private.fn_reconstruct_lf_p0_execution_v1(text) to service_role;

comment on function private.fn_persist_lf_p0_execution_v1(jsonb) is 'Atomically persists one immutable P0 execution graph; identical retries are idempotent and conflicting retries fail.';
comment on function private.fn_reconstruct_lf_p0_execution_v1(text) is 'Reconstructs the normalized P0 execution graph by execution_id without exposing private tables.';
