# Minimización de datos (solo lectura, 2026-11-05)

Las copias no son volcados íntegros de tablas: solo usan columnas que necesitan las siete funciones.

| Tabla | Filas incluidas | Campos omitidos |
|---|---:|---|
| lf_activos | 11 perfiles activos | identificadores internos, dueño/owner_name, campos de planillas, raw_payload, URLs, IDs de ejecución, marcas temporales y todas las claves de metadata excepto canonical_profile_key, profile_slug, repo_path |
| lf_profile_selection_registry_v1 | 10 | marcas temporales de sincronización, actor y stale_reason |
| lf_profile_selector_policy_v1 | 10 | timestamps |
| lf_profile_write_authority_v1 | 31 | basis, self_update_allowed |
| lf_router_action_registry | 42 | notas, actor, timestamps y flags no consultados |
| lf_operation_execution | 28 COMPLETED EJECUCION_PERFIL_LF | las restantes 2380 operaciones, 24 ejecuciones de perfil no completadas, manifest, rutas, actor, lease, timestamps, payload y datos de auditoría |

Las huellas anteriores en SOURCE_PIN.json son del registro **completo** (incluidos campos omitidos), por lo que no pueden coincidir con la copia minimizada. No se sustituirán por huellas inventadas. La paridad funcional se medirá con las salidas originales de expected/ y comparaciones JSON.

El DDL es intencionalmente mínimo: no es un respaldo fiel del esquema productivo; no copia RLS, triggers ni las restricciones de columnas no utilizadas. La función descriptor_sync recibe defaults locales para columnas obligatorias de sincronización. No ejecutar fuera de una base local desechable.
