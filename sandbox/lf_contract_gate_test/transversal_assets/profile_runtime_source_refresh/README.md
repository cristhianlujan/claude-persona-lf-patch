# PROFILE_RUNTIME_SOURCE_REFRESH

Inventory status: `ACTIVE_SHARED_ENFORCEMENT`.

## Propósito

Capability transversal que refresca la fuente de un perfil ya desplegado en el runtime Hetzner después de `ACTUALIZACION_PERFIL_LF`. No modifica el paquete del perfil, no modifica la implementación del runtime y no promueve estado ni impacto automático.

Cadena canónica: `ACTUALIZACION_PERFIL_LF -> PROFILE_RUNTIME_REFRESH_REQUIRED -> REFRESCO_RUNTIME_PERFIL_LF`.

## Cuándo consumirlo

Cuando un `PERFIL` existente tenga `metadata.post_merge_next_gate=PROFILE_RUNTIME_REFRESH_REQUIRED` y la fuente ya haya sido reconciliada post-merge. Si cambió `services/profile_runtime_api`, el caso pertenece a `ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF`, no a este refresco.

## Cómo consumirlo

1. Resolver `PERFIL/PROFILE_RUNTIME_REFRESH` por ACT-0001.
2. Crear `REFRESCO_RUNTIME_PERFIL_LF` antes de cualquier mutación del host.
3. Leer exact main y hashes canónicos del perfil desde `public.lf_activos`.
4. Capturar release/runtime source actual y rollback target.
5. Exigir delta cero en `services/profile_runtime_api` y cero cambios bajo otros `profiles/<slug>`.
6. Ejecutar `services/profile_runtime_api/scripts/install.sh --source-dir <exact-main-checkout> --source-sha <main_sha> --require-main --start`.
7. Verificar service health, runtime source SHA, hashes desplegados del target y preservación de estado.
8. Cerrar sólo con rollback disponible y `no_auto_promotion=true`.

## Superficies canónicas

- Operation: `public.lf_operation_registry/REFRESCO_RUNTIME_PERFIL_LF`
- Router: `public.lf_router_action_registry/PERFIL/PROFILE_RUNTIME_REFRESH`
- Contract: `sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json`
- Installer: `services/profile_runtime_api/scripts/install.sh`
- Releases: `/opt/lf-profile-runtime-api/releases/<source_sha>`
- Active symlink: `/opt/lf-profile-runtime-api/current`
- Service: `lf-profile-runtime-api.service`
- Asset inventory: `public.lf_activos.codigo_activo=PROFILE_RUNTIME_SOURCE_REFRESH`

## Fail-closed / límites

Bloquear si el target no es único, main no es exacto, la fuente reconciliada no coincide, existe delta de implementación del runtime, cambió otro perfil, no hay rollback, falla health/readback o cambia `runtime_estado`, `estado_operativo` o `impacto_automatico`. La operación no contiene executor SQL para mutar el host.

## Validación y readback

Exigir `runtime_endpoint_source_sha=<exact_main_sha>`, symlink a `/opt/lf-profile-runtime-api/releases/<exact_main_sha>`, health loopback verde, `SKILL.md` y `manifest.json` con hashes esperados desde Supabase, y estado del perfil idéntico antes/después. El report final conserva refs al release, service health y ejecución gobernada.

## Rollback

Antes del write capturar `runtime_source_sha_before` y `release_path_before`. Cualquier fallo posterior al switch debe reinstalar el release previo mediante el mismo `install.sh`, restaurar source SHA, reiniciar el servicio y verificar health/readback antes de declarar rollback completo.

## No duplicación

No crear otro instalador, otro runtime engine ni otra autoridad de perfil. Esta capability orquesta las superficies existentes. `ACTUALIZACION_PERFIL_LF` sigue siendo autoridad de cambio de fuente y `ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF` sigue siendo autoridad para cambios de implementación del runtime.

## Currentness

Releer en cada ejecución: main actual de GitHub, `public.lf_activos` del target, `public.lf_router_action_registry`, release activo del host, hashes de `services/profile_runtime_api`, hashes del target y health del servicio. Evidencia histórica no autoriza un refresco nuevo.
