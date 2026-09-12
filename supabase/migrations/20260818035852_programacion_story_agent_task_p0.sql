-- P0 Story/Spec -> Agent Task preparation bridge.
-- Scope: planning/preparation only. Existing Worker, Human Review, Context Pack and EKB remain unchanged.

create table public.lf_functional_versions (
  id bigint generated always as identity primary key,
  artifact_code text not null,
  artifact_type text not null check (artifact_type in ('STORY_SPEC','CANONICAL_SPEC','STORY')),
  story_code text null references public.lf_user_stories(story_code) on update restrict on delete restrict,
  parent_spec_version_id bigint null references public.lf_functional_versions(id) on update restrict on delete restrict,
  version_no integer not null check (version_no > 0),
  objective text not null,
  acceptance_criteria jsonb not null,
  invariants jsonb not null,
  negative_controls jsonb not null,
  source_rule_codes text[] not null,
  supersedes_version_id bigint null references public.lf_functional_versions(id) on update restrict on delete restrict,
  amendment_reason_code text null,
  amendment_ref text null,
  status text not null default 'DRAFT' check (status in ('DRAFT','SEALED')),
  content_sha256 text null,
  sealed_at timestamptz null,
  created_by_execution_id text not null,
  created_at timestamptz not null default now(),
  unique (artifact_code, version_no)
);

create table programacion.agent_tasks (
  id bigint generated always as identity primary key,
  task_code text not null,
  task_version integer not null check (task_version > 0),
  functional_version_id bigint not null references public.lf_functional_versions(id) on update restrict on delete restrict,
  supersedes_task_id bigint null references programacion.agent_tasks(id) on update restrict on delete restrict,
  objective text not null,
  acceptance_refs text[] not null,
  invariant_refs text[] not null,
  negative_refs text[] not null,
  context_path_patterns text[] not null,
  write_path_patterns text[] not null,
  protected_path_patterns text[] not null,
  files_expected text[] not null,
  platform_refs text[] not null default '{}',
  interface_refs text[] not null default '{}',
  unknown_refs text[] not null default '{}',
  max_attempts integer not null default 3 check (max_attempts between 1 and 5),
  max_patch_bytes integer not null default 500000 check (max_patch_bytes between 1 and 1000000),
  max_changed_files integer not null default 25 check (max_changed_files between 1 and 100),
  max_context_bytes integer not null default 500000 check (max_context_bytes between 1024 and 2000000),
  allow_deletions boolean not null default false,
  definition_status text not null default 'DRAFT' check (definition_status in ('DRAFT','SEALED')),
  task_sha256 text null,
  sealed_at timestamptz null,
  created_at timestamptz not null default now(),
  unique (task_code, task_version)
);

create table programacion.task_dependencies (
  id bigint generated always as identity primary key,
  task_id bigint not null references programacion.agent_tasks(id) on update restrict on delete restrict,
  depends_on_task_id bigint not null references programacion.agent_tasks(id) on update restrict on delete restrict,
  relation_type text not null default 'REQUIRES' check (relation_type = 'REQUIRES'),
  created_at timestamptz not null default now(),
  check (task_id <> depends_on_task_id),
  unique (task_id, depends_on_task_id)
);

create table programacion.task_blockers (
  id bigint generated always as identity primary key,
  task_id bigint not null references programacion.agent_tasks(id) on update restrict on delete restrict,
  blocker_code text not null,
  owner_type text not null,
  owner_ref text null,
  required_action text not null,
  source_ref text not null,
  status text not null default 'OPEN' check (status in ('OPEN','RESOLVED')),
  opened_at timestamptz not null default now(),
  resolved_at timestamptz null,
  resolved_by text null,
  resolution_ref text null,
  unique (task_id, blocker_code, source_ref)
);

create table programacion.test_contracts (
  id bigint generated always as identity primary key,
  task_id bigint not null unique references programacion.agent_tasks(id) on update restrict on delete restrict,
  contract_version integer not null check (contract_version > 0),
  supersedes_contract_id bigint null references programacion.test_contracts(id) on update restrict on delete restrict,
  suite_code text null references public.lf_test_suites(suite_code) on update restrict on delete restrict,
  visible_commands jsonb not null,
  hidden_oracle_ref text not null,
  hidden_oracle_sha256 text not null,
  generator_identity text not null,
  generator_channel text not null,
  criteria_snapshot jsonb not null default '{}'::jsonb,
  amendment_reason_code text null,
  amendment_ref text null,
  status text not null default 'DRAFT' check (status in ('DRAFT','SEALED')),
  contract_sha256 text null,
  sealed_at timestamptz null,
  created_at timestamptz not null default now()
);

create index idx_lf_functional_versions_story on public.lf_functional_versions(story_code, version_no desc);
create index idx_agent_tasks_functional on programacion.agent_tasks(functional_version_id, task_code, task_version desc);
create index idx_task_dependencies_dep on programacion.task_dependencies(depends_on_task_id);
create index idx_task_blockers_open on programacion.task_blockers(task_id) where status='OPEN';

alter table public.lf_functional_versions enable row level security;
alter table public.lf_functional_versions force row level security;
alter table programacion.agent_tasks enable row level security;
alter table programacion.agent_tasks force row level security;
alter table programacion.task_dependencies enable row level security;
alter table programacion.task_dependencies force row level security;
alter table programacion.task_blockers enable row level security;
alter table programacion.task_blockers force row level security;
alter table programacion.test_contracts enable row level security;
alter table programacion.test_contracts force row level security;

