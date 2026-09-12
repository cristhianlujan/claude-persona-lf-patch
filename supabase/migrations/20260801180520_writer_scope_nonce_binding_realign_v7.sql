-- PR #93 / CA-N39..CA-N42 scope and nonce-binding realignment.
-- Versioned only. Exercise in an isolated environment before deployment.
--
-- The active V7 preimage is:
--   frame(scope) || frame(execution_id) || frame(payload_sha256)
-- This migration makes the nonce consumer and post-write validators understand that
-- same contract without adding columns or weakening fail-closed behavior.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_reconciliation_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_match_key(text,text,text)') is null
     or to_regprocedure('private.fn_frame_component_v7(text)') is null then
    raise exception 'V7 writer, nonce validators and framing helper must exist before realignment';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7')
     or not exists (select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'V7 writer roles must exist before realignment';
  end if;
end
$preflight$;

grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_writer_verifier_v7;
grant create on schema private to lf_governance_owner_v3;

-- This is the first migration that compiles an extensions.digest reference while
-- executing as the verifier owner. Grant parser/runtime USAGE before SET ROLE;
-- the later extensions migration keeps the grant idempotent and performs the
-- final no-CREATE/function-EXECUTE readback.
grant usage on schema extensions to lf_writer_verifier_v7;
revoke create on schema extensions from lf_writer_verifier_v7;

set local role lf_writer_verifier_v7;

-- Decode all three length-framed components. Returning NULL is the fail-closed result
-- for legacy, malformed, truncated or overlong input.
create or replace function private.fn_writer_preimage_scope_v7(p_preimage text)
returns text
language plpgsql
immutable
strict
set search_path to ''
as $function$
declare
  v_bytes bytea:=convert_to(p_preimage,'UTF8');
  v_total integer:=octet_length(p_preimage);
  v_offset integer:=1;
  v_tail text;
  v_separator integer;
  v_length_text text;
  v_length integer;
  v_value_bytes bytea;
  v_value text;
  v_scope text;
  v_execution text;
  v_payload_hash text;
  v_frame integer;
begin
  for v_frame in 1..3 loop
    if v_offset>v_total then
      return null;
    end if;

    v_tail:=convert_from(substring(v_bytes from v_offset),'UTF8');
    v_separator:=strpos(v_tail,'#');
    if v_separator<=1 then
      return null;
    end if;

    v_length_text:=left(v_tail,v_separator-1);
    if v_length_text !~ '^(0|[1-9][0-9]*)$' then
      return null;
    end if;

    begin
      v_length:=v_length_text::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        return null;
    end;

    if v_length<0 or v_length>1048576 then
      return null;
    end if;

    v_value_bytes:=substring(v_bytes from v_offset+v_separator for v_length);
    if octet_length(v_value_bytes)<>v_length then
      return null;
    end if;

    begin
      v_value:=convert_from(v_value_bytes,'UTF8');
    exception
      when character_not_in_repertoire then
        return null;
    end;

    if v_frame=1 then
      v_scope:=v_value;
    elsif v_frame=2 then
      v_execution:=v_value;
    else
      v_payload_hash:=v_value;
    end if;

    v_offset:=v_offset+v_separator+v_length;
  end loop;

  if v_offset<>v_total+1
     or nullif(v_execution,'') is null
     or coalesce(v_payload_hash,'') !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  if v_scope='reconciliation-v7' then
    return 'RECONCILIATION';
  elsif v_scope='gate-v7' then
    return 'GATE';
  end if;

  return null;
exception
  when invalid_parameter_value
    or character_not_in_repertoire
    or numeric_value_out_of_range then
    return null;
end;
$function$;

alter function private.fn_writer_preimage_scope_v7(text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_writer_preimage_scope_v7(text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_writer_preimage_scope_v7(text)
  to lf_governance_owner_v3;

create or replace function private.fn_consume_writer_proof_v7(
  p_preimage text,
  p_signature text,
  p_writer_nonce text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_claims jsonb:='{}'::jsonb;
  v_role text;
  v_exp timestamptz;
  v_scope text;
  v_key_id text;
  v_rows integer:=0;
begin
  begin
    v_claims:=coalesce(
      nullif(current_setting('request.jwt.claims',true),'')::jsonb,
      '{}'::jsonb
    );
  exception
    when invalid_text_representation then
      return false;
  end;

  v_role:=coalesce(v_claims->>'role','');
  if v_role<>'service_role' then
    return false;
  end if;

  if nullif(p_preimage,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  if coalesce(p_writer_nonce,'') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  begin
    v_exp:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range
      or datetime_field_overflow then
      return false;
  end;

  if v_exp<=clock_timestamp()-interval '5 seconds'
     or v_exp>clock_timestamp()+interval '6 minutes' then
    return false;
  end if;

  v_scope:=private.fn_writer_preimage_scope_v7(p_preimage);
  if v_scope is null then
    return false;
  end if;

  v_key_id:=private.fn_writer_hmac_v7_match_key(
    p_preimage,p_writer_nonce,lower(p_signature)
  );
  if v_key_id is null then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role,key_id
  ) values (
    encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role,
    v_key_id
  )
  on conflict do nothing;

  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$function$;

alter function private.fn_consume_writer_proof_v7(text,text,text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_consume_writer_proof_v7(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to lf_governance_owner_v3;

reset role;
set local role lf_governance_owner_v3;

-- Link a reconciliation row to the exact nonce and exact signed preimage persisted by
-- the public writer. No legacy preimage reconstruction is attempted.
create or replace function private.fn_reconciliation_nonce_v7_valid(p_run_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='RECONCILIATION'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=g.details->>'signed_preimage_sha256'
     and n.nonce_sha256=g.details->>'writer_nonce_sha256'
    where g.id=p_run_id
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(g.details->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(g.details->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (g.reconciled_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_reconciliation_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

-- Gate rows keep signed_preimage_sha256 in persisted_effects; the nonce hash is bound
-- through the immutable evidence event written in the same transaction.
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
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=t.persisted_effects->>'signed_preimage_sha256'
     and n.nonce_sha256=e.payload->>'writer_nonce_sha256'
    where t.id=p_test_id
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.persisted_effects->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(e.payload->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
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
revoke create on schema private from lf_writer_verifier_v7;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;
revoke lf_writer_verifier_v7 from postgres granted by postgres;

commit;
