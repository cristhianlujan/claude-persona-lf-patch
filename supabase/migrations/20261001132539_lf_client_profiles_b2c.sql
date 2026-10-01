-- DEC-CLIENT-PROFILES-B2C-001: modelo de perfiles del cliente (B2C).
-- Aprobada por Cristhian Luján el 2026-10-01. Dos perfiles: CLIENTE_ANONIMO (antes del login) y CLIENTE_AUTENTICADO (después).
-- Habilita el ámbito B2C en lf_ops.perfiles y liga las 5 pantallas de cliente con perfil y permiso de ver.

alter table lf_ops.perfiles drop constraint if exists perfiles_scope_ck;
alter table lf_ops.perfiles add constraint perfiles_scope_ck check (profile_scope = any (array['B2B','ADMIN','GLOBAL','B2C']));

insert into public.lf_decisiones_gov(id_decision, decision_number, fecha, decision, contexto, impacto, estado_original, estado_normalizado, source_sheet_name, migration_batch_id, raw_payload, created_by_execution_id)
select 'DEC-CLIENT-PROFILES-B2C-001', (select coalesce(max(decision_number),0)+1 from public.lf_decisiones_gov), '2026-10-01',
  'El cliente final (B2C) tiene dos perfiles: CLIENTE_ANONIMO, para las pantallas previas al login (onboarding ONB_001 a ONB_004), y CLIENTE_AUTENTICADO, para las pantallas con sesión (HOME_002). Ambos con permiso CLIENT_SCREEN_VIEW sobre su pantalla. Se mantienen separados para distinguir en la medición a quien llega sin identificarse de quien se autentica.',
  'Las 5 pantallas de cliente no tenían perfil ni permiso porque el catálogo solo admitía ámbitos B2B, ADMIN y GLOBAL. Analizado en el plan IG_CURATOR_VALIDATOR_REFACTOR_V2 (causa C: dato de pantalla faltante).',
  'Habilita el ámbito B2C en lf_ops.perfiles. Simulación con ROLLBACK sobre el clasificador de Input Governance: +10 celdas listas para implementación (PROFILES y PERMISSIONS completas en las 5 pantallas). La identidad para contar personas distintas en analytics es una decisión aparte.',
  'APROBADO_OWNER', 'VIGENTE', 'CHAT_OWNER_DECISION', gen_random_uuid(),
  jsonb_build_object('approved_by','Cristhian Luján','approved_at','2026-10-01','profiles',jsonb_build_array('CLIENTE_ANONIMO','CLIENTE_AUTENTICADO'),'permission','CLIENT_SCREEN_VIEW','screens',jsonb_build_object('CLIENTE_ANONIMO',jsonb_build_array('ONB_001','ONB_002','ONB_003','ONB_004'),'CLIENTE_AUTENTICADO',jsonb_build_array('HOME_002'))),
  'CLAUDE-LF-CLIENT-PROFILES-B2C-20261001'
where not exists (select 1 from public.lf_decisiones_gov where id_decision='DEC-CLIENT-PROFILES-B2C-001');

insert into lf_ops.perfiles(profile_code, name, description, profile_scope, status, is_active, source_decision_number)
select v.code, v.name, v.descr, 'B2C', 'VIGENTE', true, d.decision_number
from (values ('CLIENTE_ANONIMO','Cliente no autenticado','Cliente final antes de identificarse (onboarding y recuperación previos al login).'),
             ('CLIENTE_AUTENTICADO','Cliente autenticado','Cliente final con sesión iniciada.')) v(code,name,descr)
cross join (select decision_number from public.lf_decisiones_gov where id_decision='DEC-CLIENT-PROFILES-B2C-001') d
where not exists (select 1 from lf_ops.perfiles p where p.profile_code=v.code);

insert into lf_ops.permisos(permission_code, name, description, resource_type, action_code, status, source_decision_number)
select 'CLIENT_SCREEN_VIEW', 'Ver pantalla de cliente', 'Permite al cliente final ver la pantalla a la que está ligado.', 'SCREEN', 'VIEW', 'VIGENTE', d.decision_number
from (select decision_number from public.lf_decisiones_gov where id_decision='DEC-CLIENT-PROFILES-B2C-001') d
where not exists (select 1 from lf_ops.permisos where permission_code='CLIENT_SCREEN_VIEW');

insert into lf_ops.pantallas_perfiles(pantalla_id, profile_code, access_level, status, profile_id, source_decision_number)
select s.id, s.prof, 'VIEW', 'VIGENTE', p.profile_id, p.source_decision_number
from (select id, case when codigo='HOME_002' then 'CLIENTE_AUTENTICADO' else 'CLIENTE_ANONIMO' end prof
        from lf_ops.pantallas where codigo in ('ONB_001','ONB_002','ONB_003','ONB_004','HOME_002')) s
join lf_ops.perfiles p on p.profile_code=s.prof
where not exists (select 1 from lf_ops.pantallas_perfiles x where x.pantalla_id=s.id and x.profile_code=s.prof);

insert into lf_ops.pantallas_permisos(pantalla_id, permission_code, access_effect, status, permission_id, source_decision_number)
select s.id, 'CLIENT_SCREEN_VIEW', 'ALLOW', 'VIGENTE', m.permission_id, m.source_decision_number
from lf_ops.pantallas s join lf_ops.permisos m on m.permission_code='CLIENT_SCREEN_VIEW'
where s.codigo in ('ONB_001','ONB_002','ONB_003','ONB_004','HOME_002')
  and not exists (select 1 from lf_ops.pantallas_permisos x where x.pantalla_id=s.id and x.permission_code='CLIENT_SCREEN_VIEW');