revoke all on public.lf_functional_versions from public, anon, authenticated;
revoke all on programacion.agent_tasks from public, anon, authenticated;
revoke all on programacion.task_dependencies from public, anon, authenticated;
revoke all on programacion.task_blockers from public, anon, authenticated;
revoke all on programacion.test_contracts from public, anon, authenticated;

grant select, insert, update on public.lf_functional_versions to service_role;
grant select, insert, update on public.lf_functional_versions to programacion_human_authority;
grant select on public.lf_functional_versions to programacion_builder, programacion_auditor, programacion_verifier;
grant usage, select on sequence public.lf_functional_versions_id_seq to service_role, programacion_human_authority;

grant select, insert, update on programacion.agent_tasks to programacion_builder;
grant select on programacion.agent_tasks to programacion_auditor, programacion_human_authority, programacion_verifier;
grant usage, select on sequence programacion.agent_tasks_id_seq to programacion_builder;

grant select, insert, delete on programacion.task_dependencies to programacion_builder;
grant select on programacion.task_dependencies to programacion_auditor, programacion_human_authority, programacion_verifier;
grant usage, select on sequence programacion.task_dependencies_id_seq to programacion_builder;

grant select, insert, update on programacion.task_blockers to programacion_builder, programacion_human_authority;
grant select on programacion.task_blockers to programacion_auditor, programacion_verifier;
grant usage, select on sequence programacion.task_blockers_id_seq to programacion_builder, programacion_human_authority;

grant select on programacion.test_contracts to programacion_builder, programacion_auditor, programacion_human_authority;
grant select, insert, update on programacion.test_contracts to programacion_verifier;
grant usage, select on sequence programacion.test_contracts_id_seq to programacion_verifier;

create policy p_functional_versions_service on public.lf_functional_versions
  for all to service_role using (true) with check (true);
create policy p_functional_versions_runtime_read on public.lf_functional_versions
  for select to programacion_human_authority, programacion_builder, programacion_auditor, programacion_verifier using (true);
create policy p_functional_versions_human_insert on public.lf_functional_versions
  for insert to programacion_human_authority with check (true);
create policy p_functional_versions_human_update on public.lf_functional_versions
  for update to programacion_human_authority using (true) with check (true);

create policy p_agent_tasks_builder_read on programacion.agent_tasks
  for select to programacion_builder, programacion_auditor, programacion_human_authority, programacion_verifier using (true);
create policy p_agent_tasks_builder_insert on programacion.agent_tasks
  for insert to programacion_builder with check (true);
create policy p_agent_tasks_builder_update on programacion.agent_tasks
  for update to programacion_builder using (true) with check (true);

create policy p_task_dependencies_read on programacion.task_dependencies
  for select to programacion_builder, programacion_auditor, programacion_human_authority, programacion_verifier using (true);
create policy p_task_dependencies_insert on programacion.task_dependencies
  for insert to programacion_builder with check (true);
create policy p_task_dependencies_delete on programacion.task_dependencies
  for delete to programacion_builder using (true);

create policy p_task_blockers_read on programacion.task_blockers
  for select to programacion_builder, programacion_auditor, programacion_human_authority, programacion_verifier using (true);
create policy p_task_blockers_insert on programacion.task_blockers
  for insert to programacion_builder, programacion_human_authority with check (true);
create policy p_task_blockers_update on programacion.task_blockers
  for update to programacion_builder, programacion_human_authority using (true) with check (true);

create policy p_test_contracts_read on programacion.test_contracts
  for select to programacion_builder, programacion_auditor, programacion_human_authority, programacion_verifier using (true);
create policy p_test_contracts_verifier_insert on programacion.test_contracts
  for insert to programacion_verifier with check (true);
create policy p_test_contracts_verifier_update on programacion.test_contracts
  for update to programacion_verifier using (true) with check (true);

create or replace function programacion.fn_p0_array_is_canonical(p_arr text[], p_allow_empty boolean default false)
returns boolean language sql immutable set search_path = pg_catalog as $$
  select p_arr is not null
     and (p_allow_empty or cardinality(p_arr) > 0)
     and not exists (select 1 from unnest(p_arr) as u(v) where v is null or btrim(v)='')
     and p_arr = coalesce((select array_agg(v order by v) from (select distinct v from unnest(p_arr) as u(v)) s), '{}'::text[])
$$;

create or replace function programacion.fn_p0_path_array_is_canonical(p_arr text[], p_allow_empty boolean default false)
returns boolean language plpgsql immutable set search_path = pg_catalog, programacion as $$
declare v text;
begin
  if not programacion.fn_p0_array_is_canonical(p_arr, p_allow_empty) then return false; end if;
  foreach v in array p_arr loop
    if v ~ '[\\[:cntrl:]\[\]{}]' or v ~ '^/' or v ~ '(^|/)\.\.(/|$)' or v ~ '(^|/)\.git(/|$)' then return false; end if;
    if v ~ '\*\*' and exists (select 1 from unnest(string_to_array(v,'/')) seg where position('**' in seg)>0 and seg <> '**') then return false; end if;
  end loop;
  return true;
end; $$;

create or replace function programacion.fn_p0_json_codes(p_doc jsonb, p_prefix text)
returns text[] language sql immutable set search_path = pg_catalog as $$
  select coalesce(array_agg(code order by code), '{}'::text[])
  from (select distinct e->>'code' code from jsonb_array_elements(p_doc) e where jsonb_typeof(e)='object' and e ? 'code' and e->>'code' ~ ('^' || p_prefix || '-[A-Za-z0-9._-]+$')) s
$$;

