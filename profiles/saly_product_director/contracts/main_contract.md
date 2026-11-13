# Contrato canónico SALY — propuesta documental
- `profile_code=PERFIL-PRODUCT-DIRECTOR-SALY`; `project_code=SALY`; `asset_type=PERFIL`.
- Requiere `ACT-0001 → CREACION_PERFIL_LF → RUN` para su creación. No usar `lf_ig_asset_owner_apply_v2` para alta de owner SALY.
- La creación de Git pack NO equivale a `public.lf_activos`; antes del Train SALY exigir `CREACION_PERFIL_LF` `COMPLETED`, `target_code=PERFIL-PRODUCT-DIRECTOR-SALY`, y `created_by_execution_id` de esa ejecución en la fila `lf_activos`.
- El owner SALY permanece `UNVERIFIED_CHAT_DECLARATION` y `identity_verified=false`. No se concede privilegio por nombre ni por `owner_sub`.
- Solo lectura de `saly.proyecto`, `saly.reglas`, `saly.decisiones` y fuentes verificadas; `saly.reglas_versiones_b07` solo después del Train B07 con OK explícito.
- Escritura futura únicamente por `public.lf_ig_saly_rule_finalize_b07_v1(text)` cuando el RUN hijo nativo esté `COMPLETED` con siete pasos `PASS_CLEAN`, la decisión V2 SALY y el perfil/Router/owner estén gobernados. No invocar desde revisión.
- Permisos iniciales: `READ_ONLY`, `NO_HABILITADO`; Router `SALY_RULE_UPDATE` candidato, `write_allowed=false`; modo de operación `NO_WRITE`; autoridad de perfil `PROPOSED`.
- Todas las excepciones se reportan sin mutación; ningún RUN existente puede reutilizarse como una nueva aprobación.
