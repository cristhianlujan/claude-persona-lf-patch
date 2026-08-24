insert into programacion.task_blockers(
  task_id,blocker_code,owner_type,owner_ref,required_action,source_ref,status
)
select
  21,
  'CLIENT_AUTH_SESSION_RUNTIME_IMPLEMENTATION_REQUIRED',
  'CLIENT_IMPLEMENTATION',
  'decision://DEC-CLIENT-AUTH-SESSION-RUNTIME-001',
  'MATERIALIZE_AUTHENTICATED_CLIENT_SESSION_RUNTIME_IN_TARGET_REPOSITORY_BEFORE_HMO_EXECUTION',
  'github://cristhianlujan/libertad-financiera@00335febcfe961a1c6d185a77970adb272af7c6b/src/app/page.tsx',
  'OPEN'
where not exists (
  select 1
  from programacion.task_blockers
  where task_id=21
    and blocker_code='CLIENT_AUTH_SESSION_RUNTIME_IMPLEMENTATION_REQUIRED'
    and source_ref='github://cristhianlujan/libertad-financiera@00335febcfe961a1c6d185a77970adb272af7c6b/src/app/page.tsx'
);

update transversal.error_knowledge
set frecuencia=frecuencia+1,
    evidencia=evidencia||E'\nRECURRENCIA 2026-08-24 Story Agent simplification: al resolver CLIENT_AUTH_SESSION_RUNTIME_REQUIRED con la decisión canónica DEC-CLIENT-AUTH-SESSION-RUNTIME-001, task21 quedó READY. Readback directo del target cristhianlujan/libertad-financiera@00335febcfe961a1c6d185a77970adb272af7c6b mostró que src/app/page.tsx sigue siendo sólo el skeleton Lote 0 y package.json no contiene runtime Supabase/SSR. La decisión cierra arquitectura para desarrollo, pero no prueba materialización en el repositorio. Se añadió CLIENT_AUTH_SESSION_RUNTIME_IMPLEMENTATION_REQUIRED y task21 vuelve fail-closed. Regla: una decisión arquitectónica no satisface por sí sola una dependencia de runtime; exigir evidencia del artefacto materializado en el HEAD objetivo.',
    updated_at=now()
where codigo='ARC-010';