create or replace function programacion.fn_guard_functional_version()
returns trigger language plpgsql set search_path = pg_catalog, public, programacion as $$
declare v_payload jsonb; v_digest text; v_parent public.lf_functional_versions%rowtype; v_sup public.lf_functional_versions%rowtype; v_codes text[];
begin
  if tg_op='DELETE' then raise exception 'functional versions are append-only'; end if;
  if tg_op='UPDATE' and old.status='SEALED' then raise exception 'sealed functional version % is immutable; create a superseding version', old.id; end if;
  if tg_op='INSERT' and new.status <> 'DRAFT' then raise exception 'functional version must be born DRAFT'; end if;
  if length(btrim(new.artifact_code))=0 or length(btrim(new.objective))=0 or length(btrim(new.created_by_execution_id))=0 then raise exception 'artifact_code, objective, created_by_execution_id required'; end if;
  if jsonb_typeof(new.acceptance_criteria)<>'array' or jsonb_array_length(new.acceptance_criteria)=0 then raise exception 'acceptance_criteria must be non-empty array'; end if;
  if jsonb_typeof(new.invariants)<>'array' or jsonb_array_length(new.invariants)=0 then raise exception 'invariants must be non-empty array'; end if;
  if jsonb_typeof(new.negative_controls)<>'array' or jsonb_array_length(new.negative_controls)=0 then raise exception 'negative_controls must be non-empty array'; end if;
  v_codes:=programacion.fn_p0_json_codes(new.acceptance_criteria,'AC'); if cardinality(v_codes)<>jsonb_array_length(new.acceptance_criteria) then raise exception 'every acceptance criterion needs unique AC-* code'; end if;
  v_codes:=programacion.fn_p0_json_codes(new.invariants,'INV'); if cardinality(v_codes)<>jsonb_array_length(new.invariants) then raise exception 'every invariant needs unique INV-* code'; end if;
  v_codes:=programacion.fn_p0_json_codes(new.negative_controls,'NEG'); if cardinality(v_codes)<>jsonb_array_length(new.negative_controls) then raise exception 'every negative control needs unique NEG-* code'; end if;
  if not programacion.fn_p0_array_is_canonical(new.source_rule_codes,false) then raise exception 'source_rule_codes must be sorted unique non-empty'; end if;
  if new.artifact_type in ('STORY_SPEC','STORY') then if new.story_code is null or new.artifact_code<>new.story_code then raise exception '% requires artifact_code=story_code',new.artifact_type; end if;
  elsif new.story_code is not null then raise exception 'CANONICAL_SPEC must not carry story_code'; end if;
  if new.artifact_type='STORY' then
    if new.parent_spec_version_id is null then raise exception 'STORY requires parent CANONICAL_SPEC version'; end if;
    select * into v_parent from public.lf_functional_versions where id=new.parent_spec_version_id;
    if v_parent.id is null or v_parent.artifact_type<>'CANONICAL_SPEC' or v_parent.status<>'SEALED' then raise exception 'parent_spec_version_id must reference SEALED CANONICAL_SPEC'; end if;
  elsif new.parent_spec_version_id is not null then raise exception '% must not carry parent_spec_version_id',new.artifact_type; end if;
  if new.supersedes_version_id is null then
    if new.version_no<>1 then raise exception 'initial functional version must be version 1'; end if;
    if new.amendment_reason_code is not null or new.amendment_ref is not null then raise exception 'initial functional version cannot carry amendment metadata'; end if;
  else
    select * into v_sup from public.lf_functional_versions where id=new.supersedes_version_id;
    if v_sup.id is null or v_sup.status<>'SEALED' or v_sup.artifact_code<>new.artifact_code or new.version_no<>v_sup.version_no+1 then raise exception 'supersedes_version_id must reference previous SEALED version of same artifact'; end if;
    if length(btrim(coalesce(new.amendment_reason_code,'')))=0 or length(btrim(coalesce(new.amendment_ref,'')))=0 then raise exception 'superseding functional version requires amendment_reason_code and amendment_ref'; end if;
  end if;
  if new.status='DRAFT' then if new.content_sha256 is not null or new.sealed_at is not null then raise exception 'DRAFT functional version cannot carry seal'; end if;
  else
    if tg_op<>'UPDATE' or old.status<>'DRAFT' then raise exception 'SEALED requires DRAFT -> SEALED transition'; end if;
    v_payload:=jsonb_build_object('schema_version',1,'artifact_code',new.artifact_code,'artifact_type',new.artifact_type,'story_code',new.story_code,'parent_spec_version_id',new.parent_spec_version_id,'version_no',new.version_no,'objective',new.objective,'acceptance_criteria',new.acceptance_criteria,'invariants',new.invariants,'negative_controls',new.negative_controls,'source_rule_codes',to_jsonb(new.source_rule_codes),'supersedes_version_id',new.supersedes_version_id,'amendment_reason_code',new.amendment_reason_code,'amendment_ref',new.amendment_ref);
    v_digest:=programacion.fn_v09_sha256_jsonb(v_payload); if new.content_sha256 is not null and new.content_sha256<>v_digest then raise exception 'functional version digest mismatch'; end if; new.content_sha256:=v_digest; new.sealed_at:=coalesce(new.sealed_at,now());
  end if; return new;
end; $$;

