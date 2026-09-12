create or replace function lf_ops.b2b_current_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.user_id
  from lf_ops.empresa_usuarios u
  where u.auth_user_id = auth.uid()
    and u.status = 'ACTIVE'
  limit 1
$$;

create or replace function lf_ops.b2b_current_company_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.company_id
  from lf_ops.empresa_usuarios u
  where u.auth_user_id = auth.uid()
    and u.status = 'ACTIVE'
  limit 1
$$;

revoke all on function lf_ops.b2b_current_user_id() from public;
revoke all on function lf_ops.b2b_current_company_id() from public;
grant execute on function lf_ops.b2b_current_user_id() to authenticated;
grant execute on function lf_ops.b2b_current_company_id() to authenticated;

grant usage on schema lf_ops to authenticated;
grant select on table lf_ops.empresas to authenticated;
grant select on table lf_ops.empresa_usuarios to authenticated;
grant select on table lf_ops.empresa_usuarios_perfiles to authenticated;
grant select on table lf_ops.empresa_usuarios_permisos to authenticated;

create policy b2b_empresas_select_own_company
on lf_ops.empresas
as restrictive
for select
to authenticated
using (
  company_id = lf_ops.b2b_current_company_id()
);

create policy b2b_empresa_usuarios_select_self
on lf_ops.empresa_usuarios
as restrictive
for select
to authenticated
using (
  user_id = lf_ops.b2b_current_user_id()
);

create policy b2b_empresa_usuarios_perfiles_select_self
on lf_ops.empresa_usuarios_perfiles
as restrictive
for select
to authenticated
using (
  user_id = lf_ops.b2b_current_user_id()
);

create policy b2b_empresa_usuarios_permisos_select_self
on lf_ops.empresa_usuarios_permisos
as restrictive
for select
to authenticated
using (
  user_id = lf_ops.b2b_current_user_id()
);