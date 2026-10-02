# STORY_CREATOR_EMBEDDED_PROFILE_ASSET_BINDINGS_V1

Registro source-first de las cinco identidades `PERFIL` ya existentes dentro de `creating-integral-user-stories`.

## Reutiliza

- `private.lf_skill_artifacts` como autoridad de contenido del Profile embebido;
- `public.lf_activos` como identidad operacional del Profile;
- `ACT-0001` como autoridad de routing;
- `CURRENTNESS_AUTHORITY` para currentness;
- `EJECUCION_PERFIL_LF` como operación de ejecución existente.

## No duplica archivos

Los Profiles permanecen en:

```text
skills/creating-integral-user-stories/perfiles/*.md
```

No se crean copias bajo `profiles/<slug>/`. Cada fila de `lf_activos` declara `source_mode=EMBEDDED_SKILL_PROFILE` y conserva `source_artifact_code/version/sha256` contra el artifact current.

## Fail closed

La migración se niega a aplicar si no existen exactamente los cinco artifacts current y todos no están `CANDIDATO_READ_ONLY + PASS_WITH_EVIDENCE`.

Después del insert revalida:

- 5/5 identidades presentes;
- `tipo_activo=PERFIL`;
- `estado_operativo=READ_ONLY`;
- `runtime_enabled=false`;
- `runtime_binding_state=BLOCKED_PENDING_PROFILE_TASK_RUNTIME_BINDING`;
- SHA de metadata igual al artifact current.

## Boundary

Este lote **no habilita runtime**. No crea relación nueva, tabla, función, queue, operation ni runtime binding. El binding task-bound y el runtime wiring pertenecen a PRs separados.

La aplicación Supabase queda bloqueada hasta que currentness de los artifacts Story esté reconciliado y el pase transversal de migraciones esté disponible.
