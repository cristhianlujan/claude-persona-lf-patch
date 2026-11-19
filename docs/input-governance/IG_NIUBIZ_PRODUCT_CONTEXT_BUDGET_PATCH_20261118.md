# IG Niubiz — compactación del contexto Producto sin relajar controles

Estado: propuesta de migración para Merge Train. **NO activa reglas ni decisiones.**

## Entrada verificable
- Función afectada exclusivamente: `public.lf_profile_execution_channel_context_v1`; preimage md5 `460a9e7f9339f6387175983d404c5808`.
- Pantallas originales: `CHECKOUT_ESTADO_TARJETA` (265 reglas directas), `CHECKOUT_PAGO_EXITOSO` (275), `CHECKOUT_ESTADO_CONFIRMANDO` (265).
- Tres padres en `IN_PROGRESS`: `EXEC-PROFILE-GATE2-8A32C42D5DE64233CB4ABE3E`, `EXEC-PROFILE-GATE2-C1988A78EEC630B2C7D3348A`, `EXEC-PROFILE-GATE2-447657D25F743AE8121267AC`.
- Bloqueo real común PREPARE HTTP 409: `BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED`. Es consecuencia de materializar cientos de tuplas de reglas en el contexto.
- El límite `hard_limit_tokens` **NO cambia**. También se conserva la lógica de estatus `RED` y el rechazo final con el mismo código.

## Reparación acotada
- Solo cuando una lectura **canónica** `LF_PRODUCT_CANONICAL_RULE_READ_V1` es `RED`, se verifica `subject_ref`, las refs de fuente y que `jsonb_array_length(direct_rules) = direct_rule_count` antes de compactar.
- Se reemplaza en el **contexto transportado**, no en la base de datos, la colección de cientos de `direct_rules` por:
  - `direct_rules_snapshot_sha256` del contenido RAW original;
  - `canonical_read_snapshot_sha256` del objeto canónico completo;
  - `direct_rule_count`, `effective_rule_count`, `category_counts`, `direct_rules_ref`, `effective_rules_ref`, `subject_ref`, pantalla y versión, sin perder identidad ni conteos;
  - `projection_mode=CANONICAL_RULES_DIGEST_LAZY_V1`, `full_context_requires_lazy_read=true`, `readback_currentness_required=true`.
- Al consumidor se le exige una lectura JIT desde la fuente canónica y comparación de digest/currentness si necesita cada regla: **la proyección por sí sola no acredita que el consumidor implemente la verificación**. Esa integración deberá demostrarse en el recorrido real.
- Si aun así el contexto excede el hard budget, conserva `BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED`. Sin ampliar topes ni inventar PASS.

## Tests exigidos
- PostgreSQL 17 real aislado, pantallas de 265/275/265 reglas sintéticas con consulta directa y SHA independiente; caso pequeño sin compactación.
- 4 controles negativos: base sobredimensionada sigue bloqueada, handoff inválido, pantalla sin selección, selección inválida.
- BEGIN/ROLLBACK y readback SELECT en sesión nueva, canarios 9/9; sin accesos a Supabase remoto.
- La migración exige MD5 del cuerpo original y md5 inalterado para todas las filas de `lf_ops.reglas` y `public.lf_global_config`; modifica una única función.

## Continuación gobernada después del Train
1. Verificar el merge exacto y la nueva definición por SELECT.
2. Reanudar **los mismos RUN** por el bridge existente OIDC, sin crear RUN alternativos.
3. Exigir Input Governance → Step50/60 → Step70 con evidencia Train `RULE_CONTRACT_LEVEL` para el patch y hash exactos. No confundir PASS de tests de contexto con evidencia oficial de cada regla.
4. Decisión `lf_ig_rule_owner_decide_v2` con `usuario=Cristhian Lujan` una por regla, solo cuando el paquete por RUN cumple todos los gates, y readback `CANDIDATO` sin promoción. Si falta evidencia, bloquear.
5. Referencias de las tres reglas: `public.lf_global_config`, `{scope:PAGOS, config_key:NIUBIZ_EMAIL_TEMPLATE}` y `{scope:PAGOS, config_key:NIUBIZ_EMAIL_DOMAIN}`. Ningún valor hardcodeado en los textos.
6. La aceptación del guion por el sandbox real de Niubiz permanece **NOT_TESTED**; el buzón técnico no requiere existencia, pero la aceptación en el formulario debe validarse.
