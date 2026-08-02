-- PR #93 / LOTE-C / CA-N44..CA-N48 evidence and runtime hardening.
-- Versioned only. Apply and exercise only in an isolated Supabase environment.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_writer_preimage_scope_v7(text)') is null
     or to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_canonical_json_v7(jsonb)') is null
     or to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_writer_key_separation_v7_valid()') is null then
    raise exception 'V7 helpers, validator and separation invariant must exist before LOTE-C';
  end if;
end
$preflight$;

-- CA-N46: trusted test/readback executor. API roles remain revoked.
grant execute on function private.fn_writer_preimage_scope_v7(text) to postgres;
grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_gate_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_canonical_json_v7(jsonb) to postgres;
grant execute on function private.fn_payload_sha256_v7(jsonb) to postgres;
grant execute on function private.fn_frame_component_v7(text) to postgres;

-- Create the private gate-row binder under the governance owner without leaving
-- residual membership or CREATE privilege.
grant lf_governance_owner_v3 to postgres
  with admin false inherit true set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

-- CA-N45: persist the exact consumed nonce hash inside the private gate row.
-- The event remains a secondary cross-check, not the sole nonce anchor.
create or replace function private.fn_bind_gate_writer_nonce_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_event_nonce text;
  v_event_preimage text;
begin
  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  select
    e.payload->>'writer_nonce_sha256',
    e.payload#>>'{persisted_effects,signed_preimage_sha256}'
    into v_event_nonce,v_event_preimage
  from public.lf_eventos e
  where e.id=new.evidence_event_id
    and e.evento_tipo='GATE_TEST_RUN_RECORDED'
    and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7';

  if coalesce(v_event_nonce,'') !~ '^[0-9a-f]{64}$'
     or coalesce(v_event_preimage,'') !~ '^[0-9a-f]{64}$'
     or v_event_preimage is distinct from new.persisted_effects->>'signed_preimage_sha256' then
    raise exception using
      errcode='23514',
      message='V7 gate evidence event does not bind the consumed writer proof';
  end if;

  new.persisted_effects:=coalesce(new.persisted_effects,'{}'::jsonb)
    ||jsonb_build_object('writer_nonce_sha256',v_event_nonce);
  new.persisted_effects_sha256:=encode(
    extensions.digest(convert_to(new.persisted_effects::text,'UTF8'),'sha256'),
    'hex'
  );
  return new;
end;
$function$;

alter function private.fn_bind_gate_writer_nonce_v7()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_bind_gate_writer_nonce_v7()
  from public,anon,authenticated,service_role;

drop trigger if exists trg_05_bind_gate_writer_nonce_v7
  on private.lf_gate_test_runs_v3;
create trigger trg_05_bind_gate_writer_nonce_v7
before insert on private.lf_gate_test_runs_v3
for each row execute function private.fn_bind_gate_writer_nonce_v7();
alter table private.lf_gate_test_runs_v3
  enable always trigger trg_05_bind_gate_writer_nonce_v7;

-- CA-N45: the private row is authoritative for both proof hashes; the event must
-- independently agree with those same values.
create or replace function private.fn_gate_nonce_v7_valid(p_test_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    join public.lf_eventos e
      on e.id=t.evidence_event_id
     and e.evento_tipo='GATE_TEST_RUN_RECORDED'
     and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
     and e.payload#>>'{persisted_effects,signed_preimage_sha256}'
         =t.persisted_effects->>'signed_preimage_sha256'
     and e.payload->>'writer_nonce_sha256'
         =t.persisted_effects->>'writer_nonce_sha256'
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=t.persisted_effects->>'signed_preimage_sha256'
     and n.nonce_sha256=t.persisted_effects->>'writer_nonce_sha256'
    where t.id=p_test_id
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.persisted_effects->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(t.persisted_effects->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_gate_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

-- CA-N48: include the framed parser and gate binder in the permanent separation
-- invariant. This function remains non-secret and executable by the established roles.
create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    exists (
      select 1
      from pg_policies p
      where p.schemaname='private'
        and p.tablename='lf_writer_hmac_keys_v7'
        and p.policyname='pol_lf_writer_hmac_keys_v7_postgres'
        and p.cmd='ALL'
        and 'postgres'=any(p.roles)
    )
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_valid(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_match_key(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_consume_writer_proof_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_bind_gate_writer_nonce_v7()','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_install_writer_hmac_key_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_challenge_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_promote_writer_hmac_key_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_retire_writer_hmac_key_v7(text,text)','EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

commit;
