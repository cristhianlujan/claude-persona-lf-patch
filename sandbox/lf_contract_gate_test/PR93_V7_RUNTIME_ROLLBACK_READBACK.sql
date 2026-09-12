\set ON_ERROR_STOP on

do $rollback_readback$
begin
  if current_setting('server_version_num')::integer < 170000
     or current_setting('server_version_num')::integer >= 180000 then
    raise exception 'rollback readback requires PostgreSQL 17';
  end if;

  if to_regclass('private.lf_reconciliation_writer_nonces_v7') is not null
     or to_regclass('private.lf_github_reconciliation_quarantine_v7') is not null
     or to_regclass('private.lf_writer_hmac_keys_v7') is not null
     or to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is not null
     or to_regprocedure('private.fn_writer_hmac_v7_match_key(text,text,text)') is not null
     or to_regprocedure('public.record_external_ci_verification_v7(jsonb,text,text,text)') is not null
     or to_regclass('public.v_lf_architecture_closure_v8') is not null then
    raise exception 'V7 objects remain after restore rollback';
  end if;

  if exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7') then
    raise exception 'V7 verifier role remains after restore rollback';
  end if;

  if to_regclass('private.lf_gate_test_runs_v3') is null
     or to_regclass('private.lf_github_reconciliation_runs_v3') is null
     or to_regclass('private.lf_skill_artifacts') is null
     or to_regclass('public.lf_eventos') is null
     or to_regclass('public.v_lf_architecture_closure_v7') is null then
    raise exception 'base objects are missing after restore rollback';
  end if;

  if exists (
       select 1
       from information_schema.columns
       where table_schema='private'
         and table_name='lf_gate_test_runs_v3'
         and column_name='writer_nonce_sha256'
     ) then
    raise exception 'V7 gate column remains after restore rollback';
  end if;

  if (select rolsuper from pg_roles where rolname='postgres') then
    raise exception 'postgres boundary changed during rollback';
  end if;

  if not exists (
       select 1
       from pg_auth_members m
       where m.roleid='lf_governance_owner_v3'::regrole
         and m.member='postgres'::regrole
         and m.grantor='lf_ci_cluster_admin'::regrole
         and m.admin_option
         and not m.inherit_option
         and not m.set_option
     ) then
    raise exception 'managed governance membership was not restored';
  end if;
end
$rollback_readback$;

select jsonb_build_object(
  'server_major', current_setting('server_version_num')::integer / 10000,
  'v7_nonce_table_present',
    to_regclass('private.lf_reconciliation_writer_nonces_v7') is not null,
  'v7_key_table_present',
    to_regclass('private.lf_writer_hmac_keys_v7') is not null,
  'v7_verifier_role_present',
    exists(select 1 from pg_roles where rolname='lf_writer_verifier_v7'),
  'base_gate_table_present',
    to_regclass('private.lf_gate_test_runs_v3') is not null,
  'base_closure_view_present',
    to_regclass('public.v_lf_architecture_closure_v7') is not null
) as rollback_readback;
