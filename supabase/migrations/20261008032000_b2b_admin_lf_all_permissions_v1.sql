-- LF product super-admin permission invariant
-- B2B_ADMIN_LF is the LF product super-admin. It is distinct from software-governance SUPER_ADMIN.
-- Invariant: every B2B permission is assigned to B2B_ADMIN_LF, and future B2B permissions
-- are assigned automatically without relying on frontend constants or manual backfills.

create or replace function lf_ops.sync_b2b_admin_lf_permission_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_profile_id bigint;
begin
  select p.profile_id
    into v_profile_id
  from lf_ops.perfiles p
  where p.profile_code='B2B_ADMIN_LF'
  limit 1;

  if v_profile_id is null then
    raise exception 'B2B_ADMIN_LF_PROFILE_REQUIRED';
  end if;

  if new.permission_code like 'B2B\_%' escape '\' then
    insert into lf_ops.perfiles_permisos(
      profile_code,
      permission_code,
      access_effect,
      condition_config,
      status,
      source_decision_id,
      profile_id,
      permission_id,
      source_decision_number
    )
    values(
      'B2B_ADMIN_LF',
      new.permission_code,
      'ALLOW',
      '{}'::jsonb,
      new.status,
      coalesce(new.source_decision_id,'AUTO_B2B_ADMIN_LF_ALL_PERMISSIONS_V1'),
      v_profile_id,
      new.permission_id,
      new.source_decision_number
    )
    on conflict (profile_id,permission_id) do update
    set profile_code='B2B_ADMIN_LF',
        permission_code=excluded.permission_code,
        access_effect='ALLOW',
        status=excluded.status,
        source_decision_id=excluded.source_decision_id,
        source_decision_number=excluded.source_decision_number,
        updated_at=now();

  elsif tg_op='UPDATE'
        and old.permission_code like 'B2B\_%' escape '\'
        and new.permission_code not like 'B2B\_%' escape '\' then
    update lf_ops.perfiles_permisos pp
    set permission_code=new.permission_code,
        access_effect='ALLOW',
        status='INACTIVO',
        source_decision_id=coalesce(new.source_decision_id,pp.source_decision_id),
        source_decision_number=coalesce(new.source_decision_number,pp.source_decision_number),
        updated_at=now()
    where pp.profile_id=v_profile_id
      and pp.permission_id=new.permission_id;
  end if;

  return new;
end
$function$;

drop trigger if exists trg_sync_b2b_admin_lf_permission_v1 on lf_ops.permisos;

create trigger trg_sync_b2b_admin_lf_permission_v1
after insert or update of permission_code,status,source_decision_id,source_decision_number
on lf_ops.permisos
for each row
execute function lf_ops.sync_b2b_admin_lf_permission_v1();

-- Backfill any current B2B permission that is not yet assigned to the LF product super-admin.
insert into lf_ops.perfiles_permisos(
  profile_code,
  permission_code,
  access_effect,
  condition_config,
  status,
  source_decision_id,
  profile_id,
  permission_id,
  source_decision_number
)
select
  'B2B_ADMIN_LF',
  p.permission_code,
  'ALLOW',
  '{}'::jsonb,
  p.status,
  coalesce(p.source_decision_id,'USER_APPROVAL_2026-10-07_B2B_ADMIN_LF_ALL_PERMISSIONS'),
  pf.profile_id,
  p.permission_id,
  p.source_decision_number
from lf_ops.permisos p
join lf_ops.perfiles pf
  on pf.profile_code='B2B_ADMIN_LF'
where p.permission_code like 'B2B\_%' escape '\'
  and not exists(
    select 1
    from lf_ops.perfiles_permisos pp
    where pp.profile_id=pf.profile_id
      and pp.permission_id=p.permission_id
  );

-- Enforce ALLOW and lifecycle parity for every current B2B permission while preserving
-- any existing condition_config (e.g. MFA recovery safeguards).
update lf_ops.perfiles_permisos pp
set access_effect='ALLOW',
    status=p.status,
    permission_code=p.permission_code,
    source_decision_id=coalesce(pp.source_decision_id,p.source_decision_id,'USER_APPROVAL_2026-10-07_B2B_ADMIN_LF_ALL_PERMISSIONS'),
    source_decision_number=coalesce(pp.source_decision_number,p.source_decision_number),
    updated_at=now()
from lf_ops.perfiles pf,
     lf_ops.permisos p
where pf.profile_code='B2B_ADMIN_LF'
  and pp.profile_id=pf.profile_id
  and pp.permission_id=p.permission_id
  and p.permission_code like 'B2B\_%' escape '\';

comment on function lf_ops.sync_b2b_admin_lf_permission_v1() is
'Keeps LF product super-admin B2B_ADMIN_LF assigned with ALLOW to every B2B_* permission. Distinct from software-governance SUPER_ADMIN. Preserves existing condition_config on updates.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'PROGRAMMING-B2B-ADMIN-LF-ALL-PERMISSIONS-001',
  'PROGRAMMING_GOVERNANCE',
  'LF product super-admin must receive every current and future B2B permission',
  'B2B_ADMIN_LF is the LF product super-admin and must have ALLOW for every B2B_* permission. A database trigger now assigns new B2B permissions automatically and synchronizes mapping lifecycle status when the permission changes. Existing condition_config is preserved.',
  'Manual permission assignment allowed the super-admin profile to drift behind newly created B2B permissions.',
  'B2B permission INSERT/UPDATE -> database invariant -> B2B_ADMIN_LF ALLOW mapping. Governance SUPER_ADMIN remains a separate authority plane.',
  'Never rely on frontend constants or periodic manual backfill for LF product super-admin coverage. New B2B permissions must flow through lf_ops.permisos so the invariant trigger executes.',
  'Migration backfills current gaps, enforces ALLOW for all existing B2B permissions, and installs trg_sync_b2b_admin_lf_permission_v1 for future permissions.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008032000_b2b_admin_lf_all_permissions_v1.sql',
  now()
)
on conflict (codigo) do update
set descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