create or replace function programacion.fn_guard_task_dependency()
returns trigger language plpgsql set search_path = pg_catalog, programacion as $$
declare v_status text; v_cycle boolean;
begin
  if tg_op='UPDATE' then raise exception 'task dependency edges are immutable; delete while DRAFT and recreate'; end if;
  select definition_status into v_status from programacion.agent_tasks where id=coalesce(new.task_id,old.task_id);
  if v_status is distinct from 'DRAFT' then raise exception 'dependency edges may change only while dependent task is DRAFT'; end if;
  if tg_op='DELETE' then return old; end if;
  if new.task_id=new.depends_on_task_id then raise exception 'task cannot depend on itself'; end if;
  with recursive reach(id) as (select new.depends_on_task_id union select d.depends_on_task_id from programacion.task_dependencies d join reach r on d.task_id=r.id) select exists(select 1 from reach where id=new.task_id) into v_cycle;
  if v_cycle then raise exception 'task dependency would create cycle'; end if; return new;
end; $$;

create or replace function programacion.fn_task_dag_metrics(p_functional_version_id bigint)
returns jsonb language sql stable set search_path = pg_catalog, programacion as $$
with recursive current_tasks as (
  select t.id from programacion.agent_tasks t where t.functional_version_id=p_functional_version_id and not exists (select 1 from programacion.agent_tasks n where n.supersedes_task_id=t.id)
), edges as (
  select d.task_id,d.depends_on_task_id from programacion.task_dependencies d join current_tasks t on t.id=d.task_id join current_tasks p on p.id=d.depends_on_task_id
), degrees as (
  select t.id,(select count(*) from edges e where e.task_id=t.id) indeg,(select count(*) from edges e where e.depends_on_task_id=t.id) outdeg from current_tasks t
), roots as (select id from degrees where indeg=0),
walk(node,depth,path) as (
  select r.id,1,array[r.id]::bigint[] from roots r
  union all
  select e.task_id,w.depth+1,w.path||e.task_id from walk w join edges e on e.depends_on_task_id=w.node where not e.task_id=any(w.path)
), agg as (
 select (select count(*) from current_tasks) task_count,(select count(*) from edges) edge_count,(select count(*) from degrees where indeg=0) root_count,(select count(*) from degrees where outdeg=0) leaf_count,(select count(*) from degrees where indeg>1 or outdeg>1) branch_count,coalesce((select max(depth) from walk),0) max_chain_length
)
select jsonb_build_object('task_count',task_count,'edge_count',edge_count,'root_count',root_count,'leaf_count',leaf_count,'branch_count',branch_count,'max_chain_length',max_chain_length,'pure_chain',(task_count>=3 and root_count=1 and leaf_count=1 and branch_count=0 and edge_count=task_count-1),'pure_chain_min_tasks',3) from agg
$$;

