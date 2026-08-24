-- AUD24-F03 remediation source only.
-- Hidden challenge bytes must be provisioned independently in Supabase Vault.
-- This migration does not create, seed, log, or expose the hidden corpus.

create or replace function public.programming_hidden_oracle_bundle_v3()
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'vault'
as $function$
declare
  v_raw text;
  v_bundle jsonb;
  v_family_keys text[];
  v_policy_id constant text := 'c6f2c34aa7fac4117fb2df29a343164e7b9ed132a261052eb9e95370be75924b';
begin
  select ds.decrypted_secret
    into v_raw
  from vault.decrypted_secrets ds
  where ds.name = 'PROGRAMMING_AGENT_HIDDEN_ORACLE_BUNDLE_V3'
  limit 1;

  if v_raw is null or length(v_raw) = 0 then
    raise exception 'HIDDEN_ORACLE_BUNDLE_V3_UNAVAILABLE';
  end if;

  begin
    v_bundle := v_raw::jsonb;
  exception
    when others then
      raise exception 'HIDDEN_ORACLE_BUNDLE_V3_INVALID_JSON';
  end;

  if jsonb_typeof(v_bundle) <> 'object' then
    raise exception 'HIDDEN_ORACLE_BUNDLE_V3_OBJECT_REQUIRED';
  end if;
  if coalesce(v_bundle->>'schema_version','') <> '1' then
    raise exception 'HIDDEN_ORACLE_BUNDLE_V3_SCHEMA_INVALID';
  end if;
  if coalesce(v_bundle->>'policy_id','') <> v_policy_id then
    raise exception 'HIDDEN_ORACLE_BUNDLE_V3_POLICY_INVALID';
  end if;
  if jsonb_typeof(v_bundle->'families') <> 'object' then
    raise exception 'HIDDEN_ORACLE_BUNDLE_V3_FAMILIES_INVALID';
  end if;

  select coalesce(array_agg(k order by k), '{}'::text[])
    into v_family_keys
  from jsonb_object_keys(v_bundle->'families') as x(k);

  if v_family_keys <> array[
    'concurrency_partial_failure',
    'multi_file_feature',
    'root_cause_bug',
    'security'
  ]::text[] then
    raise exception 'HIDDEN_ORACLE_BUNDLE_V3_FAMILY_SET_INVALID';
  end if;

  return v_bundle;
end;
$function$;

revoke all on function public.programming_hidden_oracle_bundle_v3() from public, anon, authenticated;
grant execute on function public.programming_hidden_oracle_bundle_v3() to service_role;

comment on function public.programming_hidden_oracle_bundle_v3() is
  'Fail-closed service-role-only bridge to the independently provisioned AUD24 hidden challenge bundle in Supabase Vault. Hidden bytes are not stored in repository source.';
