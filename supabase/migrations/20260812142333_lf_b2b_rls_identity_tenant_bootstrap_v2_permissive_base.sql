drop policy if exists b2b_empresas_select_own_company on lf_ops.empresas;
drop policy if exists b2b_empresa_usuarios_select_self on lf_ops.empresa_usuarios;
drop policy if exists b2b_empresa_usuarios_perfiles_select_self on lf_ops.empresa_usuarios_perfiles;
drop policy if exists b2b_empresa_usuarios_permisos_select_self on lf_ops.empresa_usuarios_permisos;

create policy b2b_empresas_select_own_company
on lf_ops.empresas
as permissive
for select
to authenticated
using (company_id = lf_ops.b2b_current_company_id());

create policy b2b_empresa_usuarios_select_self
on lf_ops.empresa_usuarios
as permissive
for select
to authenticated
using (user_id = lf_ops.b2b_current_user_id());

create policy b2b_empresa_usuarios_perfiles_select_self
on lf_ops.empresa_usuarios_perfiles
as permissive
for select
to authenticated
using (user_id = lf_ops.b2b_current_user_id());

create policy b2b_empresa_usuarios_permisos_select_self
on lf_ops.empresa_usuarios_permisos
as permissive
for select
to authenticated
using (user_id = lf_ops.b2b_current_user_id());