create or replace function programacion.fn_guard_agent_task()
returns trigger language plpgsql set search_path = pg_catalog, public, programacion as $$
declare v_f public.lf_functional_versions%rowtype; v_sup programacion.agent_tasks%rowtype; v_payload jsonb; v_digest text; v_dep_ids bigint[]; v_metrics jsonb; v_ac text[]; v_inv text[]; v_neg text[];
begin
  if tg_op='DELETE' then raise exception 'agent tasks are append-only'; end if;
  if tg_op='UPDATE' and old.definition_status='SEALED' then raise exception 'sealed agent task % is immutable; create a superseding task version',old.id; end if;
  if tg_op='INSERT' and new.definition_status<>'DRAFT' then raise exception 'agent task must be born DRAFT'; end if;
  if length(btrim(new.task_code))=0 or length(btrim(new.objective))=0 then raise exception 'task_code/objective required'; end if;
  select * into v_f from public.lf_functional_versions where id=new.functional_version_id; if v_f.id is null or v_f.status<>'SEALED' then raise exception 'agent task requires SEALED functional version'; end if;
  if not programacion.fn_p0_array_is_canonical(new.acceptance_refs,false) or not programacion.fn_p0_array_is_canonical(new.invariant_refs,false) or not programacion.fn_p0_array_is_canonical(new.negative_refs,false) then raise exception 'AC/INV/NEG refs must be sorted unique non-empty'; end if;
  v_ac:=programacion.fn_p0_json_codes(v_f.acceptance_criteria,'AC'); v_inv:=programacion.fn_p0_json_codes(v_f.invariants,'INV'); v_neg:=programacion.fn_p0_json_codes(v_f.negative_controls,'NEG');
  if exists(select 1 from unnest(new.acceptance_refs) x where not x=any(v_ac)) then raise exception 'acceptance_refs contain code outside functional version'; end if;
  if exists(select 1 from unnest(new.invariant_refs) x where not x=any(v_inv)) then raise exception 'invariant_refs contain code outside functional version'; end if;
  if exists(select 1 from unnest(new.negative_refs) x where not x=any(v_neg)) then raise exception 'negative_refs contain code outside functional version'; end if;
  if not programacion.fn_p0_path_array_is_canonical(new.context_path_patterns,false) or not programacion.fn_p0_path_array_is_canonical(new.write_path_patterns,false) or not programacion.fn_p0_path_array_is_canonical(new.protected_path_patterns,false) or not programacion.fn_p0_path_array_is_canonical(new.files_expected,false) then raise exception 'path arrays must be canonical sorted unique non-empty'; end if;
  if not programacion.fn_p0_array_is_canonical(new.platform_refs,true) or not programacion.fn_p0_array_is_canonical(new.interface_refs,true) or not programacion.fn_p0_array_is_canonical(new.unknown_refs,true) then raise exception 'platform/interface/unknown refs must be canonical sorted unique arrays'; end if;
  if new.supersedes_task_id is null then if new.task_version<>1 then raise exception 'initial task version must be 1'; end if;
  else
    select * into v_sup from programacion.agent_tasks where id=new.supersedes_task_id;
    if v_sup.id is null or v_sup.definition_status<>'SEALED' or v_sup.task_code<>new.task_code or new.task_version<>v_sup.task_version+1 then raise exception 'supersedes_task_id must reference previous SEALED task version with same task_code'; end if;
    if v_sup.functional_version_id<>new.functional_version_id and v_f.supersedes_version_id is distinct from v_sup.functional_version_id then raise exception 'superseding task may change functional version only to its exact superseding functional version'; end if;
  end if;
  if new.definition_status='DRAFT' then if new.task_sha256 is not null or new.sealed_at is not null then raise exception 'DRAFT task cannot carry seal'; end if;
  else
    if tg_op<>'UPDATE' or old.definition_status<>'DRAFT' then raise exception 'SEALED task requires DRAFT -> SEALED transition'; end if;
    if cardinality(new.unknown_refs)>0 then raise exception 'task sizing BLOCKED: unknown_refs must be resolved before seal'; end if;
    if cardinality(new.files_expected)>new.max_changed_files then raise exception 'task sizing REVIEW_SPLIT: files_expected exceeds max_changed_files'; end if;
    v_metrics:=programacion.fn_task_dag_metrics(new.functional_version_id); if coalesce((v_metrics->>'pure_chain')::boolean,false) then raise exception 'RECOMBINE_REQUIRED: pure task chain of length %',v_metrics->>'max_chain_length'; end if;
    select coalesce(array_agg(depends_on_task_id order by depends_on_task_id),'{}'::bigint[]) into v_dep_ids from programacion.task_dependencies where task_id=new.id;
    v_payload:=jsonb_build_object('schema_version',1,'task_code',new.task_code,'task_version',new.task_version,'functional_version_id',new.functional_version_id,'functional_sha256',v_f.content_sha256,'supersedes_task_id',new.supersedes_task_id,'objective',new.objective,'acceptance_refs',to_jsonb(new.acceptance_refs),'invariant_refs',to_jsonb(new.invariant_refs),'negative_refs',to_jsonb(new.negative_refs),'context_path_patterns',to_jsonb(new.context_path_patterns),'write_path_patterns',to_jsonb(new.write_path_patterns),'protected_path_patterns',to_jsonb(new.protected_path_patterns),'files_expected',to_jsonb(new.files_expected),'platform_refs',to_jsonb(new.platform_refs),'interface_refs',to_jsonb(new.interface_refs),'unknown_refs',to_jsonb(new.unknown_refs),'max_attempts',new.max_attempts,'max_patch_bytes',new.max_patch_bytes,'max_changed_files',new.max_changed_files,'max_context_bytes',new.max_context_bytes,'allow_deletions',new.allow_deletions,'dependency_task_ids',to_jsonb(v_dep_ids));
    v_digest:=programacion.fn_v09_sha256_jsonb(v_payload); if new.task_sha256 is not null and new.task_sha256<>v_digest then raise exception 'agent task digest mismatch'; end if; new.task_sha256:=v_digest; new.sealed_at:=coalesce(new.sealed_at,now());
  end if; return new;
end; $$;

create or replace function programacion.fn_guard_task_blocker()
returns trigger language plpgsql set search_path = pg_catalog, programacion as $$
begin
  if tg_op='DELETE' then raise exception 'task blockers are append-only'; end if;
  if length(btrim(new.blocker_code))=0 or length(btrim(new.owner_type))=0 or length(btrim(new.required_action))=0 or length(btrim(new.source_ref))=0 then raise exception 'blocker_code, owner_type, required_action and source_ref are required'; end if;
  if tg_op='INSERT' then if new.status<>'OPEN' or new.resolved_at is not null or new.resolved_by is not null or new.resolution_ref is not null then raise exception 'new blocker must be OPEN without resolution fields'; end if;
  else
    if old.status='RESOLVED' then raise exception 'resolved blocker is immutable'; end if;
    if new.task_id<>old.task_id or new.blocker_code<>old.blocker_code or new.owner_type<>old.owner_type or new.required_action<>old.required_action or new.source_ref<>old.source_ref then raise exception 'blocker identity/ownership/action cannot change'; end if;
    if new.status='RESOLVED' then if length(btrim(coalesce(new.resolved_by,'')))=0 or length(btrim(coalesce(new.resolution_ref,'')))=0 then raise exception 'resolving blocker requires resolved_by and resolution_ref'; end if; new.resolved_at:=coalesce(new.resolved_at,now());
    elsif new.resolved_at is not null or new.resolved_by is not null or new.resolution_ref is not null then raise exception 'OPEN blocker cannot carry resolution fields'; end if;
  end if; return new;
end; $$;

