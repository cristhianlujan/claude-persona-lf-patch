-- Remove residual "selected" identity-adapter markers after lf-platform alignment.

begin;

update lf_ops.reglas
set valor_config=(valor_config
      - 'selected_server_adapter_status'
    ) || jsonb_build_object(
      'selected_server_adapter_status','PENDING_M1_IDENTITY_SPIKE'
    ),
    updated_at=now()
where codigo='B2B-RULE-AUTH-013'
  and valor_config->>'selected_server_adapter'='OIDC_PROVIDER_PENDING_M1_SPIKE';

update lf_ops.reglas
set valor_config=(valor_config
      - 'preferred_adapter_status'
    ) || jsonb_build_object(
      'preferred_adapter_status','PENDING_M1_IDENTITY_SPIKE'
    ),
    updated_at=now()
where codigo='B2B-RULE-AUTH-026'
  and valor_config->>'provider_binding'='PENDING_M1_IDENTITY_SPIKE';

do $$
begin
  if exists (
    select 1
    from lf_ops.reglas
    where codigo in ('B2B-RULE-AUTH-013','B2B-RULE-AUTH-026')
      and (
        coalesce(valor_config->>'selected_server_adapter_status','') like 'SELECTED%'
        or coalesce(valor_config->>'preferred_adapter_status','')='SELECTED'
      )
  ) then
    raise exception 'B2B_AUTH_IDENTITY_BINDING_SELECTED_MARKER_REMAINS';
  end if;
end
$$;

commit;
