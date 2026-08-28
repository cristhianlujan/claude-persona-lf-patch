do $$
declare
  d text;
  d2 text;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) into d;
  d2 := replace(d,
$old$  select count(*) filter (where b.required), count(*) filter (where b.required and pv.policy_code is not null)
  into v_required_policy_count,v_resolved_policy_count
  from public.lf_operation_policy_bindings b
  left join public.lf_policy_versions pv on pv.policy_code=b.policy_code and pv.status='ACTIVE'
  where b.operation_code=v_operation.operation_code and b.binding_status='ACTIVE';$old$,
$new$  select count(*) filter (where b.required)
  into v_required_policy_count
  from public.lf_operation_policy_bindings b
  where b.operation_code=v_operation.operation_code
    and b.binding_status='ACTIVE'
    and (p_distribution_mode is null or p_distribution_mode=any(b.distribution_modes));

  select count(*)
  into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and p.required
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$new$);
  if d2=d then
    raise exception 'router policy resolution replacement did not match current function body';
  end if;
  execute d2;
end $$;

revoke all on function public.lf_router_resolve_v1(text,text,text,text,text) from public, anon, authenticated;

update public.lf_activos
set metadata=jsonb_set(
      coalesce(metadata,'{}'::jsonb),
      '{deterministic_blocking}',
      coalesce(metadata->'deterministic_blocking','[]'::jsonb) || to_jsonb('BLOCK_MASTER_ASSET_HYDRATION_FAILED'::text),
      true
    ) || jsonb_build_object(
      'policy_resolution_rule','required ACTIVE binding for distribution_mode must resolve through v_lf_operation_policy_snapshot; otherwise BLOCK_REQUIRED_POLICY_MISSING'
    ),
    updated_by_execution_id='EXEC-GOV-ROUTER-ACT0001-20260827-001',
    updated_at=now()
where codigo_activo='ACT-0001';