create or replace function programacion.fn_guard_test_contract()
returns trigger language plpgsql set search_path = pg_catalog, public, programacion as $$
declare v_task programacion.agent_tasks%rowtype; v_prior programacion.test_contracts%rowtype; v_payload jsonb; v_digest text; v_snapshot jsonb; v_cmd jsonb;
begin
  if tg_op='DELETE' then raise exception 'test contracts are append-only'; end if;
  if tg_op='UPDATE' and old.status='SEALED' then raise exception 'sealed test contract % is immutable; amend Spec/Task and create a new contract',old.id; end if;
  if tg_op='INSERT' and new.status<>'DRAFT' then raise exception 'test contract must be born DRAFT'; end if;
  select * into v_task from programacion.agent_tasks where id=new.task_id; if v_task.id is null or v_task.definition_status<>'SEALED' then raise exception 'test contract requires SEALED task'; end if;
  if jsonb_typeof(new.visible_commands)<>'array' or jsonb_array_length(new.visible_commands)=0 then raise exception 'visible_commands must be non-empty array'; end if;
  for v_cmd in select value from jsonb_array_elements(new.visible_commands) loop
    if jsonb_typeof(v_cmd)<>'object' or not (v_cmd ?& array['name','argv','timeout_seconds','max_output_bytes']) or (select count(*) from jsonb_object_keys(v_cmd))<>4 or length(btrim(coalesce(v_cmd->>'name','')))=0 or (v_cmd->>'name') !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' or jsonb_typeof(v_cmd->'argv')<>'array' or jsonb_array_length(v_cmd->'argv') not between 1 and 64 or exists(select 1 from jsonb_array_elements(v_cmd->'argv') a where jsonb_typeof(a)<>'string' or length(a#>>'{}')=0 or octet_length(a#>>'{}')>4096) or (v_cmd->>'timeout_seconds') !~ '^[0-9]+$' or (v_cmd->>'timeout_seconds')::integer not between 1 and 900 or (v_cmd->>'max_output_bytes') !~ '^[0-9]+$' or (v_cmd->>'max_output_bytes')::integer not between 1024 and 2000000 then raise exception 'visible command does not match Worker acceptance command contract'; end if;
  end loop;
  if (select count(*) from jsonb_array_elements(new.visible_commands) c) <> (select count(distinct c->>'name') from jsonb_array_elements(new.visible_commands) c) then raise exception 'visible command names must be unique'; end if;
  if length(btrim(new.hidden_oracle_ref))=0 or new.hidden_oracle_ref !~ '^[A-Za-z][A-Za-z0-9+.-]*://.+' then raise exception 'hidden_oracle_ref must be external URI'; end if;
  if new.hidden_oracle_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'hidden_oracle_sha256 invalid'; end if;
  if length(btrim(new.generator_identity))=0 or length(btrim(new.generator_channel))=0 then raise exception 'generator identity/channel required'; end if;
  if new.supersedes_contract_id is null then if new.contract_version<>v_task.task_version then raise exception 'contract_version must equal task_version'; end if; if new.amendment_reason_code is not null or new.amendment_ref is not null then raise exception 'initial task contract cannot carry amendment metadata'; end if;
  else
    select * into v_prior from programacion.test_contracts where id=new.supersedes_contract_id; if v_prior.id is null or v_prior.status<>'SEALED' then raise exception 'superseded contract must be SEALED'; end if;
    if v_task.supersedes_task_id is distinct from v_prior.task_id or new.contract_version<>v_prior.contract_version+1 then raise exception 'contract amendment requires superseding task version'; end if;
    if length(btrim(coalesce(new.amendment_reason_code,'')))=0 or length(btrim(coalesce(new.amendment_ref,'')))=0 then raise exception 'contract amendment reason/ref required'; end if;
  end if;
  if new.status='DRAFT' then if new.contract_sha256 is not null or new.sealed_at is not null then raise exception 'DRAFT test contract cannot carry seal'; end if;
  else
    if tg_op<>'UPDATE' or old.status<>'DRAFT' then raise exception 'SEALED test contract requires DRAFT -> SEALED transition'; end if;
    v_snapshot:=jsonb_build_object('acceptance_refs',to_jsonb(v_task.acceptance_refs),'invariant_refs',to_jsonb(v_task.invariant_refs),'negative_refs',to_jsonb(v_task.negative_refs),'task_sha256',v_task.task_sha256); new.criteria_snapshot:=v_snapshot;
    v_payload:=jsonb_build_object('schema_version',1,'task_id',new.task_id,'task_sha256',v_task.task_sha256,'contract_version',new.contract_version,'supersedes_contract_id',new.supersedes_contract_id,'suite_code',new.suite_code,'visible_commands',new.visible_commands,'hidden_oracle_ref',new.hidden_oracle_ref,'hidden_oracle_sha256',new.hidden_oracle_sha256,'generator_identity',new.generator_identity,'generator_channel',new.generator_channel,'criteria_snapshot',new.criteria_snapshot,'amendment_reason_code',new.amendment_reason_code,'amendment_ref',new.amendment_ref);
    v_digest:=programacion.fn_v09_sha256_jsonb(v_payload); if new.contract_sha256 is not null and new.contract_sha256<>v_digest then raise exception 'test contract digest mismatch'; end if; new.contract_sha256:=v_digest; new.sealed_at:=coalesce(new.sealed_at,now());
  end if; return new;
end; $$;

