-- INV-6.4a - governed read surface for Input Governance recuration allowlist
-- Exact-version identity: 20261002165938
-- Transport: EXACT_VERSION_SOURCE_FIRST
-- Consumer: lf-profiles-governance-caller-v1 v8
--
-- This migration does not expose lf_ops and grants no schema/table privileges.
-- It creates one minimal SECURITY DEFINER RPC that returns only rule 661.

do $preflight$
declare
  v_count integer;
  v_rule_id bigint;
  v_estado text;
begin
  if pg_catalog.to_regprocedure('public.lf_input_gov_recuration_allowlist_v1()') is not null then
    raise exception 'INV_6_4A_FUNCTION_ALREADY_EXISTS';
  end if;

  select count(*), min(id), min(estado)
    into v_count, v_rule_id, v_estado
  from lf_ops.reglas
  where codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

  if v_count <> 1 then
    raise exception 'INV_6_4A_RULE_CARDINALITY_MISMATCH expected=1 actual=%', v_count;
  end if;

  if v_rule_id <> 661 then
    raise exception 'INV_6_4A_RULE_ID_MISMATCH expected=661 actual=%', v_rule_id;
  end if;

  if v_estado <> 'VIGENTE' then
    raise exception 'INV_6_4A_RULE_NOT_VIGENTE actual=%', v_estado;
  end if;
end
$preflight$;

create function public.lf_input_gov_recuration_allowlist_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_count integer;
  v_rule record;
begin
  select count(*)
    into v_count
  from lf_ops.reglas
  where codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

  if v_count <> 1 then
    raise exception 'LF_INPUT_GOV_RECURATION_ALLOWLIST_CARDINALITY_MISMATCH expected=1 actual=%', v_count;
  end if;

  select id, codigo, estado, valor_config, updated_at
    into v_rule
  from lf_ops.reglas
  where codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

  return pg_catalog.jsonb_build_object(
    'schema_version','lf-input-gov-recuration-allowlist/v1',
    'rule_id',v_rule.id,
    'codigo',v_rule.codigo,
    'estado',v_rule.estado,
    'valor_config',v_rule.valor_config,
    'updated_at',v_rule.updated_at,
    'observed_at',pg_catalog.now()
  );
end
$function$;

alter function public.lf_input_gov_recuration_allowlist_v1() owner to postgres;

revoke all on function public.lf_input_gov_recuration_allowlist_v1() from public, anon, authenticated;
grant execute on function public.lf_input_gov_recuration_allowlist_v1() to service_role;

comment on function public.lf_input_gov_recuration_allowlist_v1() is
'Governed minimal read surface for lf_ops.reglas rule INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001 (rule 661), consumed by lf-profiles-governance-caller-v1 v8. Returns rule fields only; validation remains in the caller.';
