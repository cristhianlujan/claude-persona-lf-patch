# LF #3774 / Ratificación de reglas — control de autoridad

**Alcance:** Product Director sigue ejecutando IG y las operaciones existentes. No se añade skill, perfil ni ruta Router. Código candidato sin despliegue. La intervención humana NO se solicita por defecto por el mero estado CANDIDATO.

## Reutilización

- IG existente: `private.fn_lf_ig_candidate_promotion_authority_v1` clasifica específicamente TRANSITIONS y nunca se usa como permiso de acción sobre reglas.
- Autoridad de consumo: `programacion.fn_source_rule_authority` clasifica status de fuentes. No prueba paridad semántica por sí sola.
- Para regla `lf_ops.reglas`, nueva función de lectura `public.lf_rule_promotion_authority_assess_v1(screen_code)` comprueba decisión existente, estado owner, paridad exacta de `rule_code/title/description/reason/rule_config`, sucesión y flags de activación. **Si un campo material no está representado en la autoridad, NO PASS**.
- Ruta humana actual `lf_rule_promotion_decide_v1` se conserva. El trigger `lf_rule_promotion_guard_v1` y aplicación oficial `lf_rule_promotion_apply_v1` siguen vigentes.
- La ruta automática nueva `lf_rule_promotion_auto_ratify_v1(promotion_id,protected_receipt_id)` solo puede actuar con un recibo externamente emitido que ligue acción, fuente, snapshot, juez/seguridad, operación y currentness. Reutiliza `programacion.provenance_receipts`, su insert guard con token, y `lf_rule_promotion_v1`; no permite inventar identidad `HUMAN:`.

## Restricciones técnicas

- **No existe canal productivo** que emita actualmente `RULE_PROMOTION_ACTION_AUTHORIZATION`. Este cambio **NO crea ni activa issuer/canal**; por lo tanto en Supabase actual queda fail-closed aunque se desplegase. No declarar auto-ratificación productiva hasta configurar issuer externo autorizado, generar recibos auténticos y acreditar callback de Product Director.
- La fuente que solo dice `origen=... ` no sirve. `raw_payload.action_authorized=true` NO sirve. La aprobación funcional del owner no equivale a autorización de la acción.
- Prohibidos: `VIGENTE` con `pendiente_decision=true`, producción expresamente desautorizada, fuente reemplazada/ambigua, parámetros diferentes, recibo sin canal permitido, recibo con digest inconsistente, solicitud/ejecución no ligadas y replay.
- Exigir pruebas PostgreSQL 17 positivo, negativo de no-receipt/token, autoridad no aprobada, cambios de regla/snapshot, source drift, rollback, estado final; conservar PR en DRAFT hasta revisión independiente, source parity exacta y despliegue gobernado.

## Inventario real B2B-AUTH-001 (readback 2026-11-10)

- 33 reglas candidatas; 6 con enlaces T_REMED (técnicos, no necesariamente decisiones); 1 con decisión directa `DEC-B2B-AUTH-ROUTING-001` / #134 en `CANDIDATO_CONTROLADO`, sin autoridad de activación.
- Las demás requieren `SOURCE_LOOKUP_REQUIRED`/reconciliación de decisiones, no convocatoria masiva a humanos.
- Con datos actuales **0 reglas automáticamente promocionables acreditadas**.
- Las PR #3775 (LINK) y #3776 (CREATE) siguen en DRAFT con pruebas aisladas PASS. La promoción no depende de mezclarlas en una sola PR, pero producción necesita sus propios gates.

**Cierre técnico** = SQL y tests positivos/negativos PASS sobre HEAD congelado.  
**Cierre operativo** = issuer externo, readback Supabase, 33 reglas evaluadas, Product Director+IG E2E, trazabilidad de cada decisión y autorización de despliegue.