create or replace function programacion.fn_task_readiness(p_task_id bigint)
returns jsonb language plpgsql stable set search_path = pg_catalog, public, programacion as $$
declare t programacion.agent_tasks%rowtype; f public.lf_functional_versions%rowtype; tc programacion.test_contracts%rowtype; b record; d record; v_ready boolean:=true; v_exec boolean:=true; v_sizing text:='EXECUTABLE'; v_blockers jsonb:='[]'::jsonb; v_waiting jsonb:='[]'::jsonb; v_metrics jsonb;
begin
  select * into t from programacion.agent_tasks where id=p_task_id; if t.id is null then raise exception 'agent task % not found',p_task_id; end if;
  select * into f from public.lf_functional_versions where id=t.functional_version_id; select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED'; v_metrics:=programacion.fn_task_dag_metrics(t.functional_version_id);
  if exists(select 1 from programacion.agent_tasks n where n.supersedes_task_id=t.id) then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TASK_SUPERSEDED','owner_type','TASK_PREPARATION','required_action','USE_CURRENT_TASK_VERSION','source_ref','agent-task://'||t.id)); end if;
  if f.status<>'SEALED' then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','FUNCTIONAL_VERSION_NOT_SEALED','owner_type','FUNCTIONAL_OWNER','required_action','SEAL_FUNCTIONAL_VERSION','source_ref','functional-version://'||t.functional_version_id)); end if;
  if t.definition_status<>'SEALED' then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TASK_NOT_SEALED','owner_type','TASK_PREPARATION','required_action','SEAL_AGENT_TASK','source_ref','agent-task://'||t.id)); end if;
  if tc.id is null then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TEST_CONTRACT_NOT_SEALED','owner_type','VERIFIER','required_action','CREATE_AND_SEAL_TEST_CONTRACT','source_ref','agent-task://'||t.id)); end if;
  if cardinality(t.unknown_refs)>0 then v_ready:=false; v_sizing:='BLOCKED'; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','UNKNOWN_SCOPE_REFS','owner_type','TASK_PREPARATION','required_action','RESOLVE_UNKNOWNS','source_ref','agent-task://'||t.id)); elsif cardinality(t.files_expected)>t.max_changed_files then v_ready:=false; v_sizing:='REVIEW_SPLIT'; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SIZING_REVIEW_SPLIT','owner_type','TASK_PREPARATION','required_action','SPLIT_OR_REDUCE_SCOPE','source_ref','agent-task://'||t.id)); end if;
  if coalesce((v_metrics->>'pure_chain')::boolean,false) then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PURE_CHAIN_RECOMBINE_REQUIRED','owner_type','TASK_PREPARATION','required_action','RECOMBINE_TASKS','source_ref','functional-version://'||t.functional_version_id)); end if;
  for b in select * from programacion.task_blockers where task_id=t.id and status='OPEN' loop v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code',b.blocker_code,'owner_type',b.owner_type,'owner_ref',b.owner_ref,'required_action',b.required_action,'source_ref',b.source_ref)); end loop;
  for d in select depends_on_task_id from programacion.task_dependencies where task_id=t.id order by depends_on_task_id loop
    if exists(select 1 from programacion.agent_tasks n where n.supersedes_task_id=d.depends_on_task_id) or not exists(select 1 from programacion.agent_tasks x where x.id=d.depends_on_task_id and x.definition_status='SEALED') then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DEPENDENCY_TASK_NOT_CURRENT_SEALED','owner_type','TASK_PREPARATION','required_action','RESOLVE_DEPENDENCY_TASK','source_ref','agent-task://'||d.depends_on_task_id)); end if;
    if not exists(select 1 from programacion.v_ejecucion_autoridad ea join programacion.ejecuciones ex on ex.id=ea.execution_id where ex.request_ref='agent-task://'||d.depends_on_task_id and ea.effective_verdict='PASS') then v_exec:=false; v_waiting:=v_waiting||jsonb_build_array(d.depends_on_task_id); end if;
  end loop;
  if not v_ready then v_exec:=false; end if;
  return jsonb_build_object('task_id',t.id,'task_code',t.task_code,'task_version',t.task_version,'ready_for_development',v_ready,'executable_now',v_exec,'sizing',v_sizing,'sizing_metrics',jsonb_build_object('files_expected',cardinality(t.files_expected),'dependency_count',(select count(*) from programacion.task_dependencies where task_id=t.id),'platform_count',cardinality(t.platform_refs),'interface_count',cardinality(t.interface_refs),'unknown_count',cardinality(t.unknown_refs)),'dag',v_metrics,'blockers',v_blockers,'waiting_on_task_ids',v_waiting);
end; $$;

create or replace function programacion.fn_agent_task_execution_bundle(p_task_id bigint, p_base_head_sha text, p_source_snapshot_sha256 text)
returns jsonb language plpgsql stable set search_path = pg_catalog, public, programacion as $$
declare t programacion.agent_tasks%rowtype; f public.lf_functional_versions%rowtype; tc programacion.test_contracts%rowtype; r jsonb; v_spec jsonb;
begin
  if p_base_head_sha !~ '^[0-9a-f]{40}$' or p_source_snapshot_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid source identity'; end if;
  r:=programacion.fn_task_readiness(p_task_id); if not coalesce((r->>'ready_for_development')::boolean,false) then raise exception 'TASK_NOT_READY: %',r->'blockers'; end if; if not coalesce((r->>'executable_now')::boolean,false) then raise exception 'TASK_WAITING_DEPENDENCIES: %',r->'waiting_on_task_ids'; end if;
  select * into t from programacion.agent_tasks where id=p_task_id; select * into f from public.lf_functional_versions where id=t.functional_version_id; select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED';
  v_spec:=jsonb_build_object('schema_version',1,'task_id',t.task_code||'@v'||t.task_version,'objective',t.objective,'base_head_sha',p_base_head_sha,'source_snapshot_sha256',p_source_snapshot_sha256,'context_path_patterns',to_jsonb(t.context_path_patterns),'write_path_patterns',to_jsonb(t.write_path_patterns),'protected_path_patterns',to_jsonb(t.protected_path_patterns),'acceptance_commands',tc.visible_commands,'max_attempts',t.max_attempts,'max_patch_bytes',t.max_patch_bytes,'max_changed_files',t.max_changed_files,'max_context_bytes',t.max_context_bytes,'allow_deletions',t.allow_deletions);
  return jsonb_build_object('request_ref','agent-task://'||t.id,'worker_task_spec',v_spec,'hidden_oracle_ref',tc.hidden_oracle_ref,'hidden_oracle_sha256',tc.hidden_oracle_sha256,'functional_version_sha256',f.content_sha256,'task_sha256',t.task_sha256,'test_contract_sha256',tc.contract_sha256,'readiness',r);
