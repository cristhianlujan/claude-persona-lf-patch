-- LF PR #93 / LOTE 1 / read-only inspection.
-- SELECT statements only. This file does not validate runtime behavior by itself.

-- 1. Role attributes and memberships.
select
  r.rolname,
  r.rolcanlogin,
  r.rolinherit,
  r.rolbypassrls,
  exists (
    select 1
    from pg_auth_members m
    join pg_roles member_role on member_role.oid = m.member
    where m.roleid = r.oid
      and member_role.rolname = 'postgres'
  ) as granted_to_postgres
from pg_roles r
where r.rolname in ('lf_writer_verifier_v7', 'lf_governance_owner_v3')
order by r.rolname;

-- Expected for lf_writer_verifier_v7: no login, no inherit, no bypass RLS,
-- and no residual membership granted to postgres.

-- 2. Relation existence, owner and row security.
select
  n.nspname as schema_name,
  c.relname,
  c.relkind,
  pg_get_userbyid(c.relowner) as owner_name,
  c.relrowsecurity,
  c.relforcerowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'private'
  and c.relname in (
    'lf_writer_hmac_keys_v7',
    'lf_reconciliation_writer_nonces_v7'
  )
order by c.relname;

-- Expected: both relations owned by lf_writer_verifier_v7 with RLS and FORCE RLS.

-- 3. Effective table privileges for API and application roles.
with targets(role_name, relation_name) as (
  values
    ('anon', 'private.lf_writer_hmac_keys_v7'),
    ('authenticated', 'private.lf_writer_hmac_keys_v7'),
    ('service_role', 'private.lf_writer_hmac_keys_v7'),
    ('lf_governance_owner_v3', 'private.lf_writer_hmac_keys_v7'),
    ('anon', 'private.lf_reconciliation_writer_nonces_v7'),
    ('authenticated', 'private.lf_reconciliation_writer_nonces_v7'),
    ('service_role', 'private.lf_reconciliation_writer_nonces_v7'),
    ('lf_governance_owner_v3', 'private.lf_reconciliation_writer_nonces_v7')
)
select
  role_name,
  relation_name,
  case when to_regclass(relation_name) is null then null
       else has_table_privilege(role_name, relation_name, 'SELECT') end as can_select,
  case when to_regclass(relation_name) is null then null
       else has_table_privilege(role_name, relation_name, 'INSERT') end as can_insert,
  case when to_regclass(relation_name) is null then null
       else has_table_privilege(role_name, relation_name, 'UPDATE') end as can_update,
  case when to_regclass(relation_name) is null then null
       else has_table_privilege(role_name, relation_name, 'DELETE') end as can_delete
from targets
order by relation_name, role_name;

-- Expected: all values false for the listed roles.

-- 4. Function ownership, SECURITY DEFINER, search_path and source digest.
select
  n.nspname as schema_name,
  p.proname,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_userbyid(p.proowner) as owner_name,
  p.prosecdef,
  p.provolatile,
  p.proconfig,
  md5(p.prosrc) as source_md5
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'private'
  and p.proname in (
    'fn_verify_reconciliation_writer_token_v7',
    'fn_install_writer_hmac_key_v7',
    'fn_writer_hmac_challenge_v7',
    'fn_promote_writer_hmac_key_v7',
    'fn_retire_writer_hmac_key_v7',
    'fn_guard_lf_writer_hmac_keys_v7',
    'fn_guard_lf_reconciliation_writer_nonces_v7'
  )
order by p.proname, identity_arguments;

-- Expected: owner lf_writer_verifier_v7, SECURITY DEFINER, search_path="".

-- 5. Function EXECUTE privileges.
with signatures(role_name, function_signature) as (
  values
    ('service_role', 'private.fn_verify_reconciliation_writer_token_v7(text,text,text,text)'),
    ('lf_governance_owner_v3', 'private.fn_verify_reconciliation_writer_token_v7(text,text,text,text)'),
    ('service_role', 'private.fn_install_writer_hmac_key_v7(text,text,text)'),
    ('lf_governance_owner_v3', 'private.fn_install_writer_hmac_key_v7(text,text,text)'),
    ('service_role', 'private.fn_writer_hmac_challenge_v7(text,text)'),
    ('lf_governance_owner_v3', 'private.fn_writer_hmac_challenge_v7(text,text)'),
    ('service_role', 'private.fn_promote_writer_hmac_key_v7(text,text)'),
    ('service_role', 'private.fn_retire_writer_hmac_key_v7(text,text)')
)
select
  role_name,
  function_signature,
  case when to_regprocedure(function_signature) is null then null
       else has_function_privilege(role_name, function_signature, 'EXECUTE') end as can_execute
from signatures
order by function_signature, role_name;

-- Expected: governance owner can execute only the verifier; service_role cannot execute
-- any listed private function directly.

-- 6. Policies and ENABLE ALWAYS triggers.
select
  schemaname,
  tablename,
  policyname,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'private'
  and tablename in ('lf_writer_hmac_keys_v7', 'lf_reconciliation_writer_nonces_v7')
order by tablename, policyname;

select
  n.nspname as schema_name,
  c.relname,
  t.tgname,
  t.tgenabled,
  pg_get_triggerdef(t.oid, true) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal
  and n.nspname = 'private'
  and c.relname in ('lf_writer_hmac_keys_v7', 'lf_reconciliation_writer_nonces_v7')
order by c.relname, t.tgname;

-- Expected trigger state: A, meaning ENABLE ALWAYS.

-- 7. Non-secret invariants. key_material is deliberately not selected.
select
  count(*) filter (where lifecycle_state = 'PREPARED') as prepared_keys,
  count(*) filter (where lifecycle_state = 'ACTIVE') as active_keys,
  count(*) filter (where lifecycle_state = 'RETIRING') as retiring_keys,
  count(*) filter (where lifecycle_state = 'RETIRED') as retired_keys,
  count(*) as total_keys
from private.lf_writer_hmac_keys_v7;

select
  key_id,
  lifecycle_state,
  installed_at,
  activated_at,
  retiring_at,
  retired_at,
  installed_by_execution_id,
  last_transition_execution_id
from private.lf_writer_hmac_keys_v7
order by installed_at, key_id;

select
  count(*) as consumed_nonces,
  count(distinct nonce_sha256) as distinct_nonces,
  count(*) filter (where expires_at < consumed_at - interval '5 seconds') as invalid_past_ttl,
  count(*) filter (where expires_at > consumed_at + interval '10 minutes') as invalid_future_ttl
from private.lf_reconciliation_writer_nonces_v7;

-- 8. Vault must not be referenced by the LOTE 1 functions.
select
  p.proname,
  position('vault.' in lower(pg_get_functiondef(p.oid))) > 0 as references_vault
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'private'
  and p.proname in (
    'fn_verify_reconciliation_writer_token_v7',
    'fn_install_writer_hmac_key_v7',
    'fn_writer_hmac_challenge_v7',
    'fn_promote_writer_hmac_key_v7',
    'fn_retire_writer_hmac_key_v7'
  )
order by p.proname;

-- Expected: references_vault=false for every row.
