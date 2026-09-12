-- PR #93 / CA-N36..CA-N38 full-payload binding for the active V7 writer.
-- Versioned only. Exercise in an isolated environment before deployment.
--
-- Canonical contract shared with Edge:
--   * every payload key is ASCII and sorted bytewise;
--   * strings use JSON escaping;
--   * arrays preserve order;
--   * numbers must be JavaScript-safe integers;
--   * the signed payload component is SHA-256(canonical JSON);
--   * preimage components use UTF-8 byte-length framing, not delimiters.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null then
    raise exception 'V7 canonical preimage helpers must exist before full-payload binding';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'lf_governance_owner_v3 must exist before full-payload binding';
  end if;
end
$preflight$;

-- Temporary owner context. A failure rolls this back with the migration.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;

-- This is the first V7 owner-context function compilation that references
-- extensions.digest. Parser/runtime schema USAGE must exist before SET ROLE;
-- CREATE remains forbidden.
grant usage on schema extensions to lf_governance_owner_v3;
revoke create on schema extensions from lf_governance_owner_v3;

set local role lf_governance_owner_v3;

create or replace function private.fn_canonical_json_v7(p_value jsonb)
returns text
language plpgsql
immutable
strict
set search_path to ''
as $function$
declare
  v_type text;
  v_result text;
  v_number numeric;
begin
  v_type:=jsonb_typeof(p_value);

  if v_type='null' then
    return 'null';
  elsif v_type='boolean' then
    return p_value::text;
  elsif v_type='number' then
    begin
      v_number:=(p_value#>>'{}')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception using
          errcode='22023',
          message='canonical JSON number is invalid';
    end;

    if v_number<>trunc(v_number)
       or v_number < -9007199254740991::numeric
       or v_number >  9007199254740991::numeric then
      raise exception using
        errcode='22023',
        message='canonical JSON numbers must be JavaScript-safe integers';
    end if;

    return trunc(v_number)::text;
  elsif v_type='string' then
    return to_jsonb(p_value#>>'{}')::text;
  elsif v_type='array' then
    select '['||coalesce(string_agg(
      private.fn_canonical_json_v7(e.value),
      ',' order by e.ordinality
    ),'')||']'
      into v_result
    from jsonb_array_elements(p_value) with ordinality as e(value,ordinality);

    return v_result;
  elsif v_type='object' then
    if exists (
      select 1
      from jsonb_object_keys(p_value) as k(key_name)
      where k.key_name !~ '^[A-Za-z0-9_.-]+$'
    ) then
      raise exception using
        errcode='22023',
        message='canonical JSON object keys must be ASCII identifiers';
    end if;

    select '{'||coalesce(string_agg(
      to_jsonb(e.key)::text||':'||private.fn_canonical_json_v7(e.value),
      ',' order by e.key collate "C"
    ),'')||'}'
      into v_result
    from jsonb_each(p_value) as e(key,value);

    return v_result;
  end if;

  raise exception using
    errcode='22023',
    message='canonical JSON value has unsupported type';
end;
$function$;

alter function private.fn_canonical_json_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_canonical_json_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_canonical_json_v7(jsonb)
  to lf_governance_owner_v3;

create or replace function private.fn_payload_sha256_v7(p_payload jsonb)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select encode(
    extensions.digest(
      convert_to(private.fn_canonical_json_v7(p_payload),'UTF8'),
      'sha256'
    ),
    'hex'
  );
$function$;

alter function private.fn_payload_sha256_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_payload_sha256_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_payload_sha256_v7(jsonb)
  to lf_governance_owner_v3;

create or replace function private.fn_frame_component_v7(p_value text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select octet_length(coalesce(p_value,''))::text||'#'||coalesce(p_value,'');
$function$;

alter function private.fn_frame_component_v7(text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_frame_component_v7(text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_frame_component_v7(text)
  to lf_governance_owner_v3;

-- CA-N36: framing removes delimiter ambiguity.
-- CA-N37: the payload digest binds every payload field, including nested details.
-- CA-N38: canonical JSON rejects non-integer and unsafe numeric values.
create or replace function private.fn_reconciliation_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select
    private.fn_frame_component_v7('reconciliation-v7')
    ||private.fn_frame_component_v7(p_execution_id)
    ||private.fn_frame_component_v7(private.fn_payload_sha256_v7(p_payload));
$function$;

alter function private.fn_reconciliation_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

create or replace function private.fn_gate_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select
    private.fn_frame_component_v7('gate-v7')
    ||private.fn_frame_component_v7(p_execution_id)
    ||private.fn_frame_component_v7(private.fn_payload_sha256_v7(p_payload));
$function$;

alter function private.fn_gate_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_gate_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

commit;