end; $$;

create or replace function programacion.fn_guard_execution_insert()
returns trigger language plpgsql set search_path = pg_catalog, public, programacion as $$
declare v_task_id bigint; v_ready jsonb; v_task programacion.agent_tasks%rowtype; v_f public.lf_functional_versions%rowtype; v_tc programacion.test_contracts%rowtype; v_expected_scope jsonb;
begin
  if new.estado is distinct from 'CREATED' then raise exception 'execution must start CREATED; observed estado=%',coalesce(new.estado,'<NULL>'); end if;
  if new.veredicto is not null or new.completed_at is not null or new.bloqueo_razon is not null then raise exception 'new CREATED execution cannot carry terminal verdict/completion/block reason'; end if;
  if new.request_ref like 'agent-task://%' then
    begin v_task_id:=substring(new.request_ref from 14)::bigint; exception when others then raise exception 'invalid agent-task request_ref'; end;
    v_ready:=programacion.fn_task_readiness(v_task_id); if not coalesce((v_ready->>'ready_for_development')::boolean,false) then raise exception 'agent task is not READY_FOR_DEVELOPMENT: %',v_ready->'blockers'; end if; if not coalesce((v_ready->>'executable_now')::boolean,false) then raise exception 'agent task is not EXECUTABLE_NOW: %',v_ready->'waiting_on_task_ids'; end if;
    select * into v_task from programacion.agent_tasks where id=v_task_id; select * into v_f from public.lf_functional_versions where id=v_task.functional_version_id; select * into v_tc from programacion.test_contracts where task_id=v_task.id and status='SEALED';
    v_expected_scope:=jsonb_build_object('task_id',v_task.id,'task_sha256',v_task.task_sha256,'functional_version_sha256',v_f.content_sha256,'test_contract_sha256',v_tc.contract_sha256,'write_path_patterns',to_jsonb(v_task.write_path_patterns),'protected_path_patterns',to_jsonb(v_task.protected_path_patterns));
    if new.scope is distinct from v_expected_scope then raise exception 'execution scope does not match sealed agent task contract'; end if;
  end if; return new;
end; $$;

create trigger trg_lf_functional_versions_guard before insert or update or delete on public.lf_functional_versions for each row execute function programacion.fn_guard_functional_version();
create trigger trg_task_dependencies_guard before insert or update or delete on programacion.task_dependencies for each row execute function programacion.fn_guard_task_dependency();
create trigger trg_agent_tasks_guard before insert or update or delete on programacion.agent_tasks for each row execute function programacion.fn_guard_agent_task();
create trigger trg_task_blockers_guard before insert or update or delete on programacion.task_blockers for each row execute function programacion.fn_guard_task_blocker();
create trigger trg_test_contracts_guard before insert or update or delete on programacion.test_contracts for each row execute function programacion.fn_guard_test_contract();

create or replace view programacion.v_agent_task_readiness with (security_invoker=true) as select t.id task_id,t.task_code,t.task_version,t.functional_version_id,programacion.fn_task_readiness(t.id) readiness from programacion.agent_tasks t where not exists(select 1 from programacion.agent_tasks n where n.supersedes_task_id=t.id);
create or replace view programacion.v_task_blocked_queue with (security_invoker=true) as select r.task_id,r.task_code,r.task_version,b->>'code' blocker_code,b->>'owner_type' owner_type,b->>'owner_ref' owner_ref,b->>'required_action' required_action,b->>'source_ref' source_ref from programacion.v_agent_task_readiness r cross join lateral jsonb_array_elements(r.readiness->'blockers') b where coalesce((r.readiness->>'ready_for_development')::boolean,false)=false;
create or replace view programacion.v_agent_task_next_executable with (security_invoker=true) as select * from programacion.v_agent_task_readiness where coalesce((readiness->>'ready_for_development')::boolean,false)=true and coalesce((readiness->>'executable_now')::boolean,false)=true;

revoke execute on function programacion.fn_p0_array_is_canonical(text[],boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_p0_path_array_is_canonical(text[],boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_p0_json_codes(jsonb,text) from public, anon, authenticated;
revoke execute on function programacion.fn_guard_functional_version() from public, anon, authenticated;
revoke execute on function programacion.fn_guard_task_dependency() from public, anon, authenticated;
revoke execute on function programacion.fn_task_dag_metrics(bigint) from public, anon, authenticated;
revoke execute on function programacion.fn_guard_agent_task() from public, anon, authenticated;
revoke execute on function programacion.fn_guard_task_blocker() from public, anon, authenticated;
revoke execute on function programacion.fn_guard_test_contract() from public, anon, authenticated;
revoke execute on function programacion.fn_task_readiness(bigint) from public, anon, authenticated;
revoke execute on function programacion.fn_agent_task_execution_bundle(bigint,text,text) from public, anon, authenticated;

grant select on programacion.v_agent_task_readiness, programacion.v_task_blocked_queue, programacion.v_agent_task_next_executable to programacion_builder, programacion_auditor, programacion_human_authority, programacion_verifier;
grant execute on function programacion.fn_task_dag_metrics(bigint), programacion.fn_task_readiness(bigint), programacion.fn_agent_task_execution_bundle(bigint,text,text) to programacion_builder, programacion_auditor, programacion_human_authority, programacion_verifier;