-- Router: ACT-0001
-- Operation: ACTUALIZACION_DB_LF
-- Scope: enable RLS on 8 newly-created LF-owned tables detected after the 2026-10-20 hardening.
-- EKB: RLS-001 / SEC-007
-- No FORCE RLS. No DML. No grant widening.
-- Legitimate direct PG-01 access is preserved with minimal permissive policies.

begin;

do $pre$
declare
  v_missing text;
begin
  with targets(schema_name, table_name) as (
    values
      ('private','lf_pg01_review_attestations_v1'),
      ('private','lf_pg01_subject_verifications_v1'),
      ('private','lf_profile_capability_registry_v1'),
      ('private','lf_profile_input_governance_runtime_ticket_v1'),
      ('private','lf_programming_admission_revocations_v1'),
      ('private','lf_programming_context_handoff_receipts_v1'),
      ('private','lf_reusable_policy_registry_v1'),
      ('public','lf_profile_selection_registry_v1')
  )
  select string_agg(format('%I.%I',t.schema_name,t.table_name),', ' order by t.schema_name,t.table_name)
    into v_missing
  from targets t
  where to_regclass(format('%I.%I',t.schema_name,t.table_name)) is null;

  if v_missing is not null then
    raise exception 'RLS_NEW_TABLES_TARGET_MISSING:%', v_missing;
  end if;

  if not exists (select 1 from pg_roles where rolname='programacion_verifier' and not rolbypassrls)
     or not exists (select 1 from pg_roles where rolname='programacion_auditor' and not rolbypassrls)
  then
    raise exception 'RLS_NEW_TABLES_AUTHORITY_ROLE_PRECONDITION_FAILED';
  end if;

  if not has_table_privilege('programacion_verifier','private.lf_pg01_subject_verifications_v1','SELECT')
     or not has_table_privilege('programacion_auditor','private.lf_pg01_subject_verifications_v1','SELECT')
     or not has_column_privilege('programacion_verifier','private.lf_pg01_subject_verifications_v1','receipt_id','INSERT')
     or not has_column_privilege('programacion_verifier','private.lf_pg01_subject_verifications_v1','context_id','INSERT')
     or not has_column_privilege('programacion_auditor','private.lf_pg01_review_attestations_v1','judge_execution_id','INSERT')
  then
    raise exception 'RLS_NEW_TABLES_PG01_EXISTING_PRIVILEGE_PRECONDITION_FAILED';
  end if;
end
$pre$;

alter table private.lf_pg01_review_attestations_v1 enable row level security;
alter table private.lf_pg01_subject_verifications_v1 enable row level security;
alter table private.lf_profile_capability_registry_v1 enable row level security;
alter table private.lf_profile_input_governance_runtime_ticket_v1 enable row level security;
alter table private.lf_programming_admission_revocations_v1 enable row level security;
alter table private.lf_programming_context_handoff_receipts_v1 enable row level security;
alter table private.lf_reusable_policy_registry_v1 enable row level security;
alter table public.lf_profile_selection_registry_v1 enable row level security;

drop policy if exists pol_lf_pg01_subject_verifications_v1_select on private.lf_pg01_subject_verifications_v1;
create policy pol_lf_pg01_subject_verifications_v1_select
  on private.lf_pg01_subject_verifications_v1
  as permissive
  for select
  to programacion_verifier, programacion_auditor
  using (true);

drop policy if exists pol_lf_pg01_subject_verifications_v1_insert_verifier on private.lf_pg01_subject_verifications_v1;
create policy pol_lf_pg01_subject_verifications_v1_insert_verifier
  on private.lf_pg01_subject_verifications_v1
  as permissive
  for insert
  to programacion_verifier
  with check (true);

drop policy if exists pol_lf_pg01_review_attestations_v1_insert_auditor on private.lf_pg01_review_attestations_v1;
create policy pol_lf_pg01_review_attestations_v1_insert_auditor
  on private.lf_pg01_review_attestations_v1
  as permissive
  for insert
  to programacion_auditor
  with check (true);

do $post$
declare
  v_bad text;
  v_subject_policies int;
  v_review_policies int;
begin
  with targets(schema_name, table_name) as (
    values
      ('private','lf_pg01_review_attestations_v1'),
      ('private','lf_pg01_subject_verifications_v1'),
      ('private','lf_profile_capability_registry_v1'),
      ('private','lf_profile_input_governance_runtime_ticket_v1'),
      ('private','lf_programming_admission_revocations_v1'),
      ('private','lf_programming_context_handoff_receipts_v1'),
      ('private','lf_reusable_policy_registry_v1'),
      ('public','lf_profile_selection_registry_v1')
  )
  select string_agg(format('%I.%I',t.schema_name,t.table_name),', ' order by t.schema_name,t.table_name)
    into v_bad
  from targets t
  join pg_namespace n on n.nspname=t.schema_name
  join pg_class c on c.relnamespace=n.oid and c.relname=t.table_name and c.relkind in ('r','p')
  where not c.relrowsecurity or c.relforcerowsecurity;

  if v_bad is not null then
    raise exception 'RLS_NEW_TABLES_POSTCONDITION_FAILED:%', v_bad;
  end if;

  select count(*) into v_subject_policies
  from pg_policy p
  where p.polrelid='private.lf_pg01_subject_verifications_v1'::regclass;

  select count(*) into v_review_policies
  from pg_policy p
  where p.polrelid='private.lf_pg01_review_attestations_v1'::regclass;

  if v_subject_policies <> 2 or v_review_policies <> 1 then
    raise exception 'RLS_NEW_TABLES_POLICY_COUNT_POSTCONDITION_FAILED:subject=%,review=%',
      v_subject_policies,v_review_policies;
  end if;
end
$post$;

commit;
